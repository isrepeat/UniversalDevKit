@echo off

call "%~dp0RunTests.cmd" -Scenario Disconnect %*
exit /b %errorlevel%