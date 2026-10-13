@echo off

call "%~dp0RunTests.cmd" -Mode Submodule %*
exit /b %errorlevel%