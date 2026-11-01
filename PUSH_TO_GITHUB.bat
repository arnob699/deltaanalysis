@echo off
setlocal

echo =====================================================================
echo    Push FXSSI Gold Delta to GitHub: arnob699/deltaanalysis
echo =====================================================================
echo.

set GIT="C:\Users\ARNOB\AppData\Local\Programs\MinGit\cmd\git.exe"
set DEFAULT_REPO=https://github.com/arnob699/deltaanalysis.git

echo Target Repository: %DEFAULT_REPO%
echo.

%GIT% remote remove origin 2>nul
%GIT% remote add origin %DEFAULT_REPO%
%GIT% branch -M main

echo Pushing to GitHub...
echo (If prompted for password, paste your GitHub Personal Access Token)
echo.

%GIT% push -u origin main

echo.
if %ERRORLEVEL% EQU 0 (
    echo =====================================================================
    echo   SUCCESS: All files successfully pushed to your GitHub repository!
    echo   View online: https://github.com/arnob699/deltaanalysis
    echo =====================================================================
) else (
    echo.
    echo =====================================================================
    echo If authentication failed, you need a Personal Access Token:
    echo 1. Open: https://github.com/settings/tokens
    echo 2. Generate new token (classic) with "repo" checkbox selected.
    echo 3. Copy the token and push via:
    echo    git push https://TOKEN@github.com/arnob699/deltaanalysis.git main
    echo =====================================================================
)

pause
