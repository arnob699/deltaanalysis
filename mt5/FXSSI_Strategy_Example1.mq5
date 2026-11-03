//+------------------------------------------------------------------+
//|                                     FXSSI_Strategy_Example1.mq5  |
//|                                  Copyright 2026, Delta Analyse   |
//|               Based on FXSSI Sentiment Strategy Guide (Ex. #1)   |
//+------------------------------------------------------------------+
#property copyright   "Delta Analyse"
#property link        "https://fxssi.com/beginners-guide#example-1"
#property version     "1.00"
#property description "Automated Trading Indicator for FXSSI Strategy Example #1 (MVP + Ratios + SLC)"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

//--- Plot 1: Buy Signal Arrow
#property indicator_label1  "Example1 Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'46,204,113' // Emerald Green
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Sell Signal Arrow
#property indicator_label2  "Example1 Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'231,76,60'  // Crimson Red
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "---- [1] Strategy Example #1 Rule Settings ----"
input double           InpRatiosSellThreshold = 60.0;               // Ratios Sell Threshold (% Longs >= 60%)
input double           InpRatiosBuyThreshold  = 40.0;               // Ratios Buy Threshold (% Longs <= 40%)
input int              InpMaxStopLossPips     = 200;                // Max Stop Loss in Pips (Max 200 pips)
input int              InpTakeProfitPips      = 300;                // Take Profit in Pips (300 pips)
input double           InpPipSizeOverride     = 0.0;                // Pip Size Override (0.0 = Auto: 0.10 Gold, 0.0001 FX)
input int              InpSlcMarginPoints     = 30;                 // Margin Beyond MVP/SLC (Points)
input int              InpMvpFluctuateHours   = 5;                  // MVP Exit Fluctuation Range (4-7 hours)

input group "---- [2] Indicator Binding / Fallback Paths ----"
input string           InpDerivativesPath     = "FXSSI.com\\FXSSI.Derivatives";      // FXSSI Derivatives Path (MVP)
input string           InpRatiosPath          = "FXSSI.com\\FXSSI.Ratios";           // FXSSI Ratios Path
input string           InpCurrentRatioPath    = "FXSSI.com\\FXSSI.CurrentRatio";      // FXSSI CurrentRatio Path
input string           InpSlcPath             = "FXSSI.com\\FXSSI.StopLossClusters"; // FXSSI StopLossClusters Path
input bool             InpAutoSearchChart     = true;                                // Auto-link to chart indicators if present

input group "---- [3] On-Chart Visual Display & HUD ----"
input bool             InpShowDashboard       = true;                                // Show Strategy #1 On-Chart HUD
input ENUM_BASE_CORNER InpHudCorner           = CORNER_RIGHT_UPPER;                  // Dashboard Screen Corner
input int              InpHudX                = 20;                                  // Dashboard X Distance (Pixels)
input int              InpHudY                = 30;                                  // Dashboard Y Distance (Pixels)
input bool             InpDrawTradeLines      = true;                                // Draw Live Entry, SL & TP Lines on Chart
input color            InpEntryColor          = C'245,185,25';                       // Entry Line Color (Gold)
input color            InpSlColor             = C'231,76,60';                        // Stop Loss Line Color (Red)
input color            InpTpColor             = C'46,204,113';                       // Take Profit Line Color (Green)

input group "---- [4] Alerts & Notifications ----"
input bool             InpEnableAlerts        = true;                                // MT5 Pop-up Alerts
input bool             InpEnableSound         = true;                                // Play Alert Sound
input bool             InpEnablePush          = false;                               // Send Push Notification to Mobile
input string           InpSoundFile           = "alert.wav";                         // Sound File

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double g_buf_buy_arrows[];
double g_buf_sell_arrows[];
double g_buf_mvp_cache[];
double g_buf_ratios_cache[];

//+------------------------------------------------------------------+
//| Global Handles & Cache State                                     |
//+------------------------------------------------------------------+
int    g_hDerivatives = INVALID_HANDLE;
int    g_hRatios      = INVALID_HANDLE;
int    g_hSLC         = INVALID_HANDLE;
datetime g_last_signal_time = 0;

// Current Active Signal State
enum ENUM_STRATEGY_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

struct SignalSetup
{
   ENUM_STRATEGY_SIGNAL signal;
   datetime             time;
   double               entry_price;
   double               mvp_price;
   double               ratios_val;
   double               sl_cluster_price;
   double               stop_loss;
   double               take_profit;
   double               risk_reward;
   string               narrative;
};

SignalSetup g_current_setup;

// HUD Element Names
string g_hud_prefix  = "FXSSI_EX1_";
string g_line_entry  = "FXSSI_EX1_LINE_ENTRY";
string g_line_sl     = "FXSSI_EX1_LINE_SL";
string g_line_tp     = "FXSSI_EX1_LINE_TP";

//+------------------------------------------------------------------+
//| Helper: Find Indicator Handle on Active Chart                    |
//+------------------------------------------------------------------+
int FindChartIndicatorHandle(string pattern)
{
   int total_windows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = 0; w < total_windows; w++)
   {
      int total_ind = ChartIndicatorsTotal(0, w);
      for(int i = 0; i < total_ind; i++)
      {
         string name = ChartIndicatorName(0, w, i);
         if(StringFind(name, pattern) >= 0)
         {
            int h = ChartIndicatorGet(0, w, name);
            if(h != INVALID_HANDLE) return h;
         }
      }
   }
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Bind or Create FXSSI Indicator Handles                           |
//+------------------------------------------------------------------+
void InitializeHandles()
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = _Period;

   // 1. Bind Derivatives (MVP is Buffer 2)
   if(InpAutoSearchChart && g_hDerivatives == INVALID_HANDLE)
   {
      g_hDerivatives = FindChartIndicatorHandle("Derivatives");
      if(g_hDerivatives == INVALID_HANDLE) g_hDerivatives = FindChartIndicatorHandle("FXSSI.Derivatives");
   }
   if(g_hDerivatives == INVALID_HANDLE)
   {
      ResetLastError();
      g_hDerivatives = iCustom(sym, tf, InpDerivativesPath);
      if(g_hDerivatives == INVALID_HANDLE) g_hDerivatives = iCustom(sym, tf, "FXSSI.Derivatives");
   }

   // 2. Bind Ratios (Current Ratio / Sentiment)
   if(InpAutoSearchChart && g_hRatios == INVALID_HANDLE)
   {
      g_hRatios = FindChartIndicatorHandle("Ratios");
      if(g_hRatios == INVALID_HANDLE) g_hRatios = FindChartIndicatorHandle("CurrentRatio");
   }
   if(g_hRatios == INVALID_HANDLE)
   {
      ResetLastError();
      g_hRatios = iCustom(sym, tf, InpRatiosPath);
      if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, InpCurrentRatioPath);
      if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, "FXSSI.Ratios");
      if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, "FXSSI.CurrentRatio");
   }

   // 3. Bind StopLossClusters (SLC)
   if(InpAutoSearchChart && g_hSLC == INVALID_HANDLE)
   {
      g_hSLC = FindChartIndicatorHandle("StopLossClusters");
      if(g_hSLC == INVALID_HANDLE) g_hSLC = FindChartIndicatorHandle("StopLoss");
      if(g_hSLC == INVALID_HANDLE) g_hSLC = FindChartIndicatorHandle("SLC");
   }
   if(g_hSLC == INVALID_HANDLE)
   {
      ResetLastError();
      g_hSLC = iCustom(sym, tf, InpSlcPath);
      if(g_hSLC == INVALID_HANDLE) g_hSLC = iCustom(sym, tf, "FXSSI.StopLossClusters");
   }
}

//+------------------------------------------------------------------+
//| Get Live MVP Price Level                                         |
//+------------------------------------------------------------------+
double GetMvpPrice(int shift)
{
   if(g_hDerivatives != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      // Buffer 2 in FXSSI.Derivatives corresponds to MVP
      if(CopyBuffer(g_hDerivatives, 2, shift, 1, buf) > 0)
      {
         if(buf[0] != EMPTY_VALUE && buf[0] > 0.0) return buf[0];
      }
      // Check buffer 0 or 1 fallback
      for(int b = 0; b < 4; b++)
      {
         if(b == 2) continue;
         if(CopyBuffer(g_hDerivatives, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] > 10.0) return buf[0];
         }
      }
   }

   // Robust Autonomous Fallback: Session Volume-Weighted Middle Price
   datetime t_start = iTime(_Symbol, PERIOD_D1, 0);
   int start_bar = iBarShift(_Symbol, _Period, t_start);
   if(start_bar <= 0) start_bar = 24;

   double sum_pv = 0.0;
   long sum_v = 0;
   for(int k = 0; k <= start_bar; k++)
   {
      double mid = (iHigh(_Symbol, _Period, k) + iLow(_Symbol, _Period, k) + iClose(_Symbol, _Period, k)) / 3.0;
      long vol = iTickVolume(_Symbol, _Period, k);
      if(vol <= 0) vol = 1;
      sum_pv += (mid * vol);
      sum_v  += vol;
   }
   return (sum_v > 0) ? (sum_pv / (double)sum_v) : iClose(_Symbol, _Period, shift);
}

//+------------------------------------------------------------------+
//| Get Live Ratios (% Buyers / Longs)                               |
//+------------------------------------------------------------------+
double GetRatiosValue(int shift)
{
   if(g_hRatios != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      for(int b = 0; b < 6; b++)
      {
         if(CopyBuffer(g_hRatios, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] > 5.0 && buf[0] < 95.0)
            {
               return buf[0];
            }
         }
      }
   }

   // Fallback: Read from fxssi_daily_delta.json if bridge is running
   int fh = FileOpen("fxssi_daily_delta.json", FILE_READ|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      string content = "";
      while(!FileIsEnding(fh)) content += FileReadString(fh);
      FileClose(fh);
      
      int pos = StringFind(content, "\"ratio\":");
      if(pos >= 0)
      {
         string sub = StringSubstr(content, pos + 8, 10);
         double r = StringToDouble(sub);
         if(r > 5.0 && r < 95.0) return r;
      }
      
      // Fallback ratio from activity delta crowd flow
      int pos_net = StringFind(content, "\"net_delta\":");
      if(pos_net >= 0)
      {
         string sub_net = StringSubstr(content, pos_net + 12, 10);
         double net_d = StringToDouble(sub_net);
         return 50.0 + (net_d * 2.5); // Convert delta into ratio equilibrium estimate
      }
   }

   // Default neutral
   return 50.0;
}

//+------------------------------------------------------------------+
//| Get Stop Loss Clusters (SLC) Above & Below Price                 |
//+------------------------------------------------------------------+
void GetSlcClusters(int shift, double &upper_slc, double &lower_slc)
{
   upper_slc = 0.0;
   lower_slc = 0.0;

   double cur_price = iClose(_Symbol, _Period, shift);

   if(g_hSLC != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);

      // Upper Clusters (Resistance / Sell Stop / Buyer SL) -> Buffers 1, 2
      for(int b = 2; b >= 0; b--)
      {
         if(CopyBuffer(g_hSLC, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] > cur_price)
            {
               upper_slc = buf[0];
               break;
            }
         }
      }

      // Lower Clusters (Support / Buy Stop / Seller SL) -> Buffers 4, 5
      for(int b = 5; b >= 3; b--)
      {
         if(CopyBuffer(g_hSLC, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] < cur_price && buf[0] > 0.0)
            {
               lower_slc = buf[0];
               break;
            }
         }
      }
   }

   // Autonomous Fallback: Locate significant recent swing liquidity pools
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;

   if(upper_slc == 0.0)
   {
      double highest = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, 20, shift + 1));
      upper_slc = highest + (10.0 * pt);
   }
   if(lower_slc == 0.0)
   {
      double lowest = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, 20, shift + 1));
      lower_slc = lowest - (10.0 * pt);
   }
}

//+------------------------------------------------------------------+
//| Helper: Get Pip Size for Active Symbol                           |
//+------------------------------------------------------------------+
double GetPipSize()
{
   if(InpPipSizeOverride > 0.0) return InpPipSizeOverride;

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;

   string sym = _Symbol;
   StringToUpper(sym);
   // Gold / Silver / Metals:
   // For 3-digit gold (e.g. 3920.123): 1 pip = 0.10 (100 points)
   // For 2-digit gold (e.g. 3920.12): 1 pip = 0.10 (10 points)
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      return (_Digits == 3) ? (pt * 100.0) : (pt * 10.0);
   }

   // 5-digit & 3-digit Forex:
   if(_Digits == 3 || _Digits == 5) return (pt * 10.0);

   return pt;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss Level                                        |
//| Rule: Must be above MVP line (for SELL) or below MVP line (for BUY)|
//|       AND max 200 pips from entry.                               |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_STRATEGY_SIGNAL sig, double entry, double mvp_price, double upper_slc, double lower_slc)
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;
   double pip = GetPipSize();
   double max_sl_dist = InpMaxStopLossPips * pip; // 200 pips max
   double margin = InpSlcMarginPoints * pt;

   if(sig == SIGNAL_SELL)
   {
      // SELL: Price is below MVP. Stop Loss MUST be ABOVE the MVP line.
      // Base: higher of (MVP + margin) or (Upper SLC + margin)
      double base_sl = MathMax(mvp_price + margin, (upper_slc > entry ? upper_slc + margin : mvp_price + margin));
      
      // Enforce: strictly above MVP line
      if(base_sl <= mvp_price) base_sl = mvp_price + margin;
      
      // Enforce: max 200 pips from entry
      if(base_sl - entry > max_sl_dist)
      {
         base_sl = entry + max_sl_dist;
      }

      return NormalizeDouble(base_sl, _Digits);
   }
   else if(sig == SIGNAL_BUY)
   {
      // BUY: Price is above MVP. Stop Loss MUST be BELOW the MVP line.
      // Base: lower of (MVP - margin) or (Lower SLC - margin)
      double base_sl = MathMin(mvp_price - margin, (lower_slc > 0.0 && lower_slc < entry ? lower_slc - margin : mvp_price - margin));
      
      // Enforce: strictly below MVP line
      if(base_sl >= mvp_price) base_sl = mvp_price - margin;
      
      // Enforce: max 200 pips from entry
      if(entry - base_sl > max_sl_dist)
      {
         base_sl = entry - max_sl_dist;
      }

      return NormalizeDouble(base_sl, _Digits);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit Level (Targeting 300 Pips)                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_STRATEGY_SIGNAL sig, double entry)
{
   double pip = GetPipSize();
   double tp_dist = InpTakeProfitPips * pip; // 300 pips

   if(sig == SIGNAL_BUY)
   {
      return NormalizeDouble(entry + tp_dist, _Digits);
   }
   else if(sig == SIGNAL_SELL)
   {
      return NormalizeDouble(entry - tp_dist, _Digits);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Send Notification Alert                                          |
//+------------------------------------------------------------------+
void TriggerSignalAlert(SignalSetup &setup)
{
   string type = (setup.signal == SIGNAL_BUY) ? "BUY SETUP" : "SELL SETUP";
   string msg = StringFormat("[FXSSI Example #1] %s on %s (%s)!\nEntry: %.2f | TP: %.2f (+%d pips) | SL: %.2f (Above MVP, Max %d pips) | Ratios: %.1f%% Longs",
                             type, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                             setup.entry_price, setup.take_profit, InpTakeProfitPips, setup.stop_loss, InpMaxStopLossPips, setup.ratios_val);

   if(InpEnableAlerts) Alert(msg);
   if(InpEnableSound && InpSoundFile != "") PlaySound(InpSoundFile);
   if(InpEnablePush) SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Render Trade Lines on Chart                                      |
//+------------------------------------------------------------------+
void DrawTradeLines(SignalSetup &setup)
{
   if(!InpDrawTradeLines || setup.signal == SIGNAL_NONE) return;

   datetime t1 = iTime(_Symbol, _Period, 0);
   datetime t2 = t1 + (PeriodSeconds(_Period) * 12);

   // 1. Entry Line
   ObjectDelete(0, g_line_entry);
   ObjectCreate(0, g_line_entry, OBJ_TREND, 0, t1, setup.entry_price, t2, setup.entry_price);
   ObjectSetInteger(0, g_line_entry, OBJPROP_COLOR, InpEntryColor);
   ObjectSetInteger(0, g_line_entry, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_line_entry, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_line_entry, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, g_line_entry, OBJPROP_TEXT, StringFormat("Ex#1 Entry @ %.2f", setup.entry_price));

   // 2. Stop Loss Line
   ObjectDelete(0, g_line_sl);
   ObjectCreate(0, g_line_sl, OBJ_TREND, 0, t1, setup.stop_loss, t2, setup.stop_loss);
   ObjectSetInteger(0, g_line_sl, OBJPROP_COLOR, InpSlColor);
   ObjectSetInteger(0, g_line_sl, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, g_line_sl, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, g_line_sl, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, g_line_sl, OBJPROP_TEXT, StringFormat("Ex#1 Stop Loss (Above MVP, Max %d pips) @ %.2f", InpMaxStopLossPips, setup.stop_loss));

   // 3. Take Profit Line (300 Pips Target)
   ObjectDelete(0, g_line_tp);
   ObjectCreate(0, g_line_tp, OBJ_TREND, 0, t1, setup.take_profit, t2, setup.take_profit);
   ObjectSetInteger(0, g_line_tp, OBJPROP_COLOR, InpTpColor);
   ObjectSetInteger(0, g_line_tp, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, g_line_tp, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, g_line_tp, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, g_line_tp, OBJPROP_TEXT, StringFormat("Ex#1 Target (%d pips TP) @ %.2f", InpTakeProfitPips, setup.take_profit));

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Remove Trade Lines                                               |
//+------------------------------------------------------------------+
void RemoveTradeLines()
{
   ObjectDelete(0, g_line_entry);
   ObjectDelete(0, g_line_sl);
   ObjectDelete(0, g_line_tp);
}

//+------------------------------------------------------------------+
//| Build / Update On-Chart Strategy #1 Dashboard                    |
//+------------------------------------------------------------------+
void UpdateDashboard(SignalSetup &setup, double mvp, double ratios, double upper_slc, double lower_slc, double cur_price)
{
   if(!InpShowDashboard) return;

   int x = InpHudX;
   int y = InpHudY;

   string bg_name     = g_hud_prefix + "BG";
   string title_name  = g_hud_prefix + "TITLE";
   string mvp_name    = g_hud_prefix + "MVP";
   string ratios_name = g_hud_prefix + "RATIOS";
   string slc_name    = g_hud_prefix + "SLC";
   string sig_name    = g_hud_prefix + "STATUS";
   string target_name = g_hud_prefix + "TARGETS";

   // 1. Container Card
   if(ObjectFind(0, bg_name) < 0)
   {
      ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 370);
      ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 138);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, C'16,23,36');
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_COLOR, C'42,58,84');
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
   }

   // 2. Title
   if(ObjectFind(0, title_name) < 0)
   {
      ObjectCreate(0, title_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, title_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, title_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, title_name, OBJPROP_YDISTANCE, y + 8);
      ObjectSetString(0, title_name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, title_name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, title_name, OBJPROP_COLOR, C'245,185,25');
      ObjectSetInteger(0, title_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, title_name, OBJPROP_TEXT, "FXSSI STRATEGY #1: MVP + RATIOS + SLC");

   // 3. MVP Condition Status
   bool mvp_bear = (cur_price < mvp);
   bool mvp_bull = (cur_price > mvp);
   string mvp_str = StringFormat("[1] MVP Trend: %s (MVP: %.2f | Price: %.2f)",
                                 mvp_bear ? "BEARISH (Price < MVP)" : "BULLISH (Price > MVP)",
                                 mvp, cur_price);
   if(ObjectFind(0, mvp_name) < 0)
   {
      ObjectCreate(0, mvp_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, mvp_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, mvp_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, mvp_name, OBJPROP_YDISTANCE, y + 28);
      ObjectSetString(0, mvp_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, mvp_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, mvp_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, mvp_name, OBJPROP_TEXT, mvp_str);
   ObjectSetInteger(0, mvp_name, OBJPROP_COLOR, mvp_bear ? C'231,76,60' : C'46,204,113');

   // 4. Ratios Condition Status
   bool rat_sell = (ratios >= InpRatiosSellThreshold);
   bool rat_buy  = (ratios <= InpRatiosBuyThreshold);
   string rat_str = StringFormat("[2] Ratios (Sentiment): %.1f%% Longs -> %s",
                                 ratios,
                                 rat_sell ? "Crowd Buying (FADE SELL >=60%)" :
                                 (rat_buy  ? "Crowd Selling (FADE BUY <=40%)" : "Neutral Range (40-60%)"));
   if(ObjectFind(0, ratios_name) < 0)
   {
      ObjectCreate(0, ratios_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, ratios_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, ratios_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, ratios_name, OBJPROP_YDISTANCE, y + 46);
      ObjectSetString(0, ratios_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, ratios_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, ratios_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, ratios_name, OBJPROP_TEXT, rat_str);
   ObjectSetInteger(0, ratios_name, OBJPROP_COLOR, (rat_sell || rat_buy) ? C'245,185,25' : C'160,185,215');

   // 5. SLC Clusters Status
   string slc_str = StringFormat("[3] SLC Levels: Upper SLC @ %.2f | Lower SLC @ %.2f", upper_slc, lower_slc);
   if(ObjectFind(0, slc_name) < 0)
   {
      ObjectCreate(0, slc_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, slc_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, slc_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, slc_name, OBJPROP_YDISTANCE, y + 64);
      ObjectSetString(0, slc_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, slc_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, slc_name, OBJPROP_COLOR, C'160,185,215');
      ObjectSetInteger(0, slc_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, slc_name, OBJPROP_TEXT, slc_str);

   // 6. Signal Output Banner
   string sig_str = "STATUS: WAITING FOR ALL 3 CONDITIONS";
   color sig_col  = C'160,185,215';
   if(setup.signal == SIGNAL_BUY)
   {
      sig_str = "STATUS: 🟢 BUY SIGNAL ACTIVE (Ex. #1 Confluence)";
      sig_col = C'46,204,113';
   }
   else if(setup.signal == SIGNAL_SELL)
   {
      sig_str = "STATUS: 🔴 SELL SIGNAL ACTIVE (Ex. #1 Confluence)";
      sig_col = C'231,76,60';
   }

   if(ObjectFind(0, sig_name) < 0)
   {
      ObjectCreate(0, sig_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, sig_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, sig_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, sig_name, OBJPROP_YDISTANCE, y + 84);
      ObjectSetString(0, sig_name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, sig_name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, sig_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, sig_name, OBJPROP_TEXT, sig_str);
   ObjectSetInteger(0, sig_name, OBJPROP_COLOR, sig_col);

   // 7. Order Execution Targets Line (SL, TP, R:R)
   string tgt_str = StringFormat("Plan: SL max %d pips (above MVP)  |  TP %d pips", InpMaxStopLossPips, InpTakeProfitPips);
   if(setup.signal != SIGNAL_NONE)
   {
      double pip = GetPipSize();
      double sl_pips = MathAbs(setup.entry_price - setup.stop_loss) / (pip > 0 ? pip : 1.0);
      double tp_pips = MathAbs(setup.take_profit - setup.entry_price) / (pip > 0 ? pip : 1.0);
      tgt_str = StringFormat("Entry: %.2f  |  SL: %.2f (%.0f pips)  |  TP: %.2f (%.0f pips)  |  R:R 1:%.1f",
                             setup.entry_price, setup.stop_loss, sl_pips, setup.take_profit, tp_pips, setup.risk_reward);
   }

   if(ObjectFind(0, target_name) < 0)
   {
      ObjectCreate(0, target_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, target_name, OBJPROP_CORNER, InpHudCorner);
      ObjectSetInteger(0, target_name, OBJPROP_XDISTANCE, x + 14);
      ObjectSetInteger(0, target_name, OBJPROP_YDISTANCE, y + 104);
      ObjectSetString(0, target_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, target_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, target_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, target_name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, target_name, OBJPROP_TEXT, tgt_str);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Remove Dashboard Objects from Chart                              |
//+------------------------------------------------------------------+
void RemoveDashboard()
{
   ObjectDelete(0, g_hud_prefix + "BG");
   ObjectDelete(0, g_hud_prefix + "TITLE");
   ObjectDelete(0, g_hud_prefix + "MVP");
   ObjectDelete(0, g_hud_prefix + "RATIOS");
   ObjectDelete(0, g_hud_prefix + "SLC");
   ObjectDelete(0, g_hud_prefix + "STATUS");
   ObjectDelete(0, g_hud_prefix + "TARGETS");
   RemoveTradeLines();
}

//+------------------------------------------------------------------+
//| Indicator Initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_buf_buy_arrows, INDICATOR_DATA);
   SetIndexBuffer(1, g_buf_sell_arrows, INDICATOR_DATA);
   SetIndexBuffer(2, g_buf_mvp_cache, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, g_buf_ratios_cache, INDICATOR_CALCULATIONS);

   ArraySetAsSeries(g_buf_buy_arrows, true);
   ArraySetAsSeries(g_buf_sell_arrows, true);
   ArraySetAsSeries(g_buf_mvp_cache, true);
   ArraySetAsSeries(g_buf_ratios_cache, true);

   // Set arrow symbols (Wingdings 233 = Bullish Arrow Up, 234 = Bearish Arrow Down)
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   InitializeHandles();
   EventSetTimer(1);

   Print("===============================================================");
   Print("   FXSSI Strategy Example #1 (MVP + Ratios + SLC) Initialized   ");
   Print("===============================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator Deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemoveDashboard();

   if(g_hDerivatives != INVALID_HANDLE) IndicatorRelease(g_hDerivatives);
   if(g_hRatios != INVALID_HANDLE)      IndicatorRelease(g_hRatios);
   if(g_hSLC != INVALID_HANDLE)         IndicatorRelease(g_hSLC);

   g_hDerivatives = INVALID_HANDLE;
   g_hRatios      = INVALID_HANDLE;
   g_hSLC         = INVALID_HANDLE;

   ChartRedraw();
   Print("[FXSSI Strategy #1] Deinitialized cleanly.");
}

//+------------------------------------------------------------------+
//| Timer Event (1-Second Real-Time Check)                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Recheck bindings if needed
   if(g_hDerivatives == INVALID_HANDLE || g_hRatios == INVALID_HANDLE || g_hSLC == INVALID_HANDLE)
   {
      InitializeHandles();
   }

   double cur_price = iClose(_Symbol, _Period, 0);
   double mvp       = GetMvpPrice(0);
   double ratios    = GetRatiosValue(0);
   double upper_slc = 0.0, lower_slc = 0.0;
   GetSlcClusters(0, upper_slc, lower_slc);

   // Evaluate Example #1 Rules:
   // Condition 1: MVP Trend
   bool mvp_sell = (cur_price < mvp);
   bool mvp_buy  = (cur_price > mvp);

   // Condition 2: Ratios Contrarian Threshold
   bool rat_sell = (ratios >= InpRatiosSellThreshold);
   bool rat_buy  = (ratios <= InpRatiosBuyThreshold);

   ENUM_STRATEGY_SIGNAL sig = SIGNAL_NONE;

   // Sell Confluence: Price < MVP AND Ratios >= 60%
   if(mvp_sell && rat_sell)
   {
      sig = SIGNAL_SELL;
   }
   // Buy Confluence: Price > MVP AND Ratios <= 40%
   else if(mvp_buy && rat_buy)
   {
      sig = SIGNAL_BUY;
   }

   g_current_setup.signal = sig;
   g_current_setup.time   = iTime(_Symbol, _Period, 0);
   g_current_setup.entry_price = cur_price;
   g_current_setup.mvp_price   = mvp;
   g_current_setup.ratios_val  = ratios;

   if(sig != SIGNAL_NONE)
   {
      g_current_setup.stop_loss   = CalculateStopLoss(sig, cur_price, mvp, upper_slc, lower_slc);
      g_current_setup.take_profit = CalculateTakeProfit(sig, cur_price);

      double risk   = MathAbs(cur_price - g_current_setup.stop_loss);
      double reward = MathAbs(g_current_setup.take_profit - cur_price);
      g_current_setup.risk_reward = (risk > 0.0) ? (reward / risk) : 1.0;

      // Trigger Alert on fresh signal
      if(g_last_signal_time != g_current_setup.time)
      {
         TriggerSignalAlert(g_current_setup);
         g_last_signal_time = g_current_setup.time;
      }

      DrawTradeLines(g_current_setup);
   }
   else
   {
      RemoveTradeLines();
   }

   UpdateDashboard(g_current_setup, mvp, ratios, upper_slc, lower_slc, cur_price);
}

//+------------------------------------------------------------------+
//| Indicator Calculation Function                                   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 50) return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int limit = rates_total - prev_calculated;
   if(limit > 200) limit = 200; // Scan recent history bars

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;

   for(int i = limit; i >= 0; i--)
   {
      g_buf_buy_arrows[i]  = 0.0;
      g_buf_sell_arrows[i] = 0.0;

      double bar_price = close[i];
      double mvp       = GetMvpPrice(i);
      double ratios    = GetRatiosValue(i);

      g_buf_mvp_cache[i]    = mvp;
      g_buf_ratios_cache[i] = ratios;

      // Check Example #1 Sell: Price < MVP AND Ratios >= 60%
      if(bar_price < mvp && ratios >= InpRatiosSellThreshold)
      {
         // Verify transition or fresh trigger
         if(i == 0 || close[i+1] >= g_buf_mvp_cache[i+1] || g_buf_ratios_cache[i+1] < InpRatiosSellThreshold)
         {
            g_buf_sell_arrows[i] = high[i] + (25 * pt);
         }
      }
      // Check Example #1 Buy: Price > MVP AND Ratios <= 40%
      else if(bar_price > mvp && ratios <= InpRatiosBuyThreshold)
      {
         // Verify transition or fresh trigger
         if(i == 0 || close[i+1] <= g_buf_mvp_cache[i+1] || g_buf_ratios_cache[i+1] > InpRatiosBuyThreshold)
         {
            g_buf_buy_arrows[i] = low[i] - (25 * pt);
         }
      }
   }

   // Update dashboard & state on current candle
   OnTimer();

   return(rates_total);
}
//+------------------------------------------------------------------+

