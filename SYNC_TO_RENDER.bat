@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo    FXSSI Gold Delta — Live Cloud Stream to Render (1-Sec Sync)
echo =====================================================================
echo.

set PYTHONUNBUFFERED=1

set CONFIG_FILE="%~dp0render_url.txt"
set RENDER_URL=

if exist %CONFIG_FILE% (
    set /p RENDER_URL=<%CONFIG_FILE%
)

if "%RENDER_URL%"=="" (
    echo Enter your live Render URL from your Render dashboard:
    echo (Example: https://gold-delta.onrender.com)
    echo.
    set /p RENDER_URL="Render URL: "
    echo !RENDER_URL!> %CONFIG_FILE%
)

echo.
echo [OK] Streaming MT5 to: %RENDER_URL%
echo Press Ctrl+C to stop.
echo.

python "%~dp0tools\sync_to_render.py" "%RENDER_URL%"

pause

