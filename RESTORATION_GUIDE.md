# 🛡️ Activity Delta — Complete Project Restoration & Reinstall Guide

This standalone package contains the complete, self-contained **FXSSI Gold (XAUUSD) 20-Min Delta Live Bridge & Institutional Multi-Day Dashboard**.

Everything required to run, recover, or move this system to another computer is organized right here.

---

## 📁 Package Directory Structure

```
Activity Delta/
├── mt5/                                 <-- MetaTrader 5 Expert Advisor, Indicator & Scripts
│   ├── FXSSI_DailyDelta_Bridge.mq5      <-- MQL5 Source Code (BST 12-Hour & Multi-Day)
│   ├── FXSSI_DailyDelta_Bridge.ex5      <-- Compiled binary (Drop onto Gold chart)
│   ├── Export_Gold_Delta_Once.mq5       <-- One-Click Manual Export Script Source
│   ├── Export_Gold_Delta_Once.ex5       <-- One-Click Manual Export Script Binary
│   ├── Test_History_Scan.mq5            <-- Verification Script Source
│   └── Test_History_Scan.ex5            <-- Verification Script Binary
│
├── backend/                             <-- Python Live Server
│   ├── app.py                           <-- FastAPI Server (Endpoints & Multi-Day Cache)
│   ├── requirements.txt                 <-- Python Dependencies (fastapi, uvicorn, pydantic)
│   └── data/
│       └── cached_delta.json            <-- 26-Day Historical Gold Delta Dataset Backup
│
├── frontend/                            <-- Institutional Web Dashboard
│   ├── index.html                       <-- Dark Institutional Trading UI
│   ├── style.css                        <-- Full Responsive Theme & Day Selector Styling
│   ├── app.js                           <-- Live BST Clock, Chart.js & Multi-Day Switcher
│   └── chart.umd.min.js                 <-- Offline Local Chart.js Library
│
├── docs/                                <-- Official Documentation
│   └── FXSSI_TradingActivity_Documentation.pdf
│
├── latest_snapshot_backup/              <-- Cold Data Recovery
│   └── fxssi_daily_delta.json           <-- Raw JSON exported from MT5 Files
│
├── INSTALL_TO_MT5.bat                   <-- 1-Click Automated MT5 Reinstaller (Batch)
├── INSTALL_TO_MT5.ps1                   <-- 1-Click Automated MT5 Reinstaller (PowerShell)
├── RUN_DASHBOARD.bat                    <-- 1-Click Dashboard Launcher & Browser Opener
├── RUN_DASHBOARD.ps1                    <-- 1-Click Dashboard Launcher (PowerShell)
└── RESTORATION_GUIDE.md                 <-- This Guide
```

---

## ⚡ How to Reinstall / Restore in 2 Steps

### Step 1: Deploy to MetaTrader 5
Double-click:
👉 **`INSTALL_TO_MT5.bat`**

This script automatically:
1. Locates your MT5 terminal folder (`%APPDATA%\MetaQuotes\Terminal\<hash>\MQL5\`).
2. Copies `FXSSI_DailyDelta_Bridge` into `MQL5\Experts\` and `MQL5\Indicators\`.
3. Copies `Export_Gold_Delta_Once` into `MQL5\Scripts\`.
4. Restores `fxssi_daily_delta.json` into `MQL5\Files\`.

### Step 2: Launch the Web Dashboard
* **For Local Use:** Double-click 👉 **`RUN_DASHBOARD.bat`** (Opens `http://localhost`).
* **For Free Online Access (Mobile & Web):** Double-click 👉 **`RUN_ONLINE.bat`** (Streams live to `https://viral-demystify-siesta.ngrok-free.dev` with 1-second auto-sync).

---

## ⚙️ MetaTrader 5 Chart Setup Checklist

1. **Enable DLLs in MT5:**
   * Go to **Tools** &rarr; **Options** (`Ctrl + O`).
   * Select the **Expert Advisors** tab.
   * Ensure **"Allow DLL imports"** is **CHECKED**.
2. **Open Gold Chart:**
   * Symbol: **`XAUUSDm`** (or `XAUUSD` depending on your broker).
   * Timeframe: **`PERIOD_M20`** (20-Minute).
3. **FXSSI Indicators:**
   * Ensure `FXSSI.TradingActivity` is attached to the chart with your FXSSI account logged in.
4. **Attach Bridge:**
   * Drag `FXSSI_DailyDelta_Bridge` from the Navigator onto the chart.
   * In the popup, make sure **"Allow DLL imports"** is checked.
   * Click **OK**.
5. **Verify:**
   * The green on-chart button **`[ REFRESH GOLD DELTA (BST) ]`** will appear in the top-left corner.
   * The web dashboard at `http://localhost` will show **All Systems Operational** (Green).

---

## 🇧🇩 Bangladesh Time (BST 12-Hour) Details

* **Timezone:** Asia/Dhaka (`UTC+6`).
* **Format:** 12-Hour Clock (`hh:mm AM/PM`).
* **Daily Open:** `06:00 AM BST` (`00:00` Broker Time).
* **Daily Close:** `05:40 AM BST` (`23:40` Broker Time).
* **History:** Browse all available past sessions (up to 29 days) using the ribbon pills or dropdown menu.
