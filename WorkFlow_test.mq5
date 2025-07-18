// ==================================================================
// FILE 4: Main_EA.mq5 (Predicting Price Delta Only)
// DESCRIPTION: The main EA, modified ONLY to predict price deltas.
// MODIFICATION:
// 1. Prediction target and primary feature is now price change (delta).
// 2. Trading logic remains the same as the original, but uses the
//    predicted delta to forecast the next price.
// 3. Removed added risk management inputs (SL, TP, Threshold).
// ==================================================================
#include <DeepLearning\Architectures\C_MLP.mqh>
#include <DeepLearning\Architectures\C_RNN.mqh>
#include <DeepLearning\Architectures\C_LSTM.mqh>

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade          m_Trade;
CPositionInfo   m_Position;

//--- ──── GLOBAL SAFETY UTILS ────
#define EPS      (1e-8)

inline bool IsFiniteNumber(const double x)
{
   return (x == x) && (MathAbs(x) < DBL_MAX / 2) && (x != EMPTY_VALUE);
}

inline double NormalizeValue(const double v, const double min_v, const double max_v)
{
   if(!IsFiniteNumber(v) || max_v - min_v < EPS)
      return 0.0;
   return 2.0 * ((v - min_v) / (max_v - min_v)) - 1.0;
}

double DeNormalizeValue(double norm_value, double min_val, double max_val)
{
   return (((norm_value + 1.0) / 2.0) * (max_val - min_val)) + min_val;
}


//--- EA Inputs
enum ENUM_MODEL_TYPE
{
   MODEL_MLP,
   MODEL_RNN,
   MODEL_LSTM
};
//--- Model and Training Inputs
input ENUM_MODEL_TYPE   ModelToUse        = MODEL_LSTM; // Which neural network model to use?
input bool              TrainMode         = true;       // Set to true for initial training, false for deployment.
input double            TargetMAE         = 0.02;       // Train until the average error is below this value.
input int               MaxTrainingEpochs = 100;        // Safety break for training loop.
input int               PredictionBars    = 1;          // How many bars into the future to predict.
input int               SequenceLength    = 60;         // Fixed lookback window for the model.
input int               RsiPeriod         = 14;         // RSI Period for the new indicator feature.

//--- Global variables
INeuralNetworkModel *g_model;
const int            g_number_of_features = 2;
int                  g_rsi_handle = INVALID_HANDLE;

struct NormalizationInfo
{
   double min_val;
   double max_val;
};

// **MODIFIED**: Now holds normalization info for price CHANGE and RSI
NormalizationInfo g_price_change_norm_info;
NormalizationInfo g_rsi_norm_info;


// ------------------------------------------------------------------
// Utility: robust min/max finder (no changes)
void GetMinMax(const double &series[], const int count, double &min_out, double &max_out)
{
   min_out =  DBL_MAX;
   max_out = -DBL_MAX;
   for(int i = 0; i < count; ++i)
   {
      const double v = series[i];
      if(!IsFiniteNumber(v)) continue;
      if(v < min_out) min_out = v;
      if(v > max_out) max_out = v;
   }
   if(max_out - min_out < EPS)
   {
      min_out -= 0.5;
      max_out += 0.5;
   }
}

// ------------------------------------------------------------------
// **REBUILT**: Now creates features and targets based on price CHANGE.
bool GetNormalizedSample(const int               start_pos,
                         double                   &inputs[],
                         double                   &targets[],
                         const NormalizationInfo &price_change_norm, // Note the name change
                         const NormalizationInfo &rsi_norm)
{
   // Need one extra bar to calculate the first price change
   const int bars_needed = SequenceLength + PredictionBars + 1;

   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, start_pos, bars_needed, rates) < bars_needed)
      return false;

   double rsi_vals[];
   if(CopyBuffer(g_rsi_handle, 0, start_pos, bars_needed, rsi_vals) < bars_needed)
      return false;

   // --- Fill input tensor (sequence × features)
   ArrayResize(inputs, SequenceLength * g_number_of_features);
   for(int t = 0; t < SequenceLength; t++)
   {
      // Current bar index in the 'rates' array is t+1, previous is t
      double price_change = rates[t + 1].close - rates[t].close;
      
      if(!IsFiniteNumber(price_change) || !IsFiniteNumber(rsi_vals[t+1])) return false;

      inputs[t * g_number_of_features + 0] = NormalizeValue(price_change, price_change_norm.min_val, price_change_norm.max_val);
      inputs[t * g_number_of_features + 1] = NormalizeValue(rsi_vals[t + 1], rsi_norm.min_val, rsi_norm.max_val);
   }

   // --- Fill Targets
   ArrayResize(targets, PredictionBars);
   for(int i = 0; i < PredictionBars; ++i)
   {
      // Target is the change of the bar we want to predict
      int target_idx = SequenceLength + i + 1;
      double target_price_change = rates[target_idx].close - rates[target_idx - 1].close;
      
      if(!IsFiniteNumber(target_price_change)) return false;

      targets[i] = NormalizeValue(target_price_change, price_change_norm.min_val, price_change_norm.max_val);
   }

   return true;
}

// Functions to save and load normalization parameters
bool SaveNormalizationInfo(const string file_path, const NormalizationInfo &price_change, const NormalizationInfo &rsi)
{
   int fh = FileOpen(file_path, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;
   FileWriteStruct(fh, price_change);
   FileWriteStruct(fh, rsi);
   FileClose(fh);
   return true;
}

bool LoadNormalizationInfo(const string file_path, NormalizationInfo &price_change, NormalizationInfo &rsi)
{
   int fh = FileOpen(file_path, FILE_READ | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;
   FileReadStruct(fh, price_change);
   FileReadStruct(fh, rsi);
   FileClose(fh);
   return true;
}


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   MathSrand((int)TimeCurrent());

   g_rsi_handle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
   if(g_rsi_handle == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator handle! Error: ", GetLastError());
      return(INIT_FAILED);
   }

   switch(ModelToUse)
   {
      case MODEL_MLP:
         g_model = new C_MLP(SequenceLength * g_number_of_features, 50, PredictionBars, 0.001, 0.9, 0.999);
         break;
      case MODEL_RNN:
         g_model = new C_RNN(g_number_of_features, 40, PredictionBars, SequenceLength, 0.0001, 0.9, 0.999);
         break;
      case MODEL_LSTM:
         g_model = new C_LSTM(g_number_of_features, 30, PredictionBars, SequenceLength, 0.0001, 0.9, 0.999);
         break;
   }
   if(CheckPointer(g_model) != POINTER_DYNAMIC)
   {
      Print("Failed to instantiate model!");
      return INIT_FAILED;
   }

   // Filenames now include "_delta" to avoid using old models.
   string base_file_name = "My_AI_Models\\" + EnumToString(ModelToUse) + "_" + _Symbol + "_" + EnumToString(_Period) + "_delta";
   string weight_file_path = base_file_name + "_weights.bin";
   string norm_file_path = base_file_name + "_norm.bin";
   Print("Weight file path: ", weight_file_path);
   Print("Norm file path: ", norm_file_path);

   // ==================================================================
   // --- TRAINING MODE ---
   // ==================================================================
   if(TrainMode)
   {
      Print("Preparing data for global normalization on PRICE DELTAS...");
      int total_bars_available = Bars(_Symbol, _Period) - 1;
      if(total_bars_available <= SequenceLength + PredictionBars + 1)
      {
         Print("Not enough historical data for training. Aborting.");
         return INIT_FAILED;
      }

      MqlRates all_rates[];
      if(CopyRates(_Symbol, _Period, 0, total_bars_available, all_rates) != total_bars_available) return INIT_FAILED;
      
      double all_rsi_values[];
      if(CopyBuffer(g_rsi_handle, 0, 0, total_bars_available, all_rsi_values) != total_bars_available) return INIT_FAILED;

      // Create an array of price changes to find min/max
      double all_price_changes[];
      ArrayResize(all_price_changes, total_bars_available - 1);
      for(int i = 1; i < total_bars_available; i++)
      {
         all_price_changes[i - 1] = all_rates[i].close - all_rates[i - 1].close;
      }

      GetMinMax(all_price_changes, total_bars_available - 1, g_price_change_norm_info.min_val, g_price_change_norm_info.max_val);
      GetMinMax(all_rsi_values, total_bars_available, g_rsi_norm_info.min_val, g_rsi_norm_info.max_val);

      PrintFormat("Global Price-Change Norm: min=%.5f, max=%.5f", g_price_change_norm_info.min_val, g_price_change_norm_info.max_val);
      PrintFormat("Global RSI Norm: min=%.2f, max=%.2f", g_rsi_norm_info.min_val, g_rsi_norm_info.max_val);

      if(!SaveNormalizationInfo(norm_file_path, g_price_change_norm_info, g_rsi_norm_info)) return INIT_FAILED;

      Print("Starting training with sliding window...");
      for(int epoch = 1; epoch <= MaxTrainingEpochs; epoch++)
      {
         double total_mae_epoch = 0;
         int samples_in_epoch = 0;
         for(int start_pos = 1; start_pos < total_bars_available - (SequenceLength + PredictionBars + 1); start_pos++)
         {
            double training_inputs[], training_targets[];
            if(!GetNormalizedSample(start_pos, training_inputs, training_targets, g_price_change_norm_info, g_rsi_norm_info)) continue;

            double current_mae = g_model.Train(training_inputs, training_targets);
            if(!IsFiniteNumber(current_mae)) continue;

            total_mae_epoch += current_mae;
            samples_in_epoch++;
         }

         if(samples_in_epoch == 0)
         {
            Print("Could not generate any training samples. Aborting.");
            return INIT_FAILED;
         }
         double avg_mae = total_mae_epoch / samples_in_epoch;
         PrintFormat("Epoch %d/%d | Avg MAE: %.5f | Samples: %d", epoch, MaxTrainingEpochs, avg_mae, samples_in_epoch);
         if(avg_mae <= TargetMAE)
         {
            Print("Target MAE reached!");
            break;
         }
      }

      Print("Training complete. Saving weights...");
      g_model.SaveWeights(weight_file_path);
      ExpertRemove();
      return INIT_SUCCEEDED;
   }
   // ==================================================================
   // --- DEPLOYMENT MODE ---
   // ==================================================================
   else
   {
      Print("Deployment mode. Loading pre-trained model...");
      if(!LoadNormalizationInfo(norm_file_path, g_price_change_norm_info, g_rsi_norm_info))
      {
         Print("CRITICAL: Failed to load normalization parameters! Run in TrainMode first. EA will stop.");
         return INIT_FAILED;
      }
      if(!g_model.LoadWeights(weight_file_path))
      {
         Print("CRITICAL: Failed to load weights! Run in TrainMode first. EA will stop.");
         return INIT_FAILED;
      }
      Print("Model loaded successfully. EA is live.");
   }

   EventSetTimer(60);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(TrainMode) return;

   double latest_inputs[], latest_targets[];
   if(!GetNormalizedSample(1, latest_inputs, latest_targets, g_price_change_norm_info, g_rsi_norm_info))
   {
      Print("Could not get latest data for prediction.");
      return;
   }

   double prediction_normalized[];
   g_model.Predict(latest_inputs, prediction_normalized);

   // --- Reverted Trading Logic ---
   // 1. De-normalize the prediction to get the predicted price CHANGE.
   double predicted_change = DeNormalizeValue(prediction_normalized[0], g_price_change_norm_info.min_val, g_price_change_norm_info.max_val);

   // 2. Get current price and calculate the predicted future price.
   double current_close = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Use BID as the base
   double predicted_price = current_close + predicted_change;

   // 3. Get current market prices for trading decisions.
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spread_price = spread_points * _Point;

   // 4. Original trading logic using the new predicted_price
   if(m_Position.Select(_Symbol))
   {
      long posType = m_Position.PositionType();

      if(posType == POSITION_TYPE_BUY  &&  predicted_price < bid - spread_price)
         m_Trade.PositionClose(_Symbol);

      if(posType == POSITION_TYPE_SELL &&  predicted_price > ask + spread_price)
         m_Trade.PositionClose(_Symbol);
   }

   if(!m_Position.Select(_Symbol))
   {
      if(predicted_price > ask + spread_price)
      {
         if(m_Trade.Buy(0.10, _Symbol, ask, 0, 0))
            Print("BUY @", ask, " | forecast=", predicted_price);
         else
            Print("Buy error ", GetLastError());
      }

      if(predicted_price < bid - spread_price)
      {
         if(m_Trade.Sell(0.10, _Symbol, bid, 0, 0))
            Print("SELL @", bid, " | forecast=", predicted_price);
         else
            Print("Sell error ", GetLastError());
      }
   }
   
   Print("forecast=", predicted_price);
}


//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_rsi_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_rsi_handle);
   }
   if(CheckPointer(g_model) == POINTER_DYNAMIC)
   {
      delete g_model;
   }
   Print("Main EA Deinitialized. Reason: ", reason);
}
