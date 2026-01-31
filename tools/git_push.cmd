@echo off
setlocal EnableExtensions

rem git_push.cmd
rem Wrapper for tools\git_push.ps1

set "SCRIPT_DIR=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%git_push.ps1" %*
exit /b %ERRORLEVEL%
