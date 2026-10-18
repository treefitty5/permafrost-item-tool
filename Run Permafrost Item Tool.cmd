@echo off
rem Starts the Permafrost Item Tool (needs PowerShell 7 / pwsh).
rem conhost --headless runs it with NO console window (Windows Terminal would otherwise open a black window).
cd /d "%~dp0"
where pwsh >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 ^(pwsh^) was not found. Install it from the Microsoft Store or https://aka.ms/powershell and try again.
  pause
  exit /b 1
)
start "" conhost.exe --headless pwsh -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0PermafrostItemTool.ps1"
