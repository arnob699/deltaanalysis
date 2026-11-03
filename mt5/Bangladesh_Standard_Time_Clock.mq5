//+------------------------------------------------------------------+
//|                               Bangladesh_Standard_Time_Clock.mq5 |
//|                                  Copyright 2026, Delta Analyse   |
//+------------------------------------------------------------------+
#property copyright   "Delta Analyse"
#property link        "http://localhost"
#property version     "1.00"
#property description "Live Bangladesh Standard Time (BST, UTC+6) Clock and Candle Countdown for MT5"
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "---- Timezone Settings ----"
input int              InpBstUtcOffsetHours = 6;                  // Bangladesh UTC Offset (BST = UTC+6)

input group "---- Display Position & Styling ----"
input ENUM_BASE_CORNER InpClockCorner       = CORNER_RIGHT_UPPER; // Screen Corner (Right-Upper by default)
input int              InpClockX            = 20;                 // X Distance from Corner (Pixels)
input int              InpClockY            = 30;                 // Y Distance from Corner (Pixels)
input color            InpBgColor           = C'16,23,36';        // Panel Background Color
input color            InpBorderColor       = C'42,58,84';        // Panel Border Color
input color            InpClockColor        = clrWhite;           // Live Clock Color
input color            InpTitleColor        = C'245,185,25';      // Header Title Color (Gold)

// Global Object Names
string g_obj_bg    = "BST_HUD_BOX";
string g_obj_title = "BST_HUD_TITLE";
string g_obj_clock = "BST_HUD_CLOCK";
string g_obj_date  = "BST_HUD_DATE";
string g_obj_info  = "BST_HUD_INFO";

//+------------------------------------------------------------------+
//| Helper: Calculate Bangladesh Time Offset                         |
//+------------------------------------------------------------------+
int GetBstOffsetSeconds()
{
   datetime gmt = TimeGMT();
   datetime cur = TimeCurrent();
   if(gmt > 0 && cur > 0)
   {
      int broker_utc_offset = (int)(cur - gmt);
      return (InpBstUtcOffsetHours * 3600) - broker_utc_offset;
   }
   datetime loc = TimeLocal();
   int diff = (int)(loc - cur);
   int rounded = (int)MathRound((double)diff / 1800.0) * 1800;
   if(rounded == 0) rounded = InpBstUtcOffsetHours * 3600;
   return rounded;
}

//+------------------------------------------------------------------+
//| Helper: Format 12-Hour Time with Seconds "hh:mm:ss AM/PM"        |
//+------------------------------------------------------------------+
string FormatTime12(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   int h = mdt.hour;
   int m = mdt.min;
   int s = mdt.sec;
   string ampm = (h >= 12) ? "PM" : "AM";
   int h12 = h % 12;
   if(h12 == 0) h12 = 12;
   return StringFormat("%02d:%02d:%02d %s", h12, m, s, ampm);
}

//+------------------------------------------------------------------+
//| Helper: Day of Week Name                                         |
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
//| Create Clock Objects on Chart                                    |
//+------------------------------------------------------------------+
void CreateClockPanel()
{
   RemoveClockPanel();

   int x = InpClockX;
   int y = InpClockY;

   // 1. Background Panel
   ObjectCreate(0, g_obj_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_CORNER, InpClockCorner);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_YSIZE, 76);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_BORDER_COLOR, InpBorderColor);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_obj_bg, OBJPROP_SELECTABLE, false);

   // 2. Title Label (Gold)
   ObjectCreate(0, g_obj_title, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_obj_title, OBJPROP_CORNER, InpClockCorner);
   ObjectSetInteger(0, g_obj_title, OBJPROP_XDISTANCE, x + 12);
   ObjectSetInteger(0, g_obj_title, OBJPROP_YDISTANCE, y + 8);
   ObjectSetString(0, g_obj_title, OBJPROP_TEXT, "BANGLADESH TIME (BST, UTC+6)");
   ObjectSetString(0, g_obj_title, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, g_obj_title, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_obj_title, OBJPROP_COLOR, InpTitleColor);
   ObjectSetInteger(0, g_obj_title, OBJPROP_SELECTABLE, false);

   // 3. Live BST Clock (Large Bold)
   ObjectCreate(0, g_obj_clock, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_obj_clock, OBJPROP_CORNER, InpClockCorner);
   ObjectSetInteger(0, g_obj_clock, OBJPROP_XDISTANCE, x + 12);
   ObjectSetInteger(0, g_obj_clock, OBJPROP_YDISTANCE, y + 22);
   ObjectSetString(0, g_obj_clock, OBJPROP_TEXT, "--:--:-- --");
   ObjectSetString(0, g_obj_clock, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, g_obj_clock, OBJPROP_FONTSIZE, 13);
   ObjectSetInteger(0, g_obj_clock, OBJPROP_COLOR, InpClockColor);
   ObjectSetInteger(0, g_obj_clock, OBJPROP_SELECTABLE, false);

   // 4. Date Label
   ObjectCreate(0, g_obj_date, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_obj_date, OBJPROP_CORNER, InpClockCorner);
   ObjectSetInteger(0, g_obj_date, OBJPROP_XDISTANCE, x + 140);
   ObjectSetInteger(0, g_obj_date, OBJPROP_YDISTANCE, y + 26);
   ObjectSetString(0, g_obj_date, OBJPROP_TEXT, "---");
   ObjectSetString(0, g_obj_date, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, g_obj_date, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_obj_date, OBJPROP_COLOR, C'165,190,220');
   ObjectSetInteger(0, g_obj_date, OBJPROP_SELECTABLE, false);

   // 5. Broker Time & Candle Countdown
   ObjectCreate(0, g_obj_info, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_obj_info, OBJPROP_CORNER, InpClockCorner);
   ObjectSetInteger(0, g_obj_info, OBJPROP_XDISTANCE, x + 12);
   ObjectSetInteger(0, g_obj_info, OBJPROP_YDISTANCE, y + 52);
   ObjectSetString(0, g_obj_info, OBJPROP_TEXT, "---");
   ObjectSetString(0, g_obj_info, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, g_obj_info, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_obj_info, OBJPROP_COLOR, C'46,204,113');
   ObjectSetInteger(0, g_obj_info, OBJPROP_SELECTABLE, false);

   UpdateClockPanel();
}

//+------------------------------------------------------------------+
//| Update Clock Display                                             |
//+------------------------------------------------------------------+
void UpdateClockPanel()
{
   int bst_offset = GetBstOffsetSeconds();
   datetime cur = TimeCurrent();
   datetime now_bst = cur + bst_offset;

   // 1. Clock
   ObjectSetString(0, g_obj_clock, OBJPROP_TEXT, FormatTime12(now_bst));

   // 2. Date
   string day_str = GetDayOfWeekName(now_bst);
   string date_str = TimeToString(now_bst, TIME_DATE);
   ObjectSetString(0, g_obj_date, OBJPROP_TEXT, day_str + " | " + date_str);

   // 3. Candle Closes In
   int bar_sec = PeriodSeconds(_Period);
   datetime bar_open = iTime(_Symbol, _Period, 0);
   int sec_elapsed = (int)(cur - bar_open);
   int sec_left = (bar_sec > sec_elapsed) ? (bar_sec - sec_elapsed) : 0;
   string cd_str = StringFormat("%02dm %02ds", sec_left / 60, sec_left % 60);

   // 4. Broker time
   string broker_time = TimeToString(cur, TIME_SECONDS);

   string info_text = StringFormat("Broker Server: %s  |  Candle Closes: %s", broker_time, cd_str);
   ObjectSetString(0, g_obj_info, OBJPROP_TEXT, info_text);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Remove Clock Objects                                             |
//+------------------------------------------------------------------+
void RemoveClockPanel()
{
   ObjectDelete(0, g_obj_bg);
   ObjectDelete(0, g_obj_title);
   ObjectDelete(0, g_obj_clock);
   ObjectDelete(0, g_obj_date);
   ObjectDelete(0, g_obj_info);
}

//+------------------------------------------------------------------+
//| Indicator Initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   CreateClockPanel();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator Deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemoveClockPanel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Timer Event (1s update)                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateClockPanel();
}

//+------------------------------------------------------------------+
//| Indicator Calculation (OnTick update)                            |
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
   UpdateClockPanel();
   return(rates_total);
}
//+------------------------------------------------------------------+
