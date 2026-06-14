@echo off
REM run.cmd -- double-clickable wrapper for install.ps1
REM
REM Solves the two friction points a normal Windows user hits:
REM   1. .ps1 files are blocked by default (ExecutionPolicy)
REM   2. Double-clicking .ps1 opens Notepad, not PowerShell
REM
REM Just double-click this file in Explorer. You'll get a PowerShell
REM window with the installer running. The window stays open at the
REM end so you can read the output.

setlocal
cd /d "%~dp0"

REM -NoProfile        : skip user's PS profile (faster + reproducible)
REM -ExecutionPolicy  : bypass the unsigned-script block for this run only
REM -NoExit           : keep the window open after the script finishes
REM -File             : run our installer
REM %*                : pass through any args the user supplied
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1" %*

endlocal
