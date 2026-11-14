@echo off
setlocal
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\ApplyVisualStudioXmlStyle.ps1"
set "scriptExitCode=%errorlevel%"
echo.
if not "%scriptExitCode%"=="0" echo Failed with exit code %scriptExitCode%.
echo Press any key to continue...
pause >nul
exit /b %scriptExitCode%