@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\ConnectConsole.ps1" %*
set "scriptExitCode=%errorlevel%"
pause >nul
exit /b %scriptExitCode%