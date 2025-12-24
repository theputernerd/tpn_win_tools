<# 
compile_all_apps.ps1

Compiles every Python entrypoint in ..\scripts into one-file EXEs in ..\dist
using PyInstaller, with per-app work/spec dirs under ..\build.

Also embeds the bundle version from ..\VERSION into each EXE (Windows file properties).

Run from repo root:
  tools\compile_all_apps.cmd
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

function Read-BundleVersion([string]$RepoRoot) {
  $vPath = Join-Path $RepoRoot "VERSION"
  if (-not (Test-Path -LiteralPath $vPath)) { return "0.0.0" }
  $v = (Get-Content -LiteralPath $vPath -Raw).Trim()
  if (-not $v) { return "0.0.0" }
  return $v
}

function Parse-SemVerToWin([string]$SemVer) {
  # Accept: X.Y.Z or X.Y.Z-suffix or X.Y.Z+meta; map to X.Y.Z.0
  $main = $SemVer.Split("+")[0].Split("-")[0]
  $parts = $main.Split(".")
  $maj = 0; $min = 0; $pat = 0
  if ($parts.Length -ge 1) { [int]::TryParse($parts[0], [ref]$maj) | Out-Null }
  if ($parts.Length -ge 2) { [int]::TryParse($parts[1], [ref]$min) | Out-Null }
  if ($parts.Length -ge 3) { [int]::TryParse($parts[2], [ref]$pat) | Out-Null }
  return @($maj, $min, $pat, 0)
}

function New-VersionFile([string]$Path, [string]$AppName, [string]$BundleVersion) {
  $win = Parse-SemVerToWin $BundleVersion
  $fv = "$($win[0]).$($win[1]).$($win[2]).$($win[3])"

  $content = @"
# UTF-8
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=($($win[0]), $($win[1]), $($win[2]), $($win[3])),
    prodvers=($($win[0]), $($win[1]), $($win[2]), $($win[3])),
    mask=0x3f,
    flags=0x0,
    OS=0x4,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo(
      [
        StringTable(
          '040904B0',
          [
            StringStruct('CompanyName', 'tpn'),
            StringStruct('FileDescription', '$AppName'),
            StringStruct('FileVersion', '$fv'),
            StringStruct('InternalName', '$AppName'),
            StringStruct('OriginalFilename', '$AppName.exe'),
            StringStruct('ProductName', 'tpn_win_tools'),
            StringStruct('ProductVersion', '$fv'),
            StringStruct('Comments', 'Bundle version $BundleVersion')
          ]
        )
      ]
    ),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"@

  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$repoRoot = Normalize-FullPath (Join-Path $PSScriptRoot "..")

if (-not $AppsDir) { $AppsDir = Join-Path $repoRoot "scripts" }
if (-not $DistDir) { $DistDir = Join-Path $repoRoot "dist" }
if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot "build" }

$AppsDir  = Normalize-FullPath $AppsDir
$DistDir  = Normalize-FullPath $DistDir
$BuildDir = Normalize-FullPath $BuildDir

Assert-Command "python"

$pyiCheck = & python -c "import PyInstaller, sys; print(PyInstaller.__version__)" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "PyInstaller is not installed in this Python environment. Run: pip install -r requirements.txt"
}

$bundleVersion = Read-BundleVersion $repoRoot

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
Write-Host "Version:   $bundleVersion"
Write-Host ""
Write-Host "Compiling $($pyFiles.Count) app(s)..."
Write-Host ""

foreach ($f in $pyFiles) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

  $workPath = Join-Path $BuildDir $name
  $specPath = Join-Path $workPath "spec"
  Ensure-Dir $workPath
  Ensure-Dir $specPath

  $verFile = Join-Path $workPath ($name + ".version")
  New-VersionFile -Path $verFile -AppName $name -BundleVersion $bundleVersion

  $args = @(
    "-m","PyInstaller",
    "--noconfirm",
    "--onefile",
    "--name",$name,
    "--distpath",$DistDir,
    "--workpath",$workPath,
    "--specpath",$specPath,
    "--clean",
    "--version-file",$verFile,
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
