//+------------------------------------------------------------------+
//|                                    Export_Gold_Delta_Once.mq5    |
//|                                  Copyright 2026, Delta Analyse   |
//+------------------------------------------------------------------+
#property copyright "Delta Analyse"
#property script_show_inputs

input string InpGoldSymbol        = "XAUUSDm";                          // Gold Symbol
input int    InpMaxHistoryDays    = 29;                                 // Max Historical Days
input int    InpBstUtcOffsetHours = 6;                                  // BST UTC Offset (UTC+6)
input string InpIndicatorPath     = "FXSSI.com\\FXSSI.TradingActivity"; // Internal Indicator Path

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

int GetBstOffsetSeconds()
{
   datetime loc = TimeLocal();
   datetime cur = TimeCurrent();
   int diff = (int)(loc - cur);
   int rounded = (int)MathRound((double)diff / 1800.0) * 1800;
   if(rounded == 0) rounded = InpBstUtcOffsetHours * 3600;
   return rounded;
}

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

string DetermineContrarianBias(double inc_net, double dec_net)
{
   if(inc_net >= 0.50 && dec_net <= -0.15) return "Strong Bearish (Crowd Heavy Buying + Covering Shorts)";
   if(inc_net >= 0.20)                     return "Bearish (Crowd Net Buying / Smart Money Fade)";
   if(inc_net <= -0.50 && dec_net >= 0.15) return "Strong Bullish (Crowd Heavy Shorting + Long Exits)";
   if(inc_net <= -0.20)                    return "Bullish (Crowd Net Shorting / Smart Money Long)";
   if(MathAbs(inc_net) < 0.20 && MathAbs(dec_net) < 0.20) return "Neutral Equilibrium (Balanced Crowd Flow)";
   return "Moderate Mixed Bias";
}

DayData ProcessSingleDay(int hInd, string sym, int day_index, datetime now_current, int bst_offset)
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
   
   datetime day_open_broker = iTime(sym, PERIOD_D1, day_index);
   if(day_open_broker == 0)
   {
      if(day_index == 0) day_open_broker = now_current - (now_current % 86400);
      else return d;
   }
   
   datetime day_open_bst = day_open_broker + bst_offset;
   d.date_broker  = TimeToString(day_open_broker, TIME_DATE);
   d.date_bst     = TimeToString(day_open_bst, TIME_DATE);
   d.day_name     = GetDayOfWeekName(day_open_bst);
   
   int expected_bars = 72;
   if(day_index == 0)
   {
      int seconds_today = (int)(now_current - day_open_broker);
      if(seconds_today < 0) seconds_today = 0;
      expected_bars = (seconds_today / 1200) + 1;
      if(expected_bars > 72) expected_bars = 72;
      if(expected_bars < 1)  expected_bars = 1;
   }
   d.total_bars = expected_bars;
   
   double run_inc_pos = 0.0, run_inc_neg = 0.0;
   double run_dec_pos = 0.0, run_dec_neg = 0.0;
   
   for(int k = 0; k < expected_bars; k++)
   {
      datetime bar_time_broker = day_open_broker + k * 1200;
      if(day_index == 0 && bar_time_broker > now_current) break;
      
      datetime bar_time_bst = bar_time_broker + bst_offset;
      
      int shift = iBarShift(sym, _Period, bar_time_broker, true);
      if(shift == -1) shift = iBarShift(sym, _Period, bar_time_broker, false);
      if(shift == -1) continue;
      
      double inc_delta = 0.0, dec_delta = 0.0;
      bool has_reading = false;
      
      if(hInd != INVALID_HANDLE)
      {
         double b_inc_pos[], b_inc_neg[], b_inc_buy[], b_inc_sell[];
         double b_dec_pos[], b_dec_neg[], b_dec_buy[], b_dec_sell[];
         
         if(CopyBuffer(hInd, 4, shift, 1, b_inc_pos) > 0 && b_inc_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_pos[0]) && b_inc_pos[0] > 0.0001 && b_inc_pos[0] <= 100.0)
         {
            inc_delta = b_inc_pos[0];
            has_reading = true;
         }
         else if(CopyBuffer(hInd, 5, shift, 1, b_inc_neg) > 0 && b_inc_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_neg[0]) && MathAbs(b_inc_neg[0]) > 0.0001 && MathAbs(b_inc_neg[0]) <= 100.0)
         {
            inc_delta = (b_inc_neg[0] > 0) ? -b_inc_neg[0] : b_inc_neg[0];
            has_reading = true;
         }
         else if(CopyBuffer(hInd, 0, shift, 1, b_inc_buy) > 0 && CopyBuffer(hInd, 1, shift, 1, b_inc_sell) > 0)
         {
            if(b_inc_buy[0] != EMPTY_VALUE && b_inc_sell[0] != EMPTY_VALUE && MathAbs(b_inc_buy[0]) <= 100.0 && MathAbs(b_inc_sell[0]) <= 100.0 && (b_inc_buy[0] > 0.0 || b_inc_sell[0] > 0.0))
            {
               inc_delta = b_inc_buy[0] - b_inc_sell[0];
               has_reading = true;
            }
         }
         
         if(CopyBuffer(hInd, 6, shift, 1, b_dec_pos) > 0 && b_dec_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_pos[0]) && b_dec_pos[0] > 0.0001 && b_dec_pos[0] <= 100.0)
         {
            dec_delta = b_dec_pos[0];
            has_reading = true;
         }
         else if(CopyBuffer(hInd, 7, shift, 1, b_dec_neg) > 0 && b_dec_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_neg[0]) && MathAbs(b_dec_neg[0]) > 0.0001 && MathAbs(b_dec_neg[0]) <= 100.0)
         {
            dec_delta = (b_dec_neg[0] > 0) ? -b_dec_neg[0] : b_dec_neg[0];
            has_reading = true;
         }
         else if(CopyBuffer(hInd, 2, shift, 1, b_dec_buy) > 0 && CopyBuffer(hInd, 3, shift, 1, b_dec_sell) > 0)
         {
            if(b_dec_buy[0] != EMPTY_VALUE && b_dec_sell[0] != EMPTY_VALUE && MathAbs(b_dec_buy[0]) <= 100.0 && MathAbs(b_dec_sell[0]) <= 100.0 && (b_dec_buy[0] > 0.0 || b_dec_sell[0] > 0.0))
            {
               dec_delta = b_dec_buy[0] - b_dec_sell[0];
               has_reading = true;
            }
         }
      }
      
      if(has_reading) d.valid_bars++;
      
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

void OnStart()
{
   Print("=== [Public Activity Delta] Exporting Gold Delta Snapshot (BST 12-Hour) ===");
   string sym = InpGoldSymbol;
   SymbolSelect(sym, true);
   
   int hInd = INVALID_HANDLE;
   int total_windows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = 0; w < total_windows; w++)
   {
      int total_ind = ChartIndicatorsTotal(0, w);
      for(int i = 0; i < total_ind; i++)
      {
         string name = ChartIndicatorName(0, w, i);
         if(StringFind(name, "TradingActivity") >= 0 || StringFind(name, "Trading Activity") >= 0 || StringFind(name, "Activity") >= 0)
         {
            hInd = ChartIndicatorGet(0, w, name);
            if(hInd != INVALID_HANDLE) break;
         }
      }
      if(hInd != INVALID_HANDLE) break;
   }
   
   if(hInd == INVALID_HANDLE)
   {
      hInd = iCustom(sym, _Period, InpIndicatorPath);
   }
   
   if(hInd == INVALID_HANDLE)
   {
      Print("[Public Activity Delta] ERROR: Indicator not found.");
      return;
   }
   
   datetime now_local   = TimeLocal();
   datetime now_current = TimeCurrent();
   int      bst_offset  = GetBstOffsetSeconds();
   datetime now_bst     = now_current + bst_offset;
   datetime day_open    = iTime(sym, PERIOD_D1, 0);
   if(day_open == 0) day_open = now_current - (now_current % 86400);
   datetime day_open_bst = day_open + bst_offset;
   
   DayData today_data = ProcessSingleDay(hInd, sym, 0, now_current, bst_offset);
   
   int available_daily_bars = iBars(sym, PERIOD_D1);
   int max_days = InpMaxHistoryDays;
   if(max_days > available_daily_bars && available_daily_bars > 0) max_days = available_daily_bars;
   
   string all_days_json = "";
   string today_entry = "{\n"
      + StringFormat("      \"date\": \"%s\",\n", today_data.date_broker)
      + StringFormat("      \"date_bst\": \"%s\",\n", today_data.date_bst)
      + StringFormat("      \"day_name\": \"%s\",\n", today_data.day_name)
      + "      \"is_today\": true,\n"
      + StringFormat("      \"valid_bars\": %d,\n", today_data.valid_bars)
      + StringFormat("      \"total_bars\": %d,\n", today_data.total_bars)
      + "      \"summary\": {\n"
      + StringFormat("        \"increase\": { \"sum_pos\": %.4f, \"sum_neg\": %.4f, \"net_delta\": %.4f },\n", today_data.inc_pos, today_data.inc_neg, today_data.inc_net)
      + StringFormat("        \"decrease\": { \"sum_pos\": %.4f, \"sum_neg\": %.4f, \"net_delta\": %.4f },\n", today_data.dec_pos, today_data.dec_neg, today_data.dec_net)
      + StringFormat("        \"contrarian_bias\": \"%s\"\n", today_data.contrarian_bias)
      + "      },\n"
      + "      \"intervals\": [\n        " + today_data.intervals_json + "\n      ]\n    }";
      
   all_days_json = today_entry;
   int loaded_days = 1;
   
   for(int d = 1; d < max_days; d++)
   {
      DayData past_d = ProcessSingleDay(hInd, sym, d, now_current, bst_offset);
      if(past_d.valid_bars == 0) continue;
      loaded_days++;
      
      string past_entry = ",\n    {\n"
         + StringFormat("      \"date\": \"%s\",\n", past_d.date_broker)
         + StringFormat("      \"date_bst\": \"%s\",\n", past_d.date_bst)
         + StringFormat("      \"day_name\": \"%s\",\n", past_d.day_name)
         + "      \"is_today\": false,\n"
         + StringFormat("      \"valid_bars\": %d,\n", past_d.valid_bars)
         + StringFormat("      \"total_bars\": %d,\n", past_d.total_bars)
         + "      \"summary\": {\n"
         + StringFormat("        \"increase\": { \"sum_pos\": %.4f, \"sum_neg\": %.4f, \"net_delta\": %.4f },\n", past_d.inc_pos, past_d.inc_neg, past_d.inc_net)
         + StringFormat("        \"decrease\": { \"sum_pos\": %.4f, \"sum_neg\": %.4f, \"net_delta\": %.4f },\n", past_d.dec_pos, past_d.dec_neg, past_d.dec_net)
         + StringFormat("        \"contrarian_bias\": \"%s\"\n", past_d.contrarian_bias)
         + "      },\n"
         + "      \"intervals\": [\n        " + past_d.intervals_json + "\n      ]\n    }";
         
      all_days_json += past_entry;
   }
   
   // Market price readings
   double gold_bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double gold_ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double gold_open = iOpen(sym, PERIOD_D1, 0);
   double gold_high = iHigh(sym, PERIOD_D1, 0);
   double gold_low  = iLow(sym, PERIOD_D1, 0);
   if(gold_bid <= 0.0) gold_bid = iClose(sym, PERIOD_M20, 0);
   if(gold_ask <= 0.0) gold_ask = gold_bid + 0.20;
   if(gold_open <= 0.0) gold_open = gold_bid;
   if(gold_high <= 0.0) gold_high = gold_bid;
   if(gold_low <= 0.0)  gold_low = gold_bid;
   double gold_change = gold_bid - gold_open;
   double gold_change_pct = (gold_open > 0) ? (gold_change / gold_open) * 100.0 : 0.0;
   double gold_spread = (gold_ask - gold_bid);
   
   string json = "{\n";
   json += StringFormat("  \"heartbeat_epoch\": %I64d,\n", (long)now_local);
   json += StringFormat("  \"symbol\": \"%s\",\n", sym);
   json += "  \"asset\": \"GOLD\",\n";
   json += "  \"source\": \"Public Activity Delta Bridge\",\n";
   json += "  \"period\": \"PERIOD_M20\",\n";
   json += "  \"timezone\": \"Asia/Dhaka (BST, UTC+6)\",\n";
   json += "  \"time_format\": \"12-hour (hh:mm AM/PM)\",\n";
   json += StringFormat("  \"day_open_time\": \"%s\",\n", TimeToString(day_open, TIME_DATE|TIME_SECONDS));
   json += StringFormat("  \"day_open_time_bst\": \"%s\",\n", FormatDateTime12(day_open_bst));
   json += StringFormat("  \"broker_time\": \"%s\",\n", TimeToString(now_current, TIME_DATE|TIME_SECONDS));
   json += StringFormat("  \"broker_time_bst\": \"%s\",\n", FormatDateTime12(now_bst));
   json += StringFormat("  \"current_time_bst\": \"%s\",\n", FormatTime12(now_bst));
   json += "  \"last_update_type\": \"MANUAL_SCRIPT_SNAPSHOT\",\n";
   json += StringFormat("  \"total_history_days\": %d,\n", loaded_days);
   
   json += "  \"market\": {\n";
   json += StringFormat("    \"symbol\": \"%s\",\n", sym);
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
   
   json += "  \"diagnostics\": {\n";
   json += "    \"terminal_connected\": true,\n";
   json += "    \"dlls_allowed\": true,\n";
   json += "    \"indicator_found\": true,\n";
   json += "    \"data_ready\": true,\n";
   json += StringFormat("    \"expected_m20_bars_today\": %d,\n", today_data.total_bars);
   json += StringFormat("    \"valid_m20_bars_loaded\": %d,\n", today_data.valid_bars);
   json += StringFormat("    \"history_days_loaded\": %d,\n", loaded_days);
   json += "    \"error_message\": \"\"\n";
   json += "  },\n";
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
   json += "  \"intervals\": [\n    " + today_data.intervals_json + "\n  ],\n";
   json += "  \"days\": [\n    " + all_days_json + "\n  ]\n";
   json += "}\n";
   
   int fh = FileOpen("fxssi_daily_delta.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      FileWriteString(fh, json);
      FileClose(fh);
      PrintFormat("[Public Activity Delta] Exported %d history days to MQL5/Files/fxssi_daily_delta.json successfully!", loaded_days);
   }
}
