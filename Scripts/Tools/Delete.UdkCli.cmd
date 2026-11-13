@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Delete.UdkCli.ps1"
set "result=%errorlevel%"
pause
exit /b %result%