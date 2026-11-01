@echo off
setlocal

echo =====================================================================
echo    FXSSI Gold Delta Live Bridge & Institutional Dashboard
echo =====================================================================
echo.

python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python is not installed or not in system PATH!
    echo Please install Python 3.10+ from python.org and check "Add Python to PATH".
    pause
    exit /b 1
)

echo Checking dependencies...
python -m pip install -r "%~dp0backend\requirements.txt" --quiet

echo.
echo Starting FastAPI Live Bridge Server on http://localhost (Port 80) ...
start "" "http://localhost"
python "%~dp0backend\app.py"

pause
