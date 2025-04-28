//+------------------------------------------------------------------+
//|                                             TurtleBreakoutEA.mq5 |
//|                        Turtle Breakout Strategy for MT5          |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"
#property strict
#property description "Turtle Breakout - No Visualization with Trailing Stop (MT5 EA)"
#property script_show_inputs

//--- input parameters
input int    length_entry = 20;         // Entry Breakout Length
input int    length_exit  = 10;         // Exit Breakout Length
input double risk_pct     = 1.0;        // Risk per Trade (%)
input int    atr_length   = 14;         // ATR Length
input double trail_offset = 3.0;        // Trailing Stop Offset (ATR)
input double account_scale = 1.0;       // Account size scaling (1.0 = full account)
input double slippage     = 3;          // Slippage in points
input bool   show_visuals = true;       // Show trade arrows and labels
input bool   show_historical = true;    // Show historical trades

//--- global variables
int          ticket_long  = -1;
int          ticket_short = -1;
double       last_atr     = 0;
datetime     last_trade_time = 0;
bool         is_new_bar = false;
int          atr_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastbar;
   datetime curbar = iTime(_Symbol, _Period, 0);
   if(lastbar != curbar)
   {
      lastbar = curbar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channel High                                   |
//+------------------------------------------------------------------+
double DonchianHigh(int length) {
   double max_high = iHigh(_Symbol, _Period, 1);
   for(int i=2; i<=length; i++) {
      if(iHigh(_Symbol, _Period, i) > max_high) max_high = iHigh(_Symbol, _Period, i);
   }
   return max_high;
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channel Low                                    |
//+------------------------------------------------------------------+
double DonchianLow(int length) {
   double min_low = iLow(_Symbol, _Period, 1);
   for(int i=2; i<=length; i++) {
      if(iLow(_Symbol, _Period, i) < min_low) min_low = iLow(_Symbol, _Period, i);
   }
   return min_low;
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                    |
//+------------------------------------------------------------------+
double GetATR(int period) {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(atr_handle == INVALID_HANDLE) {
      atr_handle = iATR(_Symbol, _Period, period);
      if(atr_handle == INVALID_HANDLE) return 0;
   }
   if(CopyBuffer(atr_handle, 0, 0, 1, atr) <= 0) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double GetPositionSize(double atr) {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY) * account_scale;
   double min_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(atr < min_tick) atr = min_tick;
   double size = (risk_pct/100.0) * equity / atr;
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   size = MathMax(min_lot, MathMin(max_lot, MathFloor(size/lot_step)*lot_step));
   return size;
}

//+------------------------------------------------------------------+
//| Create visual object                                             |
//+------------------------------------------------------------------+
void CreateVisualObject(string name, string type, datetime time, double price, color clr, string text = "") {
   if(!show_visuals) return;
   
   if(type == "ARROW") {
      // Delete existing object if it exists
      ObjectDelete(0, name);
      
      // Create new arrow
      ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (clr == clrLime || clr == clrYellow) ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);  // Increased width
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   }
   else if(type == "TEXT") {
      // Delete existing object if it exists
      ObjectDelete(0, name);
      
      // Create new text label
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 12);  // Increased font size
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   }
}

//+------------------------------------------------------------------+
//| Place Entry Order                                                |
//+------------------------------------------------------------------+
void PlaceEntry(string signal, double lots) {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   
   double price = (signal=="Long") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE type = (signal=="Long") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl = 0, tp = 0; // No initial SL/TP, trailing only
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = (int)slippage;
   request.magic = 123456;
   request.comment = signal;
   request.type_filling = ORDER_FILLING_FOK;
   
   bool success = OrderSend(request, result);
   if(!success) {
      Print("OrderSend failed. Error: ", GetLastError());
      return;
   }
   
   if(result.retcode == TRADE_RETCODE_DONE) {
      if(signal=="Long") ticket_long = (int)result.order;
      else ticket_short = (int)result.order;
      last_trade_time = TimeCurrent();
      
      if(show_visuals) {
         datetime time = iTime(_Symbol, _Period, 0);
         color arrow_color = (signal=="Long") ? clrLime : clrRed;
         
         // Draw entry arrow
         string arrow_name = signal+"Entry"+IntegerToString(TimeCurrent());
         CreateVisualObject(arrow_name, "ARROW", time, price, arrow_color);
         
         // Add label
         string label_name = signal+"Label"+IntegerToString(TimeCurrent());
         CreateVisualObject(label_name, "TEXT", time, price, arrow_color, signal+" Entry");
         
         // Force chart update
         ChartRedraw();
      }
   } else {
      Print("Order failed. Retcode: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Place Exit Order (close position)                                |
//+------------------------------------------------------------------+
void PlaceExit(string signal) {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetTicket(i) > 0) {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol) {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if((signal=="Long" && type==POSITION_TYPE_BUY) || (signal=="Short" && type==POSITION_TYPE_SELL)) {
               double lots = PositionGetDouble(POSITION_VOLUME);
               double price = (signal=="Long") ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_DEAL;
               request.symbol = _Symbol;
               request.volume = lots;
               request.type = (signal=="Long") ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               request.price = price;
               request.deviation = (int)slippage;
               request.magic = 123456;
               request.comment = signal+"Exit";
               request.type_filling = ORDER_FILLING_FOK;
               
               bool success = OrderSend(request, result);
               if(!success) {
                  Print("OrderSend failed. Error: ", GetLastError());
                  continue;
               }
               
               if(result.retcode == TRADE_RETCODE_DONE) {
                  if(show_visuals) {
                     datetime time = iTime(_Symbol, _Period, 0);
                     color arrow_color = (signal=="Long") ? clrYellow : clrAqua;
                     
                     // Draw exit arrow
                     string arrow_name = signal+"Exit"+IntegerToString(TimeCurrent());
                     CreateVisualObject(arrow_name, "ARROW", time, price, arrow_color);
                     
                     // Add label
                     string label_name = signal+"ExitLabel"+IntegerToString(TimeCurrent());
                     CreateVisualObject(label_name, "TEXT", time, price, arrow_color, signal+" Exit");
                     
                     // Force chart update
                     ChartRedraw();
                  }
               } else {
                  Print("Order failed. Retcode: ", result.retcode);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Logic                                              |
//+------------------------------------------------------------------+
void UpdateTrailingStops(double atr) {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionGetTicket(i) > 0) {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol) {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ulong ticket = PositionGetTicket(i);
            double trail = trail_offset * atr;
            double new_sl = 0;
            
            if(type==POSITION_TYPE_BUY) {
               new_sl = MathMax(PositionGetDouble(POSITION_SL), iClose(_Symbol, _Period, 0) - trail);
               if(new_sl > 0 && (PositionGetDouble(POSITION_SL)==0 || new_sl > PositionGetDouble(POSITION_SL))) {
                  MqlTradeRequest request = {};
                  MqlTradeResult result = {};
                  
                  request.action = TRADE_ACTION_SLTP;
                  request.symbol = _Symbol;
                  request.sl = new_sl;
                  request.tp = PositionGetDouble(POSITION_TP);
                  request.position = ticket;
                  
                  bool success = OrderSend(request, result);
                  if(!success) {
                     Print("Trailing stop modification failed. Error: ", GetLastError());
                  }
               }
            }
            else if(type==POSITION_TYPE_SELL) {
               new_sl = MathMin(PositionGetDouble(POSITION_SL), iClose(_Symbol, _Period, 0) + trail);
               if(new_sl > 0 && (PositionGetDouble(POSITION_SL)==0 || new_sl < PositionGetDouble(POSITION_SL))) {
                  MqlTradeRequest request = {};
                  MqlTradeResult result = {};
                  
                  request.action = TRADE_ACTION_SLTP;
                  request.symbol = _Symbol;
                  request.sl = new_sl;
                  request.tp = PositionGetDouble(POSITION_TP);
                  request.position = ticket;
                  
                  bool success = OrderSend(request, result);
                  if(!success) {
                     Print("Trailing stop modification failed. Error: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check if trading is allowed
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      Print("Trading is not allowed!");
      return INIT_FAILED;
   }
   
   // Check if we can trade this symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE)) {
      Print("Symbol ", _Symbol, " is not available for trading!");
      return INIT_FAILED;
   }
   
   // Initialize variables
   ticket_long = -1;
   ticket_short = -1;
   last_atr = 0;
   last_trade_time = 0;
   
   // Initialize ATR handle
   atr_handle = iATR(_Symbol, _Period, atr_length);
   if(atr_handle == INVALID_HANDLE) {
      Print("Failed to create ATR indicator!");
      return INIT_FAILED;
   }
   
   // Set chart properties for better visualization
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(0, CHART_SHOW_BID_LINE, true);
   ChartSetInteger(0, CHART_SHOW_LAST_LINE, true);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up objects
   ObjectsDeleteAll(0, "Long");
   ObjectsDeleteAll(0, "Short");
   
   // Release indicator handle
   if(atr_handle != INVALID_HANDLE) {
      IndicatorRelease(atr_handle);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   is_new_bar = IsNewBar();
   
   //--- Calculate Donchian channels and ATR
   double entry_high = DonchianHigh(length_entry);
   double entry_low  = DonchianLow(length_entry);
   double exit_high  = DonchianHigh(length_exit);
   double exit_low   = DonchianLow(length_exit);
   double atr = GetATR(atr_length);
   last_atr = atr;
   double pos_size = GetPositionSize(atr);

   //--- Check for existing positions
   ENUM_POSITION_TYPE pos_type = POSITION_TYPE_BUY;
   double pos_volume = 0;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionGetTicket(i) > 0) {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol) {
            pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            pos_volume = PositionGetDouble(POSITION_VOLUME);
            break;
         }
      }
   }

   //--- Entry logic (only on new bar)
   if(is_new_bar) {
      if(iClose(_Symbol, _Period, 0) > entry_high && pos_type != POSITION_TYPE_BUY) {
         // Close short if any
         if(pos_type == POSITION_TYPE_SELL) PlaceExit("Short");
         // Enter long
         PlaceEntry("Long", pos_size);
      }
      if(iClose(_Symbol, _Period, 0) < entry_low && pos_type != POSITION_TYPE_SELL) {
         // Close long if any
         if(pos_type == POSITION_TYPE_BUY) PlaceExit("Long");
         // Enter short
         PlaceEntry("Short", pos_size);
      }
   }

   //--- Trailing stop logic (every tick)
   UpdateTrailingStops(atr);
}
//+------------------------------------------------------------------+