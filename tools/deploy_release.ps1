<# 
deploy_release.ps1

Orchestrates release steps by calling per-step scripts.
#>

[CmdletBinding()]
param(
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

function Show-Usage {
  Write-Host ""
  Write-Host "deploy_release options:"
  Write-Host "  /y or /yes          Auto-accept prompts (no push/gh unless specified)"
  Write-Host "  /auto              Auto-accept all prompts and run commit, push, gh"
  Write-Host "  /version X.Y.Z     Set release version (also accepts /version=X.Y.Z)"
  Write-Host "  /no-commit         Skip commit and tag"
  Write-Host "  /commit            Force commit and tag"
  Write-Host "  /no-push           Skip push"
  Write-Host "  /push              Force push"
  Write-Host "  /no-gh             Skip gh release"
  Write-Host "  /gh                Force gh release"
  Write-Host ""
}

function Normalize-Text {
  param([string]$Text)
  if ($null -eq $Text) { return $null }
  $t = $Text -replace "^\uFEFF", ""
  $t = $t -replace "\u0000", ""
  $t = $t.Trim()
  if (-not $t) { return $null }
  return $t
}

$autoYes = $false
$autoAll = $false
$skipCommit = $false
$skipPush = $false
$skipGh = $false
$forceCommit = $false
$forcePush = $false
$forceGh = $false
$releaseVersion = $null
$buildArgs = @()

for ($i = 0; $i -lt $Args.Count; $i++) {
  $arg = $Args[$i]
  switch -Regex ($arg) {
    "^/(\?|help)$" { Show-Usage; exit 0 }
    "^/y$" { $autoYes = $true; continue }
    "^/yes$" { $autoYes = $true; continue }
    "^/auto$" { $autoAll = $true; continue }
    "^/no-commit$" { $skipCommit = $true; continue }
    "^/commit$" { $forceCommit = $true; continue }
    "^/no-push$" { $skipPush = $true; continue }
    "^/push$" { $forcePush = $true; continue }
    "^/no-gh$" { $skipGh = $true; continue }
    "^/gh$" { $forceGh = $true; continue }
    "^/version=(.+)$" { $releaseVersion = $Matches[1]; continue }
    "^/version$" {
      if ($i + 1 -lt $Args.Count) {
        $releaseVersion = $Args[$i + 1]
        $i++
      }
      continue
    }
    default { $buildArgs += $arg; continue }
  }
}

if ($autoAll) {
  $autoYes = $true
  $forceCommit = $true
  $forcePush = $true
  $forceGh = $true
}

$runDir = (Get-Location).Path
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$toolsDir = $scriptDir
$distDir = Join-Path $repoRoot "dist"
$logFile = Join-Path $runDir "deploy_release.log"
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$header = @(
  "===============================================",
  "DEPLOY RELEASE STARTED",
  ("Timestamp: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")),
  ("Run dir:   " + $runDir),
  ("Repo root: " + $repoRoot),
  ("Tools dir: " + $toolsDir),
  "===============================================",
  ""
)
Set-Content -Path $logFile -Value $header -Encoding ASCII
$header | ForEach-Object { Write-Host $_ }

function Write-Log {
  param([string]$Text)
  if ($null -eq $Text) { $Text = "" }
  Write-Host $Text
  Add-Content -Path $logFile -Value $Text
}

function Invoke-Logged {
  param(
    [string]$Command,
    [string[]]$Arguments = @()
  )
  $oldEA = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $restoreNative = $false
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $restoreNative = $true
    $oldNative = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
  }

  $output = & $Command @Arguments 2>&1
  $exitCode = $LASTEXITCODE

  if ($restoreNative) {
    $PSNativeCommandUseErrorActionPreference = $oldNative
  }
  $ErrorActionPreference = $oldEA

  if ($output) {
    foreach ($line in $output) {
      $text = $null
      if ($line -is [System.Management.Automation.ErrorRecord]) {
        if ($line.Exception -and $line.Exception.Message) {
          $text = $line.Exception.Message
        } else {
          $text = $line.ToString()
        }
      } else {
        $text = [string]$line
      }
      $text = Normalize-Text $text
      if (-not $text) { continue }
      if ($text -eq "System.Management.Automation.RemoteException") { continue }
      Write-Host $text
      Add-Content -Path $logFile -Value $text -Encoding ASCII
    }
  }
  return $exitCode
}

try {
  Push-Location -LiteralPath $repoRoot
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found on PATH."
  }

  Write-Log "=== Checking git status ==="
  $gitExit = Invoke-Logged -Command "git" -Arguments @("status", "--short")
  if ($gitExit -ne 0) { throw "git status failed." }

  Write-Log ""
  Write-Log "=== Select release version ==="
  $versionOut = Join-Path $env:TEMP ("tpn_release_version_" + [Guid]::NewGuid().ToString("N") + ".txt")
  $selectArgs = @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "select_release_version.ps1"),
    "-RepoRoot",$repoRoot,
    "-OutFile",$versionOut
  )
  if ($releaseVersion) { $selectArgs += @("-Version", $releaseVersion) }
  if ($autoYes) { $selectArgs += "-AutoYes" }
  $selExit = Invoke-Logged -Command $psExe -Arguments $selectArgs
  if ($selExit -ne 0) { throw "Release version selection failed." }

  $releaseVersion = $null
  if (Test-Path -LiteralPath $versionOut) {
    $releaseVersion = Normalize-Text (Get-Content -LiteralPath $versionOut -Raw)
    Remove-Item -Force -ErrorAction SilentlyContinue $versionOut | Out-Null
  }
  if (-not $releaseVersion) { throw "Release version not selected." }

  Write-Log ("Using release version: " + $releaseVersion)

  Write-Log ""
  Write-Log "=== Update VERSION ==="
  $updExit = Invoke-Logged -Command $psExe -Arguments @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "update_version.ps1"),
    "-RepoRoot",$repoRoot,
    "-Version",$releaseVersion
  )
  if ($updExit -ne 0) { throw "VERSION update failed." }

  Write-Log ""
  Write-Log "=== Compiling apps ==="
  $buildExit = Invoke-Logged -Command "cmd" -Arguments @("/c", (Join-Path $toolsDir "compile_all_apps.cmd")) + $buildArgs
  if ($buildExit -ne 0) { throw "Build failed." }

  Write-Log ""
  Write-Log "=== Smoke test ==="
  $smokeExit = Invoke-Logged -Command $psExe -Arguments @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "smoke_test.ps1"),
    "-DistDir",$distDir
  )
  if ($smokeExit -ne 0) { throw "Smoke test failed." }

  Write-Log ""
  Write-Log "=== Checksums ==="
  $csExit = Invoke-Logged -Command $psExe -Arguments @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "write_checksums.ps1"),
    "-DistDir",$distDir
  )
  if ($csExit -ne 0) { throw "Checksums failed." }
  Write-Log ("Checksums written to: " + (Join-Path $distDir "checksums.sha256"))

  $tag = "v" + $releaseVersion
  Write-Log ""
  Write-Log "=== Git commit and tag ==="
  Write-Log ("Proposed tag: " + $tag)

  if ($skipCommit) {
    Write-Log "Skipping commit and tag."
    return
  }

  $doCommit = $forceCommit -or $autoYes
  if (-not $doCommit) {
    $resp = Read-Host "Create commit and tag (y/N)"
    $doCommit = ($resp -match "^(?i)y")
  }
  if (-not $doCommit) {
    Write-Log "Skipping commit and tag."
    return
  }

  $commitArgs = @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "git_commit_tag.ps1"),
    "-RepoRoot",$repoRoot,
    "-Tag",$tag
  )
  if ($autoYes) { $commitArgs += "-AutoYes" }
  $commitExit = Invoke-Logged -Command $psExe -Arguments $commitArgs
  if ($commitExit -ne 0) { throw "Commit/tag failed." }

  if ($skipPush) {
    return
  }

  $pushExit = Invoke-Logged -Command $psExe -Arguments @(
    "-NoProfile","-ExecutionPolicy","Bypass",
    "-File",(Join-Path $toolsDir "git_push.ps1"),
    "-RepoRoot",$repoRoot,
    "-Remote","origin"
  )
  if ($pushExit -ne 0) { throw "Push failed." }

  if ($skipGh) {
    return
  }

  $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $ghCmd) {
    if ($forceGh) { throw "gh not found on PATH." }
    Write-Log "gh not found on PATH. Skipping GitHub release."
    return
  }

  $doGh = $forceGh
  if (-not $doGh -and -not $autoYes) {
    $resp = Read-Host "Create GitHub release via gh (y/N)"
    if ($resp -match "^(?i)y") { $doGh = $true }
  }

  if ($doGh) {
    $publishArgs = @(
      "-NoProfile","-ExecutionPolicy","Bypass",
      "-File",(Join-Path $toolsDir "publish_release.ps1"),
      "-Tag",$tag,
      "-DistDir",$distDir,
      "-NotesFile",(Join-Path $repoRoot "RELEASE_NOTES.md")
    )
    $publishArgs += "-AutoYes"
    $pubExit = Invoke-Logged -Command $psExe -Arguments $publishArgs
    if ($pubExit -ne 0) { throw "Publish release failed." }
  }
}
catch {
  $msg = $_.Exception.Message
  if (-not $msg) {
    $msg = ($_ | Out-String).Trim()
  }
  if (-not $msg) { $msg = "Unknown error." }
  Write-Log ("*** ERROR: " + $msg)
  exit 1
}
finally {
  Pop-Location
  Write-Log ""
  Write-Log "=== DEPLOY RELEASE DONE ==="
  Write-Log ("Log written to: " + $logFile)
}
