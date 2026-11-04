import os
import json
import time
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
import pandas as pd
import numpy as np

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

    # 2. Live cached delta (today)
    if DELTA_CACHE_FILE.exists():
        try:
            with open(DELTA_CACHE_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                today_day = d.get("selected_day")
                if today_day:
                    all_days.append(today_day)
                elif "intervals" in d:
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

                inc_net = float(iv.get("inc_running_net", 0.0))
                dec_net = float(iv.get("dec_running_net", 0.0))
                net_total = inc_net + dec_net

                # Calculate sentiment ratio (% Longs) bounded realistically
                ratio = 50.0 + (net_total * 2.5)
                ratio = max(15.0, min(88.0, ratio))
                ratio_lookup[epoch] = round(ratio, 2)
            except Exception:
                continue

    return delta_lookup, ratio_lookup

def fetch_candles_from_mt5(symbol: str = "XAUUSDm", timeframe_str: str = "M20", count: int = 500) -> Optional[Dict[str, Any]]:
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
    df["mvp"] = df["cum_pv_session"] / df["cum_v_session"].replace(0, 1)

    delta_lookup, ratio_lookup = get_delta_and_ratio_lookup()

    candles_list: List[Dict[str, Any]] = []
    last_ratio = 50.0

    for _, row in df.iterrows():
        t = int(row["time"])
        delta_val = delta_lookup.get(t, 0.0)
        ratio_val = ratio_lookup.get(t, last_ratio)
        last_ratio = ratio_val

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
            "ratio": round(float(ratio_val), 2),
        })

    return {
        "symbol": symbol,
        "timeframe": timeframe_str,
        "count": len(candles_list),
        "updated_at": time.time(),
        "candles": candles_list
    }

def get_or_build_candles(symbol: str = "XAUUSDm", timeframe_str: str = "M20", count: int = 500) -> Dict[str, Any]:
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
