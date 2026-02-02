<# 
select_build_env.ps1

Outputs:
  PY=<python executable>
  REQ=<requirements file>
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$hasPy = Get-Command "py" -ErrorAction SilentlyContinue
$hasPython = Get-Command "python" -ErrorAction SilentlyContinue

$venvDirs = Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter ".venv_py*" -ErrorAction SilentlyContinue
$choice = $null
if ($venvDirs) {
  $cands = @()
  foreach ($d in $venvDirs) {
    if ($d.Name -match "^\.venv_py(\d+)\.(\d+)$") {
      $spec = "$($Matches[1]).$($Matches[2])"
      $ver = [Version]::new($spec + ".0")
      $cands += [PSCustomObject]@{ Dir = $d.FullName; Spec = $spec; Ver = $ver }
    }
  }
  if ($cands.Count -gt 0) {
    $choice = $cands | Sort-Object Ver -Descending | Select-Object -First 1
  } else {
    $choice = [PSCustomObject]@{ Dir = $venvDirs[0].FullName; Spec = $null }
  }
}

$reqFiles = Get-ChildItem -LiteralPath $RepoRoot -File -Filter "requirements_py*.txt" -ErrorAction SilentlyContinue
$reqSpecs = @()
if ($reqFiles) {
  foreach ($f in $reqFiles) {
    if ($f.Name -match "^requirements_py(\d+)\.(\d+)\.txt$") {
      $spec = "$($Matches[1]).$($Matches[2])"
      $ver = [Version]::new($spec + ".0")
      $reqSpecs += [PSCustomObject]@{ Spec = $spec; Ver = $ver }
    }
  }
}

if (-not $choice -and $hasPy -and $reqSpecs.Count -gt 0) {
  $cands = $reqSpecs | Sort-Object Ver -Descending
  foreach ($c in $cands) {
    $spec = $c.Spec
    $probe = & py "-$spec" -c "import sys; print('{}.{}'.format(sys.version_info[0], sys.version_info[1]))" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $venvDir = Join-Path $RepoRoot (".venv_py" + $spec)
    if (-not (Test-Path -LiteralPath $venvDir)) {
      & py "-$spec" "-m" "venv" $venvDir
      if ($LASTEXITCODE -ne 0) { continue }
    }
    $choice = [PSCustomObject]@{ Dir = $venvDir; Spec = $spec }
    break
  }
}

$py = $null
$spec = $null

if (-not $choice -and $reqSpecs.Count -gt 0) {
  if (-not $hasPy) {
    Write-Host "NOTE: 'py' launcher not found; install it to enable multi-version builds."
  }
  if ($hasPython) {
    $probe = & python -c "import sys; print('{}.{}'.format(sys.version_info[0], sys.version_info[1]))" 2>$null
    if ($LASTEXITCODE -eq 0) {
      $sysSpec = $probe.Trim()
      $match = $reqSpecs | Where-Object { $_.Spec -eq $sysSpec } | Select-Object -First 1
      if ($match) {
        $venvDir = Join-Path $RepoRoot (".venv_py" + $sysSpec)
        if (-not (Test-Path -LiteralPath $venvDir)) {
          & python "-m" "venv" $venvDir
        }
        if (Test-Path -LiteralPath $venvDir) {
          $choice = [PSCustomObject]@{ Dir = $venvDir; Spec = $sysSpec }
        }
      }
    }
  }
}

if ($choice) {
  $py = Join-Path $choice.Dir "Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $py)) { $py = $null }
  $spec = $choice.Spec
}

if (-not $py) {
  $fallback = Join-Path $RepoRoot ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $fallback) { $py = $fallback }
}

if (-not $py) { $py = "python" }

if (-not $spec) {
  $spec = & $py -c "import sys; print('{}.{}'.format(sys.version_info[0], sys.version_info[1]))" 2>$null
  if ($LASTEXITCODE -ne 0) { $spec = $null }
  if ($spec) { $spec = $spec.Trim() }
}

$req = $null
if ($spec) {
  $req = Join-Path $RepoRoot ("requirements_py" + $spec + ".txt")
  if (-not (Test-Path -LiteralPath $req)) { $req = $null }
}

Write-Output ("PY=" + $py)
Write-Output ("REQ=" + $req)
