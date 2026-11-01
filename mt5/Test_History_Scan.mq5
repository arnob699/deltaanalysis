//+------------------------------------------------------------------+
//|                                           Test_History_Scan.mq5  |
//|                                  Copyright 2026, Delta Analyse   |
//+------------------------------------------------------------------+
#property copyright "Delta Analyse"
#property script_show_inputs

input string InpGoldSymbol = "XAUUSDm";
input int    InpMaxDays    = 29;

void OnStart()
{
   Print("==================================================================");
   Print("[FXSSI History Test] Checking past ", InpMaxDays, " days on ", InpGoldSymbol);
   
   // 1. Locate indicator handle
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
            if(hInd != INVALID_HANDLE)
            {
               PrintFormat("[FXSSI History Test] Found indicator in Window %d: '%s' (Handle=%d)", w, name, hInd);
               break;
            }
         }
      }
      if(hInd != INVALID_HANDLE) break;
   }
   
   if(hInd == INVALID_HANDLE)
   {
      Print("[FXSSI History Test] Indicator not found on chart!");
      return;
   }
   
   datetime now_curr = TimeCurrent();
   int daily_bars_available = iBars(InpGoldSymbol, PERIOD_D1);
   PrintFormat("[FXSSI History Test] Daily bars available on %s: %d", InpGoldSymbol, daily_bars_available);
   
   int days_to_scan = InpMaxDays;
   if(days_to_scan > daily_bars_available) days_to_scan = daily_bars_available;
   
   int days_with_data = 0;
   
   for(int d = 0; d < days_to_scan; d++)
   {
      datetime d_open = iTime(InpGoldSymbol, PERIOD_D1, d);
      if(d_open == 0) continue;
      
      int valid_bars_in_day = 0;
      double sum_inc = 0.0;
      double sum_dec = 0.0;
      
      // Check 72 M20 intervals in this day
      for(int k = 0; k < 72; k++)
      {
         datetime bar_time = d_open + k * 1200;
         if(bar_time > now_curr) break;
         
         int shift = iBarShift(InpGoldSymbol, _Period, bar_time, true);
         if(shift == -1) shift = iBarShift(InpGoldSymbol, _Period, bar_time, false);
         if(shift == -1) continue;
         
         double b_inc_pos[], b_inc_neg[], b_dec_pos[], b_dec_neg[];
         double inc = 0.0, dec = 0.0;
         bool has = false;
         
         if(CopyBuffer(hInd, 4, shift, 1, b_inc_pos) > 0 && b_inc_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_pos[0]) && b_inc_pos[0] > 0.0001 && b_inc_pos[0] <= 100.0)
         {
            inc = b_inc_pos[0];
            has = true;
         }
         else if(CopyBuffer(hInd, 5, shift, 1, b_inc_neg) > 0 && b_inc_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_inc_neg[0]) && MathAbs(b_inc_neg[0]) > 0.0001 && MathAbs(b_inc_neg[0]) <= 100.0)
         {
            inc = (b_inc_neg[0] > 0) ? -b_inc_neg[0] : b_inc_neg[0];
            has = true;
         }
         
         if(CopyBuffer(hInd, 6, shift, 1, b_dec_pos) > 0 && b_dec_pos[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_pos[0]) && b_dec_pos[0] > 0.0001 && b_dec_pos[0] <= 100.0)
         {
            dec = b_dec_pos[0];
            has = true;
         }
         else if(CopyBuffer(hInd, 7, shift, 1, b_dec_neg) > 0 && b_dec_neg[0] != EMPTY_VALUE && MathIsValidNumber(b_dec_neg[0]) && MathAbs(b_dec_neg[0]) > 0.0001 && MathAbs(b_dec_neg[0]) <= 100.0)
         {
            dec = (b_dec_neg[0] > 0) ? -b_dec_neg[0] : b_dec_neg[0];
            has = true;
         }
         
         if(has)
         {
            valid_bars_in_day++;
            sum_inc += inc;
            sum_dec += dec;
         }
      }
      
      PrintFormat("[FXSSI History Test] Day [%02d] Date: %s | Valid M20 Bars: %d/72 | IncNet: %+.2f | DecNet: %+.2f",
         d, TimeToString(d_open, TIME_DATE), valid_bars_in_day, sum_inc, sum_dec);
         
      if(valid_bars_in_day > 0) days_with_data++;
   }
   
   PrintFormat("[FXSSI History Test] COMPLETED: %d of %d days have valid FXSSI delta data!", days_with_data, days_to_scan);
   Print("==================================================================");
}

