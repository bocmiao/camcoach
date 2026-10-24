@echo off
rem SPDX-License-Identifier: Apache-2.0
rem One-click wrapper for apple-auto.py on Windows.
rem This file is pure ASCII on purpose: cmd.exe reads .cmd in the OEM
rem code page (GBK on Chinese Windows) and mangles UTF-8 Chinese text.
rem All human-readable Chinese output comes from the Python script instead.

chcp 65001 >nul 2>nul
setlocal
cd /d "%~dp0"

set "PYEXE="

python --version >nul 2>nul
if not errorlevel 1 set "PYEXE=python"

if not defined PYEXE (
  py -3 --version >nul 2>nul
  if not errorlevel 1 set "PYEXE=py -3"
)

if not defined PYEXE (
  if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
)
if not defined PYEXE (
  if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
)
if not defined PYEXE (
  if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
)
if not defined PYEXE (
  if exist "C:\Python313\python.exe" set "PYEXE=C:\Python313\python.exe"
)
if not defined PYEXE (
  if exist "C:\Python312\python.exe" set "PYEXE=C:\Python312\python.exe"
)

if not defined PYEXE (
  echo.
  echo   Python not found. / Python mei zhuang.
  echo.
  echo   Install it here:  https://www.python.org/downloads/
  echo   IMPORTANT: during install, tick "Add python.exe to PATH".
  echo.
  pause
  exit /b 1
)

%PYEXE% -c "import cryptography" >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Installing one dependency ^(first run only^) ...
  %PYEXE% -m pip install --quiet --upgrade cryptography
  %PYEXE% -c "import cryptography" >nul 2>nul
  if errorlevel 1 (
    echo.
    echo   Failed to install "cryptography".
    echo   Try running this manually:
    echo     %PYEXE% -m pip install cryptography
    echo.
    pause
    exit /b 1
  )
)

%PYEXE% "%~dp0apple-auto.py" %*
set "RC=%errorlevel%"

echo.
if not "%RC%"=="0" echo   Exit code: %RC%
pause
exit /b %RC%
