@echo off

setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Integration\Packages\NuGet.Registry.Tests.ps1" %*
set "testExitCode=%errorlevel%"
pause
exit /b %testExitCode%