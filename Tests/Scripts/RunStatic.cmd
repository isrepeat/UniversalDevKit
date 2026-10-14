@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"

call "%~dp0RunTests.cmd" -Scenario Static %*
exit /b %errorlevel%