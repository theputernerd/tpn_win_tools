<# 
render_release_notes.ps1

Renders release notes from a template and per-tool notes.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = $null,
  [string]$Version = $null,
  [string]$DistDir = $null,
  [string]$TemplatePath = $null,
  [string]$NotesFile = $null,
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

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not $OutFile) { throw "OutFile is required." }

if (-not $DistDir) { $DistDir = Join-Path $RepoRoot "dist" }
if (-not $TemplatePath) { $TemplatePath = Join-Path $RepoRoot "RELEASE_TEMPLATE.md" }
if (-not $NotesFile) { $NotesFile = Join-Path $RepoRoot "RELEASE_NOTES.md" }

if (-not $Version) {
  $versionPath = Join-Path $RepoRoot "VERSION"
  if (Test-Path -LiteralPath $versionPath) {
    $Version = Normalize-Text (Get-Content -LiteralPath $versionPath -Raw)
  }
}
if (-not $Version) { $Version = "0.0.0" }
$tag = "v" + $Version

$bundleNotes = "None."
if (Test-Path -LiteralPath $NotesFile) {
  $raw = Normalize-Text (Get-Content -LiteralPath $NotesFile -Raw)
  if ($raw) { $bundleNotes = $raw }
}

$toolsDir = Join-Path $RepoRoot "scripts"
$tools = @()
if (Test-Path -LiteralPath $toolsDir) {
  $tools = Get-ChildItem -LiteralPath $toolsDir -Directory | Sort-Object Name
}

$repoUrl = $null
$remoteUrl = & git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0) {
  $remoteUrl = Normalize-Text $remoteUrl
  if ($remoteUrl -and ($remoteUrl -match "github\.com[:/](.+?)(\.git)?$")) {
    $repoUrl = "https://github.com/" + $Matches[1]
  }
}

$toolLines = @()
$toolDetailBlocks = @()
foreach ($tool in $tools) {
  $name = $tool.Name
  if ($name.StartsWith("_")) { continue }
  $toolVer = "0.0.0"
  $verPath = Join-Path $tool.FullName "VERSION"
  if (Test-Path -LiteralPath $verPath) {
    $toolVer = Normalize-Text (Get-Content -LiteralPath $verPath -Raw)
    if (-not $toolVer) { $toolVer = "0.0.0" }
  }
  $srcCell = "-"
  if ($repoUrl) {
    $srcCell = "[src](" + $repoUrl + "/tree/" + $tag + "/scripts/" + $name + ")"
  }
  $toolLine = "| " + $name + " | " + $toolVer + " | " + $srcCell + " |"
  $toolLines += $toolLine

  $notePath = Join-Path $tool.FullName "RELEASE_NOTES.md"
  $toolNotes = "No notes."
  if (Test-Path -LiteralPath $notePath) {
    $noteRaw = Normalize-Text (Get-Content -LiteralPath $notePath -Raw)
    if ($noteRaw) { $toolNotes = $noteRaw }
  }

  $examplePath = Join-Path $tool.FullName "RELEASE_EXAMPLES.md"
  $toolExamples = "None."
  if (Test-Path -LiteralPath $examplePath) {
    $exRaw = Normalize-Text (Get-Content -LiteralPath $examplePath -Raw)
    if ($exRaw) { $toolExamples = $exRaw }
  }

  $summary = $name + " (" + $toolVer + ")"
  $toolDetailBlocks += "<details>"
  $toolDetailBlocks += "<summary>" + $summary + "</summary>"
  $toolDetailBlocks += ""
  $toolDetailBlocks += "- Version: " + $toolVer
  if ($repoUrl) {
    $toolDetailBlocks += "- Source: [src](" + $repoUrl + "/tree/" + $tag + "/scripts/" + $name + ")"
  }
  $toolDetailBlocks += ""
  $toolDetailBlocks += "#### Release notes"
  $toolDetailBlocks += $toolNotes
  $toolDetailBlocks += ""
  $toolDetailBlocks += "#### Examples"
  $toolDetailBlocks += $toolExamples
  $toolDetailBlocks += "</details>"
  $toolDetailBlocks += ""
}

$toolsText = if ($toolLines.Count -gt 0) { $toolLines -join "`n" } else { "| (none) | - | - |" }
$toolDetailsText = if ($toolDetailBlocks.Count -gt 0) { $toolDetailBlocks -join "`n" } else { "None." }

$checksumsText = "checksums.sha256 not found."
$checksumPath = Join-Path $DistDir "checksums.sha256"
if (Test-Path -LiteralPath $checksumPath) {
  $csLines = Get-Content -LiteralPath $checksumPath
  if ($csLines -and $csLines.Count -gt 0) {
    $checksumsText = ($csLines -join "`n")
  }
}

$date = (Get-Date).ToString("yyyy-MM-dd")

$template = $null
if (Test-Path -LiteralPath $TemplatePath) {
  $template = Get-Content -LiteralPath $TemplatePath -Raw
}

if ($template) {
  $content = $template
  $content = $content.Replace("{{VERSION}}", $Version)
  $content = $content.Replace("{{TAG}}", $tag)
  $content = $content.Replace("{{DATE}}", $date)
  $content = $content.Replace("{{TOOLS}}", $toolsText)
  $content = $content.Replace("{{TOOLS_DETAIL}}", $toolDetailsText)
  $content = $content.Replace("{{BUNDLE_NOTES}}", $bundleNotes)
  $content = $content.Replace("{{CHECKSUMS}}", $checksumsText)
} else {
  $content = $bundleNotes
}

Set-Content -Path $OutFile -Value $content -Encoding ASCII
