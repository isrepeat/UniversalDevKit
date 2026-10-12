@echo off

call "%~dp0RunTests.cmd" -Scenario Static %*
exit /b %errorlevel%