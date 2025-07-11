// ==================================================================
// FILE: C_LSTM.mqh
// DESCRIPTION: A Long Short-Term Memory (LSTM) network implementation
//              with full Backpropagation Through Time (BPTT).
//              MODIFICATION: Added weight clipping to Adam optimizer.
// ==================================================================
#include <DeepLearning\Util\INeuralNetworkModel.mqh>

class C_LSTM : public INeuralNetworkModel
{
private:
    //--- Architecture
    int    m_input_nodes, m_hidden_nodes, m_output_nodes;
    int    m_sequence_length;

    //--- Adam Hyper-parameters
    double m_learning_rate, m_beta1, m_beta2;
    long   m_t; // Adam timestep

    //--- LSTM parameters for Forget, Input, Cell Candidate, and Output gates
    #define LSTM_PARAMS(name) double m_weights_i##name[], m_weights_h##name[], m_bias_##name[]
    LSTM_PARAMS(f); LSTM_PARAMS(i); LSTM_PARAMS(c); LSTM_PARAMS(o);
    #undef LSTM_PARAMS
    
    //--- Final output layer parameters
    double m_weights_ho_final[], m_bias_o_final[];

    //--- Adam Optimizer Moments for all parameters
    #define ADAM_MOMENTS(name) double m_m_##name[], m_v_##name[]
    ADAM_MOMENTS(weights_if); ADAM_MOMENTS(weights_ii); ADAM_MOMENTS(weights_ic); ADAM_MOMENTS(weights_io);
    ADAM_MOMENTS(weights_hf); ADAM_MOMENTS(weights_hi); ADAM_MOMENTS(weights_hc); ADAM_MOMENTS(weights_ho);
    ADAM_MOMENTS(weights_ho_final);
    ADAM_MOMENTS(bias_f); ADAM_MOMENTS(bias_i); ADAM_MOMENTS(bias_c); ADAM_MOMENTS(bias_o); ADAM_MOMENTS(bias_o_final);
    #undef ADAM_MOMENTS

    //--- Helper: Clip gradients
    static double ClipGradient(double g, double lim) { return(g > lim) ? lim : (g < -lim) ? -lim : g; }

    // ---- NEW: keep parameters bounded too
    static double ClipWeight(double w, const double lim = 5.0)
    {
       return (w > lim) ? lim : (w < -lim) ? -lim : w;
    }

    //--- Helper: Adam Optimizer update rule
    void AdamUpdate(double &p, double &m, double &v, double grad)
    {
        m = m_beta1 * m + (1.0 - m_beta1) * grad;
        v = m_beta2 * v + (1.0 - m_beta2) * MathPow(grad, 2);
        double m_hat = m / (1.0 - MathPow(m_beta1, (double)m_t));
        double v_hat = v / (1.0 - MathPow(m_beta2, (double)m_t));
        p -= m_learning_rate * m_hat / (MathSqrt(v_hat) + 1e-8);
        p = ClipWeight(p);          // <── keeps weights in a sane range
    }

    //--- Activation functions
    static double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
    static double SigmoidDerivative(double sig_x) { return sig_x * (1.0 - sig_x); }
    static double Tanh(double x) { return (MathExp(x) - MathExp(-x)) / (MathExp(x) + MathExp(-x)); }
    static double TanhDerivative(double tanh_x) { return 1.0 - MathPow(tanh_x, 2); }

public:
    //--- Constructor
    C_LSTM(int inputs, int hidden, int outputs, int sequence_length,
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

        #define RESIZE_GATE_PARAMS(gate) \
            ArrayResize(m_weights_i##gate, m_input_nodes * m_hidden_nodes); \
            ArrayResize(m_weights_h##gate, m_hidden_nodes * m_hidden_nodes); \
            ArrayResize(m_bias_##gate, m_hidden_nodes)
        RESIZE_GATE_PARAMS(f); RESIZE_GATE_PARAMS(i); RESIZE_GATE_PARAMS(c); RESIZE_GATE_PARAMS(o);
        #undef RESIZE_GATE_PARAMS

        ArrayResize(m_weights_ho_final, m_hidden_nodes * m_output_nodes);
        ArrayResize(m_bias_o_final, m_output_nodes);

        #define RESIZE_ADAM(name) ArrayResize(m_m_##name, ArraySize(m_##name)); ArrayInitialize(m_m_##name, 0.0); \
                                  ArrayResize(m_v_##name, ArraySize(m_##name)); ArrayInitialize(m_v_##name, 0.0)
        RESIZE_ADAM(weights_if); RESIZE_ADAM(weights_ii); RESIZE_ADAM(weights_ic); RESIZE_ADAM(weights_io);
        RESIZE_ADAM(weights_hf); RESIZE_ADAM(weights_hi); RESIZE_ADAM(weights_hc); RESIZE_ADAM(weights_ho);
        RESIZE_ADAM(weights_ho_final);
        RESIZE_ADAM(bias_f); RESIZE_ADAM(bias_i); RESIZE_ADAM(bias_c); RESIZE_ADAM(bias_o); RESIZE_ADAM(bias_o_final);
        #undef RESIZE_ADAM
        
        #define INIT_WEIGHTS(name, n_in, n_out) \
            double limit_##name = MathSqrt(6.0 / (n_in + n_out)); \
            for(int k = 0; k < ArraySize(m_weights_##name); ++k) m_weights_##name[k] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * limit_##name
        INIT_WEIGHTS(if, m_input_nodes, m_hidden_nodes); INIT_WEIGHTS(ii, m_input_nodes, m_hidden_nodes);
        INIT_WEIGHTS(ic, m_input_nodes, m_hidden_nodes); INIT_WEIGHTS(io, m_input_nodes, m_hidden_nodes);
        INIT_WEIGHTS(hf, m_hidden_nodes, m_hidden_nodes); INIT_WEIGHTS(hi, m_hidden_nodes, m_hidden_nodes);
        INIT_WEIGHTS(hc, m_hidden_nodes, m_hidden_nodes); INIT_WEIGHTS(ho, m_hidden_nodes, m_hidden_nodes);
        INIT_WEIGHTS(ho_final, m_hidden_nodes, m_output_nodes);
        #undef INIT_WEIGHTS

        ArrayInitialize(m_bias_f, 1.0); ArrayInitialize(m_bias_i, 0.0);
        ArrayInitialize(m_bias_c, 0.0); ArrayInitialize(m_bias_o, 0.0);
        ArrayInitialize(m_bias_o_final, 0.0);

        Print("LSTM Model initialized.");
    }

    virtual double Train(const double &inputs[], const double &targets[]) override
    {
        m_t++;

        //--- Forward Pass Cache
        double hidden_states[], cell_states[], f_gates[], i_gates[], c_gates[], o_gates[];
        ArrayResize(hidden_states, (m_sequence_length + 1) * m_hidden_nodes); ArrayInitialize(hidden_states, 0.0);
        ArrayResize(cell_states, (m_sequence_length + 1) * m_hidden_nodes);   ArrayInitialize(cell_states, 0.0);
        ArrayResize(f_gates, m_sequence_length * m_hidden_nodes);
        ArrayResize(i_gates, m_sequence_length * m_hidden_nodes);
        ArrayResize(c_gates, m_sequence_length * m_hidden_nodes);
        ArrayResize(o_gates, m_sequence_length * m_hidden_nodes);

        //--- 1. Forward Pass
        for(int t = 0; t < m_sequence_length; ++t)
        {
            int h_prev_idx = t * m_hidden_nodes;
            int c_prev_idx = t * m_hidden_nodes;
            int h_curr_idx = (t + 1) * m_hidden_nodes;
            int c_curr_idx = (t + 1) * m_hidden_nodes;

            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                double f_sum=m_bias_f[j], i_sum=m_bias_i[j], c_sum=m_bias_c[j], o_sum=m_bias_o[j];
                for(int i=0; i<m_input_nodes; ++i)
                {
                    double input_val = inputs[t*m_input_nodes+i];
                    f_sum += input_val * m_weights_if[i*m_hidden_nodes+j]; i_sum += input_val * m_weights_ii[i*m_hidden_nodes+j];
                    c_sum += input_val * m_weights_ic[i*m_hidden_nodes+j]; o_sum += input_val * m_weights_io[i*m_hidden_nodes+j];
                }
                for(int k=0; k<m_hidden_nodes; ++k)
                {
                    double h_prev = hidden_states[h_prev_idx+k];
                    f_sum += h_prev * m_weights_hf[k*m_hidden_nodes+j]; i_sum += h_prev * m_weights_hi[k*m_hidden_nodes+j];
                    c_sum += h_prev * m_weights_hc[k*m_hidden_nodes+j]; o_sum += h_prev * m_weights_ho[k*m_hidden_nodes+j];
                }
                f_gates[h_prev_idx+j] = Sigmoid(f_sum); i_gates[h_prev_idx+j] = Sigmoid(i_sum);
                c_gates[h_prev_idx+j] = Tanh(c_sum);   o_gates[h_prev_idx+j] = Sigmoid(o_sum);
                cell_states[c_curr_idx+j] = f_gates[h_prev_idx+j] * cell_states[c_prev_idx+j] + i_gates[h_prev_idx+j] * c_gates[h_prev_idx+j];
                hidden_states[h_curr_idx+j] = o_gates[h_prev_idx+j] * Tanh(cell_states[c_curr_idx+j]);
            }
        }

        double predictions[]; ArrayResize(predictions, m_output_nodes);
        for(int j=0; j<m_output_nodes; ++j)
        {
            double sum=0.0;
            for(int i=0; i<m_hidden_nodes; ++i) sum += hidden_states[m_sequence_length*m_hidden_nodes+i] * m_weights_ho_final[i*m_output_nodes+j];
            predictions[j] = sum + m_bias_o_final[j];
        }

        //--- 2. Calculate Initial Error
        double total_error=0.0; double output_deltas[]; ArrayResize(output_deltas, m_output_nodes);
        for(int j=0; j<m_output_nodes; ++j)
        {
            double err = predictions[j] - targets[j];
            total_error += MathAbs(err);
            output_deltas[j] = (err >= 0.0) ? 1.0 : -1.0;
        }

        //--- 3. Backward Pass (BPTT)
        #define ZERO_GRADS(name) double d_##name[]; ArrayResize(d_##name, ArraySize(m_##name)); ArrayInitialize(d_##name, 0.0)
        ZERO_GRADS(weights_if); ZERO_GRADS(weights_ii); ZERO_GRADS(weights_ic); ZERO_GRADS(weights_io);
        ZERO_GRADS(weights_hf); ZERO_GRADS(weights_hi); ZERO_GRADS(weights_hc); ZERO_GRADS(weights_ho);
        ZERO_GRADS(weights_ho_final);
        ZERO_GRADS(bias_f); ZERO_GRADS(bias_i); ZERO_GRADS(bias_c); ZERO_GRADS(bias_o); ZERO_GRADS(bias_o_final);
        #undef ZERO_GRADS

        for(int j=0; j<m_output_nodes; ++j)
        {
            for(int i=0; i<m_hidden_nodes; ++i) d_weights_ho_final[i*m_output_nodes+j] += output_deltas[j] * hidden_states[m_sequence_length*m_hidden_nodes+i];
            d_bias_o_final[j] += output_deltas[j];
        }

        double dh_next[], dc_next[]; ArrayResize(dh_next, m_hidden_nodes); ArrayInitialize(dh_next, 0.0);
        ArrayResize(dc_next, m_hidden_nodes); ArrayInitialize(dc_next, 0.0);
        for(int i=0; i<m_hidden_nodes; ++i)
        {
            for(int j=0; j<m_output_nodes; ++j) dh_next[i] += output_deltas[j] * m_weights_ho_final[i*m_output_nodes+j];
        }

        for(int t = m_sequence_length - 1; t >= 0; --t)
        {
            int h_curr_idx = (t+1)*m_hidden_nodes, h_prev_idx = t*m_hidden_nodes;
            int c_curr_idx = (t+1)*m_hidden_nodes, c_prev_idx = t*m_hidden_nodes;

            double dh[], dc[]; ArrayResize(dh, m_hidden_nodes); ArrayResize(dc, m_hidden_nodes);
            for(int j=0; j<m_hidden_nodes; ++j) { dh[j] = dh_next[j]; dc[j] = dc_next[j]; }

            double df[], di[], dg[], d_o[]; ArrayResize(df, m_hidden_nodes); ArrayResize(di, m_hidden_nodes);
            ArrayResize(dg, m_hidden_nodes); ArrayResize(d_o, m_hidden_nodes);

            for(int j=0; j<m_hidden_nodes; ++j)
            {
                d_o[j] = dh[j] * Tanh(cell_states[c_curr_idx+j]) * SigmoidDerivative(o_gates[h_prev_idx+j]);
                dc[j] += dh[j] * o_gates[h_prev_idx+j] * TanhDerivative(Tanh(cell_states[c_curr_idx+j]));
                df[j] = dc[j] * cell_states[c_prev_idx+j] * SigmoidDerivative(f_gates[h_prev_idx+j]);
                di[j] = dc[j] * c_gates[h_prev_idx+j] * SigmoidDerivative(i_gates[h_prev_idx+j]);
                dg[j] = dc[j] * i_gates[h_prev_idx+j] * TanhDerivative(c_gates[h_prev_idx+j]);
            }

            for(int j=0; j<m_hidden_nodes; ++j)
            {
                d_bias_f[j] += df[j]; d_bias_i[j] += di[j]; d_bias_c[j] += dg[j]; d_bias_o[j] += d_o[j];
                for(int i=0; i<m_input_nodes; ++i)
                {
                    double input_val = inputs[t*m_input_nodes+i];
                    d_weights_if[i*m_hidden_nodes+j] += df[j] * input_val; d_weights_ii[i*m_hidden_nodes+j] += di[j] * input_val;
                    d_weights_ic[i*m_hidden_nodes+j] += dg[j] * input_val; d_weights_io[i*m_hidden_nodes+j] += d_o[j] * input_val;
                }
                for(int k=0; k<m_hidden_nodes; ++k)
                {
                    double h_prev = hidden_states[h_prev_idx+k];
                    d_weights_hf[k*m_hidden_nodes+j] += df[j] * h_prev; d_weights_hi[k*m_hidden_nodes+j] += di[j] * h_prev;
                    d_weights_hc[k*m_hidden_nodes+j] += dg[j] * h_prev; d_weights_ho[k*m_hidden_nodes+j] += d_o[j] * h_prev;
                }
            }

            ArrayInitialize(dh_next, 0.0); ArrayInitialize(dc_next, 0.0);
            for(int j=0; j<m_hidden_nodes; ++j)
            {
                dc_next[j] = dc[j] * f_gates[h_prev_idx+j];
                for(int k=0; k<m_hidden_nodes; ++k)
                {
                    dh_next[j] += df[k]*m_weights_hf[j*m_hidden_nodes+k] + di[k]*m_weights_hi[j*m_hidden_nodes+k] +
                                  dg[k]*m_weights_hc[j*m_hidden_nodes+k] + d_o[k]*m_weights_ho[j*m_hidden_nodes+k];
                }
            }
        }

        //--- 4. Update all weights using Adam
        #define UPDATE_GATE(gate) \
            for(int k=0; k<ArraySize(m_weights_i##gate); ++k) AdamUpdate(m_weights_i##gate[k], m_m_weights_i##gate[k], m_v_weights_i##gate[k], ClipGradient(d_weights_i##gate[k], 1.0)); \
            for(int k=0; k<ArraySize(m_weights_h##gate); ++k) AdamUpdate(m_weights_h##gate[k], m_m_weights_h##gate[k], m_v_weights_h##gate[k], ClipGradient(d_weights_h##gate[k], 1.0)); \
            for(int k=0; k<ArraySize(m_bias_##gate); ++k) AdamUpdate(m_bias_##gate[k], m_m_bias_##gate[k], m_v_bias_##gate[k], ClipGradient(d_bias_##gate[k], 1.0));
        UPDATE_GATE(f); UPDATE_GATE(i); UPDATE_GATE(c); UPDATE_GATE(o);
        #undef UPDATE_GATE
        
        for(int k=0; k<ArraySize(m_weights_ho_final); ++k) AdamUpdate(m_weights_ho_final[k], m_m_weights_ho_final[k], m_v_weights_ho_final[k], ClipGradient(d_weights_ho_final[k], 1.0));
        for(int k=0; k<ArraySize(m_bias_o_final); ++k) AdamUpdate(m_bias_o_final[k], m_m_bias_o_final[k], m_v_bias_o_final[k], ClipGradient(d_bias_o_final[k], 1.0));

        return total_error / (double)m_output_nodes;
    }

    virtual void Predict(const double &inputs[], double &outputs[]) override
    {
        double hidden_state[], cell_state[];
        ArrayResize(hidden_state, m_hidden_nodes); ArrayInitialize(hidden_state, 0.0);
        ArrayResize(cell_state, m_hidden_nodes);   ArrayInitialize(cell_state, 0.0);
        
        for(int t = 0; t < m_sequence_length; ++t)
        {
            double next_hidden[], next_cell[]; ArrayResize(next_hidden, m_hidden_nodes); ArrayResize(next_cell, m_hidden_nodes);
            for(int j = 0; j < m_hidden_nodes; ++j)
            {
                double f_sum=m_bias_f[j], i_sum=m_bias_i[j], c_sum=m_bias_c[j], o_sum=m_bias_o[j];
                for(int i=0; i<m_input_nodes; ++i)
                {
                    double input_val = inputs[t*m_input_nodes+i];
                    f_sum += input_val * m_weights_if[i*m_hidden_nodes+j]; i_sum += input_val * m_weights_ii[i*m_hidden_nodes+j];
                    c_sum += input_val * m_weights_ic[i*m_hidden_nodes+j]; o_sum += input_val * m_weights_io[i*m_hidden_nodes+j];
                }
                for(int k=0; k<m_hidden_nodes; ++k)
                {
                    double h_prev = hidden_state[k];
                    f_sum += h_prev * m_weights_hf[k*m_hidden_nodes+j]; i_sum += h_prev * m_weights_hi[k*m_hidden_nodes+j];
                    c_sum += h_prev * m_weights_hc[k*m_hidden_nodes+j]; o_sum += h_prev * m_weights_ho[k*m_hidden_nodes+j];
                }
                double f = Sigmoid(f_sum), i = Sigmoid(i_sum), g = Tanh(c_sum), o = Sigmoid(o_sum);
                next_cell[j] = f * cell_state[j] + i * g;
                next_hidden[j] = o * Tanh(next_cell[j]);
            }
            ArrayCopy(hidden_state, next_hidden); ArrayCopy(cell_state, next_cell);
        }

        ArrayResize(outputs, m_output_nodes);
        for(int j = 0; j < m_output_nodes; ++j)
        {
            double sum = 0.0;
            for(int i = 0; i < m_hidden_nodes; ++i) sum += hidden_state[i] * m_weights_ho_final[i * m_output_nodes + j];
            outputs[j] = sum + m_bias_o_final[j];
        }
    }

    virtual bool SaveWeights(const string file_name) override
    {
        int fh = FileOpen(file_name, FILE_WRITE | FILE_BIN | FILE_COMMON) ;
        if(fh == INVALID_HANDLE) return false;
        FileWriteLong(fh, m_t);
        #define WRITE_ARRAY(name) FileWriteArray(fh, m_##name)
        WRITE_ARRAY(weights_if); WRITE_ARRAY(weights_ii); WRITE_ARRAY(weights_ic); WRITE_ARRAY(weights_io);
        WRITE_ARRAY(weights_hf); WRITE_ARRAY(weights_hi); WRITE_ARRAY(weights_hc); WRITE_ARRAY(weights_ho);
        WRITE_ARRAY(weights_ho_final);
        WRITE_ARRAY(bias_f); WRITE_ARRAY(bias_i); WRITE_ARRAY(bias_c); WRITE_ARRAY(bias_o); WRITE_ARRAY(bias_o_final);
        WRITE_ARRAY(m_weights_if); WRITE_ARRAY(v_weights_if); WRITE_ARRAY(m_weights_ii); WRITE_ARRAY(v_weights_ii);
        WRITE_ARRAY(m_weights_ic); WRITE_ARRAY(v_weights_ic); WRITE_ARRAY(m_weights_io); WRITE_ARRAY(v_weights_io);
        WRITE_ARRAY(m_weights_hf); WRITE_ARRAY(v_weights_hf); WRITE_ARRAY(m_weights_hi); WRITE_ARRAY(v_weights_hi);
        WRITE_ARRAY(m_weights_hc); WRITE_ARRAY(v_weights_hc); WRITE_ARRAY(m_weights_ho); WRITE_ARRAY(v_weights_ho);
        WRITE_ARRAY(m_weights_ho_final); WRITE_ARRAY(v_weights_ho_final);
        WRITE_ARRAY(m_bias_f); WRITE_ARRAY(v_bias_f); WRITE_ARRAY(m_bias_i); WRITE_ARRAY(v_bias_i);
        WRITE_ARRAY(m_bias_c); WRITE_ARRAY(v_bias_c); WRITE_ARRAY(m_bias_o); WRITE_ARRAY(v_bias_o);
        WRITE_ARRAY(m_bias_o_final); WRITE_ARRAY(v_bias_o_final);
        #undef WRITE_ARRAY
        FileClose(fh);
        Print("LSTM weights saved to ", file_name);
        return true;
    }

    virtual bool LoadWeights(const string file_name) override
    {
        int fh = FileOpen(file_name, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE) return false;
        m_t = FileReadLong(fh);
        #define READ_ARRAY(name) FileReadArray(fh, m_##name)
        READ_ARRAY(weights_if); READ_ARRAY(weights_ii); READ_ARRAY(weights_ic); READ_ARRAY(weights_io);
        READ_ARRAY(weights_hf); READ_ARRAY(weights_hi); READ_ARRAY(weights_hc); READ_ARRAY(weights_ho);
        READ_ARRAY(weights_ho_final);
        READ_ARRAY(bias_f); READ_ARRAY(bias_i); READ_ARRAY(bias_c); READ_ARRAY(bias_o); READ_ARRAY(bias_o_final);
        READ_ARRAY(m_weights_if); READ_ARRAY(v_weights_if); READ_ARRAY(m_weights_ii); READ_ARRAY(v_weights_ii);
        READ_ARRAY(m_weights_ic); READ_ARRAY(v_weights_ic); READ_ARRAY(m_weights_io); READ_ARRAY(v_weights_io);
        READ_ARRAY(m_weights_hf); READ_ARRAY(v_weights_hf); READ_ARRAY(m_weights_hi); READ_ARRAY(v_weights_hi);
        READ_ARRAY(m_weights_hc); READ_ARRAY(v_weights_hc); READ_ARRAY(m_weights_ho); READ_ARRAY(v_weights_ho);
        READ_ARRAY(m_weights_ho_final); READ_ARRAY(v_weights_ho_final);
        READ_ARRAY(m_bias_f); READ_ARRAY(v_bias_f); READ_ARRAY(m_bias_i); READ_ARRAY(v_bias_i);
        READ_ARRAY(m_bias_c); READ_ARRAY(v_bias_c); READ_ARRAY(m_bias_o); READ_ARRAY(v_bias_o);
        READ_ARRAY(m_bias_o_final); READ_ARRAY(v_bias_o_final);
        #undef READ_ARRAY
        FileClose(fh);
        Print("LSTM weights loaded from ", file_name);
        return true;
    }
};
