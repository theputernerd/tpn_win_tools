@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem make_release.cmd
rem - Ensures build deps for the selected Python
rem - Compiles all tools
rem - Leaves install and publishing to the user

set "RUN_DIR=%CD%"
set "LOG_FILE=%RUN_DIR%\release_build.log"

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..") do set "REPO_ROOT=%%~fI"
set "TOOLS_DIR=%REPO_ROOT%\tools"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

echo =============================================== > "%LOG_FILE%"
echo RELEASE BUILD STARTED >> "%LOG_FILE%"
echo Timestamp: %DATE% %TIME% >> "%LOG_FILE%"
echo Run dir:   %RUN_DIR% >> "%LOG_FILE%"
echo Repo root: %REPO_ROOT% >> "%LOG_FILE%"
echo Tools dir: %TOOLS_DIR% >> "%LOG_FILE%"
echo =============================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

pushd "%REPO_ROOT%" >nul

if not exist "%TOOLS_DIR%\compile_all_apps.cmd" (
  echo *** ERROR: tools\compile_all_apps.cmd not found ***
  echo *** ERROR: tools\compile_all_apps.cmd not found *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo === Ensuring build dependencies ===
echo === Ensuring build dependencies === >> "%LOG_FILE%"

set "PY_CMD="
set "REQ_FILE="
if not exist "%TOOLS_DIR%\select_build_env.ps1" (
  echo *** ERROR: tools\select_build_env.ps1 not found ***
  echo *** ERROR: tools\select_build_env.ps1 not found *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

set "ENV_FILE=%TEMP%\tpn_build_env_%RANDOM%.txt"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%\select_build_env.ps1" -RepoRoot "%REPO_ROOT%" > "%ENV_FILE%"
if errorlevel 1 (
  echo *** ERROR: select_build_env.ps1 failed ***
  echo *** ERROR: select_build_env.ps1 failed *** >> "%LOG_FILE%"
  del "%ENV_FILE%" >nul 2>&1
  popd >nul
  exit /b 1
)

for /f "usebackq tokens=1* delims==" %%K in ("%ENV_FILE%") do (
  if /I "%%K"=="PY" set "PY_CMD=%%L"
  if /I "%%K"=="REQ" set "REQ_FILE=%%L"
)
del "%ENV_FILE%" >nul 2>&1

if not defined PY_CMD set "PY_CMD=python"
if not defined REQ_FILE (
  echo *** ERROR: matching requirements_py*.txt not found ***
  echo *** ERROR: matching requirements_py*.txt not found *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo Build Python: %PY_CMD%
echo Build Python: %PY_CMD% >> "%LOG_FILE%"
echo Build requirements: %REQ_FILE%
echo Build requirements: %REQ_FILE% >> "%LOG_FILE%"

"%PY_CMD%" -m pip install -r "%REQ_FILE%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
  echo *** pip install failed ***
  echo *** pip install failed *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Compiling apps ===
echo === Compiling apps === >> "%LOG_FILE%"

call "%TOOLS_DIR%\compile_all_apps.cmd" %* >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
  echo *** BUILD FAILED ***
  echo *** BUILD FAILED *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

popd >nul

echo.
echo === RELEASE BUILD DONE ===
echo Log written to:
echo   %LOG_FILE%
echo.
echo Next:
echo   1) Run: dist\*.exe --version
echo   2) Commit + tag
echo   3) Upload dist\ EXEs to the release page
exit /b 0
