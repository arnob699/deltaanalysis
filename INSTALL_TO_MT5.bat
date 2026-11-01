@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo    FXSSI Gold Delta Bridge — Automated MT5 Reinstaller / Restorer
echo =====================================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0INSTALL_TO_MT5.ps1"

echo.
pause
