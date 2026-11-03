import sys
sys.path.insert(0, '.')
from tools.backtest_example1 import load_market_data, calculate_indicators, analyze_performance

df = load_market_data('XAUUSDm')
df = calculate_indicators(df, slc_lookback=20)

def test_breakeven_strategy(be_trigger=10.0, slc_margin=3.0, tp_target=25.0):
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
            
            # Check Break-Even trigger
            if not active['is_be']:
                if pos == 'BUY' and (h - entry_p) >= be_trigger:
                    active['sl'] = entry_p + 0.5 # move to BE+0.5
                    active['is_be'] = True
                    sl = active['sl']
                elif pos == 'SELL' and (entry_p - l) >= be_trigger:
                    active['sl'] = entry_p - 0.5 # move to BE+0.5
                    active['is_be'] = True
                    sl = active['sl']
                    
            exit_r = None
            exit_p = None
            
            # Check SL
            if pos == 'BUY' and l <= sl:
                exit_r, exit_p = ('BE_HIT' if active['is_be'] else 'SL_HIT'), sl
            elif pos == 'SELL' and h >= sl:
                exit_r, exit_p = ('BE_HIT' if active['is_be'] else 'SL_HIT'), sl
            # Check TP
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
                    sl = min(upper_slc + slc_margin, entry + 25.0)
                    tp = entry - tp_target
                else:
                    sl = max(lower_slc - slc_margin, entry - 25.0)
                    tp = entry + tp_target
                active = {
                    'type': sig,
                    'entry_time': curr_time,
                    'entry_price': entry,
                    'sl': sl,
                    'tp': tp,
                    'bars_held': 0,
                    'is_be': False
                }
    return trades

print("=== BREAK-EVEN OPTIMIZATION RESULTS ===")
for be in [4.0, 6.0, 8.0, 10.0, 12.0]:
    for tp in [15.0, 20.0, 25.0, 30.0, 35.0]:
        t = test_breakeven_strategy(be_trigger=be, tp_target=tp)
        s = analyze_performance(t)
        print(f"BE: {be:4.1f} | TP: {tp:4.1f} | Win%: {s['win_rate_pct']:5.1f}% | PF: {s['profit_factor']:4.2f} | Net USD: ${s['net_profit_usd']:8.2f} | MaxDD: {s['max_drawdown_pct']:4.1f}% | Trades: {s['total_trades']}")
