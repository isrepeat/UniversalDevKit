@echo off

call "%~dp0RunTests.cmd" -Scenario Dynamic %*
exit /b %errorlevel%