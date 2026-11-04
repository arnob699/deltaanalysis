"""
Public Activity Delta — Cloud Sync Agent
Watches MT5's fxssi_daily_delta.json on Oracle VPS (or local PC)
and syncs live updates to your Render.com website every second.
"""

import os
import sys
import time
import json
import glob
import re
from pathlib import Path

try:
    import requests
except ImportError:
    print("[ERROR] 'requests' library not found. Run: pip install requests")
    sys.exit(1)

def safe_load_json(text: str) -> dict:
    # Remove any illegal leading plus sign on numbers (e.g. "+2.79")
    cleaned = re.sub(r':\s*\+(\d+(\.\d+)?)', r': \1', text)
    return json.loads(cleaned)

# Configure your Render app URL: e.g. "https://your-gold-delta.onrender.com"
RENDER_URL = os.environ.get("RENDER_URL", "").rstrip("/")

def disable_quickedit():
    """Prevents Windows CMD from freezing the script if someone clicks inside the console."""
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        h_stdin = kernel32.GetStdHandle(-10)  # STD_INPUT_HANDLE
        mode = ctypes.c_ulong()
        if kernel32.GetConsoleMode(h_stdin, ctypes.byref(mode)):
            new_mode = (mode.value & ~0x0040) | 0x0080  # Disable ENABLE_QUICK_EDIT_MODE
            kernel32.SetConsoleMode(h_stdin, new_mode)
    except Exception:
        pass

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

    fallback = Path.cwd() / "mt5_files"
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback

def main():
    disable_quickedit()
    print("=====================================================================", flush=True)
    print("   Public Activity Delta — Oracle/PC to Render 1-Second Cloud Sync Agent", flush=True)
    print("=====================================================================", flush=True)
    
    global RENDER_URL
    if not RENDER_URL:
        if len(sys.argv) > 1:
            RENDER_URL = sys.argv[1].rstrip("/")
        else:
            RENDER_URL = input("Enter your Render Web App URL (e.g. https://gold-delta.onrender.com): ").strip().rstrip("/")
            
    if not RENDER_URL.startswith("http"):
        RENDER_URL = "https://" + RENDER_URL

    sync_endpoint = f"{RENDER_URL}/api/sync"
    files_dir = locate_mt5_files_dir()
    delta_file = files_dir / "fxssi_daily_delta.json"

    print(f"\n[OK] Target Render URL: {sync_endpoint}")
    print(f"[OK] Watching MT5 File:  {delta_file}\n")
    print("Syncing live every second to Render... (Press Ctrl+C to stop)\n")

    session = requests.Session()
    # Enable HTTP Keep-Alive and optimize connection pooling
    adapter = requests.adapters.HTTPAdapter(pool_connections=1, pool_maxsize=2, max_retries=1)
    session.mount("https://", adapter)
    session.mount("http://", adapter)

    last_sent_mtime = 0.0
    last_sync_clock = 0.0
    last_candles_sync = 0.0
    fail_count = 0
    candles_file = Path.cwd() / "backend" / "data" / "cached_candles.json"

    while True:
        try:
            if delta_file.exists():
                curr_mtime = os.path.getmtime(delta_file)
                now_t = time.time()
                # Send if MT5 updated the file, or heartbeat every 5 seconds
                if (curr_mtime != last_sent_mtime) or (now_t - last_sync_clock >= 5.0):
                    with open(delta_file, "r", encoding="utf-8", errors="ignore") as f:
                        payload = safe_load_json(f.read())

                    payload["heartbeat_epoch"] = int(now_t)
                    payload["mt5_online"] = True

                    # Periodically attach live candles cache (every 10 seconds)
                    if candles_file.exists() and (now_t - last_candles_sync >= 10.0):
                        try:
                            with open(candles_file, "r", encoding="utf-8") as cf:
                                payload["candles_cache"] = json.load(cf)
                            last_candles_sync = now_t
                        except Exception:
                            pass

                    res = session.post(sync_endpoint, json=payload, timeout=(3.0, 5.0))
                    if res.status_code == 200:
                        last_sent_mtime = curr_mtime
                        last_sync_clock = now_t
                        fail_count = 0
                        t_now = time.strftime("%H:%M:%S")
                        symbol = payload.get("symbol", "XAUUSD")
                        bid = payload.get("market", {}).get("bid", 0)
                        print(f"[{t_now}] [SUCCESS] Synced live to Render: {symbol} @ {bid:.2f} (Status: 200 OK)", end="\r", flush=True)
                    else:
                        print(f"\n[WARN] Render responded with HTTP {res.status_code}: {res.text[:100]}", flush=True)
            else:
                print(f"[WAIT] Waiting for MT5 to export {delta_file.name}...", end="\r", flush=True)

        except Exception as e:
            fail_count += 1
            if fail_count <= 3 or fail_count % 10 == 0:
                print(f"\n[NOTICE] Sync waiting for Render connection ({fail_count} attempts): {e}", flush=True)
            time.sleep(2)

        time.sleep(1)

if __name__ == "__main__":
    main()

