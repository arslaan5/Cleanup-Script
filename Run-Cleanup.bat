@echo off
TITLE Windows Cleanup Utility PRO+ Launcher
echo Launching Windows Cleanup Utility PRO+...

REM Check for Administrative permissions
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Administrator privileges confirmed.
    PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup.ps1"
) else (
    echo Requesting Administrator privileges...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0cleanup.ps1""' -Verb RunAs}"
)
exit
