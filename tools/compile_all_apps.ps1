<# 
compile_all_apps.ps1

Compiles every Python entrypoint in ..\scripts into one-file EXEs in ..\dist
using PyInstaller, with per-app work/spec dirs under ..\build.

Entrypoints are:
  - .py files directly under ..\scripts
  - folders under ..\scripts containing <foldername>.py

Per-tool metadata:
  - requirements.txt (installed before building that tool)
  - python-version.txt (uses "py -<version>" for that tool)

Build environment:
  - Uses .venv_py<major>.<minor> if present, otherwise .venv (shared build env)
  - Falls back to a per-tool venv if requirements conflict or Python differs
  - Per-version build requirements: requirements_py<major>.<minor>.txt

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

function Read-OptionalText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $v = (Get-Content -LiteralPath $Path -Raw).Trim()
  if (-not $v) { return $null }
  return $v
}

function Normalize-PySpec([string]$Spec) {
  if (-not $Spec) { return $null }
  $s = $Spec.Trim()
  if (-not $s) { return $null }
  $s = $s.Split("+")[0].Split("-")[0]
  $parts = $s.Split(".")
  if ($parts.Length -ge 2) { return "$($parts[0]).$($parts[1])" }
  if ($parts.Length -eq 1) { return $parts[0] }
  return $s
}

function Parse-VenvSpecFromName([string]$Name) {
  if (-not $Name) { return $null }
  if ($Name -match "^\.venv_py(\d+)\.(\d+)$") { return "$($Matches[1]).$($Matches[2])" }
  if ($Name -match "^\.venv_py(\d+)$") { return $Matches[1] }
  return $null
}

function Get-RootRequirementsPath([string]$RepoRoot, [string]$PySpecNorm, [string]$DefaultSpec) {
  $ver = if ($PySpecNorm) { $PySpecNorm } else { $DefaultSpec }
  $verFile = Join-Path $RepoRoot ("requirements_py" + $ver + ".txt")

  if (Test-Path -LiteralPath $verFile) { return $verFile }

  throw "requirements file not found for Python $ver. Expected: $verFile"
}

function Get-RequirementName([string]$Line) {
  if (-not $Line) { return $null }
  $t = $Line.Trim()
  if (-not $t) { return $null }
  if ($t.StartsWith("#")) { return $null }
  if ($t.StartsWith("-")) { return $null }
  if ($t.Contains("://")) { return $null }
  $namePart = ($t -split "[<>=!~]")[0]
  if (-not $namePart) { return $null }
  $name = $namePart.Split("[")[0].Trim()
  if (-not $name) { return $null }
  return $name.ToLower()
}

function Read-RequirementNames([string]$Path) {
  $names = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $names }
  $lines = Get-Content -LiteralPath $Path
  foreach ($line in $lines) {
    $name = Get-RequirementName $line
    if ($name) { $names[$name] = $true }
  }
  return $names
}

function Get-PythonMajorMinor([string[]]$PyCmd) {
  $v = & $PyCmd "-c" "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Failed to query Python version for: $($PyCmd -join ' ')" }
  return $v.Trim()
}

function Get-SafeName([string]$Name) {
  return ($Name -replace "[^A-Za-z0-9._-]", "_")
}

function Ensure-ToolVenv([string]$VenvDir, [string[]]$CreateCmd, [switch]$DryRun) {
  if (-not (Test-Path -LiteralPath $VenvDir)) {
    Write-Host "Creating tool venv: $VenvDir"
    if (-not $DryRun) {
      & $CreateCmd "-m" "venv" $VenvDir
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to create venv at: $VenvDir"
      }
    }
  }

  $py = Join-Path $VenvDir "Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $py) -and -not $DryRun) {
    throw "Tool venv missing python.exe: $py"
  }
  return $py
}

function Install-Requirements([string[]]$PyCmd, [string]$ReqPath, [string]$Label, [switch]$DryRun) {
  Write-Host "Installing ${Label}: $ReqPath"
  if (-not $DryRun) {
    & $PyCmd "-m" "pip" "install" "-r" $ReqPath
    if ($LASTEXITCODE -ne 0) {
      return $false
    }
  }
  return $true
}

function Format-PyCmd([string[]]$PyCmd) {
  return ($PyCmd -join " ")
}

function Ensure-PyInstaller([string[]]$PyCmd, [string]$RootReqPath, [switch]$DryRun) {
  if ($DryRun) { return }
  $null = & $PyCmd "-c" "import PyInstaller, sys; print(PyInstaller.__version__)" 2>$null
  if ($LASTEXITCODE -ne 0) {
    $cmdText = Format-PyCmd $PyCmd
    throw "PyInstaller is not installed for: $cmdText. Run: $cmdText -m pip install -r $RootReqPath"
  }
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

function New-ToolVersionModule([string]$Path, [string]$ToolVersion, [string]$BundleVersion) {
  $content = @"
TOOL_VERSION = "$ToolVersion"
BUNDLE_VERSION = "$BundleVersion"
"@
  Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

$repoRoot = Normalize-FullPath (Join-Path $PSScriptRoot "..")

if (-not $AppsDir) { $AppsDir = Join-Path $repoRoot "scripts" }
if (-not $DistDir) { $DistDir = Join-Path $repoRoot "dist" }
if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot "build" }

$AppsDir  = Normalize-FullPath $AppsDir
$DistDir  = Normalize-FullPath $DistDir
$BuildDir = Normalize-FullPath $BuildDir

$hasPython = Get-Command "python" -ErrorAction SilentlyContinue
$hasPy = Get-Command "py" -ErrorAction SilentlyContinue
if (-not $hasPython -and -not $hasPy) {
  throw "Required command not found on PATH: python or py"
}

$defaultPyCmd = @()
$defaultPyDisplay = ""
$defaultPySpec = $null

$venvPyChoice = $null
$venvPyDirs = Get-ChildItem -LiteralPath $repoRoot -Directory -Filter ".venv_py*" -ErrorAction SilentlyContinue
if ($venvPyDirs) {
  $candidates = @()
  foreach ($d in $venvPyDirs) {
    $spec = Parse-VenvSpecFromName $d.Name
    if ($spec) {
      $verObj = [Version]::new($spec + ".0")
      $candidates += [PSCustomObject]@{ Dir = $d.FullName; Name = $d.Name; Spec = $spec; Ver = $verObj }
    }
  }
  if ($candidates.Count -gt 0) {
    $venvPyChoice = $candidates | Sort-Object Ver -Descending | Select-Object -First 1
  } else {
    $venvPyChoice = [PSCustomObject]@{ Dir = $venvPyDirs[0].FullName; Name = $venvPyDirs[0].Name; Spec = $null }
  }
}

if ($venvPyChoice) {
  $venvPy = Join-Path $venvPyChoice.Dir "Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPy) {
    $defaultPyCmd = @($venvPy)
    $defaultPyDisplay = $venvPyChoice.Name
    $defaultPySpec = if ($venvPyChoice.Spec) { $venvPyChoice.Spec } else { Get-PythonMajorMinor $defaultPyCmd }
  }
}

if (-not $defaultPyCmd -or $defaultPyCmd.Count -eq 0) {
  $venvPy = Join-Path $repoRoot ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPy) {
    $defaultPyCmd = @($venvPy)
    $defaultPyDisplay = ".venv"
  } elseif ($hasPython) {
    $defaultPyCmd = @("python")
    $defaultPyDisplay = "python"
  } else {
    $defaultPyCmd = @("py")
    $defaultPyDisplay = "py"
  }
}

if (-not $defaultPySpec) {
  $defaultPySpec = Get-PythonMajorMinor $defaultPyCmd
}
$rootReqNamesCache = @{}

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

$rootPyFiles = Get-ChildItem -LiteralPath $AppsDir -Filter "*.py" -File | Sort-Object Name
if (-not $IncludeUnderscoreFiles) {
  $rootPyFiles = $rootPyFiles | Where-Object { -not $_.Name.StartsWith("_") }
}
$rootPyFiles = @($rootPyFiles)

$dirPyFiles = @()
$dirs = Get-ChildItem -LiteralPath $AppsDir -Directory | Sort-Object Name
if (-not $IncludeUnderscoreFiles) {
  $dirs = $dirs | Where-Object { -not $_.Name.StartsWith("_") }
}

foreach ($d in $dirs) {
  $entry = Join-Path $d.FullName ($d.Name + ".py")
  if (Test-Path -LiteralPath $entry) {
    $dirPyFiles += Get-Item -LiteralPath $entry
  }
}

$pyFiles = @($rootPyFiles) + @($dirPyFiles)

if (-not $pyFiles -or $pyFiles.Count -eq 0) {
  throw "No .py entrypoints found in: $AppsDir"
}

$nameMap = @{}
foreach ($f in $pyFiles) {
  $appName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  if ($nameMap.ContainsKey($appName)) {
    throw "Duplicate app name '$appName' from: $($nameMap[$appName]) and $($f.FullName)"
  }
  $nameMap[$appName] = $f.FullName
}

Write-Host ""
Write-Host "Repo root: $repoRoot"
Write-Host "Scripts:   $AppsDir"
Write-Host "Dist:      $DistDir"
Write-Host "Build:     $BuildDir"
Write-Host "Version:   $bundleVersion"
Write-Host "Python:    $defaultPyDisplay ($defaultPySpec)"
Write-Host ""
Write-Host "Compiling $($pyFiles.Count) app(s)..."
Write-Host ""

$pyInstallerOk = @{}
$installedReqs = @{}
$appsDirNorm = Normalize-FullPath $AppsDir

foreach ($f in $pyFiles) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $entryDir = Split-Path -Parent $f.FullName
  $entryDirNorm = Normalize-FullPath $entryDir

  $reqPath = $null
  $pyVerPath = $null
  $toolVerPath = $null

  if ($entryDirNorm.Equals($appsDirNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $altDir = Join-Path $AppsDir $name
    $altReq = Join-Path $altDir "requirements.txt"
    $altPy = Join-Path $altDir "python-version.txt"
    $altVer = Join-Path $altDir "VERSION"
    $rootReq = Join-Path $AppsDir ($name + ".requirements.txt")
    $rootPy = Join-Path $AppsDir ($name + ".python-version.txt")
    $rootVer = Join-Path $AppsDir ($name + ".VERSION")

    if (Test-Path -LiteralPath $altReq) { $reqPath = $altReq }
    elseif (Test-Path -LiteralPath $rootReq) { $reqPath = $rootReq }

    if (Test-Path -LiteralPath $altPy) { $pyVerPath = $altPy }
    elseif (Test-Path -LiteralPath $rootPy) { $pyVerPath = $rootPy }

    if (Test-Path -LiteralPath $altVer) { $toolVerPath = $altVer }
    elseif (Test-Path -LiteralPath $rootVer) { $toolVerPath = $rootVer }
  } else {
    $dirReq = Join-Path $entryDir "requirements.txt"
    $dirPy = Join-Path $entryDir "python-version.txt"
    $dirVer = Join-Path $entryDir "VERSION"
    if (Test-Path -LiteralPath $dirReq) { $reqPath = $dirReq }
    if (Test-Path -LiteralPath $dirPy) { $pyVerPath = $dirPy }
    if (Test-Path -LiteralPath $dirVer) { $toolVerPath = $dirVer }
  }

  $pySpec = $null
  if ($pyVerPath) { $pySpec = Read-OptionalText $pyVerPath }
  $pyCmd = $defaultPyCmd
  $toolVenvDir = $null
  $createCmdForVenv = $defaultPyCmd
  $usingSharedEnv = $true
  $usingDefaultEnv = $true

  $pySpecNorm = Normalize-PySpec $pySpec

  if ($pySpec) {
    if (-not $hasPy) {
      throw "python-version.txt requires the 'py' launcher (missing). Tool: $name"
    }
    $createCmdForVenv = @("py", "-$pySpec")
    if ($pySpecNorm -and ($pySpecNorm -ne $defaultPySpec)) {
      $usingDefaultEnv = $false
      $specTag = Get-SafeName $pySpecNorm
      $toolVenvDir = Join-Path $BuildDir ("venv\py-" + $specTag)
      $pyCmd = @(Ensure-ToolVenv -VenvDir $toolVenvDir -CreateCmd $createCmdForVenv -DryRun:$DryRun)
    }
  }

  $pyKey = Format-PyCmd $pyCmd
  $rootReqPath = Get-RootRequirementsPath -RepoRoot $repoRoot -PySpecNorm $pySpecNorm -DefaultSpec $defaultPySpec
  if (-not $rootReqNamesCache.ContainsKey($rootReqPath)) {
    $rootReqNamesCache[$rootReqPath] = Read-RequirementNames $rootReqPath
  }
  $rootReqNames = $rootReqNamesCache[$rootReqPath]

  $workPath = Join-Path $BuildDir $name
  $specPath = Join-Path $workPath "spec"
  Ensure-Dir $workPath
  Ensure-Dir $specPath

  $verFile = Join-Path $workPath ($name + ".version")
  New-VersionFile -Path $verFile -AppName $name -BundleVersion $bundleVersion

  $toolVersion = $null
  if ($toolVerPath) { $toolVersion = Read-OptionalText $toolVerPath }
  if (-not $toolVersion) { $toolVersion = $bundleVersion }
  $toolVersionModule = Join-Path $workPath "tool_version.py"
  New-ToolVersionModule -Path $toolVersionModule -ToolVersion $toolVersion -BundleVersion $bundleVersion

  if (-not $usingDefaultEnv) {
    $rootKey = $pyKey + "`n" + $rootReqPath
    if (-not $installedReqs.ContainsKey($rootKey)) {
      $ok = Install-Requirements -PyCmd $pyCmd -ReqPath $rootReqPath -Label "build requirements" -DryRun:$DryRun
      if (-not $ok) {
        throw "pip install failed for build requirements (exit $LASTEXITCODE)"
      }
      $installedReqs[$rootKey] = $true
    }
  }

  if (-not $pyInstallerOk.ContainsKey($pyKey)) {
    Ensure-PyInstaller -PyCmd $pyCmd -RootReqPath $rootReqPath -DryRun:$DryRun
    $pyInstallerOk[$pyKey] = $true
  }

  if ($reqPath) {
    if ($usingSharedEnv) {
      $toolReqNames = Read-RequirementNames $reqPath
      $missing = @()
      foreach ($n in $toolReqNames.Keys) {
        if (-not $rootReqNames.ContainsKey($n)) { $missing += $n }
      }
      if ($missing.Count -gt 0) {
        $list = $missing -join ", "
        throw "Tool $name uses shared env but requirements are not in ${rootReqPath}: $list"
      }
    }

    $reqKey = $pyKey + "`n" + $reqPath
    if (-not $installedReqs.ContainsKey($reqKey)) {
      $ok = Install-Requirements -PyCmd $pyCmd -ReqPath $reqPath -Label "requirements for ${name}" -DryRun:$DryRun
      if (-not $ok) {
        Write-Host "Shared env install failed; using tool venv for $name"
        $usingSharedEnv = $false
        $usingDefaultEnv = $false
        $isoTag = if ($pySpecNorm) { $pySpecNorm } else { $defaultPySpec }
        $toolVenvDir = Join-Path $BuildDir ("venv\isolated\" + (Get-SafeName $name) + "-" + (Get-SafeName $isoTag))
        $pyCmd = @(Ensure-ToolVenv -VenvDir $toolVenvDir -CreateCmd $createCmdForVenv -DryRun:$DryRun)
        $pyKey = Format-PyCmd $pyCmd

        $rootReqPath = Get-RootRequirementsPath -RepoRoot $repoRoot -PySpecNorm $isoTag -DefaultSpec $defaultPySpec
        if (-not $rootReqNamesCache.ContainsKey($rootReqPath)) {
          $rootReqNamesCache[$rootReqPath] = Read-RequirementNames $rootReqPath
        }
        $rootReqNames = $rootReqNamesCache[$rootReqPath]

        $rootKey = $pyKey + "`n" + $rootReqPath
        if (-not $installedReqs.ContainsKey($rootKey)) {
          $okRoot = Install-Requirements -PyCmd $pyCmd -ReqPath $rootReqPath -Label "build requirements" -DryRun:$DryRun
          if (-not $okRoot) {
            throw "pip install failed for build requirements (exit $LASTEXITCODE)"
          }
          $installedReqs[$rootKey] = $true
        }

        if (-not $pyInstallerOk.ContainsKey($pyKey)) {
          Ensure-PyInstaller -PyCmd $pyCmd -RootReqPath $rootReqPath -DryRun:$DryRun
          $pyInstallerOk[$pyKey] = $true
        }

        $reqKey = $pyKey + "`n" + $reqPath
        if (-not $installedReqs.ContainsKey($reqKey)) {
          $okRetry = Install-Requirements -PyCmd $pyCmd -ReqPath $reqPath -Label "requirements for ${name}" -DryRun:$DryRun
          if (-not $okRetry) {
            throw "pip install failed for $name (exit $LASTEXITCODE)"
          }
          $installedReqs[$reqKey] = $true
        }
      } else {
        $installedReqs[$reqKey] = $true
      }
    }
  }

  $args = @(
    "-m","PyInstaller",
    "--noconfirm",
    "--onefile",
    "--name",$name,
    "--paths",$workPath,
    "--distpath",$DistDir,
    "--workpath",$workPath,
    "--specpath",$specPath,
    "--clean",
    "--version-file",$verFile,
    $f.FullName
  )

  Write-Host "==> $name"
  Write-Host ((Format-PyCmd $pyCmd) + " " + ($args -join " "))
  Write-Host ""

  if (-not $DryRun) {
    & $pyCmd @args
    if ($LASTEXITCODE -ne 0) {
      throw "PyInstaller failed for $name (exit $LASTEXITCODE)"
    }
  }
}

Write-Host ""
Write-Host "Done."
Write-Host "EXEs in: $DistDir"
