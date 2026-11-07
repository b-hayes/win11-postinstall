#Requires -Version 5.1
<#
.SYNOPSIS
    Apply gaming performance tweaks and optionally disable VBS/HVCI.

.DESCRIPTION
    Game Mode on, Game DVR / background recording off, fullscreen optimizations off,
    MMCSS game scheduling priority, foreground-boosted CPU quanta, High Performance
    power plan, and a prompt for Hardware-Accelerated GPU Scheduling (HAGS).

    Separately offers to disable Virtualization Based Security (VBS / HVCI / Memory
    Integrity) for a 5-10% FPS gain and overclocking-tool kernel driver compatibility.

    One-shot by design - not re-run by the scheduled guard.

.PARAMETER Yes
    Accept all prompts (non-interactive): applies gaming tweaks, enables HAGS,
    and disables VBS/HVCI.

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
function Set-RegStr {
    param([string]$Path, [string]$Name, [string]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -Force -ErrorAction Stop
    } catch [System.UnauthorizedAccessException] {
        $rp = $Path -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
        cmd /c "reg add `"$rp`" /v `"$Name`" /t REG_SZ /d `"$Value`" /f" 2>&1 | Out-Null
    }
}

function Confirm-Default-Yes {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $ans = Read-Host "  $Prompt [Y/n]"
    return ($ans -notmatch '^[Nn]')
}

if ($Help) {
    Write-Host ""
    Write-Host "  gaming-tweaks - gaming performance tweaks and optional VBS/HVCI disable" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: gaming-tweaks [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    -Yes   Accept all prompts (applies tweaks, enables HAGS, disables VBS/HVCI)" -ForegroundColor Gray
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

$restartNeeded = $false

# ============================================================
# GAMING PERFORMANCE
# ============================================================
Write-Header "Gaming Performance"
$gameDvr = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -EA SilentlyContinue).GameDVR_Enabled
if ($gameDvr -eq 0) {
    Write-Skip "Gaming tweaks already applied"
} else {
    Write-Host "  Will apply:" -ForegroundColor White
    Write-Host "    - Game Mode on" -ForegroundColor Gray
    Write-Host "    - Game DVR / background recording off" -ForegroundColor Gray
    Write-Host "    - Fullscreen optimizations off (globally)" -ForegroundColor Gray
    Write-Host "    - MMCSS: GPU Priority 8, CPU Priority 6, High scheduling category" -ForegroundColor Gray
    Write-Host "    - CPU scheduler: foreground-boosted quanta (Win32PrioritySeparation 26)" -ForegroundColor Gray
    Write-Host "    - Power plan: High Performance" -ForegroundColor Gray
    Write-Host "    - HAGS: will ask separately" -ForegroundColor Gray
    if (Confirm-Default-Yes "Apply gaming performance tweaks?") {
        Write-Step "Enabling Game Mode..."
        Set-Reg "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1
        Set-Reg "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode"   1

        Write-Step "Disabling Game DVR background recording..."
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
        Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0

        Write-Step "Disabling fullscreen optimizations globally..."
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode"               2
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode"      1
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior"                   2
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_EFSEBehaviorMode"              2

        Write-Step "Applying MMCSS game scheduling priority..."
        $mmcss      = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        $mmcssGames = "$mmcss\Tasks\Games"
        Set-ItemProperty -Path $mmcss -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force
        Set-Reg    $mmcss "SystemResponsiveness" 10
        if (-not (Test-Path $mmcssGames)) { New-Item -Path $mmcssGames -Force | Out-Null }
        Set-Reg    $mmcssGames "GPU Priority" 8
        Set-Reg    $mmcssGames "Priority"     6
        Set-RegStr $mmcssGames "Scheduling Category" "High"
        Set-RegStr $mmcssGames "SFIO Priority"       "High"

        Write-Step "Setting CPU scheduler to foreground-boosted quanta..."
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 26

        Write-Step "Setting High Performance power plan..."
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

        Write-Host ""
        Write-Host "  Hardware-Accelerated GPU Scheduling (HAGS):" -ForegroundColor White
        $hagsVal   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -EA SilentlyContinue).HwSchMode
        $hagsState = if ($hagsVal -eq 2) { "ENABLED" } elseif ($hagsVal -eq 1) { "DISABLED" } else { "not explicitly set" }
        Write-Host "  Current state: $hagsState" -ForegroundColor $(if ($hagsVal -eq 2) { 'Green' } elseif ($hagsVal -eq 1) { 'Yellow' } else { 'DarkGray' })
        Write-Host "  - RTX 40/50 series : turn ON - DLSS frame generation is a hard requirement" -ForegroundColor Gray
        Write-Host "  - RTX 20/30 series : turn OFF - DLSS frame gen unavailable, HAGS costs ~1GB VRAM" -ForegroundColor Gray
        Write-Host "  - AMD RX 9000      : ON recommended (general best practice on RDNA 4)" -ForegroundColor Gray
        Write-Host "  - AMD RX 6000/7000 : OFF - FSR 3/4 and AFMF don't require it, saves VRAM" -ForegroundColor Gray
        Write-Host "  Note: DLSS/FSR upscaling works on all supported cards regardless of HAGS" -ForegroundColor DarkGray
        if (Confirm-Default-Yes "Enable HAGS?") {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
            Write-Done "HAGS enabled"
        } else {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 1
            Write-Done "HAGS disabled"
        }
        $restartNeeded = $true
        Write-Done "Gaming performance tweaks applied"
    } else {
        Write-Skip "Skipping gaming tweaks"
    }
}

# ============================================================
# VBS / HVCI
# ============================================================
Write-Header "Virtualization Based Security (VBS / HVCI)"
$vbsVal  = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -EA SilentlyContinue).EnableVirtualizationBasedSecurity
$hvciVal = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -EA SilentlyContinue).Enabled
if ($vbsVal -eq 0 -and $hvciVal -eq 0) {
    Write-Skip "VBS/HVCI already disabled"
} else {
    Write-Host "  VBS adds a hypervisor layer for security but costs 5-10% average FPS," -ForegroundColor White
    Write-Host "  up to 15% on 1% lows in CPU-bound games. It also blocks kernel drivers" -ForegroundColor White
    Write-Host "  used by overclocking tools like MSI Afterburner, HWiNFO64, and XTU." -ForegroundColor White
    Write-Host "  On a home gaming PC the security trade-off is generally not worth it." -ForegroundColor DarkGray
    $vbsState = if ($vbsVal -eq $null) { "unknown (check Windows Security > Device Security)" } else { "ENABLED" }
    Write-Host "  Current state: $vbsState" -ForegroundColor Yellow
    if (Confirm-Default-Yes "Disable VBS/HVCI?") {
        Write-Step "Disabling VBS / HVCI..."
        $dg   = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
        $hvci = "$dg\Scenarios\HypervisorEnforcedCodeIntegrity"
        $ks   = "$dg\Scenarios\KernelShadowStacks"
        Set-Reg $dg   "EnableVirtualizationBasedSecurity"  0
        Set-Reg $dg   "RequirePlatformSecurityFeatures"    0
        Set-Reg $hvci "Enabled"                            0
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"            "LsaCfgFlags" 0
        Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" "LsaCfgFlags" 0
        if (Test-Path $ks) { Set-Reg $ks "Enabled" 0 }
        Write-Done "VBS/HVCI disabled"
        $restartNeeded = $true
    } else {
        Write-Skip "VBS/HVCI left enabled"
    }
}

Write-Header "Done"
if ($restartNeeded) {
    Write-Host "  A restart is required for HAGS and/or VBS changes to take effect." -ForegroundColor Yellow
} else {
    Write-Host "  No restart required." -ForegroundColor Green
}
