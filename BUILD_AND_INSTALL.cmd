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

set "PY_CMD="
set "REQ_FILE="
for /f "usebackq delims=" %%A in (`"%PS%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root='%REPO_ROOT%'; ^
   $venvDirs=Get-ChildItem -LiteralPath $root -Directory -Filter '.venv_py*' -ErrorAction SilentlyContinue; ^
   $choice=$null; ^
   if ($venvDirs) { ^
     $cands=foreach ($d in $venvDirs) { ^
       if ($d.Name -match '^\.venv_py(\d+)\.(\d+)$') { ^
         [pscustomobject]@{Dir=$d.FullName; Spec=\"$($Matches[1]).$($Matches[2])\"; Ver=[Version]\"$($Matches[1]).$($Matches[2])\"} ^
       } ^
     }; ^
     if ($cands) { $choice=$cands | Sort-Object Ver -Descending | Select-Object -First 1 } ^
     else { $choice=[pscustomobject]@{Dir=$venvDirs[0].FullName; Spec=$null} } ^
   }; ^
   $py=$null; $spec=$null; ^
   if ($choice) { ^
     $py=Join-Path $choice.Dir 'Scripts\python.exe'; ^
     if (-not (Test-Path -LiteralPath $py)) { $py=$null }; ^
     $spec=$choice.Spec; ^
   }; ^
   if (-not $py) { ^
     $py=Join-Path $root '.venv\Scripts\python.exe'; ^
     if (-not (Test-Path -LiteralPath $py)) { $py='python' }; ^
   }; ^
   if (-not $spec) { ^
     $spec=& $py -c \"import sys; print('{}.{}'.format(sys.version_info[0], sys.version_info[1]))\" 2>$null; ^
     if ($LASTEXITCODE -ne 0) { $spec=$null }; ^
   }; ^
   $req=$null; ^
   if ($spec) { $req=Join-Path $root ('requirements_py' + $spec + '.txt') }; ^
   if (-not $req -or -not (Test-Path -LiteralPath $req)) { $req=Join-Path $root 'requirements.txt' }; ^
   Write-Output ('PY=' + $py); ^
   Write-Output ('REQ=' + $req)"`) do (
    for /f "tokens=1,2 delims==" %%K in ("%%A") do (
        if /I "%%K"=="PY" set "PY_CMD=%%L"
        if /I "%%K"=="REQ" set "REQ_FILE=%%L"
    )
)

if not defined PY_CMD set "PY_CMD=python"
if not defined REQ_FILE set "REQ_FILE=%REPO_ROOT%\requirements.txt"

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
