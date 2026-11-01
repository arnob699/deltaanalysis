# Start FXSSI Gold Delta Live Bridge & Online ngrok Tunnel
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   FXSSI Gold Delta — Live Online Bridge (1-Second Auto-Sync)" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verify Python
try {
    $pyVersion = python --version 2>&1
    Write-Host "[OK] Detected: $pyVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Python is not installed or not in system PATH!" -ForegroundColor Red
    pause
    exit 1
}

# 2. Dependencies
Write-Host "[1/3] Ensuring backend requirements are installed..." -ForegroundColor Cyan
python -m pip install -r "$scriptDir\backend\requirements.txt" --quiet

# 3. Start local Python server
Write-Host "[2/3] Starting FastAPI Live Bridge Server on Port 80..." -ForegroundColor Cyan
Start-Process cmd.exe -ArgumentList "/c python `"$scriptDir\backend\app.py`"" -WindowStyle Minimized
Start-Sleep -Seconds 2

# 4. Launch ngrok
Write-Host "[3/3] Launching Public HTTPS Tunnel via ngrok..." -ForegroundColor Cyan
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "  ONLINE PUBLIC URL: https://viral-demystify-siesta.ngrok-free.dev" -ForegroundColor Green
Write-Host "  LOCAL ACCESS URL:  http://localhost" -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host ""

# Open public URL in browser
Start-Process "https://viral-demystify-siesta.ngrok-free.dev"

# Run ngrok foreground to show connection logs
& ngrok http 80 --url https://viral-demystify-siesta.ngrok-free.dev

