@echo off
setlocal

echo =====================================================================
echo    FXSSI Gold Delta — Live Online Bridge (1-Second Auto-Sync)
echo =====================================================================
echo.

python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python is not installed or not in system PATH!
    echo Please install Python 3.10+ from python.org and check "Add Python to PATH".
    pause
    exit /b 1
)

echo [1/3] Ensuring backend dependencies are installed...
python -m pip install -r "%~dp0backend\requirements.txt" --quiet

echo [2/3] Starting FastAPI Live Bridge Server on Port 80...
:: Start Python server in a background window
start "Public Activity Delta - Local Server" /min cmd /c "python \"%~dp0backend\app.py\""

:: Brief pause to let server bind port 80
timeout /t 2 /nobreak >nul

echo [3/3] Starting Public Secure HTTPS Tunnel via ngrok...
echo.
echo =====================================================================
echo   ONLINE PUBLIC URL: https://viral-demystify-siesta.ngrok-free.dev
echo   LOCAL ACCESS URL:  http://localhost
echo =====================================================================
echo.
echo Opening your live online dashboard in default browser...
start "" "https://viral-demystify-siesta.ngrok-free.dev"

:: Run ngrok in the foreground to monitor incoming requests and status
ngrok http 80 --url https://viral-demystify-siesta.ngrok-free.dev

pause

