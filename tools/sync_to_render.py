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
from pathlib import Path

try:
    import requests
except ImportError:
    print("[ERROR] 'requests' library not found. Run: pip install requests")
    sys.exit(1)

# Configure your Render app URL: e.g. "https://your-gold-delta.onrender.com"
RENDER_URL = os.environ.get("RENDER_URL", "").rstrip("/")

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
    print("=====================================================================")
    print("   FXSSI Gold Delta — Oracle/PC to Render 1-Second Cloud Sync Agent")
    print("=====================================================================")
    
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

    last_sent_mtime = 0
    fail_count = 0

    while True:
        try:
            if delta_file.exists():
                curr_mtime = os.path.getmtime(delta_file)
                # Read file if modified or at least once every 10 seconds
                if curr_mtime != last_sent_mtime or (time.time() - last_sent_mtime > 10):
                    with open(delta_file, "r", encoding="utf-8", errors="ignore") as f:
                        payload = json.load(f)

                    res = requests.post(sync_endpoint, json=payload, timeout=5)
                    if res.status_code == 200:
                        last_sent_mtime = curr_mtime
                        fail_count = 0
                        t_now = time.strftime("%H:%M:%S")
                        symbol = payload.get("symbol", "XAUUSD")
                        bid = payload.get("market", {}).get("bid", 0)
                        print(f"[{t_now}] [SUCCESS] Synced live to Render: {symbol} @ {bid:.2f} (Status: 200 OK)", end="\r")
                    else:
                        print(f"\n[WARN] Render responded with HTTP {res.status_code}: {res.text[:100]}")
            else:
                print(f"[WAIT] Waiting for MT5 to export {delta_file.name}...", end="\r")

        except Exception as e:
            fail_count += 1
            if fail_count <= 3:
                print(f"\n[ERROR] Sync notice: {e}")
            time.sleep(2)

        time.sleep(1)

if __name__ == "__main__":
    main()

