//+------------------------------------------------------------------+
//|                                    FXSSI_Example1_Backtest.mq5   |
//|                                  Copyright 2026, Delta Analyse   |
//|               Natively Backtests Strategy Example #1 on Chart    |
//+------------------------------------------------------------------+
#property copyright   "Delta Analyse"
#property link        "https://fxssi.com/beginners-guide#example-1"
#property version     "1.00"
#property description "Automated 1-Month Backtest Script for FXSSI Strategy Example #1"
#property script_show_inputs

//--- Script Inputs
input group "---- [1] Backtest Range Settings ----"
input int              InpDaysToBacktest      = 30;                 // Number of Days to Backtest (e.g. 30 days)
input double           InpLotSize             = 0.10;               // Simulated Lot Size (0.10 lots)
input double           InpAccountBalance      = 10000.0;            // Starting Account Balance ($)

input group "---- [2] Strategy Example #1 Rules ----"
input double           InpRatiosSellThreshold = 60.0;               // Ratios Sell Threshold (% Longs >= 60%)
input double           InpRatiosBuyThreshold  = 40.0;               // Ratios Buy Threshold (% Longs <= 40%)
input int              InpMaxStopLossPips     = 200;                // Max Stop Loss in Pips (Max 200 pips)
input int              InpTakeProfitPips      = 300;                // Take Profit in Pips (300 pips)
input double           InpPipSizeOverride     = 0.0;                // Custom Pip Size (0.0 = Auto-Detect: 0.10 Gold, 0.0001 FX)
input int              InpSlcMarginPoints     = 30;                 // Margin Beyond MVP/SLC (Points)
input int              InpMvpZoneFluctuateHrs = 5;                  // MVP Exit Fluctuation Range (4-7 hours)

input group "---- [3] Chart Visuals & Export ----"
input bool             InpPlotTradesOnChart   = true;               // Draw Trade Arrows & Labels on Chart
input bool             InpExportCsvReport     = true;               // Export Trade Ledger to MQL5/Files CSV
input string           InpCsvFileName         = "Backtest_Example1_Gold_1Month.csv"; // CSV Filename

// Indicator Handles
int g_hDerivatives = INVALID_HANDLE;
int g_hRatios      = INVALID_HANDLE;
int g_hSLC         = INVALID_HANDLE;

// Trade Record Structure
struct TradeRecord
{
   int      trade_id;
   string   type;
   datetime entry_time;
   double   entry_price;
   double   sl;
   double   tp;
   datetime exit_time;
   double   exit_price;
   string   exit_reason;
   double   pnl_pts;
   double   pnl_usd;
   bool     is_win;
   int      bars_held;
};

//+------------------------------------------------------------------+
//| Bind FXSSI Indicator Handles                                     |
//+------------------------------------------------------------------+
void InitializeHandles()
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = _Period;

   // 1. Derivatives (MVP)
   g_hDerivatives = iCustom(sym, tf, "FXSSI.com\\FXSSI.Derivatives");
   if(g_hDerivatives == INVALID_HANDLE) g_hDerivatives = iCustom(sym, tf, "FXSSI.Derivatives");

   // 2. Ratios
   g_hRatios = iCustom(sym, tf, "FXSSI.com\\FXSSI.Ratios");
   if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, "FXSSI.com\\FXSSI.CurrentRatio");
   if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, "FXSSI.Ratios");
   if(g_hRatios == INVALID_HANDLE) g_hRatios = iCustom(sym, tf, "FXSSI.CurrentRatio");

   // 3. StopLossClusters
   g_hSLC = iCustom(sym, tf, "FXSSI.com\\FXSSI.StopLossClusters");
   if(g_hSLC == INVALID_HANDLE) g_hSLC = iCustom(sym, tf, "FXSSI.StopLossClusters");
}

//+------------------------------------------------------------------+
//| Get MVP Price Level                                              |
//+------------------------------------------------------------------+
double GetMvpPrice(int shift)
{
   if(g_hDerivatives != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(g_hDerivatives, 2, shift, 1, buf) > 0)
      {
         if(buf[0] != EMPTY_VALUE && buf[0] > 0.0) return buf[0];
      }
      for(int b = 0; b < 4; b++)
      {
         if(b == 2) continue;
         if(CopyBuffer(g_hDerivatives, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] > 10.0) return buf[0];
         }
      }
   }

   // Volume-weighted session fallback
   datetime t_bar = iTime(_Symbol, _Period, shift);
   MqlDateTime dt;
   TimeToStruct(t_bar, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime t_start = StructToTime(dt);

   int start_bar = iBarShift(_Symbol, _Period, t_start);
   if(start_bar < shift) start_bar = shift + 24;

   double sum_pv = 0.0;
   long sum_v = 0;
   for(int k = shift; k <= start_bar; k++)
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
//| Get Ratios Value (% Longs)                                       |
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

   // Fallback ratio from local sentiment JSON
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
   }
   return 50.0;
}

//+------------------------------------------------------------------+
//| Get Stop Loss Clusters                                           |
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
      for(int b = 2; b >= 0; b--)
      {
         if(CopyBuffer(g_hSLC, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] > cur_price) { upper_slc = buf[0]; break; }
         }
      }
      for(int b = 5; b >= 3; b--)
      {
         if(CopyBuffer(g_hSLC, b, shift, 1, buf) > 0)
         {
            if(buf[0] != EMPTY_VALUE && buf[0] < cur_price && buf[0] > 0.0) { lower_slc = buf[0]; break; }
         }
      }
   }

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
//| Script Program Start Function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("==================================================================");
   PrintFormat("[FXSSI Ex#1 Backtest] Initializing 1-Month Simulation on %s (%s)...",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("==================================================================");

   InitializeHandles();

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;

   // Calculate number of bars to scan (30 days * ~48 M30 bars/day = ~1440 bars)
   int bars_per_day = 86400 / PeriodSeconds(_Period);
   int total_bars_to_scan = InpDaysToBacktest * bars_per_day;
   int available_bars = iBars(_Symbol, _Period);

   if(total_bars_to_scan > available_bars - 50) total_bars_to_scan = available_bars - 50;

   PrintFormat("[FXSSI Ex#1 Backtest] Scanning %d historical bars (~%d days)...",
               total_bars_to_scan, InpDaysToBacktest);

   TradeRecord trades[];
   int trade_count = 0;

   bool in_trade = false;
   TradeRecord active_trade;

   datetime start_time = iTime(_Symbol, _Period, total_bars_to_scan);
   datetime end_time   = iTime(_Symbol, _Period, 0);

   // Iterate from oldest bar to newest bar
   for(int i = total_bars_to_scan; i >= 1; i--)
   {
      datetime t_curr = iTime(_Symbol, _Period, i);
      double o = iOpen(_Symbol, _Period, i);
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);

      double mvp = GetMvpPrice(i);
      double ratios = GetRatiosValue(i);

      double upper_slc = 0.0, lower_slc = 0.0;
      GetSlcClusters(i, upper_slc, lower_slc);

      // 1. Manage Active Trade
      if(in_trade)
      {
         active_trade.bars_held++;
         string exit_reason = "";
         double exit_price = 0.0;

         // Check SL
         if(active_trade.type == "BUY" && l <= active_trade.sl)
         {
            exit_reason = "SL_HIT";
            exit_price  = active_trade.sl;
         }
         else if(active_trade.type == "SELL" && h >= active_trade.sl)
         {
            exit_reason = "SL_HIT";
            exit_price  = active_trade.sl;
         }
         // Check TP
         else if(active_trade.type == "BUY" && h >= active_trade.tp)
         {
            exit_reason = "TP_HIT (MVP Reached)";
            exit_price  = active_trade.tp;
         }
         else if(active_trade.type == "SELL" && l <= active_trade.tp)
         {
            exit_reason = "TP_HIT (MVP Reached)";
            exit_price  = active_trade.tp;
         }
         // Check MVP Zone Fluctuation (Rule 4: within MVP zone 4-7 hours)
         else if(active_trade.bars_held >= (InpMvpZoneFluctuateHrs * 2) && MathAbs(c - mvp) <= (2.0))
         {
            exit_reason = "MVP_ZONE_EXIT";
            exit_price  = c;
         }
         // Timeout Exit (24 bars = 12h)
         else if(active_trade.bars_held >= 24)
         {
            exit_reason = "TIMEOUT";
            exit_price  = c;
         }

         if(exit_reason != "")
         {
            active_trade.exit_time   = t_curr;
            active_trade.exit_price  = exit_price;
            active_trade.exit_reason = exit_reason;

            if(active_trade.type == "BUY")
               active_trade.pnl_pts = (exit_price - active_trade.entry_price);
            else
               active_trade.pnl_pts = (active_trade.entry_price - exit_price);

            // On Gold 0.10 lot = $10 per $1.00 move
            active_trade.pnl_usd = active_trade.pnl_pts * 100.0 * InpLotSize;
            active_trade.is_win  = (active_trade.pnl_usd > 0.0);

            ArrayResize(trades, trade_count + 1);
            trades[trade_count] = active_trade;
            trade_count++;
            in_trade = false;

            // Plot Visual Exit Marker
            if(InpPlotTradesOnChart)
            {
               string obj_name = StringFormat("BT_EX1_EXIT_%d", active_trade.trade_id);
               ObjectDelete(0, obj_name);
               ObjectCreate(0, obj_name, OBJ_ARROW, 0, t_curr, exit_price);
               ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, active_trade.is_win ? 241 : 251); // Checkmark or X
               ObjectSetInteger(0, obj_name, OBJPROP_COLOR, active_trade.is_win ? C'46,204,113' : C'231,76,60');
               ObjectSetString(0, obj_name, OBJPROP_TEXT, StringFormat("#%d PnL: $%.2f (%s)", active_trade.trade_id, active_trade.pnl_usd, exit_reason));
            }
         }
      }

      // 2. Check Fresh Signal Entry
      if(!in_trade && i < total_bars_to_scan)
      {
         double prev_c   = iClose(_Symbol, _Period, i + 1);
         double prev_mvp = GetMvpPrice(i + 1);
         double prev_r   = GetRatiosValue(i + 1);

         bool prev_sell = (prev_c < prev_mvp && prev_r >= InpRatiosSellThreshold);
         bool curr_sell = (c < mvp && ratios >= InpRatiosSellThreshold);

         bool prev_buy  = (prev_c > prev_mvp && prev_r <= InpRatiosBuyThreshold);
         bool curr_buy  = (c > mvp && ratios <= InpRatiosBuyThreshold);

         bool fresh_sell = (curr_sell && !prev_sell);
         bool fresh_buy  = (curr_buy  && !prev_buy);

         if(fresh_sell || fresh_buy)
         {
            datetime next_t = iTime(_Symbol, _Period, i - 1);
            double next_o   = iOpen(_Symbol, _Period, i - 1);

            active_trade.trade_id    = trade_count + 1;
            active_trade.type        = fresh_sell ? "SELL" : "BUY";
            active_trade.entry_time  = next_t;
            active_trade.entry_price = next_o;
            active_trade.bars_held   = 0;

            double pip = GetPipSize();
            double margin = InpSlcMarginPoints * pt;
            double max_sl_dist = InpMaxStopLossPips * pip; // Max 200 pips
            double tp_dist = InpTakeProfitPips * pip;      // 300 pips TP

            if(fresh_sell)
            {
               // Rule: SL must be above MVP line, max 200 pips
               double base_sl = MathMax(mvp + margin, (upper_slc > next_o ? upper_slc + margin : mvp + margin));
               if(base_sl <= mvp) base_sl = mvp + margin;
               if(base_sl - next_o > max_sl_dist) base_sl = next_o + max_sl_dist;

               active_trade.sl = NormalizeDouble(base_sl, _Digits);
               active_trade.tp = NormalizeDouble(next_o - tp_dist, _Digits);
            }
            else
            {
               // Rule: SL must be below MVP line, max 200 pips
               double base_sl = MathMin(mvp - margin, (lower_slc > 0.0 && lower_slc < next_o ? lower_slc - margin : mvp - margin));
               if(base_sl >= mvp) base_sl = mvp - margin;
               if(next_o - base_sl > max_sl_dist) base_sl = next_o - max_sl_dist;

               active_trade.sl = NormalizeDouble(base_sl, _Digits);
               active_trade.tp = NormalizeDouble(next_o + tp_dist, _Digits);
            }

            in_trade = true;

            // Plot Visual Entry Marker
            if(InpPlotTradesOnChart)
            {
               string obj_name = StringFormat("BT_EX1_ENTRY_%d", active_trade.trade_id);
               ObjectDelete(0, obj_name);
               ObjectCreate(0, obj_name, OBJ_ARROW, 0, next_t, next_o);
               ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, fresh_sell ? 234 : 233);
               ObjectSetInteger(0, obj_name, OBJPROP_COLOR, fresh_sell ? C'231,76,60' : C'46,204,113');
               ObjectSetString(0, obj_name, OBJPROP_TEXT, StringFormat("#%d %s @ %.2f (SL: %.2f | TP: %.2f)",
                              active_trade.trade_id, active_trade.type, next_o, active_trade.sl, active_trade.tp));
            }
         }
      }
   }

   // 3. Compute Metrics
   int wins = 0, losses = 0;
   double gross_profit = 0.0, gross_loss = 0.0, net_profit = 0.0;
   double peak_balance = InpAccountBalance, cur_balance = InpAccountBalance;
   double max_dd_usd = 0.0, max_dd_pct = 0.0;

   for(int k = 0; k < trade_count; k++)
   {
      double pnl = trades[k].pnl_usd;
      cur_balance += pnl;
      net_profit  += pnl;

      if(pnl > 0.0)
      {
         wins++;
         gross_profit += pnl;
      }
      else
      {
         losses++;
         gross_loss += MathAbs(pnl);
      }

      if(cur_balance > peak_balance) peak_balance = cur_balance;
      double dd = peak_balance - cur_balance;
      double dd_p = (peak_balance > 0.0) ? (dd / peak_balance * 100.0) : 0.0;
      if(dd > max_dd_usd) max_dd_usd = dd;
      if(dd_p > max_dd_pct) max_dd_pct = dd_p;
   }

   double win_rate = (trade_count > 0) ? ((double)wins / (double)trade_count * 100.0) : 0.0;
   double pf = (gross_loss > 0.0) ? (gross_profit / gross_loss) : 99.9;
   double avg_win = (wins > 0) ? (gross_profit / wins) : 0.0;
   double avg_loss = (losses > 0) ? (gross_loss / losses) : 0.0;

   Print("==================================================================");
   Print("          FXSSI STRATEGY EXAMPLE #1 BACKTEST RESULTS              ");
   Print("==================================================================");
   PrintFormat("Period:                 %s -> %s (Past %d Days)",
               TimeToString(start_time, TIME_DATE), TimeToString(end_time, TIME_DATE), InpDaysToBacktest);
   PrintFormat("Total Completed Trades: %d", trade_count);
   PrintFormat("Winning Trades:         %d (%.2f%%)", wins, win_rate);
   PrintFormat("Losing Trades:          %d (%.2f%%)", losses, 100.0 - win_rate);
   PrintFormat("Profit Factor:          %.2f", pf);
   PrintFormat("Starting Balance:       $%.2f", InpAccountBalance);
   PrintFormat("Final Balance:          $%.2f", cur_balance);
   PrintFormat("Net Profit ($):         $%.2f (%.2f%%)", net_profit, (net_profit / InpAccountBalance) * 100.0);
   PrintFormat("Gross Profit:           $%.2f", gross_profit);
   PrintFormat("Gross Loss:             $%.2f", gross_loss);
   PrintFormat("Average Win:            $%.2f", avg_win);
   PrintFormat("Average Loss:           $%.2f", avg_loss);
   PrintFormat("Max Drawdown:           $%.2f (%.2f%%)", max_dd_usd, max_dd_pct);
   Print("==================================================================");

   // Export CSV
   if(InpExportCsvReport && trade_count > 0)
   {
      int fh = FileOpen(InpCsvFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
      if(fh != INVALID_HANDLE)
      {
         FileWrite(fh, "TradeID", "Type", "EntryTime", "EntryPrice", "SL", "TP", "ExitTime", "ExitPrice", "ExitReason", "PnLPts", "PnLUSD", "IsWin", "BarsHeld");
         for(int k = 0; k < trade_count; k++)
         {
            FileWrite(fh,
                      trades[k].trade_id,
                      trades[k].type,
                      TimeToString(trades[k].entry_time),
                      DoubleToString(trades[k].entry_price, _Digits),
                      DoubleToString(trades[k].sl, _Digits),
                      DoubleToString(trades[k].tp, _Digits),
                      TimeToString(trades[k].exit_time),
                      DoubleToString(trades[k].exit_price, _Digits),
                      trades[k].exit_reason,
                      DoubleToString(trades[k].pnl_pts, 2),
                      DoubleToString(trades[k].pnl_usd, 2),
                      trades[k].is_win ? "YES" : "NO",
                      trades[k].bars_held);
         }
         FileClose(fh);
         PrintFormat("[FXSSI Ex#1 Backtest] Trade ledger exported to: MQL5/Files/%s", InpCsvFileName);
      }
   }

   ChartRedraw();
   Alert(StringFormat("[FXSSI Ex#1 Backtest Completed] %d Trades | Win Rate: %.1f%% | PF: %.2f | Net: $%.2f",
         trade_count, win_rate, pf, net_profit));
}
//+------------------------------------------------------------------+

