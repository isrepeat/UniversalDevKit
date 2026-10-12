@echo off

call "%~dp0RunTests.cmd" -Scenario Shared %*
exit /b %errorlevel%