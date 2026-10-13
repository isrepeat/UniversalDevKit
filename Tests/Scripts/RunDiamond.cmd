@echo off

call "%~dp0RunTests.cmd" -Scenario Diamond %*
exit /b %errorlevel%