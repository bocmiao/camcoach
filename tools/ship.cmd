@echo off
setlocal enabledelayedexpansion

REM ---------------------------------------------------------------
REM  ios-ship launcher
REM
REM  Pure ASCII on purpose. cmd.exe reads .cmd files in the OEM code
REM  page (GBK on Chinese Windows), so UTF-8 Chinese text inside a
REM  batch file gets chopped into fragments and executed as commands.
REM  All Chinese output comes from Python, never from this file.
REM ---------------------------------------------------------------

set "HERE=%~dp0"
set "PY="

REM  Switch the console to UTF-8 so Python's Chinese output renders.
REM  Without this the console decodes UTF-8 bytes as GBK and every
REM  Chinese character turns into garbage.
chcp 65001 >nul 2>nul

REM  1) WorkBuddy managed venv (the usual case here)
set "CAND=%USERPROFILE%\.workbuddy\binaries\python\envs\default\Scripts\python.exe"
if exist "%CAND%" set "PY=%CAND%"

REM  2) A real python on PATH.
REM     Note: `where python` alone is not enough. Windows ships a 0-byte
REM     App Execution Alias at AppData\Local\Microsoft\WindowsApps\python.exe
REM     that opens the Store instead of running. So actually execute it.
if not defined PY (
  python -c "import sys" >nul 2>nul
  if !errorlevel! equ 0 set "PY=python"
)

if not defined PY (
  echo.
  echo  [ERROR] No usable Python found.
  echo.
  echo  Install Python 3.9+ from python.org, or point this file at one:
  echo    set "PY=C:\path\to\python.exe"
  echo.
  echo  Note: the python.exe under WindowsApps is a Store stub, not a real
  echo  interpreter -- it does nothing when run from a batch file.
  echo.
  exit /b 1
)

"%PY%" "%HERE%ship.py" %*
exit /b %errorlevel%
