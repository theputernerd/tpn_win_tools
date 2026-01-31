@echo off
setlocal EnableExtensions

rem smoke_test.cmd
rem Wrapper for tools\smoke_test.ps1

set "SCRIPT_DIR=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%smoke_test.ps1" %*
exit /b %ERRORLEVEL%
