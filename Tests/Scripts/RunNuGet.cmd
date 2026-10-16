@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"

setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Integration\Packages\NuGet.Tests.ps1" -LicenseFile "%~dp0..\..\LICENSE" %*
set "testExitCode=%errorlevel%"
echo Press any key to continue...
pause >nul
exit /b %testExitCode%