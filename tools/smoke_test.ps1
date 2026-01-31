<# 
smoke_test.ps1

Runs each dist EXE with --version.
#>

[CmdletBinding()]
param(
  [string]$DistDir = $null
)

$ErrorActionPreference = "Stop"

if (-not $DistDir) {
  $DistDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\dist")).Path
}
if (-not (Test-Path -LiteralPath $DistDir)) {
  throw "dist directory not found: $DistDir"
}

$exes = Get-ChildItem -LiteralPath $DistDir -Filter "*.exe" -File
if (-not $exes -or $exes.Count -eq 0) {
  throw "No EXEs found in dist: $DistDir"
}

$ok = $true
foreach ($exe in $exes) {
  Write-Host ("Running: " + $exe.Name + " --version")
  & $exe.FullName --version
  if ($LASTEXITCODE -ne 0) { $ok = $false }
}

if (-not $ok) {
  throw "One or more EXEs failed --version."
}
