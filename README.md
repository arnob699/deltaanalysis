# FXSSI Gold (XAUUSD) 20-Min Delta & Multi-Day Live Bridge (BST 12-Hour)

An institutional-grade, **database-free** live bridge and web dashboard built specifically for **Gold (`XAUUSDm` / `XAUUSD`)** using the official [`FXSSI.TradingActivity`](https://fxssi.com/fxssi-trading-activity-mt4) indicator (`version 1.090` for MT5).

This system captures every individual **20-minute delta interval** (72 intervals per 24-hour day) and computes the **Daily Cumulative Net Delta** (`Increase` and `Decrease`) from Daily Open to Daily Close.

All timestamps are displayed strictly in **Bangladesh Standard Time (BST, UTC+6) in 12-Hour format (`hh:mm AM/PM`)**, with full support for browsing up to **29 days of historical sentiment data** loaded from FXSSI.

---

## 🌟 Key Features

1. **Exclusively Tailored for Gold (`XAUUSDm`):**
   - Automatically binds to the active `FXSSI.TradingActivity` indicator attached to the Gold chart in MT5.
   - Prevents duplicate instance conflicts and leaks by directly referencing the active chart indicator.
2. **Bangladesh Time (BST / UTC+6) in 12-Hour Clock:**
   - Real-time live BST clock (`hh:mm:ss AM/PM BST`).
   - Every 20-minute interval bar is labeled in 12-hour BST (e.g. `06:00 AM`, `06:20 AM`, `03:20 PM`, `11:40 PM`) alongside the corresponding broker time.
   - Day open anchored to **`06:00 AM BST`** (`00:00` Broker Time).
3. **Multi-Day Historical Archive (Up to 29 Days):**
   - Full access to all 26+ historical days loaded in FXSSI memory.
   - Interactive Session Switcher Ribbon: Click any day pill or select from the dropdown to load that day's 3 Hero Cards, Chart, and 20-min table!
   - 29-Day Performance Archive Matrix table comparing net deltas and contrarian bias across all recorded trading days.
   - "Return to Today's Live Gold Stream" one-click shortcut.
4. **Zero-Database JSON State Architecture:**
   - No external SQL/NoSQL databases. MQL5 exports state directly to `MQL5/Files/fxssi_daily_delta.json`.
   - The Python FastAPI server caches snapshots so history remains accessible even if MT5 is closed.
5. **Real-Time 1-Second Listener & Bi-Directional Refresh:**
   - 1-second continuous background `OnTimer()` in MT5 updates heartbeat and listens for web refresh requests (`refresh_cmd.json`).
   - Clicking **"Refresh from MT5"** in the web dashboard forces MT5 to rescan all historical days in ~30ms and refresh the UI instantly.

---

## 🏛 Architecture Overview

```
       ┌────────────────────────────────────────────────────────┐
       │                   MetaTrader 5                         │
       │       XAUUSDm, PERIOD_M20 Chart (Exness Broker)        │
       │  FXSSI.TradingActivity.ex5 + fxssi.45.dll              │
       │                           ▲                            │
       │                           │ (Direct Chart Reuse)       │
       │                           ▼                            │
       │           FXSSI_DailyDelta_Bridge.mq5 / .ex5           │
       │   (29-Day Scan + BST 12h Conversion + 1s OnTimer)      │
       └───────────────────────────┬────────────────────────────┘
                                   │
              Writes Every 1s /    │ Reads & Deletes
              New Bar / Refresh:   │ Instant Web Command:
              fxssi_daily_delta.json refresh_cmd.json
                                   │
                                   ▼
       ┌────────────────────────────────────────────────────────┐
       │             Python FastAPI Live Server                 │
       │               http://localhost:8000                    │
       │                                                        │
       │     GET  /api/delta   ──► Full Multi-Day JSON Payload  │
       │     GET  /api/history ──► Historical Days Summary      │
       │     POST /api/refresh ──► Triggers MT5 Instant Rescan  │
       │     GET  /api/status  ──► Health & Path Diagnostics    │
       └───────────────────────────┬────────────────────────────┘
                                   │
                                   ▼
       ┌────────────────────────────────────────────────────────┐
       │       Dark Institutional Trading Web Dashboard         │
       │                                                        │
       │  1. Pinned System Health Banner with Live BST Clock    │
       │  2. Historical Session Switcher (Up to 29 Days)        │
       │  3. Daily Cumulative Hero Cards (Increase & Decrease)  │
       │  4. Interactive 20-Min Delta & Cumulative Line Chart   │
       │  5. Chronological 20-Minute Breakdown & Crowd Tags     │
       │  6. 29-Day Historical Sentiment Archive Matrix Table   │
       └────────────────────────────────────────────────────────┘
```

---

## 🚀 Running the System

### 1. MT5 Terminal Setup
1. Open MT5 on **Gold** (`XAUUSDm`, `PERIOD_M20`).
2. Attach `FXSSI.TradingActivity.ex5` (DLL imports enabled in Tools &rarr; Options &rarr; Expert Advisors).
3. Attach `FXSSI_DailyDelta_Bridge.ex5` from Expert Advisors.
4. The on-chart button **`[ REFRESH GOLD DELTA (BST) ]`** will appear in the top-left corner.

### 2. Python Live Server & Dashboard
Run the server locally:
```powershell
RUN_DASHBOARD.bat
```
Open **[http://localhost](http://localhost)** in your browser!

### 3. Put Online For Free (1-Second Real-Time Sync)
To make your dashboard accessible from anywhere in the world on mobile or web with real-time 1-second auto-sync:
Double-click:
👉 **`RUN_ONLINE.bat`**

This starts the local FastAPI server and your secure HTTPS public tunnel:
* **Public URL:** `https://viral-demystify-siesta.ngrok-free.dev`
* **Local URL:** `http://localhost`
* Updates automatically every 1 second whenever MT5 is running on your PC.
