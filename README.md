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

The training pipeline consists of three stages:

1. **Training Phase** – With `TrainMode` set to `true`, historical closing prices and the RSI indicator are used as features. Training continues until the network reaches a minimum MAE using the Adam optimizer.
![Screenshot 2025-07-09 141805](https://github.com/user-attachments/assets/80a304b9-5776-4d24-bde7-1837b1d76b8c)
![Screenshot 2025-07-09 141815](https://github.com/user-attachments/assets/2b5c8b40-2c4a-4a21-8bd3-b6e34ffc6d45)
![Screenshot 2025-07-09 141833](https://github.com/user-attachments/assets/9adb5dea-e270-4bd9-a541-c28b5a474423)
2. **Persistence Phase** – Once the model performs well, weights and biases are saved to a binary file in the shared `Files` folder. This file can be reused across Strategy Tester and live sessions.
![Screenshot 2025-07-09 141932](https://github.com/user-attachments/assets/0a192530-f810-4758-aa82-ca66bde978f9)


![Screenshot 2025-07-09 141920](https://github.com/user-attachments/assets/b0499cfd-1ddc-4faf-b200-5ba709587494)


![Screenshot 2025-07-09 141853](https://github.com/user-attachments/assets/9e53c48d-95bd-430a-a5b9-185b11738448)


![Screenshot 2025-07-09 141955](https://github.com/user-attachments/assets/36cc15b6-558a-4585-89c7-6f0febdeaf72)


![Screenshot 2025-07-09 141948](https://github.com/user-attachments/assets/bbeda210-a28b-4385-a02f-2cb102ae5d7f)


4. **Inference Phase** – When `TrainMode` is `false`, the Expert Advisor loads the saved weights, reconstructs the network, and begins making real-time predictions. Trade logic can then act on these forecasts.
![Screenshot 2025-07-09 142009](https://github.com/user-attachments/assets/17e6a260-b695-4dde-9c8c-08ff70959df7)
![Screenshot 2025-07-09 143142](https://github.com/user-attachments/assets/0063f456-dde4-45a3-b504-690732754508)

   

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
