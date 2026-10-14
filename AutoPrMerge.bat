@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"

setlocal
chcp 65001 >nul
rem Run the workflow for this checkout, independently of the current directory.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\PowerShell\AutoPrMerge.ps1" -BatDir "%~dp0." %*
set "workflowExitCode=%errorlevel%"
echo Press any key to continue...
pause >nul
exit /b %workflowExitCode%