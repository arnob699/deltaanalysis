import sys
sys.path.insert(0, '.')
from tools.backtest_example1 import load_market_data, calculate_indicators, analyze_performance

df = load_market_data('XAUUSDm')
df = calculate_indicators(df, slc_lookback=20)

def test_dynamic_rr(target_pts=20.0, max_risk_ratio=1.5):
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
        
        # 1. Manage active trade
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
            # MVP zone exit
            elif b >= 8 and abs(c - mvp) <= 2.0:
                exit_r, exit_p = 'MVP_ZONE_EXIT', c
            elif b >= 24:
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

        # 2. Check Fresh Transition
        prev_is_sell = (prev['close'] < prev['mvp'] and prev['ratios'] >= 60.0)
        curr_is_sell = (curr['close'] < curr['mvp'] and curr['ratios'] >= 60.0)
        
        prev_is_buy = (prev['close'] > prev['mvp'] and prev['ratios'] <= 40.0)
        curr_is_buy = (curr['close'] > curr['mvp'] and curr['ratios'] <= 40.0)
        
        fresh_sell = curr_is_sell and not prev_is_sell
        fresh_buy  = curr_is_buy and not prev_is_buy
        
        if active is None and i < len(df) - 1:
            next_bar = df.iloc[i+1]
            if fresh_sell:
                entry = next_bar['open']
                # Max SL capped by risk ratio
                max_sl_pts = target_pts * max_risk_ratio
                raw_sl = upper_slc + 3.0
                sl = min(raw_sl, entry + max_sl_pts)
                tp = entry - target_pts
                active = {
                    'type': 'SELL',
                    'entry_time': next_bar['timestamp'],
                    'entry_price': entry,
                    'sl': sl,
                    'tp': tp,
                    'bars_held': 0
                }
            elif fresh_buy:
                entry = next_bar['open']
                max_sl_pts = target_pts * max_risk_ratio
                raw_sl = lower_slc - 3.0
                sl = max(raw_sl, entry - max_sl_pts)
                tp = entry + target_pts
                active = {
                    'type': 'BUY',
                    'entry_time': next_bar['timestamp'],
                    'entry_price': entry,
                    'sl': sl,
                    'tp': tp,
                    'bars_held': 0
                }
    return trades

print("=== RISK-BALANCED SIMULATION ===")
for target in [12.0, 15.0, 20.0, 25.0]:
    for risk_r in [1.0, 1.25, 1.5, 2.0]:
        t = test_dynamic_rr(target_pts=target, max_risk_ratio=risk_r)
        s = analyze_performance(t)
        print(f"Target: {target:4.1f} | MaxRiskRatio: {risk_r:4.2f} | Win%: {s['win_rate_pct']:5.1f}% | PF: {s['profit_factor']:4.2f} | Net USD: ${s['net_profit_usd']:8.2f} | MaxDD: {s['max_drawdown_pct']:4.1f}% | Trades: {s['total_trades']}")

