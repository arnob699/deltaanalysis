# =====================================================================
#   FXSSI Gold Delta Bridge — Automated MT5 Reinstaller / Restorer (PowerShell)
# =====================================================================

Write-Host "Searching for MetaTrader 5 Terminal directories..." -ForegroundColor Cyan

$appData = [System.Environment]::GetFolderPath('ApplicationData')
$terminalsPattern = Join-Path $appData "MetaQuotes\Terminal\*\MQL5"
$mql5Dirs = Get-ChildItem -Path $terminalsPattern -ErrorAction SilentlyContinue

if (-not $mql5Dirs -or $mql5Dirs.Count -eq 0) {
    Write-Host "[ERROR] Could not find any MT5 Terminal installation under AppData\MetaQuotes\Terminal!" -ForegroundColor Red
    Write-Host "Please start MetaTrader 5 at least once, or manually copy files from the 'mt5' folder." -ForegroundColor Yellow
    exit 1
}

# Sort by newest modified directory
$targetMql5 = $mql5Dirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "[FOUND] Active MT5 MQL5 Directory:" -ForegroundColor Green
Write-Host "  $($targetMql5.FullName)" -ForegroundColor White
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$mt5Source = Join-Path $scriptDir "mt5"
$snapshotSource = Join-Path $scriptDir "latest_snapshot_backup\fxssi_daily_delta.json"

# Destination directories
$dstExperts = Join-Path $targetMql5.FullName "Experts"
$dstIndicators = Join-Path $targetMql5.FullName "Indicators"
$dstScripts = Join-Path $targetMql5.FullName "Scripts"
$dstFiles = Join-Path $targetMql5.FullName "Files"

# Ensure directories exist
New-Item -ItemType Directory -Path $dstExperts -Force | Out-Null
New-Item -ItemType Directory -Path $dstIndicators -Force | Out-Null
New-Item -ItemType Directory -Path $dstScripts -Force | Out-Null
New-Item -ItemType Directory -Path $dstFiles -Force | Out-Null

Write-Host "Restoring and deploying MT5 files..." -ForegroundColor Cyan

# 1. Copy Bridge to Experts and Indicators
Copy-Item (Join-Path $mt5Source "FXSSI_DailyDelta_Bridge.ex5") -Destination $dstExperts -Force
Copy-Item (Join-Path $mt5Source "FXSSI_DailyDelta_Bridge.mq5") -Destination $dstExperts -Force
Copy-Item (Join-Path $mt5Source "FXSSI_DailyDelta_Bridge.ex5") -Destination $dstIndicators -Force
Copy-Item (Join-Path $mt5Source "Bangladesh_Standard_Time_Clock.mq5") -Destination $dstIndicators -Force
Copy-Item (Join-Path $mt5Source "Bangladesh_Standard_Time_Clock.ex5") -Destination $dstIndicators -Force
Write-Host "  [OK] Deployed FXSSI_DailyDelta_Bridge (.mq5 & .ex5) to Experts and Indicators" -ForegroundColor Green
Write-Host "  [OK] Deployed Bangladesh_Standard_Time_Clock (.mq5 & .ex5) to Indicators" -ForegroundColor Green

# 2. Copy One-Click Snapshot Script
Copy-Item (Join-Path $mt5Source "Export_Gold_Delta_Once.ex5") -Destination $dstScripts -Force
Copy-Item (Join-Path $mt5Source "Export_Gold_Delta_Once.mq5") -Destination $dstScripts -Force
Copy-Item (Join-Path $mt5Source "Test_History_Scan.ex5") -Destination $dstScripts -Force
Copy-Item (Join-Path $mt5Source "Test_History_Scan.mq5") -Destination $dstScripts -Force
Write-Host "  [OK] Deployed Export_Gold_Delta_Once (.mq5 & .ex5) to Scripts" -ForegroundColor Green

# 3. Restore Latest Snapshot JSON if available
if (Test-Path $snapshotSource) {
    Copy-Item $snapshotSource -Destination $dstFiles -Force
    Write-Host "  [OK] Restored historical multi-day dataset into MQL5\Files\fxssi_daily_delta.json" -ForegroundColor Green
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  SUCCESS: All files restored and deployed into your MetaTrader 5!" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps in MT5:" -ForegroundColor Yellow
Write-Host "  1. In MT5 Navigator (Ctrl+N), right-click 'Expert Advisors' -> click 'Refresh'." -ForegroundColor White
Write-Host "  2. Open Gold chart ('XAUUSDm', M20 timeframe)." -ForegroundColor White
Write-Host "  3. Drag 'FXSSI_DailyDelta_Bridge' onto the chart (ensure 'Allow DLL imports' is checked)." -ForegroundColor White
Write-Host "  4. Double-click 'RUN_DASHBOARD.bat' in this folder to open the web dashboard!" -ForegroundColor White
