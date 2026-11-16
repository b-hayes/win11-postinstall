#Requires -Version 5.1
<#
.SYNOPSIS
    Disable Windows 11 nags, ads, suggestions, and setup prompts.

.DESCRIPTION
    Single source of truth for every "annoyance" tweak: SCOOBE "finish setting up"
    page, setup notification toast, Start menu suggestions and recommendations,
    lock screen tips (Spotlight wallpapers left on), File Explorer OneDrive/Office
    ad banners, widgets, Teams chat icon, tip notifications, search highlights, and
    tailored-experience ads.

    Many of these are reset by Windows feature updates, which is why the shared
    guard task (bin/guard.ps1) re-runs this script.

    Safe to re-run - idempotent, applies the same values every time.

.PARAMETER Yes
    Accept all prompts (non-interactive). Used by the scheduled guard.

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

if ($Help) {
    Write-Host ""
    Write-Host "  nag-removal - disable Windows 11 nags, ads, and suggestions" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: nag-removal [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    -Yes   Accept all prompts (non-interactive)" -ForegroundColor Gray
    Write-Host "    -Help  Show this help and exit" -ForegroundColor Gray
    Write-Host ""
    return
}

# Self-elevate if not already admin (git bash / double-click launches without elevation)
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

Write-Header "Windows 11 Nags, Ads & Suggestions"

$CDM = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$ADV = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

$nagTweaks = @(
    # --- Start menu suggestions / promoted and silently-installed apps ---
    @($CDM, "SubscribedContent-338388Enabled", 0),
    @($CDM, "SubscribedContent-338389Enabled", 0),
    @($CDM, "SystemPaneSuggestionsEnabled",    0),
    @($CDM, "SoftLandingEnabled",              0),
    @($CDM, "SubscribedContent-310093Enabled", 0),
    @($CDM, "SilentInstalledAppsEnabled",      0),
    @($CDM, "ContentDeliveryAllowed",          0),
    @($CDM, "OemPreInstalledAppsEnabled",      0),
    @($CDM, "PreInstalledAppsEnabled",         0),
    @($CDM, "SubscribedContentEnabled",        0),
    # --- Tip / suggestion notifications (ads in the notification area) ---
    @($CDM, "SubscribedContent-338393Enabled", 0),
    @($CDM, "SubscribedContent-353694Enabled", 0),
    @($CDM, "SubscribedContent-353696Enabled", 0),
    # --- Tailored experiences (ads based on diagnostic data) ---
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy", "TailoredExperiencesWithDiagnosticDataEnabled", 0),
    # --- "Finish setting up your device" (SCOOBE) page + setup notification toast ---
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement", "ScoobeSystemSettingEnabled", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE",                        "DisablePrivacyExperience",  1),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested", "Enabled", 0),
    # --- Backup / OneDrive suggestion banners ---
    @($CDM, "SubscribedContent-338380Enabled", 0),
    @($ADV, "ShowSyncProviderNotifications",   0),
    # --- Start menu "recommendations" (recently added / promoted content) ---
    @($ADV, "Start_IrisRecommendations",       0),
    # --- Lock screen tips overlay (Spotlight wallpaper rotation intentionally left on) ---
    @($CDM, "RotatingLockScreenOverlayEnabled", 0),
    # --- Widgets (news feed) and Teams chat icon on the taskbar ---
    @($ADV, "TaskbarDa", 0),
    @($ADV, "TaskbarMn", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Dsh", "AllowNewsAndInterests", 0),
    # --- Search highlights (bouncing doodles / web content in the search box) ---
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings", "IsDynamicSearchBoxEnabled", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",       "EnableDynamicContentInWSB", 0)
)

Write-Step "Applying nag/ad/suggestion tweaks..."
foreach ($t in $nagTweaks) { Set-Reg $t[0] $t[1] $t[2] }
Write-Done "Nags, ads, suggestions, and setup prompts disabled"
