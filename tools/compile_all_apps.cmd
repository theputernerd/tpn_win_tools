@echo off
setlocal EnableExtensions

rem Run from anywhere; always anchor to repo root (parent of this tools folder)
set "TOOLS_DIR=%~dp0"
for %%I in ("%TOOLS_DIR%\..") do set "REPO_ROOT=%%~fI"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

pushd "%REPO_ROOT%" >nul

echo === Compiling all apps ===
echo Repo: %REPO_ROOT%
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass ^
  -File "%TOOLS_DIR%\compile_all_apps.ps1" %*

if errorlevel 1 (
  echo.
  echo *** BUILD FAILED ***
  popd >nul
  exit /b 1
)

echo.
echo === Build complete ===
popd >nul
exit /b 0
