# Start FXSSI Gold Delta Live Bridge & Dashboard

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   FXSSI Gold Delta Live Bridge & Institutional Dashboard" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Verify Python
try {
    $pyVersion = python --version 2>&1
    Write-Host "[OK] Detected: $pyVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Python is not installed or not in system PATH!" -ForegroundColor Red
    pause
    exit 1
}

# Install dependencies if needed
Write-Host "Ensuring requirements are installed..." -ForegroundColor Cyan
python -m pip install -r "$scriptDir\backend\requirements.txt" --quiet

# Open browser
Start-Process "http://localhost"

# Run server
Write-Host "Server running at http://localhost (Port 80) (Press Ctrl+C to stop)" -ForegroundColor Yellow
python "$scriptDir\backend\app.py"
