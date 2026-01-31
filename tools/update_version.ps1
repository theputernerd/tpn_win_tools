<# 
update_version.ps1

Updates the bundle VERSION file.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null,
  [string]$Version = $null
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not $Version) { throw "Version is required." }

$versionPath = Join-Path $RepoRoot "VERSION"
Set-Content -Path $versionPath -Value $Version -Encoding ASCII
