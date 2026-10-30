@echo off
chcp 65001 >nul
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\ResetBuildDrives.ps1" %*
set "cleanupExitCode=%errorlevel%"
echo Press any key to continue...
pause >nul
exit /b %cleanupExitCode%