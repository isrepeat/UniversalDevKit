@echo off
setlocal
chcp 65001 >nul
pwsh.exe -NoProfile -File "%~dp0..\PowerShell\PublishUdkCli.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%