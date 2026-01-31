<# 
select_release_version.ps1

Selects a release version and verifies the tag does not already exist.
Writes the chosen version to stdout and optionally to -OutFile.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null,
  [string]$Version = $null,
  [switch]$AutoYes,
  [string]$OutFile = $null
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
Push-Location -LiteralPath $RepoRoot

try {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found on PATH."
  }

  $versionPath = Join-Path $RepoRoot "VERSION"
  $currentVersion = "0.0.0"
  if (Test-Path -LiteralPath $versionPath) {
    $currentVersion = Normalize-Text (Get-Content -LiteralPath $versionPath -Raw)
    if (-not $currentVersion) { $currentVersion = "0.0.0" }
  }

  Write-Host ("Current bundle VERSION: " + $currentVersion)

  $latestTag = $null
  $tagListAll = & git tag --list "v*" --sort=-version:refname
  if ($LASTEXITCODE -ne 0) { throw "git tag --list failed." }
  foreach ($t in $tagListAll) {
    $tNorm = Normalize-Text $t
    if ($tNorm) { $latestTag = $tNorm; break }
  }
  if ($latestTag) {
    Write-Host ("Latest tag: " + $latestTag)
  }

  $currentTag = "v" + $currentVersion
  $currentTagExists = Test-TagExists $currentTag
  $tagExistsText = "no"
  if ($currentTagExists) { $tagExistsText = "yes" }
  Write-Host ("Current version tag exists: " + $tagExistsText)

  if ($Version) { $Version = Normalize-Text $Version }
  if (-not $Version) { $Version = $currentVersion }

  if (-not $AutoYes) {
    $inputVersion = Read-Host ("Release version [" + $Version + "]")
    $inputVersion = Normalize-Text $inputVersion
    if ($inputVersion) { $Version = $inputVersion }
  } else {
    Write-Host ("Release version: " + $Version)
  }

  while ($true) {
    if (-not $Version) { $Version = $currentVersion }
    $tag = "v" + $Version
    if (Test-TagExists $tag) {
      Write-Host ("*** ERROR: tag " + $tag + " already exists ***")
      if ($AutoYes) { throw "Tag exists." }
      $newVersion = Read-Host ("Tag " + $tag + " exists. Enter a new release version or leave blank to abort")
      $newVersion = Normalize-Text $newVersion
      if (-not $newVersion) { throw "Aborted." }
      $Version = $newVersion
      continue
    }
    break
  }

  if (-not $Version) { throw "Release version is empty." }

  if ($OutFile) {
    Set-Content -Path $OutFile -Value $Version -Encoding ASCII
  }
  Write-Output $Version
}
finally {
  Pop-Location
}
