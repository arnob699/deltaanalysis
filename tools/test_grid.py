import json
import pandas as pd
from tools.backtest_example1 import load_market_data, calculate_indicators, analyze_performance

df = load_market_data('XAUUSDm')
df = calculate_indicators(df, slc_lookback=20)

def simulate_strategy(tp_mode='OPPOSING_SLC', slc_margin=3.0, tp_target_pts=25.0):
    trades = []
    active = None
    for i in range(1, len(df)):
        prev = df.iloc[i-1]
        curr = df.iloc[i]
        curr_time = curr['timestamp']
        o, h, l, c = curr['open'], curr['high'], curr['low'], curr['close']
        mvp = curr['mvp']
        ratios = curr['ratios']
        upper_slc = curr['upper_slc']
        lower_slc = curr['lower_slc']
        
        if active is not None:
            active['bars_held'] += 1
            b = active['bars_held']
            pos = active['type']
            sl = active['sl']
            tp = active['tp']
            entry_p = active['entry_price']
            
            exit_r = None
            exit_p = None
            
            # SL check
            if pos == 'BUY' and l <= sl:
                exit_r, exit_p = 'SL_HIT', sl
            elif pos == 'SELL' and h >= sl:
                exit_r, exit_p = 'SL_HIT', sl
            # TP check
            elif pos == 'BUY' and h >= tp:
                exit_r, exit_p = 'TP_HIT', tp
            elif pos == 'SELL' and l <= tp:
                exit_r, exit_p = 'TP_HIT', tp
            # MVP zone exit (Rule 4: within MVP zone 4-7 hours = 8-14 bars)
            elif b >= 8 and abs(c - mvp) <= 2.0:
                exit_r, exit_p = 'MVP_ZONE_EXIT', c
            elif b >= 30: # 15 hours timeout
                exit_r, exit_p = 'TIMEOUT', c
                
            if exit_r is not None:
                pnl = (exit_p - entry_p) if pos == 'BUY' else (entry_p - exit_p)
                pnl_usd = pnl * 10.0 # 0.10 lot
                active['exit_time'] = curr_time
                active['exit_price'] = exit_p
                active['exit_reason'] = exit_r
                active['pnl_pts'] = pnl
                active['pnl_usd'] = pnl_usd
                active['is_win'] = pnl_usd > 0
                trades.append(active)
                active = None
                
        if active is None:
            prev_c = prev['close']
            prev_mvp = prev['mvp']
            prev_r = prev['ratios']
            sig = None
            if prev_c < prev_mvp and prev_r >= 60.0:
                sig = 'SELL'
            elif prev_c > prev_mvp and prev_r <= 40.0:
                sig = 'BUY'
                
            if sig is not None:
                entry = o
                if sig == 'SELL':
                    sl = upper_slc + slc_margin
                    if sl <= entry: sl = entry + 15.0
                    if tp_mode == 'OPPOSING_SLC':
                        tp = lower_slc + 1.0 # 5-10 pts margin from cluster towards entry
                        if (entry - tp) < 10.0 or (entry - tp) > 65.0:
                            tp = entry - tp_target_pts
                    else:
                        tp = entry - tp_target_pts
                else:
                    sl = lower_slc - slc_margin
                    if sl >= entry: sl = entry - 15.0
                    if tp_mode == 'OPPOSING_SLC':
                        tp = upper_slc - 1.0
                        if (tp - entry) < 10.0 or (tp - entry) > 65.0:
                            tp = entry + tp_target_pts
                    else:
                        tp = entry + tp_target_pts
                        
                active = {
                    'type': sig,
                    'entry_time': curr_time,
                    'entry_price': entry,
                    'sl': sl,
                    'tp': tp,
                    'bars_held': 0
                }
    return trades

print("=== GRID SIMULATION ===")
for mode in ['OPPOSING_SLC', 'FIXED_TARGET']:
    for target in [15.0, 20.0, 25.0, 30.0, 40.0]:
        t = simulate_strategy(tp_mode=mode, slc_margin=3.0, tp_target_pts=target)
        s = analyze_performance(t)
        print(f"Mode: {mode:12s} | Target: {target:4.1f} pts | Trades: {s['total_trades']:3d} | WinRate: {s['win_rate_pct']:5.1f}% | ProfitFactor: {s['profit_factor']:4.2f} | Net USD: ${s['net_profit_usd']:8.2f} | MaxDD: {s['max_drawdown_pct']:4.1f}%")
