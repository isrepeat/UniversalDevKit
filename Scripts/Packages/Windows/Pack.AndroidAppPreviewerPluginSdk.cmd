@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Windows\AndroidAppPreviewerPluginSdk\Build.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%