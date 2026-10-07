@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Connect.ps1"
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Connect.ps1"
)
set "scriptExitCode=%errorlevel%"
echo.
if "%scriptExitCode%"=="0" (
    echo Completed successfully.
) else (
    echo Failed with exit code %scriptExitCode%.
)
pause
exit /b %scriptExitCode%