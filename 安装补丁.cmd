@echo off
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Need Administrator. Elevating...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0°²×°²¹¶¡.ps1"
pause
