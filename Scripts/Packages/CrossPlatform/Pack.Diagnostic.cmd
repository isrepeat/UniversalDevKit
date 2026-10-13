@echo off

setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\Packages\Build\NuGet\Build.ps1" -Components Diagnostic -LicenseFile "%~dp0..\..\..\LICENSE" %*
set "packageExitCode=%errorlevel%"
pause
exit /b %packageExitCode%