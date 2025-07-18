//+------------------------------------------------------------------+
//|                       C_MLP.mqh                                  |
//|   Compact MLP with Adam, LeakyReLU, MAE loss                      |
//+------------------------------------------------------------------+
//#pragma once
#include <DeepLearning\Util\INeuralNetworkModel.mqh>

class C_MLP : public INeuralNetworkModel
{
private:
    //--- Network architecture
    int m_input_nodes, m_hidden_nodes, m_output_nodes;

    //--- Adam Optimizer parameters
    double            m_learning_rate;
    double            m_beta1;
    double            m_beta2;
    long              m_t; // Timestep for Adam, use long to prevent overflow

    //--- Weights and Biases
    double            m_weights_ih[]; // Input -> Hidden
    double            m_weights_ho[]; // Hidden -> Output
    double            m_bias_h[];     // Hidden bias
    double            m_bias_o[];     // Output bias
    
    //--- Adam Optimizer moment vectors
    double            m_m_weights_ih[], m_v_weights_ih[];
    double            m_m_weights_ho[], m_v_weights_ho[];
    double            m_m_bias_h[],     m_v_bias_h[];
    double            m_m_bias_o[],     m_v_bias_o[];

    //--- Helper to clip gradients
    double ClipGradient(double grad, double limit)
    {
        if(grad > limit) return limit;
        if(grad < -limit) return -limit;
        return grad;
    }

    //--- Adam update rule for a single parameter
    void AdamUpdate(double &param, double &m, double &v, double grad)
    {
        m = m_beta1 * m + (1.0 - m_beta1) * grad;
        v = m_beta2 * v + (1.0 - m_beta2) * pow(grad, 2);
        double m_hat = m / (1.0 - pow(m_beta1, (double)m_t));
        double v_hat = v / (1.0 - pow(m_beta2, (double)m_t));
        param -= m_learning_rate * m_hat / (sqrt(v_hat) + 1e-8);
    }

    //--- Leaky ReLU activation function
    double LeakyReLU(double x)
    {
        return (x > 0) ? x : 0.01 * x;
    }

    //--- Derivative of Leaky ReLU
    double LeakyReLUDerivative(double x)
    {
        return (x > 0) ? 1.0 : 0.01;
    }

public:
    C_MLP(int inputs, int hidden, int outputs, double lr, double b1, double b2)
    {
        m_input_nodes = inputs;
        m_hidden_nodes = hidden;
        m_output_nodes = outputs;
        m_learning_rate = lr;
        m_beta1 = b1;
        m_beta2 = b2;
        m_t = 0;

        //--- Resize parameter arrays
        ArrayResize(m_weights_ih, m_input_nodes * m_hidden_nodes);
        ArrayResize(m_weights_ho, m_hidden_nodes * m_output_nodes);
        ArrayResize(m_bias_h, m_hidden_nodes);
        ArrayResize(m_bias_o, m_output_nodes);
        
        //--- Resize Adam arrays and initialize to zero
        ArrayResize(m_m_weights_ih, ArraySize(m_weights_ih)); ArrayInitialize(m_m_weights_ih, 0.0);
        ArrayResize(m_v_weights_ih, ArraySize(m_weights_ih)); ArrayInitialize(m_v_weights_ih, 0.0);
        ArrayResize(m_m_weights_ho, ArraySize(m_weights_ho)); ArrayInitialize(m_m_weights_ho, 0.0);
        ArrayResize(m_v_weights_ho, ArraySize(m_weights_ho)); ArrayInitialize(m_v_weights_ho, 0.0);
        ArrayResize(m_m_bias_h, ArraySize(m_bias_h));         ArrayInitialize(m_m_bias_h, 0.0);
        ArrayResize(m_v_bias_h, ArraySize(m_bias_h));         ArrayInitialize(m_v_bias_h, 0.0);
        ArrayResize(m_m_bias_o, ArraySize(m_bias_o));         ArrayInitialize(m_m_bias_o, 0.0);
        ArrayResize(m_v_bias_o, ArraySize(m_bias_o));         ArrayInitialize(m_v_bias_o, 0.0);

        //--- Initialize weights (Xavier/Glorot initialization)
        double ih_limit = sqrt(6.0 / (m_input_nodes + m_hidden_nodes));
        double ho_limit = sqrt(6.0 / (m_hidden_nodes + m_output_nodes));
        for(int i = 0; i < ArraySize(m_weights_ih); i++) m_weights_ih[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * ih_limit;
        for(int i = 0; i < ArraySize(m_weights_ho); i++) m_weights_ho[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * ho_limit;
        ArrayInitialize(m_bias_h, 0.0);
        ArrayInitialize(m_bias_o, 0.0);
        
        Print("MLP Model Initialized.");
    }

    virtual double Train(const double &inputs[], const double &targets[]) override
    {
        m_t++; // Increment Adam timestep

        //--- Forward pass
        double hidden_inputs[], hidden_outputs[], predictions[];
        ArrayResize(hidden_inputs, m_hidden_nodes);
        ArrayResize(hidden_outputs, m_hidden_nodes);
        ArrayResize(predictions, m_output_nodes);

        for(int j = 0; j < m_hidden_nodes; j++)
        {
            double sum = 0.0;
            for(int i = 0; i < m_input_nodes; i++) sum += inputs[i] * m_weights_ih[i * m_hidden_nodes + j];
            hidden_inputs[j] = sum + m_bias_h[j];
            hidden_outputs[j] = LeakyReLU(hidden_inputs[j]);
        }
        for(int j = 0; j < m_output_nodes; j++)
        {
            double sum = 0.0;
            for(int i = 0; i < m_hidden_nodes; i++) sum += hidden_outputs[i] * m_weights_ho[i * m_output_nodes + j];
            predictions[j] = sum + m_bias_o[j]; // Linear output layer
        }

        //--- Calculate error and deltas
        double total_error = 0.0;
        double output_deltas[];
        ArrayResize(output_deltas, m_output_nodes);
        for(int j = 0; j < m_output_nodes; j++)
        {
            //--- CORRECTED GRADIENT CALCULATION FOR MAE ---
            double err = predictions[j] - targets[j];
            total_error += MathAbs(err);
            output_deltas[j] = (err >= 0.0) ? 1.0 : -1.0; // Use the sign of the error, not the magnitude
        }

        //--- Backpropagate error
        double hidden_deltas[];
        ArrayResize(hidden_deltas, m_hidden_nodes);
        for(int i = 0; i < m_hidden_nodes; i++)
        {
            double error = 0.0;
            for(int j = 0; j < m_output_nodes; j++) error += output_deltas[j] * m_weights_ho[i * m_output_nodes + j];
            hidden_deltas[i] = error * LeakyReLUDerivative(hidden_inputs[i]);
        }

        //--- Update weights with Adam
        for(int j = 0; j < m_output_nodes; j++)
        {
            for(int i = 0; i < m_hidden_nodes; i++)
            {
                int idx = i * m_output_nodes + j;
                double grad = ClipGradient(output_deltas[j] * hidden_outputs[i], 1.0);
                AdamUpdate(m_weights_ho[idx], m_m_weights_ho[idx], m_v_weights_ho[idx], grad);
            }
            double bias_grad = ClipGradient(output_deltas[j], 1.0);
            AdamUpdate(m_bias_o[j], m_m_bias_o[j], m_v_bias_o[j], bias_grad);
        }
        for(int j = 0; j < m_hidden_nodes; j++)
        {
            for(int i = 0; i < m_input_nodes; i++)
            {
                int idx = i * m_hidden_nodes + j;
                double grad = ClipGradient(hidden_deltas[j] * inputs[i], 1.0);
                AdamUpdate(m_weights_ih[idx], m_m_weights_ih[idx], m_v_weights_ih[idx], grad);
            }
            double bias_grad = ClipGradient(hidden_deltas[j], 1.0);
            AdamUpdate(m_bias_h[j], m_m_bias_h[j], m_v_bias_h[j], bias_grad);
        }
        
        return total_error / m_output_nodes;
    }

    virtual void Predict(const double &inputs[], double &outputs[]) override
    {
        double hidden_outputs[];
        ArrayResize(hidden_outputs, m_hidden_nodes);
        for(int j = 0; j < m_hidden_nodes; j++)
        {
            double sum = 0.0;
            for(int i = 0; i < m_input_nodes; i++) sum += inputs[i] * m_weights_ih[i * m_hidden_nodes + j];
            hidden_outputs[j] = LeakyReLU(sum + m_bias_h[j]);
        }
        
        ArrayResize(outputs, m_output_nodes);
        for(int j = 0; j < m_output_nodes; j++)
        {
            double sum = 0.0;
            for(int i = 0; i < m_hidden_nodes; i++) sum += hidden_outputs[i] * m_weights_ho[i * m_output_nodes + j];
            outputs[j] = sum + m_bias_o[j];
        }
    }

    virtual bool SaveWeights(const string file_name) override
    {
        int handle = FileOpen(file_name, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(handle == INVALID_HANDLE) return false;

        FileWriteLong(handle, m_t);
        FileWriteArray(handle, m_weights_ih); FileWriteArray(handle, m_weights_ho);
        FileWriteArray(handle, m_bias_h);     FileWriteArray(handle, m_bias_o);
        FileWriteArray(handle, m_m_weights_ih); FileWriteArray(handle, m_v_weights_ih);
        FileWriteArray(handle, m_m_weights_ho); FileWriteArray(handle, m_v_weights_ho);
        FileWriteArray(handle, m_m_bias_h);     FileWriteArray(handle, m_v_bias_h);
        FileWriteArray(handle, m_m_bias_o);     FileWriteArray(handle, m_v_bias_o);
        
        FileClose(handle);
        Print("MLP weights saved to ", file_name);
        return true;
    }

    virtual bool LoadWeights(const string file_name) override
    {
        int handle = FileOpen(file_name, FILE_READ | FILE_BIN | FILE_COMMON);
        if(handle == INVALID_HANDLE) return false;
        
        m_t = FileReadLong(handle);
        FileReadArray(handle, m_weights_ih); FileReadArray(handle, m_weights_ho);
        FileReadArray(handle, m_bias_h);     FileReadArray(handle, m_bias_o);
        FileReadArray(handle, m_m_weights_ih); FileReadArray(handle, m_v_weights_ih);
        FileReadArray(handle, m_m_weights_ho); FileReadArray(handle, m_v_weights_ho);
        FileReadArray(handle, m_m_bias_h);     FileReadArray(handle, m_v_bias_h);
        FileReadArray(handle, m_m_bias_o);     FileReadArray(handle, m_v_bias_o);

        FileClose(handle);
        Print("MLP weights loaded from ", file_name);
        return true;
    }
};
