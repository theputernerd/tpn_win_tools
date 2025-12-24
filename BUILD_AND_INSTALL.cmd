@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem BUILD_AND_INSTALL.cmd (repo root)
rem - Runs correctly from repo root location (this file)
rem - Writes install.log in the directory you run it from

rem Directory the user ran the command from (log lives here)
set "RUN_DIR=%CD%"
set "LOG_FILE=%RUN_DIR%\install.log"

rem Repo root = directory containing this script
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "REPO_ROOT=%%~fI"

rem Tools directory under repo root
set "TOOLS_DIR=%REPO_ROOT%\tools"

echo =============================================== > "%LOG_FILE%"
echo BUILD + INSTALL STARTED >> "%LOG_FILE%"
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

if not exist "%TOOLS_DIR%\install_TPM_apps.cmd" (
    echo *** ERROR: tools\install_TPM_apps.cmd not found ***
    echo *** ERROR: tools\install_TPM_apps.cmd not found *** >> "%LOG_FILE%"
    popd >nul
    exit /b 1
)

echo === Ensuring build dependencies ===
echo === Ensuring build dependencies === >> "%LOG_FILE%"

python -m pip install -r "%REPO_ROOT%\requirements.txt" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo *** pip install failed ***
    echo *** pip install failed *** >> "%LOG_FILE%"
    popd >nul
    exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Compiling apps ===
echo === Compiling apps === >> "%LOG_FILE%"

call "%TOOLS_DIR%\compile_all_apps.cmd" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo *** BUILD FAILED ***
    echo *** BUILD FAILED *** >> "%LOG_FILE%"
    popd >nul
    exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Installing apps ===
echo === Installing apps === >> "%LOG_FILE%"

call "%TOOLS_DIR%\install_TPM_apps.cmd" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo *** INSTALL FAILED ***
    echo *** INSTALL FAILED *** >> "%LOG_FILE%"
    popd >nul
    exit /b 1
)

popd >nul

echo. >> "%LOG_FILE%"
echo =============================================== >> "%LOG_FILE%"
echo BUILD + INSTALL COMPLETED >> "%LOG_FILE%"
echo Timestamp: %DATE% %TIME% >> "%LOG_FILE%"
echo =============================================== >> "%LOG_FILE%"

echo.
echo === BUILD + INSTALL DONE ===
echo Log written to:
echo   %LOG_FILE%
exit /b 0
