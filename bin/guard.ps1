#Requires -Version 5.1
<#
.SYNOPSIS
    Shared reinstall/nag guard. Keeps Copilot gone and nags disabled after updates.

.DESCRIPTION
    Windows re-adds Copilot and resets nag/ad settings on major feature updates.
    This registers ONE scheduled task that re-runs the feature-update-sensitive
    modules (copilot-removal.ps1 and nag-removal.ps1) daily.

    The task runs a VISIBLE window by default so you can see the result. Use
    -Hidden once you trust it to run silently.

.PARAMETER Run
    Run the guarded modules now (what the scheduled task invokes). Non-interactive.

.PARAMETER Hidden
    Re-register the task to run silently (no window) and exit.

.PARAMETER Unregister
    Remove the scheduled task and exit.

.PARAMETER Yes
    Accept all prompts (non-interactive).

.PARAMETER Help
    Show usage and exit.
#>
param(
    [switch]$Run,
    [switch]$Hidden,
    [switch]$Unregister,
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

$TaskName     = 'Win11PostInstallGuard'
$LegacyTasks  = @('DevtoolsCopilotRemoval')   # task names from older versions, removed on register
$InstallDir   = "$env:ProgramData\Win11PostInstall"
$InstalledGuard = Join-Path $InstallDir 'guard.ps1'
# Feature-update-sensitive modules the guard re-applies (order matters: policies first)
$Modules      = @('copilot-removal.ps1', 'nag-removal.ps1')

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

function Confirm-Default-Yes {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $ans = Read-Host "  $Prompt [Y/n]"
    return ($ans -notmatch '^[Nn]')
}

function Register-GuardTask {
    param([bool]$RunHidden)
    $here = Split-Path $PSCommandPath -Parent
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    # Install guard + guarded modules into ProgramData so the task has a stable copy
    foreach ($f in (@('guard.ps1') + $Modules)) {
        $src = Join-Path $here $f
        $dst = Join-Path $InstallDir $f
        if ((Test-Path $src) -and ($src -ne $dst)) { Copy-Item -Path $src -Destination $dst -Force }
    }

    if ($RunHidden) {
        # Hidden: no window. S4U runs in the user context without an interactive
        # desktop session, so nothing flashes on screen.
        $arg       = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstalledGuard`" -Run -Yes"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest
    } else {
        # Visible: -NoExit keeps the window open so a success/failure is always seen
        $arg       = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstalledGuard`" -Run -Yes"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    }
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    # Daily only (no AtLogOn) so there's no window at every login; StartWhenAvailable
    # catches up shortly after boot if the daily slot was missed.
    $triggers = @((New-ScheduledTaskTrigger -Daily -At 9am))
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
    # Remove tasks left by older versions so they don't double up
    foreach ($legacy in $LegacyTasks) {
        if (Get-ScheduledTask -TaskName $legacy -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $legacy -Confirm:$false
        }
    }
}

if ($Help) {
    Write-Host ""
    Write-Host "  guard - shared scheduled task that re-applies Copilot and nag removal" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: guard [-Run] [-Hidden] [-Unregister] [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    (no args)    Register the guard task (visible window)" -ForegroundColor Gray
    Write-Host "    -Run         Run the guarded modules now (used by the task)" -ForegroundColor Gray
    Write-Host "    -Hidden      Re-register the task to run silently and exit" -ForegroundColor Gray
    Write-Host "    -Unregister  Remove the task and exit" -ForegroundColor Gray
    Write-Host "    -Yes         Accept all prompts (non-interactive)" -ForegroundColor Gray
    Write-Host "    -Help        Show this help and exit" -ForegroundColor Gray
    Write-Host ""
    return
}

# Self-elevate if not already admin
if (-not (Test-Admin)) {
    Write-Warn "Administrator rights required - relaunching elevated..."
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File', "`"$PSCommandPath`"")
    if ($Run)        { $argList += '-Run' }
    if ($Hidden)     { $argList += '-Hidden' }
    if ($Unregister) { $argList += '-Unregister' }
    if ($Yes)        { $argList += '-Yes' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host "  Elevation was cancelled or failed. Run this from an elevated shell." -ForegroundColor Red
    }
    return
}

# ============================================================
# RUN MODE (invoked by the scheduled task)
# ============================================================
if ($Run) {
    $here = Split-Path $PSCommandPath -Parent
    foreach ($m in $Modules) {
        $path = Join-Path $here $m
        if (Test-Path $path) {
            Write-Header "Guard: $m"
            & $path -Yes
        } else {
            Write-Warn "Module not found next to guard: $m"
        }
    }
    return
}

# ============================================================
# UNREGISTER MODE
# ============================================================
if ($Unregister) {
    Write-Header "Remove Guard Task"
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Done "Scheduled task '$TaskName' removed"
    } else {
        Write-Skip "No scheduled task '$TaskName' found"
    }
    return
}

# ============================================================
# HIDE MODE (re-register to run silently)
# ============================================================
if ($Hidden) {
    Write-Header "Hide Guard Task"
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Write-Skip "No scheduled task '$TaskName' found - register it first (run guard with no args)"
        return
    }
    Write-Step "Re-registering '$TaskName' to run silently (no window)..."
    Register-GuardTask -RunHidden $true
    Write-Done "Guard now runs hidden. Make it visible again with: guard -Unregister, then re-run guard"
    return
}

# ============================================================
# REGISTER MODE (default)
# ============================================================
Write-Header "Reinstall / Nag Guard"
# Always clear any legacy-named tasks, even if the current guard is already registered
foreach ($legacy in $LegacyTasks) {
    if (Get-ScheduledTask -TaskName $legacy -ErrorAction SilentlyContinue) {
        Write-Step "Removing leftover task from an older version: $legacy"
        Unregister-ScheduledTask -TaskName $legacy -Confirm:$false
    }
}
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Skip "Guard task '$TaskName' already registered"
    Write-Host "  Make it silent with: guard -Hidden   Remove it with: guard -Unregister" -ForegroundColor DarkGray
} else {
    Write-Host "  Windows re-adds Copilot and resets nag/ad settings on major feature" -ForegroundColor Cyan
    Write-Host "  updates. A scheduled task re-runs copilot-removal and nag-removal daily" -ForegroundColor Cyan
    Write-Host "  to keep them gone." -ForegroundColor Cyan
    Write-Host "  It runs in a VISIBLE window at first so you can read the result." -ForegroundColor Cyan
    if (Confirm-Default-Yes "Register the guard task?") {
        Write-Step "Installing modules to $InstallDir and registering '$TaskName'..."
        Register-GuardTask -RunHidden $false
        Write-Done "Guard registered (run silently later with: guard -Hidden)"
    } else {
        Write-Skip "Skipping guard registration"
    }
}
