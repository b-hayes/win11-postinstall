#Requires -Version 5.1
<#
.SYNOPSIS
    Remove Microsoft Copilot and Windows Recall.

.DESCRIPTION
    Applies the current (2026) supported policies to disable and remove Copilot, disables
    Windows Recall (periodic screen snapshots), and uninstalls the Copilot Appx packages.

    Windows re-adds Copilot on major feature updates - the shared guard (bin/guard.ps1)
    re-runs this script to keep it gone.

    Safe to re-run - every step is idempotent and skips work already done.

.PARAMETER Yes
    Accept all prompts (non-interactive). Used by the scheduled guard.

.PARAMETER Help
    Show this usage and exit.

.EXAMPLE
    .\copilot-removal.ps1
.EXAMPLE
    .\copilot-removal.ps1 -Yes
#>
param(
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

# Copilot packages to remove
$CopilotPackages = @(
    'Microsoft.Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.BingSearch'
)

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
    Write-Host "  copilot-removal - remove Copilot and Recall" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: copilot-removal [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    -Yes   Accept all prompts (non-interactive)" -ForegroundColor Gray
    Write-Host "    -Help  Show this help and exit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Re-apply automatically after feature updates with: guard" -ForegroundColor DarkGray
    Write-Host ""
    return
}

# Self-elevate: relaunch as admin if we are not already (git bash launches without elevation)
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

# ============================================================
# 1. COPILOT POLICIES
# ============================================================
Write-Header "Copilot Policies"
$copilotTweaks = @(
    # New official removal policy - April 2026 update (KB5083769, build 26200.8246).
    # Auto-removes Copilot only when it was not user-installed and unused for 28 days,
    # which is why we also uninstall the packages directly below.
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI",       "RemoveMicrosoftCopilotApp", 1),
    @("HKCU:\Software\Policies\Microsoft\Windows\WindowsAI",       "RemoveMicrosoftCopilotApp", 1),
    # Legacy policy - still hides the taskbar button / Win+C on older builds
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot",  "TurnOffWindowsCopilot",     1),
    @("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",  "TurnOffWindowsCopilot",     1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot",  "DisableCopilotFeature",     1),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "ShowCopilotButton", 0),
    # Edge Copilot sidebar
    @("HKLM:\SOFTWARE\Policies\Microsoft\Edge",                    "HubsSidebarEnabled",        0),
    # Block silent reinstall of Copilot and other pushed apps
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SilentInstalledAppsEnabled", 0),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "PreInstalledAppsEnabled",    0),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "OemPreInstalledAppsEnabled", 0)
)
Write-Step "Applying registry policies..."
foreach ($t in $copilotTweaks) { Set-Reg $t[0] $t[1] $t[2] }

Write-Step "Blocking Ask Copilot context menu entry..."
$blocked = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
if (-not (Test-Path $blocked)) { New-Item -Path $blocked -Force | Out-Null }
New-ItemProperty -Path $blocked -Name "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}" -PropertyType String -Value "" -Force | Out-Null
Write-Done "Copilot policies applied"

# ============================================================
# 2. WINDOWS RECALL / AI SCREEN SNAPSHOTS
# ============================================================
Write-Header "Windows Recall & AI Screen Snapshots"
$recallTweaks = @(
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI", "DisableAIDataAnalysis",  1),
    @("HKCU:\Software\Policies\Microsoft\Windows\WindowsAI", "DisableAIDataAnalysis",  1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI", "TurnOffSavingSnapshots", 1),
    @("HKCU:\Software\Policies\Microsoft\Windows\WindowsAI", "TurnOffSavingSnapshots", 1)
)
Write-Step "Disabling Recall snapshots via policy..."
foreach ($t in $recallTweaks) { Set-Reg $t[0] $t[1] $t[2] }

Write-Step "Removing the Recall optional feature (if present)..."
try {
    Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null
    Write-Done "Recall optional feature disabled"
} catch {
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Recall" -NoRestart -ErrorAction Stop | Out-Null
        Write-Done "Recall optional feature disabled"
    } catch {
        Write-Skip "Recall optional feature not present on this build"
    }
}
Write-Done "Recall disabled"

# ============================================================
# 3. UNINSTALL COPILOT PACKAGES
# ============================================================
Write-Header "Uninstall Copilot Packages"
$provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
$removedAny = $false
foreach ($app in $CopilotPackages) {
    $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Step "Removing $app"
        $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        $removedAny = $true
    }
    $prov = $provisioned | Where-Object { $_.DisplayName -eq $app }
    if ($prov) {
        # COMException from DISM bypasses -ErrorAction; suppress via $ErrorActionPreference
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName | Out-Null
        $ErrorActionPreference = $eap
        $removedAny = $true
    }
}
if ($removedAny) { Write-Done "Copilot packages removed" } else { Write-Skip "No Copilot packages installed" }

Write-Header "Done"
Write-Host "  Copilot and Recall removed. A restart is recommended for policy changes to" -ForegroundColor Green
Write-Host "  fully take effect." -ForegroundColor Green
Write-Host ""
Write-Host "  To keep this applied after feature updates, register the guard: guard" -ForegroundColor DarkGray
Write-Host ""
