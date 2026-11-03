#!/usr/bin/env python3
"""
Backtest Engine for FXSSI Strategy Example #1 (MVP + Ratios + SLC)
Evaluates performance on XAUUSDm (Gold) over the last 1 month (Oct 1 - Nov 4, 2026).
Enforces:
- Stop Loss: Max 200 pips AND strictly above MVP line (for SELL) / below MVP line (for BUY).
- Take Profit: 300 pips from entry.
"""

import os
import json
import math
from datetime import datetime, timezone, timedelta
import pandas as pd
import numpy as np

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False


def load_market_data(symbol="XAUUSDm", timeframe=None, start_date=None, end_date=None):
    """
    Load M30 candles from MT5 and enrich with historical sentiment delta data.
    """
    if timeframe is None:
        timeframe = mt5.TIMEFRAME_M30 if MT5_AVAILABLE else 30

    if start_date is None:
        start_date = datetime(2026, 10, 1, 0, 0, tzinfo=timezone.utc)
    if end_date is None:
        end_date = datetime(2026, 11, 4, 23, 59, tzinfo=timezone.utc)

    candles = []
    if MT5_AVAILABLE and mt5.initialize():
        print(f"[Data] Connected to MT5. Fetching {symbol} M30 candles...")
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, 2000)
        mt5.shutdown()
        if rates is not None and len(rates) > 0:
            for r in rates:
                dt = datetime.fromtimestamp(r['time'], tz=timezone.utc)
                if start_date <= dt <= end_date:
                    candles.append({
                        'timestamp': dt,
                        'time_epoch': r['time'],
                        'time_str': dt.strftime('%Y-%m-%d %H:%M'),
                        'open': float(r['open']),
                        'high': float(r['high']),
                        'low': float(r['low']),
                        'close': float(r['close']),
                        'tick_volume': int(r['tick_volume']),
                        'spread': int(r['spread']),
                    })
            print(f"[Data] Loaded {len(candles)} M30 bars from MT5 between {start_date.date()} and {end_date.date()}.")

    # Load Sentiment Data from cached_delta.json
    delta_cache_path = os.path.join(os.path.dirname(__file__), "..", "backend", "data", "cached_delta.json")
    if not os.path.exists(delta_cache_path):
        delta_cache_path = os.path.join("backend", "data", "cached_delta.json")

    sentiment_lookup = {}
    if os.path.exists(delta_cache_path):
        with open(delta_cache_path, "r", encoding="utf-8") as f:
            d = json.load(f)
            days = d.get("days", [])
            for day in days:
                for intv in day.get("intervals", []):
                    ts_b = intv.get("timestamp_broker")
                    if ts_b:
                        key = ts_b[:16].replace(".", "-") # "2026-11-03 00:00"
                        inc = intv.get("inc_running_net", 0.0)
                        dec = intv.get("dec_running_net", 0.0)
                        net_d = inc + dec
                        # Compute sentiment ratio (% Longs)
                        ratio = 50.0 + (net_d * 2.5)
                        ratio = max(10.0, min(90.0, ratio))
                        sentiment_lookup[key] = {
                            'ratio': ratio,
                            'net_delta': net_d,
                            'tag': intv.get("behavior_tag", "Neutral")
                        }
        print(f"[Data] Loaded sentiment database with {len(sentiment_lookup)} interval records.")

    # Convert to DataFrame
    df = pd.DataFrame(candles)
    if df.empty:
        raise ValueError("Could not load candle data from MT5!")

    # Merge sentiment ratio with candles
    ratios = []
    tags = []
    last_ratio = 50.0
    last_tag = "Neutral"

    for idx, row in df.iterrows():
        t_key = row['time_str']
        if t_key in sentiment_lookup:
            last_ratio = sentiment_lookup[t_key]['ratio']
            last_tag = sentiment_lookup[t_key]['tag']
        else:
            dt = row['timestamp']
            found = False
            for offset in [0, -10, 10, -20, 20]:
                check_key = (dt + timedelta(minutes=offset)).strftime('%Y-%m-%d %H:%M')
                if check_key in sentiment_lookup:
                    last_ratio = sentiment_lookup[check_key]['ratio']
                    last_tag = sentiment_lookup[check_key]['tag']
                    found = True
                    break
        ratios.append(last_ratio)
        tags.append(last_tag)

    df['ratios'] = ratios
    df['sentiment_tag'] = tags

    return df


def calculate_indicators(df, slc_lookback=20):
    """
    Calculate MVP (Session Volume-Weighted Middle Price)
    and SLC (Upper/Lower Stop Loss Clusters).
    """
    df = df.copy()
    
    # 1. MVP: Session Volume-Weighted Average Price
    mvp_values = []
    current_day = None
    sum_pv = 0.0
    sum_vol = 0.0

    for idx, row in df.iterrows():
        day_date = row['timestamp'].date()
        if day_date != current_day:
            current_day = day_date
            sum_pv = 0.0
            sum_vol = 0.0

        typical_price = (row['high'] + row['low'] + row['close']) / 3.0
        vol = max(1.0, float(row['tick_volume']))
        sum_pv += typical_price * vol
        sum_vol += vol

        mvp = sum_pv / sum_vol if sum_vol > 0 else row['close']
        mvp_values.append(mvp)

    df['mvp'] = mvp_values

    # 2. SLC: Stop Loss Clusters
    df['upper_slc'] = df['high'].rolling(slc_lookback).max().shift(1) + 0.30
    df['lower_slc'] = df['low'].rolling(slc_lookback).min().shift(1) - 0.30

    df['upper_slc'] = df['upper_slc'].fillna(df['high'] + 5.0)
    df['lower_slc'] = df['lower_slc'].fillna(df['low'] - 5.0)

    return df


def run_backtest(df, 
                 ratios_sell_thresh=60.0, 
                 ratios_buy_thresh=40.0, 
                 max_sl_pips=200,
                 tp_pips=300,
                 pip_value=0.10,
                 slc_margin=0.30,
                 max_hold_bars=48,
                 account_balance=10000.0,
                 lot_size=0.10):
    """
    Simulate Example #1 Rules with User Specifics:
    - Stop Loss: Max 200 pips AND strictly above MVP line (for SELL) / below MVP line (for BUY).
    - Take Profit: Exactly 300 pips from entry.
    - Setup: Sell when Price < MVP & Ratios >= 60%; Buy when Price > MVP & Ratios <= 40%.
    - Exit rules: TP hit (300 pips), SL hit (max 200 pips above MVP), MVP zone timeout (4-7h).
    """
    trades = []
    active_trade = None

    sl_dist = max_sl_pips * pip_value  # 200 pips = $20.00 on Gold
    tp_dist = tp_pips * pip_value      # 300 pips = $30.00 on Gold

    # Track signals bar by bar
    for i in range(1, len(df)):
        prev_row = df.iloc[i-1]
        curr_row = df.iloc[i]

        curr_time = curr_row['timestamp']
        o = curr_row['open']
        h = curr_row['high']
        l = curr_row['low']
        c = curr_row['close']
        mvp = curr_row['mvp']
        ratios = curr_row['ratios']
        upper_slc = curr_row['upper_slc']
        lower_slc = curr_row['lower_slc']

        # -------------------------------------------------------------
        # 1. Manage Active Trade
        # -------------------------------------------------------------
        if active_trade is not None:
            active_trade['bars_held'] += 1
            bars_held = active_trade['bars_held']
            pos_type = active_trade['type']
            sl = active_trade['sl']
            tp = active_trade['tp']
            entry_p = active_trade['entry_price']

            # Track Max Adverse Excursion (MAE) and Max Favorable Excursion (MFE)
            if pos_type == 'BUY':
                drawdown = entry_p - l
                runup = h - entry_p
            else:
                drawdown = h - entry_p
                runup = entry_p - l

            if drawdown > active_trade['mae']:
                active_trade['mae'] = drawdown
            if runup > active_trade['mfe']:
                active_trade['mfe'] = runup

            exit_reason = None
            exit_price = None

            # Check SL Hit (Above MVP, Max 200 pips)
            if pos_type == 'BUY' and l <= sl:
                exit_reason = 'SL_HIT (Max 200 Pips / Below MVP)'
                exit_price = sl
            elif pos_type == 'SELL' and h >= sl:
                exit_reason = 'SL_HIT (Max 200 Pips / Above MVP)'
                exit_price = sl

            # Check TP (300 Pips Target)
            elif pos_type == 'BUY' and h >= tp:
                exit_reason = 'TP_HIT (300 Pips Target)'
                exit_price = tp
            elif pos_type == 'SELL' and l <= tp:
                exit_reason = 'TP_HIT (300 Pips Target)'
                exit_price = tp

            # Check MVP Zone Fluctuation Exit (Rule 4: within MVP zone 4-7 hours = 8-14 M30 bars)
            elif bars_held >= 10 and abs(c - mvp) <= 1.50:
                exit_reason = f'MVP_ZONE_EXIT ({bars_held*0.5:.1f}h in zone)'
                exit_price = c

            # Max timeout exit (24 hours / 48 bars)
            elif bars_held >= max_hold_bars:
                exit_reason = 'TIMEOUT_EXIT'
                exit_price = c

            if exit_reason is not None:
                # Finalize trade
                active_trade['exit_time'] = curr_time
                active_trade['exit_price'] = exit_price
                active_trade['exit_reason'] = exit_reason

                if pos_type == 'BUY':
                    pnl_pts = exit_price - entry_p
                else:
                    pnl_pts = entry_p - exit_price

                dollar_pnl = pnl_pts * 100.0 * lot_size
                active_trade['pnl_pts'] = round(pnl_pts, 3)
                active_trade['pnl_usd'] = round(dollar_pnl, 2)
                active_trade['is_win'] = dollar_pnl > 0.0

                risk_pts = abs(entry_p - sl)
                active_trade['r_multiple'] = round(pnl_pts / risk_pts, 2) if risk_pts > 0 else 0.0

                trades.append(active_trade)
                active_trade = None

        # -------------------------------------------------------------
        # 2. Check Fresh Signal if no trade active
        # -------------------------------------------------------------
        if active_trade is None and i < len(df) - 1:
            prev_c = prev_row['close']
            prev_mvp = prev_row['mvp']
            prev_r = prev_row['ratios']

            curr_c = curr_row['close']
            curr_mvp = curr_row['mvp']
            curr_r = curr_row['ratios']

            prev_is_sell = (prev_c < prev_mvp and prev_r >= ratios_sell_thresh)
            curr_is_sell = (curr_c < curr_mvp and curr_r >= ratios_sell_thresh)

            prev_is_buy = (prev_c > prev_mvp and prev_r <= ratios_buy_thresh)
            curr_is_buy = (curr_c > curr_mvp and curr_r <= ratios_buy_thresh)

            fresh_sell = curr_is_sell and not prev_is_sell
            fresh_buy  = curr_is_buy and not prev_is_buy

            if fresh_sell or fresh_buy:
                next_bar = df.iloc[i+1]
                entry_price = next_bar['open']
                curr_time_entry = next_bar['timestamp']

                if fresh_sell:
                    signal = 'SELL'
                    # SL must be strictly above MVP line, capped at max 200 pips
                    base_sl = max(curr_mvp + slc_margin, upper_slc + slc_margin)
                    if base_sl <= curr_mvp:
                        base_sl = curr_mvp + slc_margin
                    if (base_sl - entry_price) > sl_dist:
                        base_sl = entry_price + sl_dist

                    sl_level = base_sl
                    tp_level = entry_price - tp_dist
                else:
                    signal = 'BUY'
                    # SL must be strictly below MVP line, capped at max 200 pips
                    base_sl = min(curr_mvp - slc_margin, lower_slc - slc_margin)
                    if base_sl >= curr_mvp:
                        base_sl = curr_mvp - slc_margin
                    if (entry_price - base_sl) > sl_dist:
                        base_sl = entry_price - sl_dist

                    sl_level = base_sl
                    tp_level = entry_price + tp_dist

                risk_pts = abs(entry_price - sl_level)
                reward_pts = abs(tp_level - entry_price)
                rr = round(reward_pts / risk_pts, 2) if risk_pts > 0 else 1.0

                active_trade = {
                    'trade_id': len(trades) + 1,
                    'type': signal,
                    'entry_time': curr_time_entry,
                    'entry_time_str': curr_time_entry.strftime('%Y-%m-%d %H:%M'),
                    'entry_price': round(entry_price, 3),
                    'sl': round(sl_level, 3),
                    'tp': round(tp_level, 3),
                    'mvp_at_entry': round(curr_mvp, 3),
                    'ratios_at_entry': round(curr_r, 1),
                    'risk_pts': round(risk_pts, 2),
                    'reward_pts': round(reward_pts, 2),
                    'rr_ratio': rr,
                    'bars_held': 0,
                    'mae': 0.0,
                    'mfe': 0.0
                }

    # Close any still-open trade at the last candle
    if active_trade is not None:
        last_row = df.iloc[-1]
        c = last_row['close']
        active_trade['exit_time'] = last_row['timestamp']
        active_trade['exit_price'] = c
        active_trade['exit_reason'] = 'END_OF_DATA'
        if active_trade['type'] == 'BUY':
            pnl_pts = c - active_trade['entry_price']
        else:
            pnl_pts = active_trade['entry_price'] - c
        dollar_pnl = pnl_pts * 100.0 * lot_size
        active_trade['pnl_pts'] = round(pnl_pts, 3)
        active_trade['pnl_usd'] = round(dollar_pnl, 2)
        active_trade['is_win'] = dollar_pnl > 0.0
        active_trade['r_multiple'] = round(pnl_pts / active_trade['risk_pts'], 2) if active_trade['risk_pts'] > 0 else 0.0
        trades.append(active_trade)

    return trades


def analyze_performance(trades, initial_balance=10000.0):
    """
    Calculate comprehensive performance metrics from trade ledger.
    """
    if not trades:
        return {'total_trades': 0}

    total_trades = len(trades)
    winning_trades = [t for t in trades if t['pnl_usd'] > 0]
    losing_trades = [t for t in trades if t['pnl_usd'] < 0]

    win_count = len(winning_trades)
    loss_count = len(losing_trades)
    win_rate = (win_count / total_trades) * 100.0 if total_trades > 0 else 0.0

    gross_profit = sum(t['pnl_usd'] for t in winning_trades)
    gross_loss = abs(sum(t['pnl_usd'] for t in losing_trades))
    net_profit = sum(t['pnl_usd'] for t in trades)
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (99.9 if gross_profit > 0 else 0.0)

    avg_win = (gross_profit / win_count) if win_count > 0 else 0.0
    avg_loss = (gross_loss / loss_count) if loss_count > 0 else 0.0
    win_loss_payoff = (avg_win / avg_loss) if avg_loss > 0 else 0.0
    expectancy = (net_profit / total_trades) if total_trades > 0 else 0.0

    balance = initial_balance
    peak_balance = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    equity_curve = [initial_balance]

    streak_wins = 0
    max_streak_wins = 0
    streak_losses = 0
    max_streak_losses = 0

    cur_w = 0
    cur_l = 0

    for t in trades:
        balance += t['pnl_usd']
        equity_curve.append(round(balance, 2))

        if balance > peak_balance:
            peak_balance = balance

        dd_usd = peak_balance - balance
        dd_pct = (dd_usd / peak_balance) * 100.0 if peak_balance > 0 else 0.0

        if dd_usd > max_dd_usd:
            max_dd_usd = dd_usd
        if dd_pct > max_dd_pct:
            max_dd_pct = dd_pct

        if t['is_win']:
            cur_w += 1
            cur_l = 0
            if cur_w > max_streak_wins:
                max_streak_wins = cur_w
        else:
            cur_l += 1
            cur_w = 0
            if cur_l > max_streak_losses:
                max_streak_losses = cur_l

    # Exit reason breakdown
    exit_reasons = {}
    for t in trades:
        r = t['exit_reason']
        key = 'TP Hit (300 Pips)' if 'TP_HIT' in r else ('SL Hit (Max 200 Pips / MVP)' if 'SL_HIT' in r else ('MVP Zone Exit' if 'MVP_ZONE' in r else 'Timeout'))
        exit_reasons[key] = exit_reasons.get(key, 0) + 1

    buy_trades = [t for t in trades if t['type'] == 'BUY']
    sell_trades = [t for t in trades if t['type'] == 'SELL']

    buy_wins = len([t for t in buy_trades if t['pnl_usd'] > 0])
    sell_wins = len([t for t in sell_trades if t['pnl_usd'] > 0])

    avg_bars_held = sum(t['bars_held'] for t in trades) / total_trades if total_trades > 0 else 0.0
    avg_hours_held = avg_bars_held * 0.5

    total_pts = sum(t['pnl_pts'] for t in trades)

    return {
        'initial_balance': initial_balance,
        'final_balance': round(balance, 2),
        'net_profit_usd': round(net_profit, 2),
        'return_pct': round((net_profit / initial_balance) * 100.0, 2),
        'total_trades': total_trades,
        'winning_trades': win_count,
        'losing_trades': loss_count,
        'win_rate_pct': round(win_rate, 2),
        'profit_factor': round(profit_factor, 2),
        'gross_profit_usd': round(gross_profit, 2),
        'gross_loss_usd': round(gross_loss, 2),
        'avg_trade_usd': round(expectancy, 2),
        'avg_win_usd': round(avg_win, 2),
        'avg_loss_usd': round(avg_loss, 2),
        'payoff_ratio': round(win_loss_payoff, 2),
        'total_points_pnl': round(total_pts, 2),
        'max_drawdown_usd': round(max_dd_usd, 2),
        'max_drawdown_pct': round(max_dd_pct, 2),
        'max_streak_wins': max_streak_wins,
        'max_streak_losses': max_streak_losses,
        'avg_holding_hours': round(avg_hours_held, 1),
        'buy_trades_count': len(buy_trades),
        'buy_win_rate_pct': round((buy_wins / len(buy_trades) * 100.0), 1) if buy_trades else 0.0,
        'sell_trades_count': len(sell_trades),
        'sell_win_rate_pct': round((sell_wins / len(sell_trades) * 100.0), 1) if sell_trades else 0.0,
        'exit_reasons': exit_reasons,
        'equity_curve': equity_curve
    }


def main():
    print("="*75)
    print("   FXSSI STRATEGY EXAMPLE #1 - 1-MONTH INSTITUTIONAL BACKTEST")
    print("   Pair: XAUUSDm (Gold)  |  Timeframe: PERIOD_M30")
    print("   Rules: Stop Loss Max 200 Pips (Above MVP)  |  Take Profit 300 Pips")
    print("="*75)

    df = load_market_data(symbol="XAUUSDm")
    df = calculate_indicators(df, slc_lookback=20)

    trades = run_backtest(df, 
                          ratios_sell_thresh=60.0, 
                          ratios_buy_thresh=40.0, 
                          max_sl_pips=200,
                          tp_pips=300,
                          pip_value=0.10,
                          slc_margin=0.30,
                          max_hold_bars=48,
                          account_balance=10000.0,
                          lot_size=0.10)

    stats = analyze_performance(trades, initial_balance=10000.0)

    # Print Summary Report
    print("\n" + "="*55)
    print("        1-MONTH BACKTEST EXECUTIVE SUMMARY")
    print("="*55)
    print(f"Total Period:            Oct 1, 2026 -> Nov 4, 2026 (1 Month)")
    print(f"Total M30 Bars Scanned:  {len(df)}")
    print(f"Total Completed Trades:  {stats['total_trades']}")
    print(f"Winning Trades:          {stats['winning_trades']} ({stats['win_rate_pct']}%)")
    print(f"Losing Trades:           {stats['losing_trades']} ({100.0 - stats['win_rate_pct']:.1f}%)")
    print(f"Profit Factor:           {stats['profit_factor']}")
    print(f"Net Profit ($):          ${stats['net_profit_usd']:,.2f} ({stats['return_pct']:+.2f}%)")
    print(f"Total Gold Points PnL:   {stats['total_points_pnl']:+,.2f} pts")
    print(f"Gross Profit:            ${stats['gross_profit_usd']:,.2f}")
    print(f"Gross Loss:              ${stats['gross_loss_usd']:,.2f}")
    print(f"Average Win:             ${stats['avg_win_usd']:,.2f}")
    print(f"Average Loss:            ${stats['avg_loss_usd']:,.2f}")
    print(f"Win/Loss Payoff Ratio:   {stats['payoff_ratio']}:1")
    print(f"Max Drawdown:            ${stats['max_drawdown_usd']:,.2f} ({stats['max_drawdown_pct']:.2f}%)")
    print(f"Max Win Streak:          {stats['max_streak_wins']} trades")
    print(f"Max Loss Streak:         {stats['max_streak_losses']} trades")
    print(f"Average Holding Time:    {stats['avg_holding_hours']} hours")
    print(f"Buy Setups:              {stats['buy_trades_count']} trades ({stats['buy_win_rate_pct']}% win rate)")
    print(f"Sell Setups:             {stats['sell_trades_count']} trades ({stats['sell_win_rate_pct']}% win rate)")
    print(f"Exit Breakdown:          {stats['exit_reasons']}")
    print("="*55)

    # Save to JSON and CSV
    os.makedirs("reports", exist_ok=True)
    summary_file = os.path.join("reports", "backtest_example1_summary.json")
    trades_file = os.path.join("reports", "backtest_example1_trades.csv")

    with open(summary_file, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)

    trades_df = pd.DataFrame(trades)
    if not trades_df.empty:
        trades_df['entry_time'] = trades_df['entry_time'].astype(str)
        trades_df['exit_time'] = trades_df['exit_time'].astype(str)
        trades_df.to_csv(trades_file, index=False)

    print(f"\n[Export] Saved summary to: {summary_file}")
    print(f"[Export] Saved trade log ({len(trades)} trades) to: {trades_file}")

    # Display Top 10 Trades
    print("\n--- SAMPLE RECENT TRADES ---")
    for t in trades[-10:]:
        print(f"#{t['trade_id']:02d} | {t['entry_time_str']} | {t['type']:4s} @ {t['entry_price']:.2f} | SL: {t['sl']:.2f} | TP: {t['tp']:.2f} | Exit: {t['exit_price']:.2f} ({t['exit_reason']}) | PnL: ${t['pnl_usd']:+7.2f} ({t['pnl_pts']:+6.2f} pts) | R:R {t['r_multiple']}R")


if __name__ == "__main__":
    main()
