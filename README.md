# MQL5 Neural Network Library

This repository demonstrates a complete workflow for training and deploying neural networks **directly inside MetaTrader 5**. The goal is to show that the MQL5 language can handle custom machine learning models without relying on external tools.

This proof-of-concept aims to design and implement a reliable workflow for neural network training within the MQL5 ecosystem—an environment that typically lacks native machine learning support. By doing so it enables real-time trading strategies to leverage custom models without external dependencies.

## Project Highlights

- Native training and inference in MQL5
- Serialization of model weights for easy deployment
- Modular design supporting multiple network architectures
- Example Expert Advisor showing how to automate the process

## Supported Architectures

The library currently implements three common network types, all inheriting from the `INeuralNetworkModel` interface:

- **Multilayer Perceptron (MLP)** – a basic feedforward network suitable for simple patterns.
- **Recurrent Neural Network (RNN)** – processes sequences and retains short-term memory.
- **Long Short-Term Memory (LSTM)** – an RNN variant that captures long-range dependencies.

Adding new architectures follows the same interface so the workflow can be extended easily.

## Workflow Overview

The training pipeline consists of four stages:

1. **Training Phase** – Configure the network on the Strategy Tester **Inputs** tab with `TrainMode` set to `true`. Here you choose the architecture, set the training start date and other parameters. Training runs until the MAE target is reached using the Adam optimizer.
   - ![Strategy Tester input panel](https://github.com/user-attachments/assets/80a304b9-5776-4d24-bde7-1837b1d76b8c)
     *Inputs tab for selecting the model, enabling training and defining initial settings.*
   - ![Set training start date](https://github.com/user-attachments/assets/2b5c8b40-2c4a-4a21-8bd3-b6e34ffc6d45)
     *Example of configuring the historical range for learning.*
   - ![Begin training](https://github.com/user-attachments/assets/9adb5dea-e270-4bd9-a541-c28b5a474423)
     *Starting the Strategy Tester to launch the optimization process.*

2. **Persistence Phase** – After training completes, the weights are saved to a binary `.bin` file under the platform's common `Files` directory.
   - ![Open files panel](https://github.com/user-attachments/assets/9e53c48d-95bd-430a-a5b9-185b11738448)
     *Click the **Files** button in MetaEditor to browse generated files.*
   - ![Navigate to common folder](https://github.com/user-attachments/assets/b0499cfd-1ddc-4faf-b200-5ba709587494)
     *Use the **Common Folder** option to access shared data.*
   - ![My_AI_Models folder](https://github.com/user-attachments/assets/0a192530-f810-4758-aa82-ca66bde978f9)
     *Open the `My_AI_Models` directory created by the EA.*
   - ![Saved model binaries](https://github.com/user-attachments/assets/bbeda210-a28b-4385-a02f-2cb102ae5d7f)
     *Each `.bin` file contains the serialized weights for a trained network.*

3. **Model File and Training Log** – The binary file itself appears unreadable if opened directly, which is normal because weights are stored in a compact format. This binary representation loads quickly inside MT5, making it efficient for the workflow.
   - ![Binary weight preview](https://github.com/user-attachments/assets/36cc15b6-558a-4585-89c7-6f0febdeaf72)
     *Example `.bin` file contents shown for demonstration purposes.*
   - ![Training log showing MAE improvement](https://github.com/user-attachments/assets/17e6a260-b695-4dde-9c8c-08ff70959df7)
     *Strategy Tester log illustrates how MAE decreases over epochs.*

4. **Inference Phase** – With `TrainMode` set to `false`, the Expert Advisor loads the saved weights and begins producing live predictions.
   - ![Network predictions during inference](https://github.com/user-attachments/assets/0063f456-dde4-45a3-b504-690732754508)
     *The EA uses the stored model to forecast price movement on new data.*

   

This separation allows you to train once and deploy the same model on any chart or in live trading without modification.

## Repository Layout

```
C_MLP.mqh               // Multi-layer perceptron implementation
C_RNN.mqh               // Simple recurrent network implementation
C_LSTM.mqh              // Long short-term memory implementation
INeuralNetworkModel.mqh // Interface for all models
WorkFlow_test.mq5       // Example Expert Advisor demonstrating the workflow
```

## Getting Started

1. Copy the `.mqh` and `.mq5` files into your platform's `MQL5` directory.
2. Open `WorkFlow_test.mq5` in MetaEditor and adjust parameters as needed (such as training epochs or MAE target).
3. Run the Expert Advisor in Strategy Tester with **TrainMode = true** to generate a weight file.
4. Set **TrainMode = false** and run again on the desired symbol and timeframe to execute live predictions.

Trained weights are stored under `My_AI_Models` inside the platform's common `Files` directory so they can be reused across accounts and charts.

## Feature Engineering

The proof-of-concept uses only two input features—closing price and RSI—but the architecture is designed for easy expansion. Future updates may incorporate additional indicators (MACD, Bollinger Bands, volume) or raw OHLCV data.

## Future Plans

- Support for advanced architectures such as GRU, CNN, or Transformer
- Reinforcement learning agents for dynamic risk management
- A richer library of technical indicators

## License

This code is provided for educational and research purposes. Use it at your own risk when trading live markets.
