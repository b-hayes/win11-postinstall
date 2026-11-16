#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstall Microsoft OneDrive completely and remove its File Explorer icon.

.DESCRIPTION
    Stops OneDrive, runs the built-in uninstaller (with a winget fallback), removes
    the OneDrive icon from the File Explorer navigation pane, and clears its autostart
    entry. Does NOT delete your existing OneDrive folder / files in your profile.

    Destructive choice - only for people who do not use OneDrive. Safe to re-run.

.PARAMETER Yes
    Accept all prompts (non-interactive).

.PARAMETER Help
    Show usage and exit.
#>
param(
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

function Write-Header { param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Blue
    Write-Host "  $Text" -ForegroundColor Blue
    Write-Host ("=" * 50) -ForegroundColor Blue
}
function Write-Step { param([string]$T); Write-Host "  [*] $T" -ForegroundColor Yellow }
function Write-Done { param([string]$T); Write-Host "  [+] $T" -ForegroundColor Green }
function Write-Skip { param([string]$T); Write-Host "  [-] $T" -ForegroundColor DarkGray }
function Write-Warn { param([string]$T); Write-Host "  [!] $T" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-Reg {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
    } catch [System.UnauthorizedAccessException] {
        $rp = $Path -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
        cmd /c "reg add `"$rp`" /v `"$Name`" /t REG_DWORD /d $Value /f" 2>&1 | Out-Null
    }
}

function Confirm-Default-No {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $ans = Read-Host "  $Prompt [y/N]"
    return ($ans -match '^[Yy]')
}

if ($Help) {
    Write-Host ""
    Write-Host "  remove-onedrive - uninstall OneDrive and remove its Explorer icon" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: remove-onedrive [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    -Yes   Accept all prompts (non-interactive)" -ForegroundColor Gray
    Write-Host "    -Help  Show this help and exit" -ForegroundColor Gray
    Write-Host ""
    return
}

# Self-elevate if not already admin
if (-not (Test-Admin)) {
    Write-Warn "Administrator rights required - relaunching elevated..."
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File', "`"$PSCommandPath`"")
    if ($Yes) { $argList += '-Yes' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host "  Elevation was cancelled or failed. Run this from an elevated shell." -ForegroundColor Red
    }
    return
}

Write-Header "Remove OneDrive"

$setup32 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
$setup64 = "$env:SystemRoot\System32\OneDriveSetup.exe"
$installed = (Test-Path $setup32) -or (Test-Path $setup64) -or (Get-Process -Name OneDrive -EA SilentlyContinue)
if (-not $installed) {
    Write-Skip "OneDrive is not installed"
    return
}

Write-Host "  Uninstalls OneDrive and removes its File Explorer icon and autostart." -ForegroundColor White
Write-Host "  Your existing OneDrive folder and files are left untouched." -ForegroundColor DarkGray
if (-not (Confirm-Default-No "Remove OneDrive completely?")) {
    Write-Skip "Leaving OneDrive installed"
    return
}

Write-Step "Stopping OneDrive..."
Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue

Write-Step "Running the OneDrive uninstaller..."
$ran = $false
foreach ($s in @($setup64, $setup32)) {
    if (Test-Path $s) {
        Start-Process $s -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
        $ran = $true
    }
}
if (-not $ran -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Step "Falling back to winget uninstall..."
    winget uninstall --id Microsoft.OneDrive -e --accept-source-agreements 2>&1 | Out-Null
}

Write-Step "Removing the OneDrive icon from File Explorer..."
# System.IsPinnedToNameSpaceTree = 0 hides it in the navigation pane (64- and 32-bit)
Set-Reg "HKLM:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0
Set-Reg "HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0

Write-Step "Clearing OneDrive autostart..."
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

Write-Done "OneDrive removed (icon and autostart cleared; your OneDrive folder is untouched)"
