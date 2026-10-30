@echo off
chcp 65001 >nul
setlocal
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Setup.ps1" %*
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Setup.ps1" %*
)
set "scriptExitCode=%errorlevel%"
echo.
if "%scriptExitCode%"=="0" (
    echo Completed successfully.
) else (
    echo Failed with exit code %scriptExitCode%.
)
echo Press any key to continue...
pause >nul
exit /b %scriptExitCode%