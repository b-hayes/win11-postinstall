<#
.SYNOPSIS
    Bootstrap for win11-postinstall. Run via:
        irm https://raw.githubusercontent.com/b-hayes/win11-postinstall/main/bootstrap.ps1 | iex

    Self-elevates, downloads Win11PostInstall.ps1 and its bin/ module dependencies
    to a local folder (preserving the layout the script expects), then runs it.

    To test a branch, set $RepoRaw to that branch BEFORE the pipe (iex runs this
    script in your scope, so it honours a pre-set $RepoRaw):
        $RepoRaw='https://raw.githubusercontent.com/b-hayes/win11-postinstall/my-branch'; irm $RepoRaw/bootstrap.ps1 | iex
#>

$ErrorActionPreference = 'Stop'
# Honour a $RepoRaw pre-set by the caller (branch testing); default to main
if (-not $RepoRaw) { $RepoRaw = 'https://raw.githubusercontent.com/b-hayes/win11-postinstall/main' }

# Self-elevate if not already running as administrator.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating..." -ForegroundColor Yellow
    # Carry the resolved $RepoRaw across elevation so the elevated run uses the same source
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', "`$RepoRaw='$RepoRaw'; irm `$RepoRaw/bootstrap.ps1 | iex"
    )
    return
}

# Allow the downloaded .ps1 files to run in this process regardless of the
# machine's execution policy (process scope only, no admin needed, not persisted).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:TEMP 'win11-postinstall'
$files = @(
    'cli/setup/Win11PostInstall.ps1',
    'bin/copilot-removal.ps1',
    'bin/nag-removal.ps1',
    'bin/gaming-tweaks.ps1',
    'bin/debloat.ps1',
    'bin/guard.ps1',
    'bin/remove-onedrive.ps1'
)

foreach ($f in $files) {
    $dest = Join-Path $dir ($f -replace '/', '\')
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Host "Downloading $f..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "$RepoRaw/$f" -OutFile $dest -UseBasicParsing
}

$main = Join-Path $dir 'cli\setup\Win11PostInstall.ps1'
Write-Host "Launching post-install script..." -ForegroundColor Green
& $main -RepoRaw $RepoRaw
