@echo off

call "%~dp0RunTests.cmd" -Scenario ModeSwitch %*
exit /b %errorlevel%