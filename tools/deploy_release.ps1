<# 
deploy_release.ps1

Builds, smoke tests, generates checksums, and prepares a release commit/tag.
Optional: push and GitHub release when requested.
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
      if (-not $text) { continue }
      if ($text.Trim() -eq "System.Management.Automation.RemoteException") { continue }
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

  $versionPath = Join-Path $repoRoot "VERSION"
  $currentVersion = "0.0.0"
  if (Test-Path -LiteralPath $versionPath) {
    $currentVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    if (-not $currentVersion) { $currentVersion = "0.0.0" }
  }
  Write-Log ("Current bundle VERSION: " + $currentVersion)

  $latestTag = $null
  $tagListAll = & git tag --list "v*" --sort=-version:refname
  if ($LASTEXITCODE -ne 0) { throw "git tag --list failed." }
  foreach ($t in $tagListAll) {
    if ($t -and $t.Trim()) { $latestTag = $t.Trim(); break }
  }
  if ($latestTag) {
    Write-Log ("Latest tag: " + $latestTag)
  }
  $currentTag = "v" + $currentVersion
  $currentTagExists = $false
  foreach ($t in $tagListAll) {
    if ($t.Trim() -eq $currentTag) { $currentTagExists = $true; break }
  }
  $tagExistsText = "no"
  if ($currentTagExists) { $tagExistsText = "yes" }
  Write-Log ("Current version tag exists: " + $tagExistsText)

  if ($releaseVersion) { $releaseVersion = $releaseVersion.Trim() }
  if (-not $releaseVersion) { $releaseVersion = $currentVersion }

  if ($autoYes) {
    Write-Log ("Release version: " + $releaseVersion)
  } else {
    $inputVersion = Read-Host ("Release version [" + $releaseVersion + "]")
    if ($inputVersion) {
      $releaseVersion = $inputVersion.Trim()
    }
  }

  while ($true) {
    if (-not $releaseVersion) { $releaseVersion = $currentVersion }
    $tag = "v" + $releaseVersion
    $tagList = & git tag --list $tag
    if ($LASTEXITCODE -ne 0) { throw "git tag --list failed." }
    $tagExists = $false
    foreach ($t in $tagList) {
      if ($t.Trim() -eq $tag) { $tagExists = $true; break }
    }
    if ($tagExists) {
      Write-Log ("*** ERROR: tag " + $tag + " already exists ***")
      if ($autoYes) { throw "Tag exists." }
      $newVersion = Read-Host ("Tag " + $tag + " exists. Enter a new release version or leave blank to abort")
      if (-not $newVersion) { throw "Aborted." }
      $releaseVersion = $newVersion.Trim()
      continue
    }
    break
  }

  Write-Log ("Using release version: " + $releaseVersion)
  Set-Content -Path $versionPath -Value $releaseVersion -Encoding ASCII

  $continueBuild = $true
  if (-not $autoYes) {
    $resp = Read-Host "Continue with build (y/N)"
    $continueBuild = ($resp -match "^(?i)y")
  }
  if (-not $continueBuild) { throw "Aborted." }

  Write-Log ""
  Write-Log "=== Compiling apps ==="
  $buildExit = Invoke-Logged -Command "cmd" -Arguments @("/c", (Join-Path $toolsDir "compile_all_apps.cmd")) + $buildArgs
  if ($buildExit -ne 0) { throw "Build failed." }

  if (-not (Test-Path -LiteralPath $distDir)) {
    throw ("dist directory not found: " + $distDir)
  }

  Write-Log ""
  Write-Log "=== Smoke test ==="
  $exes = Get-ChildItem -LiteralPath $distDir -Filter "*.exe" -File
  if (-not $exes -or $exes.Count -eq 0) { throw "No EXEs found in dist." }

  $smokeOk = $true
  foreach ($exe in $exes) {
    Write-Log ("Running: " + $exe.Name + " --version")
    & $exe.FullName --version 2>&1 | Tee-Object -FilePath $logFile -Append
    if ($LASTEXITCODE -ne 0) { $smokeOk = $false }
  }
  if (-not $smokeOk) { throw "One or more EXEs failed --version." }

  Write-Log ""
  Write-Log "=== Checksums ==="
  if (-not (Test-Path -LiteralPath $psExe)) { throw "Windows PowerShell not found." }
  $csExit = Invoke-Logged -Command $psExe -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $toolsDir "write_checksums.ps1"), "-DistDir", $distDir)
  if ($csExit -ne 0) { throw "Checksums failed." }
  Write-Log ("Checksums written to: " + (Join-Path $distDir "checksums.sha256"))

  $tag = "v" + $releaseVersion
  Write-Log ""
  Write-Log "=== Git commit and tag ==="
  Write-Log ("Proposed tag: " + $tag)

  $commitMsg = "Release " + $tag
  if ($autoYes) {
    Write-Log ("Commit message: " + $commitMsg)
  } else {
    $inputMsg = Read-Host ("Commit message [" + $commitMsg + "]")
    if ($inputMsg) { $commitMsg = $inputMsg }
  }

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

  $tagList = & git tag --list $tag
  if ($LASTEXITCODE -ne 0) { throw "git tag --list failed." }
  foreach ($t in $tagList) {
    if ($t.Trim() -eq $tag) { throw ("Tag " + $tag + " already exists.") }
  }

  $addExit = Invoke-Logged -Command "git" -Arguments @("add", "-A")
  if ($addExit -ne 0) { throw "git add failed." }

  $commitExit = Invoke-Logged -Command "git" -Arguments @("commit", "-m", $commitMsg)
  if ($commitExit -ne 0) { throw "Commit failed." }

  $tagExit = Invoke-Logged -Command "git" -Arguments @("tag", $tag)
  if ($tagExit -ne 0) { throw "Tag failed." }

  if ($skipPush) {
    return
  }

  if ($forcePush) {
    Invoke-Logged -Command "git" -Arguments @("push", "origin", "HEAD", "--tags") | Out-Null
  } elseif (-not $autoYes) {
    $resp = Read-Host "Push commit and tags (y/N)"
    if ($resp -match "^(?i)y") {
      Invoke-Logged -Command "git" -Arguments @("push", "origin", "HEAD", "--tags") | Out-Null
    }
  }

  if ($skipGh) {
    return
  }

  $doGh = $forceGh
  if (-not $doGh -and -not $autoYes) {
    $resp = Read-Host "Create GitHub release via gh (y/N)"
    if ($resp -match "^(?i)y") { $doGh = $true }
  }

  if ($doGh) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-Log "gh not found on PATH. Skipping."
    } else {
      Invoke-Logged -Command "gh" -Arguments @(
        "release","create",$tag,
        (Join-Path $distDir "*.exe"),
        (Join-Path $distDir "checksums.sha256"),
        "-F",(Join-Path $repoRoot "RELEASE_NOTES.md"),
        "--title",$tag
      ) | Out-Null
    }
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
