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

$py = $null
$spec = $null
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
