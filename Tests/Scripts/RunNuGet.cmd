@echo off

setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Integration\Packages\NuGet.Tests.ps1" -LicenseFile "%~dp0..\..\LICENSE" %*
set "testExitCode=%errorlevel%"
pause
exit /b %testExitCode%