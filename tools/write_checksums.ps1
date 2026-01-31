<# 
write_checksums.ps1

Writes SHA256 checksums for EXEs in the dist folder.
#>

[CmdletBinding()]
param(
  [string]$DistDir = $null
)

$ErrorActionPreference = "Stop"

if (-not $DistDir) {
  throw "DistDir is required."
}

$distPath = (Resolve-Path -LiteralPath $DistDir).Path
$outPath = Join-Path $distPath "checksums.sha256"

Get-ChildItem -LiteralPath $distPath -Filter "*.exe" | Sort-Object Name | ForEach-Object {
  $h = Get-FileHash -Algorithm SHA256 $_.FullName
  "{0} *{1}" -f $h.Hash, $_.Name
} | Set-Content -Encoding ASCII $outPath
