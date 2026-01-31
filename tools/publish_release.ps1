<# 
publish_release.ps1

Uploads dist artifacts to a GitHub release using gh.
#>

[CmdletBinding()]
param(
  [string]$Tag = $null,
  [string]$DistDir = $null,
  [string]$NotesFile = $null,
  [string]$TemplatePath = $null,
  [switch]$AutoYes
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$psExe = Join-Path $env:SystemRoot "System32\\WindowsPowerShell\\v1.0\\powershell.exe"

if (-not $DistDir) { $DistDir = Join-Path $repoRoot "dist" }
if (-not $NotesFile) { $NotesFile = Join-Path $repoRoot "RELEASE_NOTES.md" }
if (-not $TemplatePath) { $TemplatePath = Join-Path $repoRoot "RELEASE_TEMPLATE.md" }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "gh not found on PATH."
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git not found on PATH."
}
if (-not (Test-Path -LiteralPath $DistDir)) {
  throw "dist directory not found: $DistDir"
}
if (-not (Test-Path -LiteralPath $NotesFile)) {
  throw "Release notes not found: $NotesFile"
}

$versionPath = Join-Path $repoRoot "VERSION"
if (-not $Tag) {
  $version = "0.0.0"
  if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    if (-not $version) { $version = "0.0.0" }
  }
  $Tag = "v" + $version
}

& git show-ref --verify --quiet ("refs/tags/" + $Tag) | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Tag not found: $Tag"
}

& gh auth status --hostname github.com | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "gh not authenticated. Run: gh auth login"
}

$exes = Get-ChildItem -LiteralPath $DistDir -Filter "*.exe" -File
if (-not $exes -or $exes.Count -eq 0) {
  throw "No EXEs found in dist: $DistDir"
}
$checksumPath = Join-Path $DistDir "checksums.sha256"
if (-not (Test-Path -LiteralPath $checksumPath)) {
  throw "checksums.sha256 not found in dist."
}

Write-Host ("Publishing GitHub release " + $Tag)
if (-not $AutoYes) {
  $resp = Read-Host "Continue (y/N)"
  if ($resp -notmatch "^(?i)y") { throw "Aborted." }
}

$versionForNotes = $Tag
if ($versionForNotes.StartsWith("v")) {
  $versionForNotes = $versionForNotes.Substring(1)
}
$notesOut = Join-Path $env:TEMP ("tpn_release_body_" + [Guid]::NewGuid().ToString("N") + ".md")

& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "render_release_notes.ps1") `
  -RepoRoot $repoRoot -Version $versionForNotes -DistDir $DistDir `
  -TemplatePath $TemplatePath -NotesFile $NotesFile -OutFile $notesOut
if ($LASTEXITCODE -ne 0) {
  throw "Failed to render release notes."
}

$title = "tpn_win_tools " + $Tag + " - Windows CLI tools bundle"
& gh release create $Tag (Join-Path $DistDir "*.exe") $checksumPath `
  -F $notesOut --title $title
if ($LASTEXITCODE -ne 0) {
  throw "gh release create failed."
}
Remove-Item -Force -ErrorAction SilentlyContinue $notesOut | Out-Null
