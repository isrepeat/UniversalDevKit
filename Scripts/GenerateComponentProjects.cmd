@echo off
chcp 65001 >nul
set "DOTNET_CLI_UI_LANGUAGE=en-US"
set "VSLANG=1033"
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\GenerateComponentProjects.ps1" %*
) else (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerShell\GenerateComponentProjects.ps1" %*
)
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