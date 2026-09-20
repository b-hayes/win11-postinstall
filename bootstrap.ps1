<#
.SYNOPSIS
    Bootstrap for win11-postinstall. Run via:
        irm https://raw.githubusercontent.com/b-hayes/win11-postinstall/main/bootstrap.ps1 | iex

    Self-elevates, downloads Win11PostInstall.ps1 and its bin/copilot-removal.ps1
    dependency to a local folder (preserving the layout the script expects), then runs it.
#>

$ErrorActionPreference = 'Stop'
$RepoRaw = 'https://raw.githubusercontent.com/b-hayes/win11-postinstall/main'

# Self-elevate if not already running as administrator.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', "irm $RepoRaw/bootstrap.ps1 | iex"
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
    'bin/copilot-removal.ps1'
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
& $main
