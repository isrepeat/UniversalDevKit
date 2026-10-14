@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\RunAllTests.ps1" %*
set "TestExitCode=%ERRORLEVEL%"
echo Press any key to continue...
pause >nul
exit /b %TestExitCode%