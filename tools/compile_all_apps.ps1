<# 
compile_all_apps.ps1

Compiles every Python entrypoint in ..\scripts into one-file EXEs in ..\dist
using PyInstaller, with per-app work/spec dirs under ..\build.

Run from repo root:
  tools\compile_all_apps.cmd

Or directly:
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\compile_all_apps.ps1

#>

[CmdletBinding()]
param(
  [string]$AppsDir = $null,
  [string]$DistDir = $null,
  [string]$BuildDir = $null,
  [switch]$Clean,
  [switch]$DryRun,
  [switch]$IncludeUnderscoreFiles
)

$ErrorActionPreference = "Stop"

function Assert-Command([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Required command not found on PATH: $Name" }
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Remove-DirIfExists([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -Recurse -Force -LiteralPath $Path
  }
}

function Normalize-FullPath([string]$Path) {
  return [System.IO.Path]::GetFullPath($Path)
}

$repoRoot = Normalize-FullPath (Join-Path $PSScriptRoot "..")

if (-not $AppsDir) { $AppsDir = Join-Path $repoRoot "scripts" }
if (-not $DistDir) { $DistDir = Join-Path $repoRoot "dist" }
if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot "build" }

$AppsDir  = Normalize-FullPath $AppsDir
$DistDir  = Normalize-FullPath $DistDir
$BuildDir = Normalize-FullPath $BuildDir

Assert-Command "python"

# Make sure PyInstaller is present (use the active interpreter)
$pyiCheck = & python -c "import PyInstaller, sys; print(PyInstaller.__version__)" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "PyInstaller is not installed in this Python environment. Run: pip install -r requirements.txt"
}

if ($Clean) {
  Write-Host "Cleaning build outputs..."
  if (-not $DryRun) {
    Remove-DirIfExists $DistDir
    Remove-DirIfExists $BuildDir
  }
}

Ensure-Dir $DistDir
Ensure-Dir $BuildDir

if (-not (Test-Path -LiteralPath $AppsDir)) {
  throw "AppsDir not found: $AppsDir"
}

$pyFiles = Get-ChildItem -LiteralPath $AppsDir -Filter "*.py" -File | Sort-Object Name

if (-not $IncludeUnderscoreFiles) {
  $pyFiles = $pyFiles | Where-Object { -not $_.Name.StartsWith("_") }
}

if (-not $pyFiles -or $pyFiles.Count -eq 0) {
  throw "No .py entrypoints found in: $AppsDir"
}

Write-Host ""
Write-Host "Repo root: $repoRoot"
Write-Host "Scripts:   $AppsDir"
Write-Host "Dist:      $DistDir"
Write-Host "Build:     $BuildDir"
Write-Host ""
Write-Host "Compiling $($pyFiles.Count) app(s)..."
Write-Host ""

foreach ($f in $pyFiles) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

  $workPath = Join-Path $BuildDir $name
  $specPath = Join-Path $workPath "spec"
  Ensure-Dir $workPath
  Ensure-Dir $specPath

  $args = @(
    "-m","PyInstaller",
    "--noconfirm",
    "--onefile",
    "--name",$name,
    "--distpath",$DistDir,
    "--workpath",$workPath,
    "--specpath",$specPath,
    "--clean",
    $f.FullName
  )

  Write-Host "==> $name"
  Write-Host ("python " + ($args -join " "))
  Write-Host ""

  if (-not $DryRun) {
    & python @args
    if ($LASTEXITCODE -ne 0) {
      throw "PyInstaller failed for $name (exit $LASTEXITCODE)"
    }
  }
}

Write-Host ""
Write-Host "Done."
Write-Host "EXEs in: $DistDir"
