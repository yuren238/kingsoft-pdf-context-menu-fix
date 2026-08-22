@echo off
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Need Administrator. Elevating...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
reg delete "HKLM\SOFTWARE\Classes\CLSID\{8FE8AC65-EE7F-4C29-AF72-D2BACB633558}" /f >nul 2>&1
echo Done. Fix removed.
choice /c YN /m "Restart explorer now"
if errorlevel 2 goto :end
taskkill /f /im explorer.exe >nul 2>&1
start explorer.exe
:end
pause
