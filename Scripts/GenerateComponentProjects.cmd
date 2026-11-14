@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Sources\Windows\UdkCli\Tools\ProjectTools\Generate.ps1" -ManifestPath "%~dp0..\Components" %*
set "scriptExitCode=%errorlevel%"
echo.
if "%scriptExitCode%"=="0" (
    echo Completed successfully.
) else (
    echo Failed with exit code %scriptExitCode%.
)
echo Press any key to continue...
pause >nul
exit /b %scriptExitCode%