@echo off
setlocal EnableExtensions

rem publish_release.cmd
rem Wrapper for tools\publish_release.ps1

set "SCRIPT_DIR=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%publish_release.ps1" %*
exit /b %ERRORLEVEL%
