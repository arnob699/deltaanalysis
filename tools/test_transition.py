import sys
sys.path.insert(0, '.')
from tools.backtest_example1 import load_market_data, calculate_indicators, analyze_performance

df = load_market_data('XAUUSDm')
df = calculate_indicators(df, slc_lookback=20)

def test_transition_signals(slc_margin=3.0, tp_target=25.0):
    trades = []
    active = None
    
    # Track signal states
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

        # 2. Check FRESH TRANSITION SIGNAL (exact logic from FXSSI_Strategy_Example1.mq5 lines 776-792)
        # Check Sell: Price < MVP AND Ratios >= 60%
        # Fresh if previous bar was NOT (Price < MVP AND Ratios >= 60%)
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
                sl = upper_slc + slc_margin
                if sl <= entry: sl = entry + 15.0
                tp = entry - tp_target
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
                sl = lower_slc - slc_margin
                if sl >= entry: sl = entry - 15.0
                tp = entry + tp_target
                active = {
                    'type': 'BUY',
                    'entry_time': next_bar['timestamp'],
                    'entry_price': entry,
                    'sl': sl,
                    'tp': tp,
                    'bars_held': 0
                }
    return trades

print("=== FRESH TRANSITION SIGNALS (EXACT MQ5 LOGIC) ===")
for target in [10.0, 15.0, 20.0, 25.0, 30.0, 40.0]:
    t = test_transition_signals(slc_margin=3.0, tp_target=target)
    s = analyze_performance(t)
    print(f"TP Target: {target:4.1f} pts | Trades: {s['total_trades']:2d} | WinRate: {s['win_rate_pct']:5.1f}% | ProfitFactor: {s['profit_factor']:4.2f} | Net USD: ${s['net_profit_usd']:8.2f} | MaxDD: {s['max_drawdown_pct']:4.1f}%")

