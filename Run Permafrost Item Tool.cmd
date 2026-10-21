@echo off
rem Starts the Permafrost Item Tool. Needs PowerShell 7 (pwsh, a free Microsoft download); offers to install it with winget if it is missing.
rem conhost --headless runs the tool with NO console window (Windows Terminal would otherwise open a black window).
cd /d "%~dp0"
set "PWSH="
where pwsh >nul 2>nul && set "PWSH=pwsh"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if defined PWSH goto run

echo.
echo  The Permafrost Item Tool needs PowerShell 7, which is not installed on this PC.
echo  It is a free Microsoft download (about 100 MB) and does not replace Windows PowerShell.
echo.
where winget >nul 2>nul
if errorlevel 1 (
  echo  Please install it from https://aka.ms/powershell and then start this file again.
  echo.
  pause
  exit /b 1
)
choice /c YN /n /m " Install PowerShell 7 now with winget? [Y/N] "
if errorlevel 2 (
  echo  Not installed. You can install it later from https://aka.ms/powershell
  pause
  exit /b 1
)
winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH (
  echo.
  echo  The install did not finish. Install PowerShell 7 from https://aka.ms/powershell and start this file again.
  pause
  exit /b 1
)

:run
start "" conhost.exe --headless "%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0PermafrostItemTool.ps1"
exit /b 0
