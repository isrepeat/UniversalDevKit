@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Build\Build.ps1" -PackagePath Packages/Windows/AndroidAppPreviewerPluginSdk/Package.json %*
set "result=%errorlevel%"
pause
exit /b %result%