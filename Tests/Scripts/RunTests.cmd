@echo off

setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunTests.ps1" %*
set "testExitCode=%errorlevel%"
pause
exit /b %testExitCode%