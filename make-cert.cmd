@echo off
rem ---------------------------------------------------------------------------
rem Wrapper for tools\make-ios-cert.sh
rem
rem Why this file exists:
rem   Git for Windows puts only Git\cmd on PATH by default, and that folder has
rem   git.exe but NO bash.exe. So plain "bash" fails in cmd.exe even though
rem   "git" works. This wrapper does not rely on PATH - it looks for bash.exe
rem   in the usual install locations.
rem
rem Usage (run from the ios folder):
rem   make-cert step1
rem   make-cert step2
rem
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat/.cmd in the current
rem OEM codepage (GBK on Chinese Windows), so UTF-8 Chinese comments get
rem mangled and turn into bogus commands.
rem ---------------------------------------------------------------------------

setlocal
chcp 65001 >nul 2>nul

set "SCRIPT=%~dp0tools\make-ios-cert.sh"
set "BASH="

if not exist "%SCRIPT%" (
  echo.
  echo [ERROR] Cannot find tools\make-ios-cert.sh
  echo         Run this from the ios folder.
  echo.
  exit /b 1
)

set "C1=%ProgramFiles%\Git\bin\bash.exe"
set "C2=%ProgramFiles(x86)%\Git\bin\bash.exe"
set "C3=%LocalAppData%\Programs\Git\bin\bash.exe"
set "C4=%ProgramFiles%\Git\usr\bin\bash.exe"

if exist "%C1%" set "BASH=%C1%"
if not defined BASH if exist "%C2%" set "BASH=%C2%"
if not defined BASH if exist "%C3%" set "BASH=%C3%"
if not defined BASH if exist "%C4%" set "BASH=%C4%"

if not defined BASH (
  for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined BASH set "BASH=%%B"
  )
)

if not defined BASH (
  echo.
  echo [ERROR] bash.exe not found.
  echo         Install Git for Windows: https://git-scm.com/download/win
  echo         Default options are fine; it ships bash and openssl.
  echo.
  exit /b 1
)

echo [bash] %BASH%
echo.

"%BASH%" "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo [FAILED] exit code %RC%
)
exit /b %RC%
