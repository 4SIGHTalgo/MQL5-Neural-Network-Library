// ==================================================================
// FILE: C_RNN.mqh
// DESCRIPTION: A Recurrent Neural Network (RNN) implementation that
//              fits the INeuralNetworkModel interface.
//
// FIX: Added gradient clipping inside the BPTT loop to prevent
//      exploding gradients and NaN values.
// ==================================================================
#include <DeepLearning\Util\INeuralNetworkModel.mqh>


class C_RNN : public INeuralNetworkModel
{
private:
    //--- Architecture
    int   m_input_nodes, m_hidden_nodes, m_output_nodes;
    int   m_sequence_length;

    //--- Adam Hyper-parameters
    double m_learning_rate, m_beta1, m_beta2;
    long   m_t; // Adam timestep

    //--- Parameters (Weights & Biases)
    double m_weights_ih[]; // Input -> Hidden
    double m_weights_hh[]; // Hidden -> Hidden (The recurrent connection)
    double m_weights_ho[]; // Hidden -> Output
    double m_bias_h[];     // Hidden bias
    double m_bias_o[];     // Output bias

    //--- Adam Optimizer Moments
    double m_m_weights_ih[], m_v_weights_ih[];
    double m_m_weights_hh[], m_v_weights_hh[];
    double m_m_weights_ho[], m_v_weights_ho[];
    double m_m_bias_h[],     m_v_bias_h[];
    double m_m_bias_o[],     m_v_bias_o[];

    //--- Helper: Clip gradients to prevent explosion
    static double ClipGradient(double g, double lim) { return(g > lim) ? lim : (g < -lim) ? -lim : g; }

    //--- Helper: Adam Optimizer update rule
    void AdamUpdate(double &p, double &m, double &v, double grad)
    {
        m = m_beta1 * m + (1.0 - m_beta1) * grad;
        v = m_beta2 * v + (1.0 - m_beta2) * MathPow(grad, 2);
        double m_hat = m / (1.0 - MathPow(m_beta1, (double)m_t));
        double v_hat = v / (1.0 - MathPow(m_beta2, (double)m_t));
        p -= m_learning_rate * m_hat / (MathSqrt(v_hat) + 1e-8);
    }

    //--- Helper: Tanh activation function (common for RNN hidden states)
    static double Tanh(double x) { return (MathExp(x) - MathExp(-x)) / (MathExp(x) + MathExp(-x)); }
    
    //--- Helper: Derivative of Tanh
    static double TanhDerivative(double x) { return 1.0 - MathPow(x, 2); }

public:
    //--- Constructor
    C_RNN(int inputs, int hidden, int outputs, int sequence_length,
          double lr = 0.001, double b1 = 0.9, double b2 = 0.999)
    {
        m_input_nodes  = inputs;
        m_hidden_nodes = hidden;
        m_output_nodes = outputs;
        m_sequence_length = sequence_length;
        m_learning_rate = lr;
        m_beta1 = b1;
        m_beta2 = b2;
        m_t = 0;

        //--- Resize parameter arrays
        ArrayResize(m_weights_ih, m_input_nodes * m_hidden_nodes);
        ArrayResize(m_weights_hh, m_hidden_nodes * m_hidden_nodes);
        ArrayResize(m_weights_ho, m_hidden_nodes * m_output_nodes);
        ArrayResize(m_bias_h, m_hidden_nodes);
        ArrayResize(m_bias_o, m_output_nodes);

        #define RESIZE_ADAM(arr) ArrayResize(m_m_##arr, ArraySize(m_##arr)); ArrayInitialize(m_m_##arr, 0.0); \
                                 ArrayResize(m_v_##arr, ArraySize(m_##arr)); ArrayInitialize(m_v_##arr, 0.0)
        RESIZE_ADAM(weights_ih); RESIZE_ADAM(weights_hh); RESIZE_ADAM(weights_ho);
        RESIZE_ADAM(bias_h); RESIZE_ADAM(bias_o);
        #undef RESIZE_ADAM

        #define INIT_WEIGHTS(arr, n_in, n_out) \
            double limit_##arr = MathSqrt(6.0 / (n_in + n_out)); \
            for(int i = 0; i < ArraySize(m_##arr); ++i) m_##arr[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * limit_##arr
        INIT_WEIGHTS(weights_ih, m_input_nodes, m_hidden_nodes);
        INIT_WEIGHTS(weights_hh, m_hidden_nodes, m_hidden_nodes);
        INIT_WEIGHTS(weights_ho, m_hidden_nodes, m_output_nodes);
        #undef INIT_WEIGHTS

        ArrayInitialize(m_bias_h, 0.0);
        ArrayInitialize(m_bias_o, 0.0);

        Print("RNN Model initialized: ", m_input_nodes, "-", m_hidden_nodes, "-", m_output_nodes, " Sequence: ", m_sequence_length);
    }

    virtual double Train(const double &inputs[], const double &targets[]) override
    {
        m_t++;

        //--- Use a 1D array to simulate a 2D array for hidden states
        double hidden_states[];
        ArrayResize(hidden_states, (m_sequence_length + 1) * m_hidden_nodes);
        ArrayInitialize(hidden_states, 0.0);

        for(int t = 0; t < m_sequence_length; ++t)
        {
            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                double sum = 0.0;
                for(int i = 0; i < m_input_nodes; ++i) sum += inputs[t * m_input_nodes + i] * m_weights_ih[i * m_hidden_nodes + j];
                for(int k = 0; k < m_hidden_nodes; ++k) sum += hidden_states[t * m_hidden_nodes + k] * m_weights_hh[k * m_hidden_nodes + j];
                hidden_states[(t + 1) * m_hidden_nodes + j] = Tanh(sum + m_bias_h[j]);
            }
        }

        double predictions[];
        ArrayResize(predictions, m_output_nodes);
        for(int j = 0; j < m_output_nodes; ++j)
        {
            double sum = 0.0;
            for(int i = 0; i < m_hidden_nodes; ++i) sum += hidden_states[m_sequence_length * m_hidden_nodes + i] * m_weights_ho[i * m_output_nodes + j];
            predictions[j] = sum + m_bias_o[j];
        }

        double total_error = 0.0;
        double output_deltas[];
        ArrayResize(output_deltas, m_output_nodes);
        for(int j = 0; j < m_output_nodes; ++j)
        {
            //--- CORRECTED GRADIENT CALCULATION FOR MAE ---
            double err = predictions[j] - targets[j];
            total_error += MathAbs(err);
            output_deltas[j] = (err >= 0.0) ? 1.0 : -1.0;
        }

        double ih_grads[], hh_grads[], ho_grads[], h_bias_grads[], o_bias_grads[];
        ArrayResize(ih_grads, ArraySize(m_weights_ih)); ArrayInitialize(ih_grads, 0.0);
        ArrayResize(hh_grads, ArraySize(m_weights_hh)); ArrayInitialize(hh_grads, 0.0);
        ArrayResize(ho_grads, ArraySize(m_weights_ho)); ArrayInitialize(ho_grads, 0.0);
        ArrayResize(h_bias_grads, ArraySize(m_bias_h)); ArrayInitialize(h_bias_grads, 0.0);
        ArrayResize(o_bias_grads, ArraySize(m_bias_o)); ArrayInitialize(o_bias_grads, 0.0);

        for(int j = 0; j < m_output_nodes; ++j)
        {
            for(int i = 0; i < m_hidden_nodes; ++i) ho_grads[i * m_output_nodes + j] += output_deltas[j] * hidden_states[m_sequence_length * m_hidden_nodes + i];
            o_bias_grads[j] += output_deltas[j];
        }

        double next_hidden_delta[];
        ArrayResize(next_hidden_delta, m_hidden_nodes);
        for(int i = 0; i < m_hidden_nodes; ++i)
        {
            for(int j = 0; j < m_output_nodes; ++j) next_hidden_delta[i] += output_deltas[j] * m_weights_ho[i * m_output_nodes + j];
        }

        for(int t = m_sequence_length - 1; t >= 0; --t)
        {
            double hidden_delta[];
            ArrayResize(hidden_delta, m_hidden_nodes);
            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                double tanh_deriv = TanhDerivative(hidden_states[(t + 1) * m_hidden_nodes + j]);
                hidden_delta[j] = next_hidden_delta[j] * tanh_deriv;
                // --- FIX: Clip the gradient at each timestep to prevent explosion ---
                hidden_delta[j] = ClipGradient(hidden_delta[j], 1.0);
            }

            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                h_bias_grads[j] += hidden_delta[j];
                for(int i = 0; i < m_input_nodes; ++i) ih_grads[i * m_hidden_nodes + j] += hidden_delta[j] * inputs[t * m_input_nodes + i];
                for(int k = 0; k < m_hidden_nodes; ++k) hh_grads[k * m_hidden_nodes + j] += hidden_delta[j] * hidden_states[t * m_hidden_nodes + k];
            }
            
            double prev_hidden_delta[];
            ArrayResize(prev_hidden_delta, m_hidden_nodes);
            ArrayInitialize(prev_hidden_delta, 0.0);
            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                for(int k = 0; k < m_hidden_nodes; ++k) prev_hidden_delta[j] += hidden_delta[k] * m_weights_hh[j * m_hidden_nodes + k];
            }
            ArrayCopy(next_hidden_delta, prev_hidden_delta);
        }

        #define UPDATE_PARAMS(arr, grads) for(int i=0; i<ArraySize(m_##arr); ++i) AdamUpdate(m_##arr[i], m_m_##arr[i], m_v_##arr[i], ClipGradient(grads[i], 1.0))
        UPDATE_PARAMS(weights_ih, ih_grads); UPDATE_PARAMS(weights_hh, hh_grads); UPDATE_PARAMS(weights_ho, ho_grads);
        UPDATE_PARAMS(bias_h, h_bias_grads); UPDATE_PARAMS(bias_o, o_bias_grads);
        #undef UPDATE_PARAMS

        return total_error / (double)m_output_nodes;
    }

    virtual void Predict(const double &inputs[], double &outputs[]) override
    {
        double hidden_state[];
        ArrayResize(hidden_state, m_hidden_nodes);
        ArrayInitialize(hidden_state, 0.0);

        for(int t = 0; t < m_sequence_length; ++t)
        {
            double next_hidden_state[];
            ArrayResize(next_hidden_state, m_hidden_nodes);
            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                double sum = 0.0;
                for(int i = 0; i < m_input_nodes; ++i) sum += inputs[t * m_input_nodes + i] * m_weights_ih[i * m_hidden_nodes + j];
                for(int k = 0; k < m_hidden_nodes; ++k) sum += hidden_state[k] * m_weights_hh[k * m_hidden_nodes + j];
                next_hidden_state[j] = Tanh(sum + m_bias_h[j]);
            }
            ArrayCopy(hidden_state, next_hidden_state);
        }

        ArrayResize(outputs, m_output_nodes);
        for(int j = 0; j < m_output_nodes; ++j)
        {
            double sum = 0.0;
            for(int i = 0; i < m_hidden_nodes; ++i) sum += hidden_state[i] * m_weights_ho[i * m_output_nodes + j];
            outputs[j] = sum + m_bias_o[j];
        }
    }

    virtual bool SaveWeights(const string file_name) override
    {
        int fh = FileOpen(file_name, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE) return false;

        FileWriteLong(fh, m_t);
        #define WRITE_ARRAY(arr) FileWriteArray(fh, m_##arr)
        WRITE_ARRAY(weights_ih); WRITE_ARRAY(weights_hh); WRITE_ARRAY(weights_ho);
        WRITE_ARRAY(bias_h); WRITE_ARRAY(bias_o);
        WRITE_ARRAY(m_weights_ih); WRITE_ARRAY(v_weights_ih);
        WRITE_ARRAY(m_weights_hh); WRITE_ARRAY(v_weights_hh);
        WRITE_ARRAY(m_weights_ho); WRITE_ARRAY(v_weights_ho);
        WRITE_ARRAY(m_bias_h); WRITE_ARRAY(v_bias_h);
        WRITE_ARRAY(m_bias_o); WRITE_ARRAY(v_bias_o);
        #undef WRITE_ARRAY
        
        FileClose(fh);
        Print("RNN weights saved to ", file_name);
        return true;
    }

    virtual bool LoadWeights(const string file_name) override
    {
        int fh = FileOpen(file_name, FILE_READ | FILE_BIN| FILE_COMMON);
        if(fh == INVALID_HANDLE) return false;

        m_t = FileReadLong(fh);
        #define READ_ARRAY(arr) FileReadArray(fh, m_##arr)
        READ_ARRAY(weights_ih); READ_ARRAY(weights_hh); READ_ARRAY(weights_ho);
        READ_ARRAY(bias_h); READ_ARRAY(bias_o);
        READ_ARRAY(m_weights_ih); READ_ARRAY(v_weights_ih);
        READ_ARRAY(m_weights_hh); READ_ARRAY(v_weights_hh);
        READ_ARRAY(m_weights_ho); READ_ARRAY(v_weights_ho);
        READ_ARRAY(m_bias_h); READ_ARRAY(v_bias_h);
        READ_ARRAY(m_bias_o); READ_ARRAY(v_bias_o);
        #undef READ_ARRAY

        FileClose(fh);
        Print("RNN weights loaded from ", file_name);
        return true;
    }
};
