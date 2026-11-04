@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo    Public Activity Delta — Live in BOTH Localhost & Render Server
echo =====================================================================
echo.

set RENDER_URL=https://delta-by-arnob.onrender.com
set PYTHONUNBUFFERED=1

echo [1/3] Ensuring dependencies are installed...
python -m pip install -r "%~dp0backend\requirements.txt" --quiet

echo [2/3] Starting Localhost Bridge Server on Port 80...
start "Public Activity Delta - Localhost Server" cmd /k "python \"%~dp0backend\app.py\""

timeout /t 2 /nobreak >nul

echo [3/3] Launching Live Cloud Stream to Render:
echo       %RENDER_URL%
echo.
echo =====================================================================
echo   LOCAL ACCESS:  http://localhost
echo   ONLINE CLOUD:  %RENDER_URL%
echo =====================================================================
echo.
echo Opening both dashboards in your browser...
start "" "http://localhost"
start "" "%RENDER_URL%"

:: Run the cloud sync agent in this window
python "%~dp0tools\sync_to_render.py" "%RENDER_URL%"

pause

