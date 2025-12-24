<#
install_TPM_apps.ps1

Installs compiled EXEs from ..\dist into %USERPROFILE%\tpn_apps
Creates .cmd wrappers
Prepends install dir to the USER PATH (HKCU\Environment\Path)
#>

[CmdletBinding()]
param(
  [string]$SourceDir = $null,
  [string]$AppDirName = "tpn_apps",
  [switch]$NoWrappers,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Normalize-FullPath([string]$Path) {
  return [System.IO.Path]::GetFullPath($Path)
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Write-File([string]$Path, [string]$Content) {
  if ($DryRun) { 
    Write-Host "DRYRUN write: $Path"
    return 
  }
  Set-Content -LiteralPath $Path -Value $Content -Encoding ASCII
}

function Prepend-UserPath([string]$Dir) {
  $envKey = "HKCU:\Environment"
  $current = (Get-ItemProperty -Path $envKey -Name Path -ErrorAction SilentlyContinue).Path
  if (-not $current) { $current = "" }

  $parts = $current -split ";" | Where-Object { $_ -and $_.Trim() -ne "" }
  $dirNorm = $Dir.TrimEnd("\")
  $exists = $false
  foreach ($p in $parts) {
    if ($p.TrimEnd("\").Equals($dirNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
      $exists = $true
      break
    }
  }

  if ($exists) {
    Write-Host "User PATH already contains: $dirNorm"
    return
  }

  $newPath = if ($current -and $current.Trim() -ne "") { "$dirNorm;$current" } else { $dirNorm }

  Write-Host "Prepending to User PATH (persistent): $dirNorm"
  if (-not $DryRun) {
    Set-ItemProperty -Path $envKey -Name Path -Value $newPath
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
      [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
      public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x001A
    $SMTO_ABORTIFHUNG = 0x0002
    [UIntPtr]$result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", $SMTO_ABORTIFHUNG, 2000, [ref]$result) | Out-Null
  }
}

$repoRoot = Normalize-FullPath (Join-Path $PSScriptRoot "..")
if (-not $SourceDir) { $SourceDir = Join-Path $repoRoot "dist" }
$SourceDir = Normalize-FullPath $SourceDir

if (-not (Test-Path -LiteralPath $SourceDir)) {
  throw "SourceDir not found: $SourceDir. Build first (tools\compile_all_apps.cmd)."
}

$appDir = Join-Path $env:USERPROFILE $AppDirName
$appDir = Normalize-FullPath $appDir

Ensure-Dir $appDir

$exeFiles = Get-ChildItem -LiteralPath $SourceDir -Filter "*.exe" -File | Sort-Object Name
if (-not $exeFiles -or $exeFiles.Count -eq 0) {
  throw "No EXEs found in: $SourceDir"
}

Write-Host ""
Write-Host "Repo root:  $repoRoot"
Write-Host "Source:     $SourceDir"
Write-Host "Install to: $appDir"
Write-Host ""

foreach ($exe in $exeFiles) {
  $dstExe = Join-Path $appDir $exe.Name
  Write-Host "Copy: $($exe.Name)"
  if (-not $DryRun) {
    Copy-Item -Force -LiteralPath $exe.FullName -Destination $dstExe
  }

  if (-not $NoWrappers) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)
    $cmdPath = Join-Path $appDir ($base + ".cmd")
    $cmd = "@echo off`r`n`"%~dp0" + $exe.Name + "`" %*`r`n"
    Write-File $cmdPath $cmd
  }
}

Prepend-UserPath $appDir

Write-Host ""
Write-Host "Installed EXEs: $($exeFiles.Count)"
Write-Host "Installed to:   $appDir"
Write-Host ""
Write-Host "Open a NEW terminal, then:"
Write-Host "  where ttree"
Write-Host "  ttree --version"
