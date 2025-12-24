@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem === Determine invocation directory (where user ran the command) ===
set "RUN_DIR=%CD%"
set "LOG_FILE=%RUN_DIR%\install.log"

rem === Resolve repo root (parent of tools dir) ===
set "TOOLS_DIR=%~dp0"
for %%I in ("%TOOLS_DIR%\..") do set "REPO_ROOT=%%~fI"

echo =============================================== > "%LOG_FILE%"
echo BUILD + INSTALL STARTED >> "%LOG_FILE%"
echo Timestamp: %DATE% %TIME% >> "%LOG_FILE%"
echo Run dir:   %RUN_DIR% >> "%LOG_FILE%"
echo Repo root: %REPO_ROOT% >> "%LOG_FILE%"
echo =============================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

pushd "%REPO_ROOT%" >nul

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
