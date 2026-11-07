#Requires -Version 5.1
<#
.SYNOPSIS
    Remove built-in Microsoft and third-party bloatware / recommended apps.

.DESCRIPTION
    Uninstalls the per-user and provisioned Appx packages Windows ships or pushes:
    Bing apps, games, Office hub, the new Teams/Outlook, Dev Home, Clipchamp, and
    the usual pre-installed third-party junk (Candy Crush, Spotify, TikTok, etc).

    On-demand only - not re-run by the scheduled guard (daily app-uninstall scans
    are slow and could catch Store apps you later choose to install).

    Safe to re-run - skips packages that are not installed.

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

function Confirm-Default-Yes {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $ans = Read-Host "  $Prompt [Y/n]"
    return ($ans -notmatch '^[Nn]')
}

if ($Help) {
    Write-Host ""
    Write-Host "  debloat - remove built-in and pushed bloatware apps" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: debloat [-Yes] [-Help]" -ForegroundColor White
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

Write-Header "Removing Built-in Bloatware"
$bloatCanary = @('Microsoft.BingNews','Microsoft.MicrosoftSolitaireCollection','Clipchamp.Clipchamp','Microsoft.Copilot') |
    Where-Object { Get-AppxPackage -Name $_ -AllUsers -EA SilentlyContinue }
if (-not $bloatCanary) {
    Write-Skip "Bloatware already removed"
    return
}

if (-not (Confirm-Default-Yes "Remove built-in and pushed bloatware apps?")) {
    Write-Skip "Skipping bloatware removal"
    return
}

$bloatware = @(
    # Carried over from Win10
    "Microsoft.3DBuilder"
    "Microsoft.BingFinance"
    "Microsoft.BingNews"
    "Microsoft.BingSports"
    "Microsoft.BingWeather"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.Messaging"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MixedReality.Portal"
    "Microsoft.NetworkSpeedTest"
    "Microsoft.News"
    "Microsoft.Office.Lens"
    "Microsoft.Office.OneNote"
    "Microsoft.Office.Sway"
    "Microsoft.OneConnect"
    "Microsoft.People"
    "Microsoft.Print3D"
    "Microsoft.SkypeApp"
    "Microsoft.Todos"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "MicrosoftTeams"
    "Microsoft.PowerAutomateDesktop"
    "Clipchamp.Clipchamp"
    "king.com.BubbleWitch3Saga"
    "king.com.CandyCrushSaga"
    "king.com.CandyCrushSodaSaga"
    "Disney.37853D22215E2"
    "SpotifyAB.SpotifyMusic"
    "TikTok"
    "Amazon.com.Amazon"
    # Win11 additions
    "MicrosoftCorporationII.MicrosoftTeams"   # new Teams app (Win11 24H2)
    "Microsoft.OutlookForWindows"             # new Outlook
    "Microsoft.Windows.DevHome"               # Dev Home
    "Microsoft.BingSearch"                    # Bing search integration
    "Microsoft.Windows.Ai.Copilot.Provider"   # Copilot provider
    "Microsoft.549981C3F5F10"                 # Cortana app package
    "Microsoft.MicrosoftJournal"
    "Microsoft.Whiteboard"
    "Microsoft.Copilot"
)
$provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($app in $bloatware) {
    $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Step "Removing $app"
        $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    $prov = $provisioned | Where-Object { $_.DisplayName -eq $app }
    if ($prov) {
        # COMException from DISM bypasses -ErrorAction; suppress via $ErrorActionPreference
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName | Out-Null
        $ErrorActionPreference = $eap
    }
}
Write-Done "Bloatware removal complete"
