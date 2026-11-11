@echo off
setlocal
chcp 65001 >nul
where.exe pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Publish.UdkCli.ps1" %*
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\Publish.UdkCli.ps1" %*
)
set "result=%errorlevel%"
pause
exit /b %result%