@echo off
call "%~dp0RunTests.cmd" -Scenario Export %*
exit /b %errorlevel%