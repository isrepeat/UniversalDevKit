@echo off

setlocal
chcp 65001 >nul
rem Run the workflow for this checkout, independently of the current directory.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\PowerShell\AutoPrMerge.ps1" -BatDir "%~dp0." %*
set "workflowExitCode=%errorlevel%"
pause
exit /b %workflowExitCode%