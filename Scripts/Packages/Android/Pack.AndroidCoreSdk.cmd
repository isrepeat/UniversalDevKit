@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Build\Build.ps1" -PackagePath Packages/Android/AndroidCoreSdk/Package.json -Delivery Android %*
set "result=%errorlevel%"
pause
exit /b %result%