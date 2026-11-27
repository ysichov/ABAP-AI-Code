@echo off
setlocal
chcp 65001 >nul
set "PYTHONUTF8=1"
where python.exe >nul 2>&1
if errorlevel 1 (
    py -3 "%~dp0mf0_schema_probe.py"
) else (
    python "%~dp0mf0_schema_probe.py"
)
set "probe_exit=%errorlevel%"
echo.
pause
exit /b %probe_exit%
