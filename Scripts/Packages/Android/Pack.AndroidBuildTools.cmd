@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Build\Content\Build.ps1" -Package AndroidBuildTools %*
set "packageExitCode=%errorlevel%"
pause
exit /b %packageExitCode%