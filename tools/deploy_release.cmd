@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem deploy_release.cmd
rem - Builds, generates checksums, and prepares git commit/tag
rem - Optional: create GitHub release if gh is installed and authenticated

set "RUN_DIR=%CD%"
set "LOG_FILE=%RUN_DIR%\deploy_release.log"

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..") do set "REPO_ROOT=%%~fI"
set "TOOLS_DIR=%REPO_ROOT%\tools"
set "DIST_DIR=%REPO_ROOT%\dist"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell not found at: %PS%
  exit /b 1
)

set "AUTO_YES=0"
set "AUTO_ALL=0"
set "SKIP_COMMIT=0"
set "SKIP_PUSH=0"
set "SKIP_GH=0"
set "FORCE_COMMIT=0"
set "FORCE_PUSH=0"
set "FORCE_GH=0"
set "RELEASE_VERSION="

:parse_args
if "%~1"=="" goto args_done
set "ARG=%~1"
if /I "%ARG%"=="/?" goto usage
if /I "%ARG%"=="/help" goto usage
if /I "%ARG%"=="/y" set "AUTO_YES=1"
if /I "%ARG%"=="/yes" set "AUTO_YES=1"
if /I "%ARG%"=="/auto" set "AUTO_ALL=1"
if /I "%ARG%"=="/no-commit" set "SKIP_COMMIT=1"
if /I "%ARG%"=="/no-push" set "SKIP_PUSH=1"
if /I "%ARG%"=="/no-gh" set "SKIP_GH=1"
if /I "%ARG%"=="/commit" set "FORCE_COMMIT=1"
if /I "%ARG%"=="/push" set "FORCE_PUSH=1"
if /I "%ARG%"=="/gh" set "FORCE_GH=1"
if /I "%ARG:~0,9%"=="/version=" set "RELEASE_VERSION=%ARG:~9%"
if /I "%ARG%"=="/version" (
  shift
  set "RELEASE_VERSION=%~1"
)
shift
goto parse_args

:args_done
if "%AUTO_ALL%"=="1" (
  set "AUTO_YES=1"
  set "FORCE_COMMIT=1"
  set "FORCE_PUSH=1"
  set "FORCE_GH=1"
)

goto after_usage

:usage
echo.
echo deploy_release.cmd options:
echo   /y or /yes          Auto-accept prompts (no push/gh unless specified)
echo   /auto              Auto-accept all prompts and run commit, push, gh
echo   /version X.Y.Z     Set release version (also accepts /version=X.Y.Z)
echo   /no-commit         Skip commit and tag
echo   /commit            Force commit and tag
echo   /no-push           Skip push
echo   /push              Force push
echo   /no-gh             Skip gh release
echo   /gh                Force gh release
echo.
exit /b 0

:after_usage

echo =============================================== > "%LOG_FILE%"
echo DEPLOY RELEASE STARTED >> "%LOG_FILE%"
echo Timestamp: %DATE% %TIME% >> "%LOG_FILE%"
echo Run dir:   %RUN_DIR% >> "%LOG_FILE%"
echo Repo root: %REPO_ROOT% >> "%LOG_FILE%"
echo Tools dir: %TOOLS_DIR% >> "%LOG_FILE%"
echo =============================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

pushd "%REPO_ROOT%" >nul

if not exist "%TOOLS_DIR%\make_release.cmd" (
  echo *** ERROR: tools\make_release.cmd not found ***
  echo *** ERROR: tools\make_release.cmd not found *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo === Checking git status ===
echo === Checking git status === >> "%LOG_FILE%"
git status --short >> "%LOG_FILE%" 2>&1
git status --short

for /f "usebackq delims=" %%V in ("%REPO_ROOT%\VERSION") do set "CURRENT_VERSION=%%V"
if /I "%CURRENT_VERSION%"=="ECHO is off." set "CURRENT_VERSION="
if /I "%CURRENT_VERSION%"=="ECHO is on." set "CURRENT_VERSION="
if not defined CURRENT_VERSION set "CURRENT_VERSION=0.0.0"

echo Current bundle VERSION: %CURRENT_VERSION%
echo Current bundle VERSION: %CURRENT_VERSION% >> "%LOG_FILE%"

if not defined RELEASE_VERSION set "RELEASE_VERSION=%CURRENT_VERSION%"
if "%AUTO_YES%"=="1" (
  echo Release version: %RELEASE_VERSION%
) else (
  call set /p "RELEASE_VERSION=Release version [%%RELEASE_VERSION%%]: "
)
if "%RELEASE_VERSION%"=="" set "RELEASE_VERSION=%CURRENT_VERSION%"

echo Using release version: %RELEASE_VERSION%
echo Using release version: %RELEASE_VERSION% >> "%LOG_FILE%"

> "%REPO_ROOT%\VERSION" (echo(%RELEASE_VERSION%)

if "%AUTO_YES%"=="1" (
  set "CONTINUE=y"
) else (
  set "CONTINUE="
  set /p "CONTINUE=Continue with build ^(y/N^)? "
)
if /I not "%CONTINUE%"=="y" (
  echo Aborted.
  popd >nul
  exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Build ===
echo === Build === >> "%LOG_FILE%"
call "%TOOLS_DIR%\make_release.cmd" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
  echo *** BUILD FAILED ***
  echo *** BUILD FAILED *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

if not exist "%DIST_DIR%" (
  echo *** ERROR: dist directory not found: %DIST_DIR% ***
  echo *** ERROR: dist directory not found: %DIST_DIR% *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Smoke test ===
echo === Smoke test === >> "%LOG_FILE%"
set "FOUND_EXE=0"
set "SMOKE_OK=1"
for %%F in ("%DIST_DIR%\*.exe") do (
  set "FOUND_EXE=1"
  echo Running: %%~nxF --version
  echo Running: %%~nxF --version >> "%LOG_FILE%"
  "%%~fF" --version
  "%%~fF" --version >> "%LOG_FILE%" 2>&1
  if errorlevel 1 set "SMOKE_OK=0"
)
if "%FOUND_EXE%"=="0" (
  echo *** ERROR: no EXEs found in dist ***
  echo *** ERROR: no EXEs found in dist *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)
if "%SMOKE_OK%"=="0" (
  echo *** ERROR: one or more EXEs failed --version ***
  echo *** ERROR: one or more EXEs failed --version *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo. >> "%LOG_FILE%"
echo === Checksums ===
echo === Checksums === >> "%LOG_FILE%"
if not exist "%TOOLS_DIR%\write_checksums.ps1" (
  echo *** ERROR: tools\write_checksums.ps1 not found ***
  echo *** ERROR: tools\write_checksums.ps1 not found *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%\write_checksums.ps1" -DistDir "%DIST_DIR%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
  echo *** CHECKSUMS FAILED ***
  echo *** CHECKSUMS FAILED *** >> "%LOG_FILE%"
  popd >nul
  exit /b 1
)

echo Checksums written to: %DIST_DIR%\checksums.sha256

set "VERSION="
for /f "usebackq delims=" %%V in ("%REPO_ROOT%\VERSION") do set "VERSION=%%V"
if not defined VERSION set "VERSION=0.0.0"
set "TAG=v%VERSION%"

echo.
echo === Git commit and tag ===
echo Proposed tag: %TAG%
set "COMMITMSG=Release %TAG%"
if "%AUTO_YES%"=="1" (
  echo Commit message: %COMMITMSG%
) else (
  set /p COMMITMSG=Commit message [%COMMITMSG%]: 
)
if "%COMMITMSG%"=="" set "COMMITMSG=Release %TAG%"

if "%SKIP_COMMIT%"=="1" (
  echo Skipping commit and tag.
  popd >nul
  exit /b 0
)

if "%FORCE_COMMIT%"=="1" (
  set "DO_COMMIT=y"
  echo Create commit and tag: yes
  goto do_commit
)
if "%AUTO_YES%"=="1" (
  set "DO_COMMIT=y"
  echo Create commit and tag: yes
  goto do_commit
)

set "DO_COMMIT="
set /p "DO_COMMIT=Create commit and tag ^(y/N^)? "
if /I not "%DO_COMMIT%"=="y" (
  echo Skipping commit and tag.
  popd >nul
  exit /b 0
)

:do_commit

git add -A
git commit -m "%COMMITMSG%"
if errorlevel 1 (
  echo *** COMMIT FAILED ***
  popd >nul
  exit /b 1
)

git tag "%TAG%"
if errorlevel 1 (
  echo *** TAG FAILED ***
  popd >nul
  exit /b 1
)

if "%SKIP_PUSH%"=="1" (
  goto after_push
)
if "%FORCE_PUSH%"=="1" (
  git push origin HEAD --tags
  goto after_push
)
if "%AUTO_YES%"=="1" (
  goto after_push
)
set "DO_PUSH="
set /p "DO_PUSH=Push commit and tags ^(y/N^)? "
if /I "%DO_PUSH%"=="y" (
  git push origin HEAD --tags
)

:after_push
if "%SKIP_GH%"=="1" (
  goto after_gh
)
if "%FORCE_GH%"=="1" (
  goto do_gh
)
if "%AUTO_YES%"=="1" (
  goto after_gh
)
set "DO_GH="
set /p "DO_GH=Create GitHub release via gh ^(y/N^)? "
if /I "%DO_GH%"=="y" (
  goto do_gh
)
goto after_gh

:do_gh
where gh >nul 2>&1
if errorlevel 1 (
  echo gh not found on PATH. Skipping.
) else (
  gh release create "%TAG%" "%DIST_DIR%\*.exe" "%DIST_DIR%\checksums.sha256" ^
    -F "%REPO_ROOT%\RELEASE_NOTES.md" --title "%TAG%"
)

:after_gh

popd >nul
echo.
echo === DEPLOY RELEASE DONE ===
echo Log written to:
echo   %LOG_FILE%
exit /b 0
