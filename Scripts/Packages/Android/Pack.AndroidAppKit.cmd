@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Build\Android\BuildKotlin.ps1" -Package AndroidAppKit %*
set "result=%errorlevel%"
pause
exit /b %result%