import os
import sys
import time
import json
import glob
import re
import asyncio
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List

def safe_load_json(text: str) -> Dict[str, Any]:
    cleaned = re.sub(r':\s*\+(\d+(\.\d+)?)', r': \1', text)
    return json.loads(cleaned)

from fastapi import FastAPI, HTTPException, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse

# Base directories
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))
FRONTEND_DIR = BASE_DIR / "frontend"
DATA_DIR = BASE_DIR / "backend" / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
CACHE_FILE = DATA_DIR / "cached_delta.json"

from backend.candle_service import get_or_build_candles, update_candles_from_sync

# Discover MT5 Files directory
def locate_mt5_files_dir() -> Path:
    env_dir = os.environ.get("MT5_FILES_DIR")
    if env_dir and os.path.isdir(env_dir):
        return Path(env_dir)

    appdata = os.environ.get("APPDATA")
    if appdata:
        pattern = os.path.join(appdata, "MetaQuotes", "Terminal", "*", "MQL5", "Files")
        matches = glob.glob(pattern)
        if matches:
            matches.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            return Path(matches[0])

    local_fallback = BASE_DIR / "mt5_files"
    local_fallback.mkdir(parents=True, exist_ok=True)
    return local_fallback

MT5_FILES_DIR = locate_mt5_files_dir()
DELTA_JSON_PATH = MT5_FILES_DIR / "fxssi_daily_delta.json"
REFRESH_CMD_PATH = MT5_FILES_DIR / "refresh_cmd.json"

print(f"[Public Activity Delta Server] MT5 Files Folder: {MT5_FILES_DIR}")
print(f"[Public Activity Delta Server] Delta JSON Path: {DELTA_JSON_PATH}")

app = FastAPI(
    title="Public Activity Delta Live Bridge (Gold XAU/USD)",
    description="Database-Free MT5 Live Order Activity Bridge and Institutional Multi-Day Dashboard",
    version="1.110"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def add_no_cache_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

MASTER_SNAPSHOT_PATH = BASE_DIR / "latest_snapshot_backup" / "fxssi_daily_delta.json"
MASTER_DAYS_FILE = DATA_DIR / "master_days_store.json"

# In-memory snapshot cache
last_known_payload: Optional[Dict[str, Any]] = None
_last_disk_save: float = 0.0

def init_master_days_store() -> Dict[str, Dict[str, Any]]:
    """
    Initializes master multi-day store by seeding from latest_snapshot_backup
    and layering any previously persisted records.
    """
    days_map: Dict[str, Dict[str, Any]] = {}

    # 1. Seed from backup snapshot (contains 26 verified historical days)
    if MASTER_SNAPSHOT_PATH.exists():
        try:
            with open(MASTER_SNAPSHOT_PATH, "r", encoding="utf-8", errors="ignore") as f:
                backup = json.load(f)
                for d in backup.get("days", []):
                    dt = d.get("date")
                    if dt:
                        days_map[dt] = d
        except Exception as e:
            print(f"[Public Activity Delta Server] Error reading backup snapshot: {e}")

    # 2. Layer any saved master store
    if MASTER_DAYS_FILE.exists():
        try:
            with open(MASTER_DAYS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                saved = json.load(f)
                for d in saved.get("days", []):
                    dt = d.get("date")
                    if dt:
                        if dt not in days_map or d.get("valid_bars", 0) >= days_map[dt].get("valid_bars", 0):
                            days_map[dt] = d
        except Exception as e:
            print(f"[Public Activity Delta Server] Error reading master store: {e}")

    return days_map

master_days_store: Dict[str, Dict[str, Any]] = init_master_days_store()

def load_cached_payload() -> Optional[Dict[str, Any]]:
    global last_known_payload
    if last_known_payload is not None:
        return last_known_payload
    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                last_known_payload = json.load(f)
                return last_known_payload
        except Exception as e:
            print(f"[Public Activity Delta Server] Error loading cached file: {e}")
    return None

def save_cached_payload(payload: Dict[str, Any], force: bool = False) -> None:
    global _last_disk_save
    now = time.time()
    if not force and (now - _last_disk_save < 30.0):
        return
    try:
        tmp_cache = CACHE_FILE.with_suffix(".tmp")
        with open(tmp_cache, "w", encoding="utf-8") as f:
            json.dump(payload, f, separators=(',', ':'))
        tmp_cache.replace(CACHE_FILE)
        _last_disk_save = now
    except Exception as e:
        print(f"[Public Activity Delta Server] Error writing cache file: {e}")

def extract_available_days_summary(days: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    summary_list = []
    for d in days:
        summary_list.append({
            "date": d.get("date"),
            "date_bst": d.get("date_bst", d.get("date")),
            "day_name": d.get("day_name", ""),
            "is_today": d.get("is_today", False),
            "valid_bars": d.get("valid_bars", 0),
            "total_bars": d.get("total_bars", 72),
            "inc_net": d.get("summary", {}).get("increase", {}).get("net_delta", 0.0),
            "dec_net": d.get("summary", {}).get("decrease", {}).get("net_delta", 0.0),
            "contrarian_bias": d.get("summary", {}).get("contrarian_bias", "Neutral")
        })
    return summary_list

def merge_and_assemble_payload(raw_data: Dict[str, Any], date_query: Optional[str] = None, save_to_disk: bool = False) -> Dict[str, Any]:
    global master_days_store

    # Merge any incoming days from MT5
    for d in raw_data.get("days", []):
        dt = d.get("date")
        if not dt:
            continue
        valid_bars = d.get("valid_bars", 0)
        is_today = d.get("is_today", False)

        if is_today:
            if valid_bars > 0:
                master_days_store[dt] = d
            elif dt not in master_days_store:
                master_days_store[dt] = d
            else:
                existing = master_days_store[dt]
                existing["date_bst"] = d.get("date_bst", existing.get("date_bst"))
                existing["is_today"] = True
                master_days_store[dt] = existing
        else:
            if dt not in master_days_store or valid_bars >= master_days_store[dt].get("valid_bars", 0):
                master_days_store[dt] = d

    # Sort all days descending by date (newest session first)
    all_days = sorted(master_days_store.values(), key=lambda x: x.get("date", ""), reverse=True)

    # Designate the first day as today / live session
    if all_days:
        all_days[0]["is_today"] = True
        for od in all_days[1:]:
            od["is_today"] = False

    assembled = dict(raw_data)
    assembled["days"] = all_days
    assembled["total_history_days"] = len(all_days)
    assembled["available_days"] = extract_available_days_summary(all_days)

    # Ensure market price fallback
    if "market" not in assembled or not assembled["market"] or not assembled["market"].get("bid"):
        assembled["market"] = {
            "symbol": assembled.get("symbol", "XAUUSDm"),
            "name": "Gold Spot / US Dollar",
            "bid": 3875.70,
            "ask": 3875.94,
            "spread": 0.24,
            "day_open": 4007.95,
            "day_high": 4018.93,
            "day_low": 3869.93,
            "change": -132.25,
            "change_pct": -3.30
        }

    # Resolve active day
    selected_day = None
    if date_query and all_days:
        selected_day = next((d for d in all_days if d.get("date") == date_query or d.get("date_bst") == date_query), None)

    if not selected_day:
        selected_day = all_days[0] if all_days else None

    if selected_day:
        assembled["selected_date"] = selected_day.get("date")
        assembled["selected_day"] = selected_day
        assembled["summary"] = selected_day.get("summary", assembled.get("summary", {}))
        assembled["intervals"] = selected_day.get("intervals", assembled.get("intervals", []))
        assembled["is_viewing_history"] = not selected_day.get("is_today", False)
    else:
        assembled["selected_date"] = None
        assembled["is_viewing_history"] = False

    # Persist master store to disk only when explicitly requested and throttled
    global _last_disk_save
    if save_to_disk and (time.time() - _last_disk_save >= 30.0):
        try:
            tmp_master = MASTER_DAYS_FILE.with_suffix(".tmp")
            with open(tmp_master, "w", encoding="utf-8") as f:
                json.dump({"days": all_days, "count": len(all_days), "updated_at": time.time()}, f, separators=(',', ':'))
            tmp_master.replace(MASTER_DAYS_FILE)
            _last_disk_save = time.time()
        except Exception as e:
            print(f"[Public Activity Delta Server] Error saving master store: {e}")

    return assembled

@app.get("/api/delta")
async def get_delta(date: Optional[str] = Query(None, description="Optional date filter (e.g. '2026.10.29')")):
    """
    Returns full JSON snapshot:
    - Live Gold Market Price (Bid, Ask, Spread, Change, High, Low)
    - Multi-day history array (up to 29 days)
    - Active day summary & intervals (Today by default, or specific date if requested)
    - Bangladesh Time (BST, UTC+6) 12-hour formatted timestamps
    - MT5 online status & diagnostics
    """
    global last_known_payload
    now = time.time()
    raw_data = None
    
    if DELTA_JSON_PATH.exists():
        try:
            with open(DELTA_JSON_PATH, "r", encoding="utf-8", errors="ignore") as f:
                raw_data = safe_load_json(f.read())
            
            mtime = os.path.getmtime(DELTA_JSON_PATH)
            hb_epoch = raw_data.get("heartbeat_epoch", 0)
            
            # Consider MT5 online if updated within last 10 seconds
            is_recent_heartbeat = abs(now - hb_epoch) <= 10.0
            is_recent_mtime = (now - mtime) <= 10.0
            mt5_online = is_recent_heartbeat or is_recent_mtime
            
            raw_data["mt5_online"] = mt5_online
            raw_data["seconds_since_heartbeat"] = round(abs(now - hb_epoch), 1)
            raw_data["file_age_seconds"] = round(now - mtime, 1)
            raw_data["is_simulation"] = False
            
            # Merge with master multi-day archive so historical days are NEVER lost
            raw_data = merge_and_assemble_payload(raw_data, date, save_to_disk=False)
            
            last_known_payload = raw_data
            save_cached_payload(raw_data)
            return raw_data
        except Exception as e:
            print(f"[Public Activity Delta Server] Error parsing MT5 delta JSON: {e}")
            raw_data = None
            
    if not raw_data:
        cached = load_cached_payload()
        if cached:
            last_sync = cached.get("last_sync_time", 0)
            # If updated via /api/sync within last 15 seconds, MT5 bridge is actively streaming!
            is_recent_sync = (now - last_sync) <= 15.0
            cached["mt5_online"] = is_recent_sync
            if is_recent_sync:
                if "diagnostics" not in cached:
                    cached["diagnostics"] = {}
                cached["diagnostics"]["error_message"] = "Connected via Cloud Sync."
            else:
                if "diagnostics" in cached:
                    cached["diagnostics"]["error_message"] = "MT5 offline. Serving last recorded snapshot."
            raw_data = merge_and_assemble_payload(cached, date, save_to_disk=False)
            return raw_data

    if not raw_data and MASTER_SNAPSHOT_PATH.exists():
        try:
            with open(MASTER_SNAPSHOT_PATH, "r", encoding="utf-8", errors="ignore") as f:
                backup = json.load(f)
            backup["mt5_online"] = False
            raw_data = merge_and_assemble_payload(backup, date, save_to_disk=False)
            return raw_data
        except Exception:
            pass
            
    if not raw_data:
        raise HTTPException(status_code=503, detail="No MT5 delta data available yet. Please run MT5 with Public Activity Delta Bridge.")

    return raw_data

@app.post("/api/sync")
async def sync_data_from_mt5(request: Request):
    """
    Receives live delta JSON from Oracle VPS or PC MT5 instance and merges it into the cloud database.
    """
    global last_known_payload
    try:
        incoming_data = await request.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

    # Check if candle data is included in sync payload
    if "candles_cache" in incoming_data:
        try:
            update_candles_from_sync(incoming_data["candles_cache"])
        except Exception as e:
            print(f"[Sync] Error updating candles cache: {e}")

    now = time.time()
    merged = merge_and_assemble_payload(incoming_data, None, save_to_disk=True)
    merged["mt5_online"] = True
    merged["last_sync_time"] = now
    merged["last_sync_utc"] = datetime.now(timezone.utc).isoformat()
    merged["heartbeat_epoch"] = int(now)
    
    last_known_payload = merged
    save_cached_payload(merged)
    return {"status": "SUCCESS", "total_days": len(merged.get("days", []))}

@app.get("/api/candles")
async def get_candles_endpoint(
    symbol: str = Query("XAUUSDm", description="Gold symbol"),
    timeframe: str = Query("M20", description="Timeframe (M20, M30, H1)"),
    count: int = Query(2200, description="Number of candles")
):
    """
    Returns candlestick chart data with 200 MA, Middle Volume, Activity Delta, and Sentiment Ratio.
    """
    return get_or_build_candles(symbol, timeframe, count)

@app.post("/api/sync_candles")
async def sync_candles_endpoint(request: Request):
    """
    Receives bulk candle cache updates from local PC sync agent.
    """
    try:
        payload = await request.json()
        update_candles_from_sync(payload)
        return {"status": "SUCCESS", "updated_keys": list(payload.keys())}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error syncing candles: {e}")

@app.get("/api/history")
async def get_history():
    delta_data = await get_delta(None)
    return {
        "symbol": delta_data.get("symbol", "XAUUSDm"),
        "total_days": len(delta_data.get("available_days", [])),
        "days": delta_data.get("available_days", [])
    }

@app.post("/api/refresh")
async def trigger_refresh():
    global last_known_payload
    now = time.time()
    
    try:
        cmd_payload = {
            "command": "REFRESH_DELTA",
            "requested_at": now,
            "client": "web_dashboard"
        }
        with open(REFRESH_CMD_PATH, "w", encoding="utf-8") as f:
            json.dump(cmd_payload, f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write refresh command to MT5 directory: {e}")

    start_wait = time.time()
    updated = False
    
    while time.time() - start_wait < 3.0:
        await asyncio.sleep(0.2)
        if not REFRESH_CMD_PATH.exists():
            updated = True
            break
        if DELTA_JSON_PATH.exists() and os.path.getmtime(DELTA_JSON_PATH) >= now - 0.5:
            updated = True
            break
            
    data = await get_delta(None)
    data["last_refresh_status"] = "SUCCESS" if updated else "TIMEOUT_SERVED_CURRENT"
    return data

# Backward-compatibility routes for any cached browser tabs
@app.get("/api/v1/analysis/latest")
async def legacy_analysis_latest(symbol: str = "XAUUSD"):
    return await get_delta(None)

@app.get("/api/v1/snapshots/history")
async def legacy_snapshots_history(symbol: str = "XAUUSD"):
    delta = await get_delta(None)
    return {
        "symbol": symbol,
        "available_days": delta.get("available_days", []),
        "intervals": delta.get("intervals", [])
    }

@app.get("/api/status")
async def get_status():
    now = time.time()
    file_exists = DELTA_JSON_PATH.exists()
    mtime = os.path.getmtime(DELTA_JSON_PATH) if file_exists else 0
    is_local_online = file_exists and (now - mtime <= 10.0)
    
    last_sync = last_known_payload.get("last_sync_time", 0) if last_known_payload else 0
    is_cloud_sync_online = (now - last_sync <= 15.0) if last_sync else False
    
    mt5_online = is_local_online or is_cloud_sync_online
    
    return {
        "server_status": "ONLINE",
        "mt5_online": mt5_online,
        "is_cloud_synced": is_cloud_sync_online,
        "total_days_loaded": len(master_days_store),
        "seconds_since_heartbeat": round(now - max(mtime, last_sync), 1) if (mtime or last_sync) else None,
        "has_cached_snapshot": CACHE_FILE.exists() or (last_known_payload is not None)
    }

# Mount static frontend directory
if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")

    @app.get("/")
    async def serve_index():
        return FileResponse(FRONTEND_DIR / "index.html")

    @app.get("/80")
    async def serve_80_redirect():
        return RedirectResponse(url="/")

if __name__ == "__main__":
    import uvicorn
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", 80))
    url = "http://localhost" if port == 80 else f"http://localhost:{port}"
    print("\n=======================================================")
    print("   Public Activity Delta Live Bridge Server Starting")
    print(f"   Institutional Dashboard: {url}")
    print(f"   Binding Interface: {host}:{port}")
    print("=======================================================\n")
    uvicorn.run(app, host=host, port=port)
