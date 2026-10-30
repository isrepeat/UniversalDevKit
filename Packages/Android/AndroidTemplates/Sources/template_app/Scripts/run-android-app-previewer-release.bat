@echo off
setlocal
chcp 65001 >nul

set "parentProcessId=%~1"
if "%parentProcessId%"=="" set "parentProcessId=0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\build.ps1" -Command "run-android-app-previewer" -Configuration Release -ParentProcessId %parentProcessId%
set "exitCode=%ERRORLEVEL%"

echo.
if not "%exitCode%"=="0" (
    echo Previewer build failed with exit code %exitCode%. Copy the error text above.
) else (
    echo Previewer build completed successfully.
)
pause
exit /b %exitCode%