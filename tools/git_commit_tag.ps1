<# 
git_commit_tag.ps1

Stages all changes, commits, and tags the release.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null,
  [string]$Tag = $null,
  [string]$Message = $null,
  [switch]$AutoYes
)

$ErrorActionPreference = "Stop"

function Normalize-Text {
  param([string]$Text)
  if ($null -eq $Text) { return $null }
  $t = $Text -replace "^\uFEFF", ""
  $t = $t -replace "\u0000", ""
  $t = $t.Trim()
  if (-not $t) { return $null }
  return $t
}

function Test-TagExists {
  param([string]$TagName)
  if (-not $TagName) { return $false }
  $oldEA = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $restoreNative = $false
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $restoreNative = $true
    $oldNative = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
  }
  & git show-ref --verify --quiet ("refs/tags/" + $TagName) | Out-Null
  $exitCode = $LASTEXITCODE
  if ($restoreNative) {
    $PSNativeCommandUseErrorActionPreference = $oldNative
  }
  $ErrorActionPreference = $oldEA
  return ($exitCode -eq 0)
}

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not $Tag) { throw "Tag is required." }

Push-Location -LiteralPath $RepoRoot
try {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found on PATH."
  }

  if (Test-TagExists $Tag) {
    throw ("Tag " + $Tag + " already exists.")
  }

  if ($Message) { $Message = Normalize-Text $Message }
  if (-not $Message) { $Message = "Release " + $Tag }
  if (-not $AutoYes) {
    $inputMsg = Read-Host ("Commit message [" + $Message + "]")
    $inputMsg = Normalize-Text $inputMsg
    if ($inputMsg) { $Message = $inputMsg }
  }

  & git add -A
  if ($LASTEXITCODE -ne 0) { throw "git add failed." }

  & git commit -m $Message
  if ($LASTEXITCODE -ne 0) { throw "Commit failed." }

  & git tag $Tag
  if ($LASTEXITCODE -ne 0) { throw "Tag failed." }
}
finally {
  Pop-Location
}
