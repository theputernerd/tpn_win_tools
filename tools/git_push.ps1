<# 
git_push.ps1

Pushes the current branch and tags to a remote.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null,
  [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Push-Location -LiteralPath $RepoRoot
try {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found on PATH."
  }

  & git push $Remote HEAD --tags
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }
}
finally {
  Pop-Location
}
