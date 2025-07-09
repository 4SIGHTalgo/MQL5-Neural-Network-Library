//+------------------------------------------------------------------+
//|                                        INeuralNetworkModel.mqh   |
//|      Interface for all neural network model implementations.     |
//+------------------------------------------------------------------+
#ifndef INEURALNETWORKMODEL_MQH
#define INEURALNETWORKMODEL_MQH

class INeuralNetworkModel
{
public:
    //--- Performs a single training step on a batch of data
    virtual double Train(const double &dataset[], const double &targets[]) = 0;

    //--- Makes a prediction based on a single input
    virtual void Predict(const double &inputs[], double &outputs[]) = 0;

    //--- Saves the model's state (weights, optimizer moments) to a file
    virtual bool SaveWeights(const string file_name) = 0;

    //--- Loads the model's state from a file
    virtual bool LoadWeights(const string file_name) = 0;
};

#endif // INEURALNETWORKMODEL_MQH
