@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\ConnectConsole.ps1" %*
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\ConnectConsole.ps1" %*
)
set "scriptExitCode=%errorlevel%"
pause >nul
exit /b %scriptExitCode%