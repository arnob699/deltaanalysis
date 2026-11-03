//+------------------------------------------------------------------+
//|                                     Test_Indicator_Buffers.mq5   |
//+------------------------------------------------------------------+
#property script_show_inputs

input string InpSym = "XAUUSDm";

void OnStart()
{
   Print("=== Testing FXSSI Historical Buffer Depth ===");
   
   int hDeriv = iCustom(InpSym, PERIOD_M30, "FXSSI.com\\FXSSI.Derivatives");
   if(hDeriv == INVALID_HANDLE) hDeriv = iCustom(InpSym, PERIOD_M30, "FXSSI.Derivatives");
   
   int hRatios = iCustom(InpSym, PERIOD_M30, "FXSSI.com\\FXSSI.Ratios");
   if(hRatios == INVALID_HANDLE) hRatios = iCustom(InpSym, PERIOD_M30, "FXSSI.Ratios");
   
   int hSLC = iCustom(InpSym, PERIOD_M30, "FXSSI.com\\FXSSI.StopLossClusters");
   if(hSLC == INVALID_HANDLE) hSLC = iCustom(InpSym, PERIOD_M30, "FXSSI.StopLossClusters");
   
   PrintFormat("Handles: Deriv=%d, Ratios=%d, SLC=%d", hDeriv, hRatios, hSLC);
   
   int test_shifts[] = {0, 10, 50, 100, 200, 500, 1000};
   for(int k=0; k<7; k++)
   {
      int s = test_shifts[k];
      datetime t = iTime(InpSym, PERIOD_M30, s);
      double b_d[], b_r[], b_s[];
      double vd = -1, vr = -1, vs = -1;
      
      if(hDeriv != INVALID_HANDLE && CopyBuffer(hDeriv, 2, s, 1, b_d) > 0) vd = b_d[0];
      if(hRatios != INVALID_HANDLE && CopyBuffer(hRatios, 0, s, 1, b_r) > 0) vr = b_r[0];
      if(hSLC != INVALID_HANDLE && CopyBuffer(hSLC, 0, s, 1, b_s) > 0) vs = b_s[0];
      
      PrintFormat("Shift %d (%s): Deriv=%.2f, Ratios=%.2f, SLC=%.2f", s, TimeToString(t), vd, vr, vs);
   }
   
   if(hDeriv != INVALID_HANDLE) IndicatorRelease(hDeriv);
   if(hRatios != INVALID_HANDLE) IndicatorRelease(hRatios);
   if(hSLC != INVALID_HANDLE) IndicatorRelease(hSLC);
}
