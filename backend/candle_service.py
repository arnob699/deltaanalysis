import os
import json
import time
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List

# Base paths
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "backend" / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
CANDLES_CACHE_FILE = DATA_DIR / "cached_candles.json"
DELTA_CACHE_FILE = DATA_DIR / "cached_delta.json"
MASTER_DAYS_FILE = DATA_DIR / "master_days_store.json"

# In-memory store
_candles_memory_store: Dict[str, Any] = {}
_last_calc_times: Dict[str, float] = {}

def load_cached_candles_from_disk() -> Dict[str, Any]:
    global _candles_memory_store
    if _candles_memory_store:
        return _candles_memory_store
    if CANDLES_CACHE_FILE.exists():
        try:
            with open(CANDLES_CACHE_FILE, "r", encoding="utf-8") as f:
                _candles_memory_store = json.load(f)
                return _candles_memory_store
        except Exception as e:
            print(f"[CandleService] Error loading disk candles cache: {e}")
    return {}

def save_candles_to_disk(data: Dict[str, Any]) -> None:
    try:
        tmp_file = CANDLES_CACHE_FILE.with_suffix(".tmp")
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(',', ':'))
        tmp_file.replace(CANDLES_CACHE_FILE)
    except Exception as e:
        print(f"[CandleService] Error saving candles cache: {e}")

def get_delta_and_ratio_lookup() -> tuple[Dict[int, float], Dict[int, float]]:
    delta_lookup: Dict[int, float] = {}
    ratio_lookup: Dict[int, float] = {}

    all_days: List[Dict[str, Any]] = []

    # 1. Master multi-day store
    if MASTER_DAYS_FILE.exists():
        try:
            with open(MASTER_DAYS_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                all_days.extend(d.get("days", []))
        except Exception:
            pass

    # 2. Live cached delta (all 30 historical days + today)
    if DELTA_CACHE_FILE.exists():
        try:
            with open(DELTA_CACHE_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                if "days" in d and isinstance(d["days"], list):
                    all_days.extend(d["days"])
                today_day = d.get("selected_day")
                if today_day:
                    all_days.append(today_day)
                elif "intervals" in d and isinstance(d["intervals"], list):
                    all_days.append({"intervals": d.get("intervals", [])})
        except Exception:
            pass

    for day in all_days:
        for iv in day.get("intervals", []):
            tb = iv.get("timestamp_broker")
            if not tb:
                continue
            try:
                # Format: "2026.11.04 14:00:00"
                dt = datetime.strptime(tb, "%Y.%m.%d %H:%M:%S")
                epoch = int(dt.replace(tzinfo=timezone.utc).timestamp())
                inc = float(iv.get("inc_20m", 0.0))
                delta_lookup[epoch] = inc

                # Real Sentiment Ratio (% Longs) from MT5 FXSSI.Ratios
                if "ratio" in iv and iv["ratio"] is not None:
                    try:
                        r_val = float(iv["ratio"])
                        if 1.0 <= r_val <= 99.0:
                            ratio_lookup[epoch] = round(r_val, 2)
                    except (ValueError, TypeError):
                        pass
            except Exception:
                continue

    return delta_lookup, ratio_lookup

def fetch_candles_from_mt5(symbol: str = "XAUUSDm", timeframe_str: str = "M20", count: int = 2200) -> Optional[Dict[str, Any]]:
    try:
        import MetaTrader5 as mt5
    except ImportError:
        return None

    if not mt5.initialize():
        return None

    tf_map = {
        "M20": getattr(mt5, "TIMEFRAME_M20", 20),
        "M30": getattr(mt5, "TIMEFRAME_M30", 30),
        "H1": getattr(mt5, "TIMEFRAME_H1", 16385),
    }
    tf = tf_map.get(timeframe_str.upper(), getattr(mt5, "TIMEFRAME_M20", 20))

    try:
        rates = mt5.copy_rates_from_pos(symbol, tf, 0, count)
    except Exception as e:
        print(f"[CandleService] mt5.copy_rates_from_pos error: {e}")
        rates = None
    finally:
        mt5.shutdown()

    if rates is None or len(rates) == 0:
        return None

    try:
        import pandas as pd
        import numpy as np
    except ImportError:
        return None

    df = pd.DataFrame(rates)
    df["time_dt"] = pd.to_datetime(df["time"], unit="s")
    df["date"] = df["time_dt"].dt.date
    df["typical"] = (df["high"] + df["low"] + df["close"]) / 3.0

    # 200-period Moving Average
    df["ma200"] = df["close"].rolling(200, min_periods=20).mean()

    # Session Middle Volume (Session Volume-Weighted Price)
    df["cum_pv"] = df["typical"] * df["tick_volume"]
    df["cum_pv_session"] = df.groupby("date")["cum_pv"].cumsum()
    df["cum_v_session"] = df.groupby("date")["tick_volume"].cumsum()
    df["running_mvp"] = df["cum_pv_session"] / df["cum_v_session"].replace(0, 1)

    # For historical days: horizontal level at session's final MVP
    # For today: dynamic running MVP curve
    latest_date = df["date"].iloc[-1]
    session_totals = df.groupby("date").apply(
        lambda g: (g["typical"] * g["tick_volume"]).sum() / max(1, g["tick_volume"].sum())
    )
    df["mvp"] = np.where(df["date"] == latest_date, df["running_mvp"], df["date"].map(session_totals))

    delta_lookup, ratio_lookup = get_delta_and_ratio_lookup()
    sorted_delta_epochs = sorted(delta_lookup.keys())
    sorted_delta_arr = np.array(sorted_delta_epochs) if sorted_delta_epochs else np.array([])

    sorted_ratio_epochs = sorted(ratio_lookup.keys())
    sorted_ratio_arr = np.array(sorted_ratio_epochs) if sorted_ratio_epochs else np.array([])

    span_map = {"M20": 1200, "M30": 1800, "H1": 3600}
    bar_span = span_map.get(timeframe_str.upper(), 1200)

    candles_list: List[Dict[str, Any]] = []
    last_known_ratio: Optional[float] = None

    for _, row in df.iterrows():
        t = int(row["time"])

        # 1. Delta mapping
        if t in delta_lookup:
            delta_val = delta_lookup[t]
        elif len(sorted_delta_arr) > 0:
            if bar_span > 1200:
                idx_start = np.searchsorted(sorted_delta_arr, t, side='left')
                idx_end = np.searchsorted(sorted_delta_arr, t + bar_span, side='left')
                if idx_end > idx_start:
                    delta_val = sum(delta_lookup[sorted_delta_epochs[k]] for k in range(idx_start, idx_end))
                else:
                    idx = np.clip(np.searchsorted(sorted_delta_arr, t), 0, len(sorted_delta_arr) - 1)
                    near_t = sorted_delta_epochs[idx]
                    delta_val = delta_lookup[near_t] if abs(near_t - t) <= bar_span / 2 else 0.0
            else:
                idx = np.clip(np.searchsorted(sorted_delta_arr, t), 0, len(sorted_delta_arr) - 1)
                near_t = sorted_delta_epochs[idx]
                delta_val = delta_lookup[near_t] if abs(near_t - t) <= bar_span / 2 else 0.0
        else:
            delta_val = 0.0

        # 2. Real Sentiment Ratio (% Longs) mapping
        if t in ratio_lookup:
            ratio_val = ratio_lookup[t]
            last_known_ratio = ratio_val
        elif len(sorted_ratio_arr) > 0:
            idx = np.clip(np.searchsorted(sorted_ratio_arr, t), 0, len(sorted_ratio_arr) - 1)
            near_t = sorted_ratio_epochs[idx]
            if abs(near_t - t) <= bar_span:
                ratio_val = ratio_lookup[near_t]
                last_known_ratio = ratio_val
            elif last_known_ratio is not None:
                ratio_val = last_known_ratio
            else:
                ratio_val = None
        elif last_known_ratio is not None:
            ratio_val = last_known_ratio
        else:
            ratio_val = None

        candles_list.append({
            "time": t,
            "open": round(float(row["open"]), 2),
            "high": round(float(row["high"]), 2),
            "low": round(float(row["low"]), 2),
            "close": round(float(row["close"]), 2),
            "volume": int(row["tick_volume"]),
            "ma200": round(float(row["ma200"]), 2) if not pd.isna(row["ma200"]) else None,
            "mvp": round(float(row["mvp"]), 2) if not pd.isna(row["mvp"]) else None,
            "delta": round(float(delta_val), 4),
            "ratio": ratio_val,
        })

    return {
        "symbol": symbol,
        "timeframe": timeframe_str,
        "count": len(candles_list),
        "updated_at": time.time(),
        "candles": candles_list
    }

def get_or_build_candles(symbol: str = "XAUUSDm", timeframe_str: str = "M20", count: int = 2200) -> Dict[str, Any]:
    global _candles_memory_store, _last_calc_times
    now = time.time()
    cache_key = f"{symbol}_{timeframe_str.upper()}"
    last_calc = _last_calc_times.get(cache_key, 0.0)

    # Check if we should recompute locally from MT5 (at most once every 2 seconds for this timeframe)
    if (cache_key not in _candles_memory_store) or (now - last_calc >= 2.0):
        fresh = fetch_candles_from_mt5(symbol, timeframe_str, count)
        if fresh and fresh.get("count", 0) > 0:
            _candles_memory_store[cache_key] = fresh
            _last_calc_times[cache_key] = now
            save_candles_to_disk(_candles_memory_store)
            return fresh

    # Fallback to in-memory or disk cache
    if cache_key in _candles_memory_store:
        return _candles_memory_store[cache_key]

    disk_data = load_cached_candles_from_disk()
    if cache_key in disk_data:
        _candles_memory_store[cache_key] = disk_data[cache_key]
        return disk_data[cache_key]

    # If nothing cached yet for this timeframe, return empty container
    return {
        "symbol": symbol,
        "timeframe": timeframe_str,
        "count": 0,
        "updated_at": now,
        "candles": []
    }

def update_candles_from_sync(payload: Dict[str, Any]) -> None:
    """Updates candle cache on Render when pushed by sync_to_render.py"""
    global _candles_memory_store
    if not payload:
        return
    for k, v in payload.items():
        if isinstance(v, dict) and "candles" in v:
            _candles_memory_store[k] = v
    save_candles_to_disk(_candles_memory_store)
