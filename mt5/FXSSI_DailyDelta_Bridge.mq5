//+------------------------------------------------------------------+
//|                                     PublicActivity_Bridge.mq5    |
//|                                  Copyright 2026, Delta Analyse   |
//+------------------------------------------------------------------+
#property copyright   "Delta Analyse"
#property version     "1.120"
#property description "Public Activity Delta Bridge for Gold (Multi-Day History & BST 12-Hour & Real FXSSI Sentiment)"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "---- Gold Symbol & Indicator Binding ----"
input string   InpGoldSymbol          = "XAUUSDm";                          // Target Gold Symbol (Auto-detects if empty)
input string   InpIndicatorPath       = "FXSSI.com\\FXSSI.TradingActivity"; // Internal Activity Indicator Path
input string   InpRatiosPath          = "FXSSI.com\\FXSSI.Ratios";          // Internal Ratios Indicator Path
input bool     InpReuseChartIndicator = true;                               // Reuse Active Chart Indicator (Avoids duplicates)

input group "---- Multi-Day History & Timezone Settings ----"
input int      InpMaxHistoryDays      = 29;                                 // Max Historical Days to Export (Up to 29 Days)
input int      InpBstUtcOffsetHours   = 6;                                  // Bangladesh Standard Time UTC Offset (BST = UTC+6)

input group "---- Export & Bridge Settings ----"
input string   InpJsonFileName        = "fxssi_daily_delta.json";           // JSON Bridge State File Name
input string   InpCmdFileName         = "refresh_cmd.json";                 // Web Refresh Command File Name
input int      InpTimerSeconds        = 1;                                  // Timer Interval (Seconds)
input bool     InpShowChartButton     = true;                               // Show On-Chart Refresh Button

//+------------------------------------------------------------------+
//| Structure for Day Summary                                        |
//+------------------------------------------------------------------+
struct DayData
{
   string   date_broker;
   string   date_bst;
   string   day_name;
   bool     is_today;
   int      valid_bars;
   int      total_bars;
   double   inc_pos;
   double   inc_neg;
   double   inc_net;
   double   dec_pos;
   double   dec_neg;
   double   dec_net;
   string   contrarian_bias;
   string   intervals_json;
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int      g_hIndicator        = INVALID_HANDLE;
bool     g_indicator_is_chart= false;
int      g_hRatios           = INVALID_HANDLE;
bool     g_ratios_is_chart   = false;
string   g_gold_symbol       = "XAUUSDm";
datetime g_last_m20_bar_time = 0;
datetime g_last_day_open     = 0;
string   g_button_name       = "BTN_REFRESH_ACTIVITY_DELTA";

string   g_cached_past_days_json = "";
int      g_cached_history_days_count = 0;

// Forward declarations
string   ResolveGoldSymbol();
int      BindActivityIndicator();
int      BindRatiosIndicator();
void     RecalculateAndExport(string update_type, bool full_history_refresh);
DayData  ProcessSingleDay(int day_index, datetime now_current, int bst_offset);
string   FormatTime12(datetime dt);
string   FormatDateTime12(datetime dt);
string   GetDayOfWeekName(datetime dt);
int      GetBstOffsetSeconds();
string   BuildBehaviorTag(double inc, double dec);
string   DetermineContrarianBias(double inc_net, double dec_net);
void     CreateChartButton();
void     UpdateChartButton(string text, color bg_col);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===============================================================");
   Print("[Public Activity Delta] Initializing Gold Bridge v1.120");
   Print("[Public Activity Delta] 12-Hour Bangladesh Time (BST), Real FXSSI Sentiment & Dynamic Bars Active");
   
   bool dlls_allowed = (bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED);
   if(!dlls_allowed)
   {
      Print("[Public Activity Delta] WARNING: DLL imports disabled in MT5 Options!");
   }
   
   g_gold_symbol = ResolveGoldSymbol();
   Print("[Public Activity Delta] Target Gold symbol: '", g_gold_symbol, "' (Chart Period: ", EnumToString((ENUM_TIMEFRAMES)_Period), ")");
   SymbolSelect(g_gold_symbol, true);
   
   g_hIndicator = BindActivityIndicator();
   g_hRatios    = BindRatiosIndicator();
   
   if(InpShowChartButton)
   {
      CreateChartButton();
   }
   
   EventSetTimer(InpTimerSeconds > 0 ? InpTimerSeconds : 1);
   RecalculateAndExport("INIT_STARTUP", true);
   Print("===============================================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   if(g_hIndicator != INVALID_HANDLE && !g_indicator_is_chart)
   {
      IndicatorRelease(g_hIndicator);
   }
   g_hIndicator = INVALID_HANDLE;
   
   if(g_hRatios != INVALID_HANDLE && !g_ratios_is_chart)
   {
      IndicatorRelease(g_hRatios);
   }
   g_hRatios = INVALID_HANDLE;
   
   ObjectDelete(0, g_button_name);
   ChartRedraw();
   Print("[Public Activity Delta] Bridge deinitialized.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_time = iTime(g_gold_symbol, _Period, 0);
   if(current_time != 0 && current_time != g_last_m20_bar_time)
   {
      g_last_m20_bar_time = current_time;
      RecalculateAndExport("NEW_BAR_TICK", false);
   }
}

//+------------------------------------------------------------------+
//| Timer function (Runs every 1 second continuously)               |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Check for Web Refresh Command
   if(FileIsExist(InpCmdFileName))
   {
      Print("[Public Activity Delta] Detected web refresh command. Running full multi-day scan...");
      FileDelete(InpCmdFileName);
      UpdateChartButton("SCANNING DELTA...", C'220,130,0');
      RecalculateAndExport("WEB_REFRESH", true);
      UpdateChartButton("REFRESH DELTA (BST)", C'24,140,80');
      return;
   }
   
   // 2. Check if a new trading day opened
   datetime day_open = iTime(g_gold_symbol, PERIOD_D1, 0);
   if(day_open != 0 && day_open != g_last_day_open)
   {
      Print("[Public Activity Delta] New trading session opened: ", TimeToString(day_open));
      g_last_day_open = day_open;
      RecalculateAndExport("NEW_DAY_SESSION", true);
      return;
   }
   
   // 3. Check if a new bar formed
   datetime current_time = iTime(g_gold_symbol, _Period, 0);
   if(current_time != 0 && current_time != g_last_m20_bar_time)
   {
      g_last_m20_bar_time = current_time;
      RecalculateAndExport("NEW_BAR_TIMER", false);
      return;
   }
   
   // 4. Heartbeat update (live prices & current bar progression)
   RecalculateAndExport("HEARTBEAT", false);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_button_name)
   {
      Print("[Public Activity Delta] Refresh button clicked on chart. Initiating multi-day scan...");
      UpdateChartButton("UPDATING...", C'220,130,0');
      RecalculateAndExport("MANUAL_CHART_CLICK", true);
      UpdateChartButton("REFRESH DELTA (BST)", C'24,140,80');
      ObjectSetInteger(0, g_button_name, OBJPROP_STATE, false);
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Auto-detect and validate Gold Symbol                             |
//+------------------------------------------------------------------+
string ResolveGoldSymbol()
{
   if(InpGoldSymbol != "" && SymbolInfoInteger(InpGoldSymbol, SYMBOL_EXIST))
   {
      return InpGoldSymbol;
   }
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
   {
      return _Symbol;
   }
   string candidates[] = {"XAUUSDm", "XAUUSD", "GOLD", "XAUUSD.", "XAUUSD_i", "XAUUSD.m", "XAUUSDpro", "XAUUSDc", "XAUUSD-", "XAUUSDb"};
   for(int i = 0; i < ArraySize(candidates); i++)
   {
      if(SymbolInfoInteger(candidates[i], SYMBOL_EXIST))
      {
         return candidates[i];
      }
   }
   return "XAUUSDm";
}

//+------------------------------------------------------------------+
//| Bind to Trading Activity Indicator on Chart                      |
//+------------------------------------------------------------------+
int BindActivityIndicator()
{
   if(InpReuseChartIndicator)
   {
      int total_windows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
      for(int w = 0; w < total_windows; w++)
      {
         int total_ind = ChartIndicatorsTotal(0, w);
         for(int i = 0; i < total_ind; i++)
         {
            string name = ChartIndicatorName(0, w, i);
            if(StringFind(name, "TradingActivity") >= 0 || StringFind(name, "Trading Activity") >= 0 || StringFind(name, "Activity") >= 0)
            {
               int h = ChartIndicatorGet(0, w, name);
               if(h != INVALID_HANDLE)
               {
                  PrintFormat("[Public Activity Delta] Linked directly to live Activity Indicator in Window %d: '%s' (Handle=%d)", w, name, h);
                  g_indicator_is_chart = true;
                  return h;
               }
            }
         }
      }
      
      if(total_windows >= 2)
      {
         int ind1_count = ChartIndicatorsTotal(0, 1);
         for(int i = 0; i < ind1_count; i++)
         {
            string name1 = ChartIndicatorName(0, 1, i);
            int h1 = ChartIndicatorGet(0, 1, name1);
            if(h1 != INVALID_HANDLE)
            {
               PrintFormat("[Public Activity Delta] Linked to Subwindow 1 Indicator: '%s' (Handle=%d)", name1, h1);
               g_indicator_is_chart = true;
               return h1;
            }
         }
      }
   }
   
   ResetLastError();
   int h = iCustom(g_gold_symbol, _Period, InpIndicatorPath);
   if(h == INVALID_HANDLE) h = iCustom(g_gold_symbol, _Period, "FXSSI.TradingActivity");
   if(h == INVALID_HANDLE) h = iCustom(g_gold_symbol, _Period, "FXSSI.com\\TradingActivity");
   
   if(h != INVALID_HANDLE)
   {
      PrintFormat("[Public Activity Delta] Created indicator handle on %s (Handle=%d)", g_gold_symbol, h);
      g_indicator_is_chart = false;
      return h;
   }
   
   Print("[Public Activity Delta] Note: Activity Indicator not found yet. Waiting for chart attachment.");
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Bind to Sentiment Ratio Indicator on Chart                       |
//+------------------------------------------------------------------+
int BindRatiosIndicator()
{
   if(InpReuseChartIndicator)
   {
      int total_windows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
      for(int w = 0; w < total_windows; w++)
      {
         int total_ind = ChartIndicatorsTotal(0, w);
         for(int i = 0; i < total_ind; i++)
         {
            string name = ChartIndicatorName(0, w, i);
            if(StringFind(name, "Ratios") >= 0 || StringFind(name, "Ratio") >= 0 || StringFind(name, "CurrentRatio") >= 0)
            {
               int h = ChartIndicatorGet(0, w, name);
               if(h != INVALID_HANDLE)
               {
                  PrintFormat("[Public Activity Delta] Linked directly to live Ratios Indicator in Window %d: '%s' (Handle=%d)", w, name, h);
                  g_ratios_is_chart = true;
                  return h;
               }
            }
         }
      }
      
      if(total_windows >= 3)
      {
         int ind2_count = ChartIndicatorsTotal(0, 2);
         for(int i = 0; i < ind2_count; i++)
         {
            string name2 = ChartIndicatorName(0, 2, i);
            int h2 = ChartIndicatorGet(0, 2, name2);
            if(h2 != INVALID_HANDLE)
            {
               PrintFormat("[Public Activity Delta] Linked to Subwindow 2 Indicator as Ratios: '%s' (Handle=%d)", name2, h2);
               g_ratios_is_chart = true;
               return h2;
            }
         }
      }
   }
   
   ResetLastError();
   int h = iCustom(g_gold_symbol, _Period, InpRatiosPath);
   if(h == INVALID_HANDLE) h = iCustom(g_gold_symbol, _Period, "FXSSI.Ratios");
   if(h == INVALID_HANDLE) h = iCustom(g_gold_symbol, _Period, "FXSSI.com\\FXSSI.CurrentRatio");
   if(h == INVALID_HANDLE) h = iCustom(g_gold_symbol, _Period, "FXSSI.CurrentRatio");
   
   if(h != INVALID_HANDLE)
   {
      PrintFormat("[Public Activity Delta] Created Ratios handle on %s (Handle=%d)", g_gold_symbol, h);
      g_ratios_is_chart = false;
      return h;
   }
   
   Print("[Public Activity Delta] Note: Ratios Indicator not found yet. Waiting for chart attachment.");
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Calculate Bangladesh Time UTC Offset in Seconds                  |
//+------------------------------------------------------------------+
int GetBstOffsetSeconds()
{
   datetime loc = TimeLocal();
   datetime cur = TimeCurrent();
   int diff = (int)(loc - cur);
   int rounded = (int)MathRound((double)diff / 1800.0) * 1800;
   if(rounded == 0) rounded = InpBstUtcOffsetHours * 3600; // Fallback to UTC+6
   return rounded;
}

//+------------------------------------------------------------------+
//| Format 12-Hour Time "hh:mm AM/PM"                                |
//+------------------------------------------------------------------+
string FormatTime12(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   int h = mdt.hour;
   int m = mdt.min;
   string ampm = (h >= 12) ? "PM" : "AM";
   int h12 = h % 12;
   if(h12 == 0) h12 = 12;
   return StringFormat("%02d:%02d %s", h12, m, ampm);
}

//+------------------------------------------------------------------+
//| Format 12-Hour Date & Time "YYYY.MM.DD hh:mm AM/PM"              |
//+------------------------------------------------------------------+
string FormatDateTime12(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   int h = mdt.hour;
   int m = mdt.min;
   string ampm = (h >= 12) ? "PM" : "AM";
   int h12 = h % 12;
   if(h12 == 0) h12 = 12;
   return StringFormat("%04d.%02d.%02d %02d:%02d %s", mdt.year, mdt.mon, mdt.day, h12, m, ampm);
}

//+------------------------------------------------------------------+
//| Day of Week Name                                                 |
//+------------------------------------------------------------------+
string GetDayOfWeekName(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   switch(mdt.day_of_week)
   {
      case 0: return "Sunday";
      case 1: return "Monday";
      case 2: return "Tuesday";
      case 3: return "Wednesday";
      case 4: return "Thursday";
      case 5: return "Friday";
      case 6: return "Saturday";
   }
   return "Unknown";
}

//+------------------------------------------------------------------+
//| Process a Single Day (Day 0 = Today, Day 1 = Yesterday...)       |
//+------------------------------------------------------------------+
DayData ProcessSingleDay(int day_index, datetime now_current, int bst_offset)
{
   DayData d;
   d.is_today = (day_index == 0);
   d.valid_bars = 0;
   d.total_bars = 0;
   d.inc_pos = 0.0;
   d.inc_neg = 0.0;
   d.inc_net = 0.0;
   d.dec_pos = 0.0;
   d.dec_neg = 0.0;
   d.dec_net = 0.0;
   d.intervals_json = "";
   
   datetime day_open_broker = iTime(g_gold_symbol, PERIOD_D1, day_index);
   if(day_open_broker == 0)
   {
      if(day_index == 0) day_open_broker = now_current - (now_current % 86400);
      else return d;
   }
   datetime day_close_broker = day_open_broker + 86400;
   
   datetime day_open_bst = day_open_broker + bst_offset;
   d.date_broker  = TimeToString(day_open_broker, TIME_DATE);
   d.date_bst     = TimeToString(day_open_bst, TIME_DATE);
   d.day_name     = GetDayOfWeekName(day_open_bst);
   
   // Identify actual chart bars within this day on the active timeframe
   int s_start = iBarShift(g_gold_symbol, _Period, day_open_broker, false);
   while(s_start >= 0 && iTime(g_gold_symbol, _Period, s_start) < day_open_broker)
   {
      s_start--;
   }
   
   int s_end = 0;
   if(day_index > 0)
   {
      s_end = iBarShift(g_gold_symbol, _Period, day_close_broker - 1, false);
      if(s_end < 0) s_end = 0;
   }
   
   if(s_start < s_end)
   {
      int temp = s_start;
      s_start = s_end;
      s_end = temp;
   }
   
   int bars_in_day = (s_start >= s_end) ? (s_start - s_end + 1) : 0;
   d.total_bars = bars_in_day;
   
   double run_inc_pos = 0.0, run_inc_neg = 0.0;
   double run_dec_pos = 0.0, run_dec_neg = 0.0;
   
   // Iterate sequentially from oldest bar of day down to newest bar
   for(int shift = s_start; shift >= s_end; shift--)
   {
      datetime bar_time_broker = iTime(g_gold_symbol, _Period, shift);
      if(bar_time_broker < day_open_broker || bar_time_broker >= day_close_broker) continue;
      if(day_index == 0 && bar_time_broker > now_current) continue;
      
      datetime bar_time_bst = bar_time_broker + bst_offset;
      
      double inc_delta = 0.0;
      double dec_delta = 0.0;
      bool has_activity = false;
      
      // 1. Extract Trading Activity Buffers
      if(g_hIndicator != INVALID_HANDLE)
      {
         double b_inc_pos[], b_inc_neg[], b_inc_buy[], b_inc_sell[];
         double b_dec_pos[], b_dec_neg[], b_dec_buy[], b_dec_sell[];
         
         // Increase Delta
         if(CopyBuffer(g_hIndicator, 4, shift, 1, b_inc_pos) > 0 && b_inc_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_pos[0]) && b_inc_pos[0] > 0.0001 && b_inc_pos[0] <= 100.0)
         {
            inc_delta = b_inc_pos[0];
            has_activity = true;
         }
         else if(CopyBuffer(g_hIndicator, 5, shift, 1, b_inc_neg) > 0 && b_inc_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_neg[0]) && MathAbs(b_inc_neg[0]) > 0.0001 && MathAbs(b_inc_neg[0]) <= 100.0)
         {
            inc_delta = (b_inc_neg[0] > 0) ? -b_inc_neg[0] : b_inc_neg[0];
            has_activity = true;
         }
         else if(CopyBuffer(g_hIndicator, 0, shift, 1, b_inc_buy) > 0 && CopyBuffer(g_hIndicator, 1, shift, 1, b_inc_sell) > 0)
         {
            if(b_inc_buy[0] != EMPTY_VALUE && b_inc_sell[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_buy[0]) && MathIsValidNumber(b_inc_sell[0]) && MathAbs(b_inc_buy[0]) <= 100.0 && MathAbs(b_inc_sell[0]) <= 100.0 && (b_inc_buy[0] > 0.0 || b_inc_sell[0] > 0.0))
            {
               inc_delta = b_inc_buy[0] - b_inc_sell[0];
               has_activity = true;
            }
         }
         
         // Decrease Delta
         if(CopyBuffer(g_hIndicator, 6, shift, 1, b_dec_pos) > 0 && b_dec_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_pos[0]) && b_dec_pos[0] > 0.0001 && b_dec_pos[0] <= 100.0)
         {
            dec_delta = b_dec_pos[0];
            has_activity = true;
         }
         else if(CopyBuffer(g_hIndicator, 7, shift, 1, b_dec_neg) > 0 && b_dec_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_neg[0]) && MathAbs(b_dec_neg[0]) > 0.0001 && MathAbs(b_dec_neg[0]) <= 100.0)
         {
            dec_delta = (b_dec_neg[0] > 0) ? -b_dec_neg[0] : b_dec_neg[0];
            has_activity = true;
         }
         else if(CopyBuffer(g_hIndicator, 2, shift, 1, b_dec_buy) > 0 && CopyBuffer(g_hIndicator, 3, shift, 1, b_dec_sell) > 0)
         {
            if(b_dec_buy[0] != EMPTY_VALUE && b_dec_sell[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_buy[0]) && MathIsValidNumber(b_dec_sell[0]) && MathAbs(b_dec_buy[0]) <= 100.0 && MathAbs(b_dec_sell[0]) <= 100.0 && (b_dec_buy[0] > 0.0 || b_dec_sell[0] > 0.0))
            {
               dec_delta = b_dec_buy[0] - b_dec_sell[0];
               has_activity = true;
            }
         }
      }
      
      // 2. Extract Real FXSSI.Ratios sentiment ratio (% Longs)
      double ratio_val = 50.0;
      bool has_ratio = false;
      if(g_hRatios != INVALID_HANDLE)
      {
         double b_ratio[];
         if(CopyBuffer(g_hRatios, 0, shift, 1, b_ratio) > 0)
         {
            if(b_ratio[0] != EMPTY_VALUE && MathIsValidNumber(b_ratio[0]) && b_ratio[0] > 0.0 && b_ratio[0] < 100.0)
            {
               ratio_val = b_ratio[0];
               has_ratio = true;
            }
         }
         if(!has_ratio)
         {
            for(int b = 1; b < 6; b++)
            {
               if(CopyBuffer(g_hRatios, b, shift, 1, b_ratio) > 0)
               {
                  if(b_ratio[0] != EMPTY_VALUE && MathIsValidNumber(b_ratio[0]) && b_ratio[0] > 0.0 && b_ratio[0] < 100.0)
                  {
                     ratio_val = b_ratio[0];
                     has_ratio = true;
                     break;
                  }
               }
            }
         }
      }
      
      if(has_activity || has_ratio) d.valid_bars++;
      
      if(inc_delta > 0.0)      run_inc_pos += inc_delta;
      else if(inc_delta < 0.0) run_inc_neg += inc_delta;
      double inc_net_running = run_inc_pos + run_inc_neg;
      
      if(dec_delta > 0.0)      run_dec_pos += dec_delta;
      else if(dec_delta < 0.0) run_dec_neg += dec_delta;
      double dec_net_running = run_dec_pos + run_dec_neg;
      
      string time_12_bst     = FormatTime12(bar_time_bst);
      string time_broker_hm  = TimeToString(bar_time_broker, TIME_MINUTES);
      string ts_12_bst       = FormatDateTime12(bar_time_bst);
      string ts_broker_full  = TimeToString(bar_time_broker, TIME_DATE|TIME_SECONDS);
      string behavior_tag    = BuildBehaviorTag(inc_delta, dec_delta);
      
      string item = "{"
         + "\"time\":\"" + time_12_bst + "\","
         + "\"time_broker\":\"" + time_broker_hm + "\","
         + "\"timestamp\":\"" + ts_12_bst + "\","
         + "\"timestamp_broker\":\"" + ts_broker_full + "\","
         + StringFormat("\"ratio\":%.2f,", ratio_val)
         + StringFormat("\"inc_20m\":%.4f,\"inc_cum_pos\":%.4f,\"inc_cum_neg\":%.4f,\"inc_running_net\":%.4f,", inc_delta, run_inc_pos, run_inc_neg, inc_net_running)
         + StringFormat("\"dec_20m\":%.4f,\"dec_cum_pos\":%.4f,\"dec_cum_neg\":%.4f,\"dec_running_net\":%.4f,", dec_delta, run_dec_pos, run_dec_neg, dec_net_running)
         + "\"behavior_tag\":\"" + behavior_tag + "\""
         + "}";
         
      if(d.intervals_json != "") d.intervals_json += ",";
      d.intervals_json += item;
   }
   
   d.inc_pos = run_inc_pos;
   d.inc_neg = run_inc_neg;
   d.inc_net = run_inc_pos + run_inc_neg;
   d.dec_pos = run_dec_pos;
   d.dec_neg = run_dec_neg;
   d.dec_net = run_dec_pos + run_dec_neg;
   d.contrarian_bias = DetermineContrarianBias(d.inc_net, d.dec_net);
   
   return d;
}

//+------------------------------------------------------------------+
//| Recalculate Multi-Day Gold Delta and Export JSON                 |
//+------------------------------------------------------------------+
void RecalculateAndExport(string update_type, bool full_history_refresh)
{
   datetime now_local   = TimeLocal();
   datetime now_current = TimeCurrent();
   long heartbeat_epoch = (long)now_local;
   int  bst_offset_sec  = GetBstOffsetSeconds();
   
   datetime now_bst     = now_current + bst_offset_sec;
   datetime day_open    = iTime(g_gold_symbol, PERIOD_D1, 0);
   if(day_open == 0)
   {
      day_open = now_current - (now_current % 86400);
   }
   datetime day_open_bst = day_open + bst_offset_sec;
   
   // Diagnostics setup
   bool terminal_connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   bool dlls_allowed       = (bool)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED);
   
   if(g_hIndicator == INVALID_HANDLE)
   {
      g_hIndicator = BindActivityIndicator();
   }
   if(g_hRatios == INVALID_HANDLE)
   {
      g_hRatios = BindRatiosIndicator();
   }
   
   bool indicator_found = (g_hIndicator != INVALID_HANDLE);
   bool ratios_found    = (g_hRatios != INVALID_HANDLE);
   bool data_ready      = false;
   string error_message = "";
   
   if(!dlls_allowed)
   {
      error_message = "DLL imports are disabled in MT5! Enable Tools -> Options -> Expert Advisors -> Allow DLL imports.";
   }
   else if(!indicator_found)
   {
      error_message = "Activity Indicator could not be bound on " + g_gold_symbol + ".";
   }
   
   // 1. Process Day 0 (Today / Active Day)
   DayData today_data = ProcessSingleDay(0, now_current, bst_offset_sec);
   
   if(dlls_allowed && indicator_found)
   {
      if(today_data.valid_bars > 0)
      {
         data_ready = true;
         if(today_data.valid_bars < today_data.total_bars)
         {
            error_message = StringFormat("Synchronizing Gold sentiment history: %d of %d expected bars loaded.", today_data.valid_bars, today_data.total_bars);
         }
      }
      else
      {
         data_ready = false;
         error_message = "Synchronizing Gold sentiment data...";
      }
   }
   
   // 2. Multi-day history processing
   if(full_history_refresh || g_cached_past_days_json == "")
   {
      int available_daily_bars = iBars(g_gold_symbol, PERIOD_D1);
      int max_days = InpMaxHistoryDays;
      if(max_days > available_daily_bars && available_daily_bars > 0)
      {
         max_days = available_daily_bars;
      }
      if(max_days < 1) max_days = 1;
      
      string past_days_json = "";
      int loaded_past_days = 0;
      
      for(int d = 1; d < max_days; d++)
      {
         DayData past_d = ProcessSingleDay(d, now_current, bst_offset_sec);
         if(past_d.valid_bars == 0) continue;
         
         loaded_past_days++;
         
         string day_item = "{\n";
         day_item += StringFormat("      \"date\": \"%s\",\n", past_d.date_broker);
         day_item += StringFormat("      \"date_bst\": \"%s\",\n", past_d.date_bst);
         day_item += StringFormat("      \"day_name\": \"%s\",\n", past_d.day_name);
         day_item += "      \"is_today\": false,\n";
         day_item += StringFormat("      \"valid_bars\": %d,\n", past_d.valid_bars);
         day_item += StringFormat("      \"total_bars\": %d,\n", past_d.total_bars);
         day_item += "      \"summary\": {\n";
         day_item += "        \"increase\": {\n";
         day_item += StringFormat("          \"sum_pos\": %.4f,\n", past_d.inc_pos);
         day_item += StringFormat("          \"sum_neg\": %.4f,\n", past_d.inc_neg);
         day_item += StringFormat("          \"net_delta\": %.4f\n", past_d.inc_net);
         day_item += "        },\n";
         day_item += "        \"decrease\": {\n";
         day_item += StringFormat("          \"sum_pos\": %.4f,\n", past_d.dec_pos);
         day_item += StringFormat("          \"sum_neg\": %.4f,\n", past_d.dec_neg);
         day_item += StringFormat("          \"net_delta\": %.4f\n", past_d.dec_net);
         day_item += "        },\n";
         day_item += StringFormat("        \"contrarian_bias\": \"%s\"\n", past_d.contrarian_bias);
         day_item += "      },\n";
         day_item += "      \"intervals\": [\n        " + past_d.intervals_json + "\n      ]\n";
         day_item += "    }";
         
         if(past_days_json != "") past_days_json += ",\n";
         past_days_json += day_item;
      }
      
      g_cached_past_days_json = past_days_json;
      g_cached_history_days_count = loaded_past_days;
   }
   
   // 3. Assemble Day 0 JSON entry
   string today_entry_json = "{\n";
   today_entry_json += StringFormat("      \"date\": \"%s\",\n", today_data.date_broker);
   today_entry_json += StringFormat("      \"date_bst\": \"%s\",\n", today_data.date_bst);
   today_entry_json += StringFormat("      \"day_name\": \"%s\",\n", today_data.day_name);
   today_entry_json += "      \"is_today\": true,\n";
   today_entry_json += StringFormat("      \"valid_bars\": %d,\n", today_data.valid_bars);
   today_entry_json += StringFormat("      \"total_bars\": %d,\n", today_data.total_bars);
   today_entry_json += "      \"summary\": {\n";
   today_entry_json += "        \"increase\": {\n";
   today_entry_json += StringFormat("          \"sum_pos\": %.4f,\n", today_data.inc_pos);
   today_entry_json += StringFormat("          \"sum_neg\": %.4f,\n", today_data.inc_neg);
   today_entry_json += StringFormat("          \"net_delta\": %.4f\n", today_data.inc_net);
   today_entry_json += "        },\n";
   today_entry_json += "        \"decrease\": {\n";
   today_entry_json += StringFormat("          \"sum_pos\": %.4f,\n", today_data.dec_pos);
   today_entry_json += StringFormat("          \"sum_neg\": %.4f,\n", today_data.dec_neg);
   today_entry_json += StringFormat("          \"net_delta\": %.4f\n", today_data.dec_net);
   today_entry_json += "        },\n";
   today_entry_json += StringFormat("        \"contrarian_bias\": \"%s\"\n", today_data.contrarian_bias);
   today_entry_json += "      },\n";
   today_entry_json += "      \"intervals\": [\n        " + today_data.intervals_json + "\n      ]\n";
   today_entry_json += "    }";
   
   string all_days_json = today_entry_json;
   if(g_cached_past_days_json != "")
   {
      all_days_json += ",\n" + g_cached_past_days_json;
   }
   
   int total_history_days = 1 + g_cached_history_days_count;
   
   // Live Gold Market Price Readings
   double gold_bid = SymbolInfoDouble(g_gold_symbol, SYMBOL_BID);
   double gold_ask = SymbolInfoDouble(g_gold_symbol, SYMBOL_ASK);
   double gold_open = iOpen(g_gold_symbol, PERIOD_D1, 0);
   double gold_high = iHigh(g_gold_symbol, PERIOD_D1, 0);
   double gold_low  = iLow(g_gold_symbol, PERIOD_D1, 0);
   if(gold_bid <= 0.0) gold_bid = iClose(g_gold_symbol, _Period, 0);
   if(gold_ask <= 0.0) gold_ask = gold_bid + 0.20;
   if(gold_open <= 0.0) gold_open = gold_bid;
   if(gold_high <= 0.0) gold_high = gold_bid;
   if(gold_low <= 0.0)  gold_low = gold_bid;
   double gold_change = gold_bid - gold_open;
   double gold_change_pct = (gold_open > 0) ? (gold_change / gold_open) * 100.0 : 0.0;
   double gold_spread = (gold_ask - gold_bid);
   
   // 4. Assemble Master JSON Payload
   string json = "{\n";
   json += StringFormat("  \"heartbeat_epoch\": %I64d,\n", heartbeat_epoch);
   json += StringFormat("  \"symbol\": \"%s\",\n", g_gold_symbol);
   json += "  \"asset\": \"GOLD\",\n";
   json += "  \"source\": \"Public Activity Delta Bridge\",\n";
   json += StringFormat("  \"period\": \"%s\",\n", EnumToString((ENUM_TIMEFRAMES)_Period));
   json += "  \"timezone\": \"Asia/Dhaka (BST, UTC+6)\",\n";
   json += "  \"time_format\": \"12-hour (hh:mm AM/PM)\",\n";
   json += StringFormat("  \"day_open_time\": \"%s\",\n", TimeToString(day_open, TIME_DATE|TIME_SECONDS));
   json += StringFormat("  \"day_open_time_bst\": \"%s\",\n", FormatDateTime12(day_open_bst));
   json += StringFormat("  \"broker_time\": \"%s\",\n", TimeToString(now_current, TIME_DATE|TIME_SECONDS));
   json += StringFormat("  \"broker_time_bst\": \"%s\",\n", FormatDateTime12(now_bst));
   json += StringFormat("  \"current_time_bst\": \"%s\",\n", FormatTime12(now_bst));
   json += StringFormat("  \"last_update_type\": \"%s\",\n", update_type);
   json += StringFormat("  \"total_history_days\": %d,\n", total_history_days);
   
   // Live Gold Market Stats
   json += "  \"market\": {\n";
   json += StringFormat("    \"symbol\": \"%s\",\n", g_gold_symbol);
   json += "    \"name\": \"Gold Spot / US Dollar\",\n";
   json += StringFormat("    \"bid\": %.2f,\n", gold_bid);
   json += StringFormat("    \"ask\": %.2f,\n", gold_ask);
   json += StringFormat("    \"spread\": %.2f,\n", gold_spread);
   json += StringFormat("    \"day_open\": %.2f,\n", gold_open);
   json += StringFormat("    \"day_high\": %.2f,\n", gold_high);
   json += StringFormat("    \"day_low\": %.2f,\n", gold_low);
   json += StringFormat("    \"change\": %.2f,\n", gold_change);
   json += StringFormat("    \"change_pct\": %.2f\n", gold_change_pct);
   json += "  },\n";
   
   // Diagnostics section
   json += "  \"diagnostics\": {\n";
   json += StringFormat("    \"terminal_connected\": %s,\n", terminal_connected ? "true" : "false");
   json += StringFormat("    \"dlls_allowed\": %s,\n", dlls_allowed ? "true" : "false");
   json += StringFormat("    \"indicator_found\": %s,\n", indicator_found ? "true" : "false");
   json += StringFormat("    \"ratios_found\": %s,\n", ratios_found ? "true" : "false");
   json += StringFormat("    \"data_ready\": %s,\n", data_ready ? "true" : "false");
   json += StringFormat("    \"expected_bars_today\": %d,\n", today_data.total_bars);
   json += StringFormat("    \"valid_bars_loaded\": %d,\n", today_data.valid_bars);
   json += StringFormat("    \"history_days_loaded\": %d,\n", total_history_days);
   json += StringFormat("    \"error_message\": \"%s\"\n", error_message);
   json += "  },\n";
   
   // Top-Level Summary (Today / Active Day)
   json += "  \"summary\": {\n";
   json += "    \"increase\": {\n";
   json += StringFormat("      \"sum_pos\": %.4f,\n", today_data.inc_pos);
   json += StringFormat("      \"sum_neg\": %.4f,\n", today_data.inc_neg);
   json += StringFormat("      \"net_delta\": %.4f\n", today_data.inc_net);
   json += "    },\n";
   json += "    \"decrease\": {\n";
   json += StringFormat("      \"sum_pos\": %.4f,\n", today_data.dec_pos);
   json += StringFormat("      \"sum_neg\": %.4f,\n", today_data.dec_neg);
   json += StringFormat("      \"net_delta\": %.4f\n", today_data.dec_net);
   json += "    },\n";
   json += StringFormat("    \"contrarian_bias\": \"%s\"\n", today_data.contrarian_bias);
   json += "  },\n";
   
   // Top-Level Intervals
   json += "  \"intervals\": [\n    " + today_data.intervals_json + "\n  ],\n";
   
   // Multi-Day History Array
   json += "  \"days\": [\n    " + all_days_json + "\n  ]\n";
   json += "}\n";
   
   ResetLastError();
   int file_handle = FileOpen(InpJsonFileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file_handle != INVALID_HANDLE)
   {
      FileWriteString(file_handle, json);
      FileClose(file_handle);
      if(full_history_refresh || update_type == "INIT_STARTUP" || update_type == "WEB_REFRESH" || update_type == "MANUAL_CHART_CLICK")
      {
         PrintFormat("[Public Activity Delta] Exported %d days (%d today bars) to %s (IncNet=%.2f, DecNet=%.2f, RatiosFound=%s BST)", 
            total_history_days, today_data.valid_bars, InpJsonFileName, today_data.inc_net, today_data.dec_net, ratios_found ? "YES" : "NO");
      }
   }
}

//+------------------------------------------------------------------+
//| Determine Crowd Behavior Tag                                     |
//+------------------------------------------------------------------+
string BuildBehaviorTag(double inc, double dec)
{
   if(inc > 0.05 && dec < -0.05) return "Aggressive Retail Buying (Longs Opening + Shorts Closing)";
   if(inc < -0.05 && dec > 0.05) return "Aggressive Retail Selling (Shorts Opening + Longs Closing)";
   if(inc > 0.05 && dec > 0.05)  return "Long Rotation (Longs Opening & Taking Profits)";
   if(inc < -0.05 && dec < -0.05) return "Short Rotation (Shorts Opening & Short Covering)";
   if(inc > 0.05)                return "Fresh Retail Buying (Longs Opening)";
   if(inc < -0.05)               return "Fresh Retail Selling (Shorts Opening)";
   if(dec > 0.05)                return "Profit Taking / Exit (Longs Closing)";
   if(dec < -0.05)               return "Short Squeeze / Covering (Shorts Closing)";
   return "Balanced Neutral Flow";
}

//+------------------------------------------------------------------+
//| Determine Institutional Contrarian Bias for Gold                 |
//+------------------------------------------------------------------+
string DetermineContrarianBias(double inc_net, double dec_net)
{
   if(inc_net >= 0.50 && dec_net <= -0.15)
   {
      return "Strong Bearish (Crowd Heavy Buying + Covering Shorts)";
   }
   if(inc_net >= 0.20)
   {
      return "Bearish (Crowd Net Buying / Smart Money Fade)";
   }
   if(inc_net <= -0.50 && dec_net >= 0.15)
   {
      return "Strong Bullish (Crowd Heavy Shorting + Long Exits)";
   }
   if(inc_net <= -0.20)
   {
      return "Bullish (Crowd Net Shorting / Smart Money Long)";
   }
   if(MathAbs(inc_net) < 0.20 && MathAbs(dec_net) < 0.20)
   {
      return "Neutral Equilibrium (Balanced Crowd Flow)";
   }
   return "Moderate Mixed Bias";
}

//+------------------------------------------------------------------+
//| Create On-Chart Refresh Button                                   |
//+------------------------------------------------------------------+
void CreateChartButton()
{
   ObjectDelete(0, g_button_name);
   
   ObjectCreate(0, g_button_name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, g_button_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_button_name, OBJPROP_XDISTANCE, 18);
   ObjectSetInteger(0, g_button_name, OBJPROP_YDISTANCE, 24);
   ObjectSetInteger(0, g_button_name, OBJPROP_XSIZE, 190);
   ObjectSetInteger(0, g_button_name, OBJPROP_YSIZE, 34);
   ObjectSetString(0, g_button_name, OBJPROP_TEXT, "REFRESH DELTA (BST)");
   ObjectSetString(0, g_button_name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, g_button_name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_button_name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_button_name, OBJPROP_BGCOLOR, C'24,140,80');
   ObjectSetInteger(0, g_button_name, OBJPROP_BORDER_COLOR, C'46,204,113');
   ObjectSetInteger(0, g_button_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, g_button_name, OBJPROP_STATE, false);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update On-Chart Refresh Button Appearance                        |
//+------------------------------------------------------------------+
void UpdateChartButton(string text, color bg_col)
{
   ObjectSetString(0, g_button_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, g_button_name, OBJPROP_BGCOLOR, bg_col);
   ChartRedraw();
}
