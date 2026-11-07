#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 post-install setup script.
    Run once after a clean Windows install.
#>

$ErrorActionPreference = 'Continue'

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
}
function Write-Step { param([string]$T); Write-Host "  [*] $T" -ForegroundColor Yellow }
function Write-Done { param([string]$T); Write-Host "  [+] $T" -ForegroundColor Green }
function Write-Skip { param([string]$T); Write-Host "  [-] $T" -ForegroundColor DarkGray }

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
function Test-Internet {
    try {
        $null = Invoke-WebRequest "http://www.msftconnecttest.com/connecttest.txt" -TimeoutSec 5 -UseBasicParsing
        return $true
    } catch { return $false }
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue
    return [bool]$sm.PendingFileRenameOperations
}
function Test-UpdateActive {
    foreach ($n in @('TiWorker','TrustedInstaller','MoUsoCoreWorker','UsoClient','wuauclt')) {
        if (Get-Process -Name $n -EA SilentlyContinue) { return $true }
    }
    return $false
}
function Skip-Flaky {
    param([string]$Name)
    Write-Header $Name
    Write-Skip "Deferred until after Windows Updates + reboot (menu re-opens to finish)"
}

# URL the post-reboot RunOnce re-launch pulls from (same as bootstrap.ps1)
$BootstrapUrl = 'https://raw.githubusercontent.com/b-hayes/win11-postinstall/main/bootstrap.ps1'

$restartReasons = @()

# ============================================================
# OVERVIEW
# ============================================================
Write-Host ""
Write-Host ("=" * 50) -ForegroundColor Magenta
Write-Host "  Windows 11 Post-Install Setup" -ForegroundColor Magenta
Write-Host ("=" * 50) -ForegroundColor Magenta
Write-Host ""
Write-Host "  This script will perform the following steps:" -ForegroundColor White
Write-Host ""
Write-Host "  [1]  Computer Name        - rename this machine" -ForegroundColor Gray
Write-Host "  [2]  Telemetry & Privacy  - registry tweaks to kill data collection" -ForegroundColor Gray
Write-Host "  [3]  Cortana & Web Search - disable Cortana, Start menu web results" -ForegroundColor Gray
Write-Host "  [3b] Copilot & Recall     - bin/copilot-removal (Copilot + Recall policies, package uninstall)" -ForegroundColor Gray
Write-Host "  [4]  System Nags & Ads    - bin/nag-removal (SCOOBE, suggestions, lock-screen tips, widgets, search highlights)" -ForegroundColor Gray
Write-Host "  [4b] Reinstall / Nag Guard - bin/guard: daily task re-applies Copilot + nag removal after updates" -ForegroundColor Gray
Write-Host "  [4d] Accessibility Prompts- disable Sticky/Filter/Toggle Keys shortcut popups" -ForegroundColor Gray
Write-Host "  [4e] Windows Update       - P2P LAN-only, no auto-reboot, no silent sign-in, no app relaunch" -ForegroundColor Gray
Write-Host "  [5]  Bloatware Removal    - bin/debloat (uninstall built-in Microsoft/third-party apps)" -ForegroundColor Gray
Write-Host "  [6]  Hibernation          - optional: disable hiberfil.sys and reclaim disk space" -ForegroundColor Gray
Write-Host "  [7]  Locale / Region      - restore your real language, region and timezone" -ForegroundColor Gray
Write-Host "  [8]  Gaming & VBS         - bin/gaming-tweaks (Game Mode, DVR/FSO off, MMCSS, power plan, HAGS, VBS)" -ForegroundColor Gray
Write-Host "  [10] Brave Browser        - optional install via winget + set as default browser" -ForegroundColor Gray
Write-Host "  [10b] Edge De-Nag         - kill Edge first-run splash, recommendations, sidebar, new-tab feed" -ForegroundColor Gray
Write-Host "  [11] Take Ownership Menu  - adds Take Ownership to right-click for files/folders/drives" -ForegroundColor Gray
Write-Host "  [12] Dark Mode & Appearance - dark mode, accent on taskbar/borders, auto accent from wallpaper" -ForegroundColor Gray
Write-Host "  [13] Explorer Settings    - hidden files, file extensions, separate process, start at This PC" -ForegroundColor Gray
Write-Host "  [14] Chris Titus WinUtil  - optional interactive tweaks and software install" -ForegroundColor Gray
Write-Host "  [15] Extra UI & System    - search box, taskbar, transparency, IE removal, misc tweaks" -ForegroundColor Gray
Write-Host ""
Write-Host "  Steps already done will be skipped automatically." -ForegroundColor DarkGray
Write-Host "  A restart will be offered at the end if anything needs it." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press any key to begin..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# ============================================================
# NEW MACHINE / PRE-UPDATE DETECTION
# ============================================================
Write-Header "New Machine Check"
$pendingReboot = Test-PendingReboot
$updateActive  = Test-UpdateActive
$preUpdatePass = $false
if ($pendingReboot -or $updateActive) {
    Write-Host "  Heads up: Windows Update looks active or a reboot is already pending." -ForegroundColor Yellow
}
Write-Host "  On a brand-new install it's best to let Windows Updates fully finish and reboot" -ForegroundColor White
Write-Host "  BEFORE the flaky steps run - feature updates can re-enable VBS, re-add some apps," -ForegroundColor Gray
Write-Host "  and bring back the 'finish setting up' nag." -ForegroundColor Gray
$defaultNew = if ($pendingReboot -or $updateActive) { 'Y/n' } else { 'y/N' }
$newMachine = Read-Host "  New machine with Windows Updates not yet finished? [$defaultNew]"
# Default follows the detection hint: yes when an update/reboot is pending, otherwise no
$newMachine = if ($newMachine) { $newMachine } elseif ($pendingReboot -or $updateActive) { 'y' } else { 'n' }
if ($newMachine -match '^[Yy]') {
    $preUpdatePass = $true
    Write-Host ""
    Write-Host "  Pre-update mode: applying only the safe, durable tweaks now and SKIPPING the" -ForegroundColor Cyan
    Write-Host "  flaky steps (bloatware, Brave, WinUtil, extra UI)." -ForegroundColor Cyan
    Write-Host "  This menu will re-open automatically after your next reboot to finish them." -ForegroundColor Cyan
} else {
    Write-Host "  Full run: all steps offered." -ForegroundColor DarkGray
}

# ============================================================
# 1. COMPUTER NAME
# ============================================================
Write-Header "Computer Name"
$currentName = $env:COMPUTERNAME
Write-Host "  Current name: $currentName" -ForegroundColor DarkGray
$newName = Read-Host "  Enter new name (1-15 chars, letters/numbers/hyphens), blank = keep"
if ($newName -and $newName -ne $currentName) {
    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        Write-Done "Will be renamed to '$newName' after restart"
        $restartReasons += "Computer rename to '$newName'"
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Names must be 1-15 characters, letters/numbers/hyphens only, no spaces." -ForegroundColor DarkGray
    }
} else {
    Write-Skip "Computer name unchanged ($currentName)"
}

# ============================================================
# 2. TELEMETRY & PRIVACY
# ============================================================
Write-Header "Telemetry & Privacy"
$telCheck  = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -EA SilentlyContinue).AllowTelemetry
$diagCheck = (Get-Service DiagTrack -EA SilentlyContinue).StartType
if ($telCheck -eq 0 -and $diagCheck -eq 'Disabled') {
    Write-Skip "Telemetry already disabled"
} else {
    Write-Step "Applying registry tweaks..."
    $privacyTweaks = @(
        # Core telemetry level
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",                                                    "AllowTelemetry",                               0),
        @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",                                     "AllowTelemetry",                               0),
        @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",                                     "MaxTelemetryAllowed",                          0),
        # Advertising ID
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo",                                             "Enabled",                                      0),
        # Feedback / SIUF
        @("HKCU:\Software\Microsoft\Siuf\Rules",                                                                         "NumberOfSIUFInPeriod",                         0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",                                                    "DoNotShowFeedbackNotifications",               1),
        # Activity history / Timeline
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",                                                            "EnableActivityFeed",                           0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",                                                            "PublishUserActivities",                        0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System",                                                            "UploadUserActivities",                         0),
        # App launch tracking
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",                                           "Start_TrackProgs",                             0),
        # (Start menu suggestions / tailored experiences now live in bin/nag-removal.ps1)
        # Error reporting
        @("HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting",                                                    "Disabled",                                     1),
        # Location
        @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}", "SensorPermissionState",                        0),
        @("HKLM:\System\CurrentControlSet\Services\lfsvc\Service\Configuration",                                         "Status",                                       0)
    )
    foreach ($t in $privacyTweaks) { Set-Reg $t[0] $t[1] $t[2] }
    Write-Done "Registry tweaks applied"

    Write-Step "Stopping telemetry services..."
    foreach ($svc in @('DiagTrack', 'dmwappushservice', 'diagnosticshub.standardcollector.service')) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Write-Done "Telemetry services disabled"
}

# ============================================================
# 3. CORTANA & WEB SEARCH
#    (Copilot & Recall are handled separately in Section 3b via bin/copilot-removal)
# ============================================================
Write-Header "Cortana & Web Search"
$cortanaCheck = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -EA SilentlyContinue).BingSearchEnabled
$webCheck     = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -EA SilentlyContinue).DisableWebSearch
if ($cortanaCheck -eq 0 -and $webCheck -eq 1) {
    Write-Skip "Cortana and web search already disabled"
} else {
    $cortanaTweaks = @(
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",       "AllowCortana",                   0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",       "AllowCortanaAboveLock",          0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",       "ConnectedSearchUseWeb",          0),
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",       "DisableWebSearch",               1),
        @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search",         "BingSearchEnabled",              0),
        @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search",         "CortanaConsent",                 0),
        @("HKCU:\Software\Microsoft\Personalization\Settings",              "AcceptedPrivacyPolicy",          0),
        @("HKCU:\Software\Microsoft\InputPersonalization",                  "RestrictImplicitTextCollection", 1),
        @("HKCU:\Software\Microsoft\InputPersonalization",                  "RestrictImplicitInkCollection",  1),
        @("HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore", "HarvestContacts",                0),
        # Block Bing suggestions in Explorer address bar
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer",             "DisableSearchBoxSuggestions",    1)
        # (Search highlights and pushed-app content-delivery keys now live in bin/nag-removal.ps1)
    )
    Write-Step "Applying registry tweaks..."
    foreach ($t in $cortanaTweaks) { Set-Reg $t[0] $t[1] $t[2] }

    Write-Done "Cortana and Start menu web search disabled"
}

# ============================================================
# 3b. COPILOT & RECALL REMOVAL
#     Delegated to bin/copilot-removal.ps1 - the single source of truth for
#     Copilot/Recall policies and package uninstall. The daily guard (section 4b)
#     re-applies it after feature updates.
# ============================================================
Write-Header "Copilot & Recall Removal"
$copilotScript = Join-Path $PSScriptRoot "..\..\bin\copilot-removal.ps1"
if (-not (Test-Path $copilotScript)) {
    Write-Host "  bin/copilot-removal.ps1 not found - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Runs bin/copilot-removal: removes Copilot and Windows Recall." -ForegroundColor White
    $doCopilot = Read-Host "  Run Copilot & Recall removal now? [Y/n]"
    if ($doCopilot -notmatch '^[Nn]') {
        # This script already runs elevated, so invoke inline (no re-elevation prompt)
        & $copilotScript
        $restartReasons += "Copilot / Recall policies applied - take full effect after restart"
    } else {
        Write-Skip "Skipping Copilot & Recall removal (run later with: bin/copilot-removal)"
    }
}

# ============================================================
# 4. SYSTEM NAGS & ADS
#    Delegated to bin/nag-removal.ps1 - the single source of truth for every
#    nag/ad/suggestion tweak. The daily guard (section 4b) re-applies it.
# ============================================================
Write-Header "System Nags & Ads"
$nagScript = Join-Path $PSScriptRoot "..\..\bin\nag-removal.ps1"
if (-not (Test-Path $nagScript)) {
    Write-Host "  bin/nag-removal.ps1 not found - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Runs bin/nag-removal: SCOOBE 'finish setting up' page, setup toast, Start" -ForegroundColor White
    Write-Host "  suggestions/recommendations, OneDrive banners, lock-screen tips (Spotlight" -ForegroundColor Gray
    Write-Host "  wallpapers kept), widgets, Teams icon, and search highlights." -ForegroundColor Gray
    $doNags = Read-Host "  Disable system nags and ads now? [Y/n]"
    if ($doNags -notmatch '^[Nn]') {
        # Already elevated - invoke inline (no re-elevation prompt)
        & $nagScript
    } else {
        Write-Skip "Skipping nag removal (run later with: bin/nag-removal)"
    }
}

# ============================================================
# 4b. REINSTALL / NAG GUARD
#     Delegated to bin/guard.ps1 - one scheduled task that re-runs
#     copilot-removal and nag-removal after feature updates reset them.
# ============================================================
Write-Header "Reinstall / Nag Guard"
$guardScript = Join-Path $PSScriptRoot "..\..\bin\guard.ps1"
if (-not (Test-Path $guardScript)) {
    Write-Host "  bin/guard.ps1 not found - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Feature updates re-add Copilot and reset nag settings. A single scheduled" -ForegroundColor White
    Write-Host "  task can re-run Copilot and nag removal at logon and daily to keep them gone." -ForegroundColor Gray
    $doGuard = Read-Host "  Register the guard task? [Y/n]"
    if ($doGuard -notmatch '^[Nn]') {
        & $guardScript -Yes
    } else {
        Write-Skip "Skipping guard (register later with: bin/guard)"
    }
}

# ============================================================
# 4d. ACCESSIBILITY SHORTCUT PROMPTS
# ============================================================
Write-Header "Accessibility Shortcut Prompts"
$stickyFlags = (Get-ItemProperty "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -EA SilentlyContinue).Flags
if ($stickyFlags -eq "506") {
    Write-Skip "Accessibility shortcut prompts already disabled"
} else {
    Write-Step "Disabling Sticky / Filter / Toggle Keys activation shortcuts..."
    # String (REG_SZ) values - Flags with the hotkey/on bits cleared
    Set-RegStr "HKCU:\Control Panel\Accessibility\StickyKeys"       "Flags" "506"
    Set-RegStr "HKCU:\Control Panel\Accessibility\ToggleKeys"       "Flags" "58"
    Set-RegStr "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122"
    Write-Done "Sticky Keys (5x Shift), Filter Keys, and Toggle Keys prompts disabled"
}

# ============================================================
# 4e. WINDOWS UPDATE BEHAVIOR
# ============================================================
Write-Header "Windows Update Behavior"
$doMode = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -EA SilentlyContinue).DODownloadMode
$noReboot = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -EA SilentlyContinue).NoAutoRebootWithLoggedOnUsers
if ($doMode -eq 1 -and $noReboot -eq 1) {
    Write-Skip "Update sharing and reboot behavior already set"
} else {
    Write-Step "Limiting update P2P sharing to the local network only..."
    # 1 = peer only on the same NAT/LAN - never uploads to the internet
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 1

    Write-Step "Stopping auto-reboots while signed in..."
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" 1

    Write-Step "Blocking silent auto-sign-in after an update reboot..."
    # Stops Windows signing you back in overnight to 'finish' an update
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DisableAutomaticRestartSignOn" 1

    Write-Step "Disabling app relaunch after sign-in..."
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "RestartApps" 0

    Write-Done "P2P set to LAN-only, no auto-reboots, no silent sign-in, no app relaunch"
}

# ============================================================
# 5. BLOATWARE REMOVAL
# ============================================================
#    Delegated to bin/debloat.ps1 - the single source of truth for the app list.
if ($preUpdatePass) { Skip-Flaky "Bloatware Removal" } else {
Write-Header "Bloatware Removal"
$debloatScript = Join-Path $PSScriptRoot "..\..\bin\debloat.ps1"
if (-not (Test-Path $debloatScript)) {
    Write-Host "  bin/debloat.ps1 not found - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Runs bin/debloat: uninstalls built-in and pushed Microsoft/third-party apps." -ForegroundColor White
    $doDebloat = Read-Host "  Remove bloatware now? [Y/n]"
    if ($doDebloat -notmatch '^[Nn]') {
        # Already elevated - invoke inline (no re-elevation prompt)
        & $debloatScript -Yes
    } else {
        Write-Skip "Skipping bloatware removal (run later with: bin/debloat)"
    }
}
}

# ============================================================
# 6. HIBERNATION
# ============================================================
Write-Header "Hibernation"
$hiberEnabled = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -EA SilentlyContinue).HibernateEnabled
if ($hiberEnabled -eq 0) {
    Write-Skip "Hibernation already disabled"
} else {
    Write-Host "  Disabling hibernation deletes hiberfil.sys, freeing disk space equal to your RAM size." -ForegroundColor White
    Write-Host "  Only useful if you never hibernate or use fast startup." -ForegroundColor DarkGray
    $disableHiber = Read-Host "  Disable hibernation? [y/N]"
    if ($disableHiber -match '^[Yy]') {
        powercfg /h off
        Write-Done "Hibernation disabled"
    } else {
        Write-Skip "Hibernation left enabled"
    }
}

# ============================================================
# 7. LOCALE / REGION
# ============================================================
Write-Header "Regional & Language Settings"
$currentCulture = (Get-Culture).Name
$currentTz      = (Get-TimeZone).Id
if ($currentCulture -ne 'en-001') {
    Write-Skip "Locale already set to $currentCulture / $currentTz"
} else {
    Write-Host "  Your install was set to a neutral locale to avoid region-specific bloat." -ForegroundColor White
    Write-Host "  Pick your real locale now." -ForegroundColor White
    Write-Host ""
    Write-Host "   1  en-US  English - United States"
    Write-Host "   2  en-GB  English - United Kingdom"
    Write-Host "   3  en-AU  English - Australia"
    Write-Host "   4  en-CA  English - Canada"
    Write-Host "   5  de-DE  German - Germany"
    Write-Host "   6  fr-FR  French - France"
    Write-Host "   7  es-ES  Spanish - Spain"
    Write-Host "   8  es-MX  Spanish - Mexico"
    Write-Host "   9  pt-BR  Portuguese - Brazil"
    Write-Host "  10  ja-JP  Japanese - Japan"
    Write-Host "  11  nl-NL  Dutch - Netherlands"
    Write-Host "  12  ko-KR  Korean - South Korea"
    Write-Host "  13  zh-CN  Chinese Simplified - China"
    Write-Host ""

    $localeInput = Read-Host "  Number from list, or type your own BCP-47 tag (e.g. sv-SE), blank = skip"

    $localeMap = @{
        "1"="en-US"; "2"="en-GB";  "3"="en-AU"; "4"="en-CA"; "5"="de-DE";
        "6"="fr-FR"; "7"="es-ES";  "8"="es-MX"; "9"="pt-BR"; "10"="ja-JP";
        "11"="nl-NL"; "12"="ko-KR"; "13"="zh-CN"
    }
    $geoMap = @{
        "en-US"=244; "en-GB"=242; "en-AU"=12;  "en-CA"=39;  "de-DE"=94;
        "fr-FR"=84;  "es-ES"=217; "es-MX"=166; "pt-BR"=32;  "ja-JP"=122;
        "nl-NL"=176; "ko-KR"=134; "zh-CN"=45
    }
    $tzMap = @{
        "en-AU"="AUS Eastern Standard Time"; "en-US"="Eastern Standard Time"
        "en-GB"="GMT Standard Time";         "en-CA"="Eastern Standard Time"
        "de-DE"="W. Europe Standard Time";   "fr-FR"="Romance Standard Time"
        "es-ES"="Romance Standard Time";     "es-MX"="Central Standard Time (Mexico)"
        "pt-BR"="E. South America Standard Time"; "ja-JP"="Tokyo Standard Time"
        "nl-NL"="W. Europe Standard Time";   "ko-KR"="Korea Standard Time"
        "zh-CN"="China Standard Time"
    }

    if ($localeInput) {
        $locale = if ($localeMap.ContainsKey($localeInput)) { $localeMap[$localeInput] } else { $localeInput }
        Write-Step "Setting locale to $locale..."
        try {
            Set-WinUserLanguageList $locale -Force
            Set-Culture             -CultureInfo $locale
            Set-WinSystemLocale     -SystemLocale $locale
            if ($geoMap.ContainsKey($locale)) { Set-WinHomeLocation -GeoId $geoMap[$locale] }
            Write-Done "Locale set to $locale"
            $restartReasons += "Locale changed to $locale"
        } catch {
            Write-Host "  Could not apply locale '$locale'. Check it is a valid BCP-47 tag." -ForegroundColor Red
        }
    } else {
        Write-Skip "Locale unchanged"
    }

    Write-Host ""
    Write-Host "  Common timezones:" -ForegroundColor White
    Write-Host "   1  AUS Eastern Standard Time      (Sydney, Melbourne, Hobart - DST observed)" -ForegroundColor Gray
    Write-Host "   2  E. Australia Standard Time     (Brisbane, Queensland - no DST)" -ForegroundColor Gray
    Write-Host "   3  Cen. Australia Standard Time   (Adelaide - DST observed)" -ForegroundColor Gray
    Write-Host "   4  AUS Central Standard Time      (Darwin - no DST)" -ForegroundColor Gray
    Write-Host "   5  W. Australia Standard Time     (Perth)" -ForegroundColor Gray
    Write-Host "   6  Eastern Standard Time          (New York, Toronto)" -ForegroundColor Gray
    Write-Host "   7  Central Standard Time          (Chicago, Dallas)" -ForegroundColor Gray
    Write-Host "   8  Mountain Standard Time         (Denver, Phoenix)" -ForegroundColor Gray
    Write-Host "   9  Pacific Standard Time          (Los Angeles, Vancouver)" -ForegroundColor Gray
    Write-Host "  10  GMT Standard Time              (London, Dublin)" -ForegroundColor Gray
    Write-Host "  11  W. Europe Standard Time        (Berlin, Amsterdam, Paris)" -ForegroundColor Gray
    Write-Host "  12  Tokyo Standard Time            (Japan)" -ForegroundColor Gray
    Write-Host "  13  Korea Standard Time            (Seoul)" -ForegroundColor Gray
    Write-Host "  14  China Standard Time            (Beijing, Shanghai)" -ForegroundColor Gray

    $tzList = @{
        "1"="AUS Eastern Standard Time"; "2"="E. Australia Standard Time"
        "3"="Cen. Australia Standard Time"; "4"="AUS Central Standard Time"
        "5"="W. Australia Standard Time"; "6"="Eastern Standard Time"
        "7"="Central Standard Time"; "8"="Mountain Standard Time"
        "9"="Pacific Standard Time"; "10"="GMT Standard Time"
        "11"="W. Europe Standard Time"; "12"="Tokyo Standard Time"
        "13"="Korea Standard Time"; "14"="China Standard Time"
    }

    $suggestedTz = if ($localeInput -and $tzMap.ContainsKey($locale)) { $tzMap[$locale] } else { $null }
    if ($suggestedTz) {
        Write-Host ""
        Write-Host "  Suggested for $locale`: $suggestedTz" -ForegroundColor DarkGray
    }

    $tzInput = Read-Host "  Number from list, or type a Windows timezone ID, blank = skip"
    if ($tzInput) {
        $tz = if ($tzList.ContainsKey($tzInput)) { $tzList[$tzInput] } else { $tzInput }
        try {
            Set-TimeZone -Id $tz
            Write-Done "Timezone set to $tz"
            Write-Step "Syncing clock..."
            Start-Service W32Time -ErrorAction SilentlyContinue
            w32tm /resync /force 2>&1 | Out-Null
            Write-Done "Clock synced"
        } catch {
            Write-Host "  Could not set timezone '$tz'." -ForegroundColor Red
        }
    } elseif ($suggestedTz) {
        try {
            Set-TimeZone -Id $suggestedTz
            Write-Done "Timezone set to $suggestedTz (auto from locale)"
            Write-Step "Syncing clock..."
            Start-Service W32Time -ErrorAction SilentlyContinue
            w32tm /resync /force 2>&1 | Out-Null
            Write-Done "Clock synced"
        } catch {
            Write-Host "  Could not set timezone '$suggestedTz'." -ForegroundColor Red
        }
    } else {
        Write-Skip "Timezone unchanged"
    }
}

# ============================================================
# 8. GAMING & VBS
#    Delegated to bin/gaming-tweaks.ps1 - gaming performance tweaks and the
#    optional VBS/HVCI disable, with their own HAGS/VBS prompts.
# ============================================================
Write-Header "Gaming & VBS"
$gamingScript = Join-Path $PSScriptRoot "..\..\bin\gaming-tweaks.ps1"
if (-not (Test-Path $gamingScript)) {
    Write-Host "  bin/gaming-tweaks.ps1 not found - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Runs bin/gaming-tweaks: Game Mode, DVR/FSO off, MMCSS, power plan, HAGS," -ForegroundColor White
    Write-Host "  and an optional VBS/HVCI disable for a 5-10% FPS gain." -ForegroundColor Gray
    if ($preUpdatePass) {
        Write-Host "  (Registry-only - safe pre-update; HAGS will take effect on the reboot." -ForegroundColor DarkGray
        Write-Host "   A later feature upgrade can re-enable VBS - re-run this if so.)" -ForegroundColor DarkGray
    }
    $doGaming = Read-Host "  Run gaming & VBS tweaks now? [Y/n]"
    if ($doGaming -notmatch '^[Nn]') {
        # Already elevated - invoke inline (no re-elevation prompt)
        & $gamingScript
        $restartReasons += "Gaming / VBS tweaks - HAGS and VBS changes take effect after restart"
    } else {
        Write-Skip "Skipping gaming & VBS tweaks (run later with: bin/gaming-tweaks)"
    }
}

# ============================================================
# 10. BRAVE BROWSER
# ============================================================
if ($preUpdatePass) { Skip-Flaky "Brave Browser" } else {
Write-Header "Brave Browser"
$braveExe = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
if (Test-Path $braveExe) {
    Write-Skip "Brave already installed"
} else {
    $installBrave = Read-Host "  Install Brave Browser? [Y/n]"
    if ($installBrave -notmatch '^[Nn]') {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Step "Checking internet connection..."
            $hasInternet = Test-Internet
            if (-not $hasInternet) {
                Write-Host "  No internet detected - connect first, then re-run this step." -ForegroundColor Yellow
                Write-Host "  Manual install: winget install --id Brave.Brave" -ForegroundColor DarkGray
            } else {
                Write-Step "Resetting winget sources..."
                winget source reset --force 2>&1 | Out-Null
                Write-Step "Installing Brave via winget..."
                winget install --id Brave.Brave -e --source winget `
                      --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -eq 0) {
                    Write-Done "Brave installed"
                } else {
                    Write-Host "  winget install failed (exit $LASTEXITCODE) - download from brave.com" -ForegroundColor Yellow
                }

                $setDefault = Read-Host "  Set Brave as default browser? [Y/n]"
                if ($setDefault -notmatch '^[Nn]') {
                    Write-Step "Suppressing Edge default-browser nag (policy key)..."
                    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "DefaultBrowserSettingEnabled" 0

                    Write-Step "Bootstrapping NuGet and installing PS-SFTA..."
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
                    if (-not (Get-PSRepository -Name PSGallery -EA SilentlyContinue)) {
                        Register-PSRepository -Default -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                    Install-Module -Name PS-SFTA -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue

                    if (Get-Module -ListAvailable -Name PS-SFTA) {
                        Import-Module PS-SFTA
                        Write-Step "Writing UserChoice associations for Brave..."
                        Set-PTA -ProgId BraveHTML -Protocol http
                        Set-PTA -ProgId BraveHTML -Protocol https
                        Set-FTA -ProgId BraveHTML -Extension .html
                        Set-FTA -ProgId BraveHTML -Extension .htm
                        Write-Done "Brave is now the default browser - Edge nag suppressed"
                    } else {
                        Write-Host "  PS-SFTA could not be installed." -ForegroundColor Yellow
                        Write-Host "  Opening Default Apps - select Brave Browser and click Set default." -ForegroundColor White
                        Start-Process "ms-settings:defaultapps"
                    }
                } else {
                    Write-Skip "Skipping default browser change"
                }
            }
        } else {
            Write-Host "  winget not found. Download Brave manually from brave.com" -ForegroundColor Yellow
        }
    } else {
        Write-Skip "Skipping Brave"
    }
}
}

# ============================================================
# 10b. MICROSOFT EDGE DE-NAG
# ============================================================
Write-Header "Microsoft Edge De-Nag"
$edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$edgeCheck = (Get-ItemProperty $edgePol -Name "HideFirstRunExperience" -EA SilentlyContinue).HideFirstRunExperience
if ($edgeCheck -eq 1) {
    Write-Skip "Edge nag screens already suppressed"
} else {
    Write-Step "Suppressing Edge first-run, recommendations, sidebar, and new-tab clutter..."
    $edgeTweaks = @(
        @($edgePol, "HideFirstRunExperience",                 1),  # no first-run splash
        @($edgePol, "ShowRecommendationsEnabled",              0),  # no 'recommended' nags
        @($edgePol, "SpotlightExperiencesAndRecommendationsEnabled", 0),
        @($edgePol, "StartupBoostEnabled",                     0),  # no background preload
        @($edgePol, "BackgroundModeEnabled",                   0),  # don't keep running after close
        @($edgePol, "HubsSidebarEnabled",                      0),  # no sidebar
        @($edgePol, "WebWidgetAllowed",                        0),  # no Edge bar widget
        @($edgePol, "EdgeShoppingAssistantEnabled",            0),
        @($edgePol, "ShowMicrosoftRewards",                    0),
        @($edgePol, "PersonalizationReportingEnabled",         0),
        @($edgePol, "NewTabPageContentEnabled",                0),  # no news feed on new tab
        @($edgePol, "NewTabPageQuickLinksEnabled",             0),
        @($edgePol, "DefaultBrowserSettingEnabled",            0)   # no 'make Edge default' nag
    )
    foreach ($t in $edgeTweaks) { Set-Reg $t[0] $t[1] $t[2] }
    Write-Done "Edge nag screens and clutter suppressed"
}

# ============================================================
# 11. TAKE OWNERSHIP CONTEXT MENU
# ============================================================
Write-Header "Take Ownership Context Menu"
$hkcr        = [Microsoft.Win32.Registry]::ClassesRoot
$takeOwnKey  = $hkcr.OpenSubKey('*\shell\TakeOwnership')
if ($takeOwnKey) {
    $takeOwnKey.Close()
    Write-Skip "Take Ownership already in context menu"
} else {
    Write-Host "  Adds 'Take Ownership' to the right-click menu for files, folders, and drives." -ForegroundColor White
    Write-Host "  Useful when Windows treats your other drives as belonging to a previous install." -ForegroundColor DarkGray
    $addTakeOwn = Read-Host "  Add to context menu? [Y/n]"
    if ($addTakeOwn -notmatch '^[Nn]') {
        Write-Step "Writing registry entries..."

        $fileCmd  = 'powershell -windowstyle hidden -command "Start-Process cmd -ArgumentList ''/c takeown /f \"%1\" && icacls \"%1\" /grant *S-1-3-4:F /t /c /l'' -Verb runAs"'
        $dirCmd   = 'powershell -windowstyle hidden -command "$Y = ($null | choice).Substring(1,1); Start-Process cmd -ArgumentList (''/c takeown /f \"%1\" /r /d '' + $Y + '' && icacls \"%1\" /grant *S-1-3-4:F /t /c /l /q'') -Verb runAs"'
        $driveCmd = 'cmd.exe /c takeown /f "%1\" /r /d y && icacls "%1\" /grant *S-1-3-4:F /t /c'
        $driveFilter = 'NOT (System.ItemPathDisplay:="C:\")'
        $dirFilter   = 'NOT (System.ItemPathDisplay:="C:\Users" OR System.ItemPathDisplay:="C:\ProgramData" OR System.ItemPathDisplay:="C:\Windows" OR System.ItemPathDisplay:="C:\Windows\System32" OR System.ItemPathDisplay:="C:\Program Files" OR System.ItemPathDisplay:="C:\Program Files (x86)")'

        # Files
        $k = $hkcr.CreateSubKey('*\shell\TakeOwnership', $true)
        $k.SetValue('', 'Take Ownership'); $k.SetValue('HasLUAShield', ''); $k.SetValue('NoWorkingDirectory', ''); $k.SetValue('NeverDefault', '')
        $c = $k.CreateSubKey('command', $true); $c.SetValue('', $fileCmd); $c.SetValue('IsolatedCommand', $fileCmd); $c.Close(); $k.Close()

        # Folders
        $k = $hkcr.CreateSubKey('Directory\shell\TakeOwnership', $true)
        $k.SetValue('', 'Take Ownership'); $k.SetValue('AppliesTo', $dirFilter); $k.SetValue('HasLUAShield', ''); $k.SetValue('NoWorkingDirectory', ''); $k.SetValue('Position', 'middle')
        $c = $k.CreateSubKey('command', $true); $c.SetValue('', $dirCmd); $c.SetValue('IsolatedCommand', $dirCmd); $c.Close(); $k.Close()

        # Drives - runas verb for automatic UAC elevation, excludes C:\
        $k = $hkcr.CreateSubKey('Drive\shell\runas', $true)
        $k.SetValue('', 'Take Ownership'); $k.SetValue('AppliesTo', $driveFilter); $k.SetValue('HasLUAShield', ''); $k.SetValue('NoWorkingDirectory', ''); $k.SetValue('Position', 'middle')
        $c = $k.CreateSubKey('command', $true); $c.SetValue('', $driveCmd); $c.SetValue('IsolatedCommand', $driveCmd); $c.Close(); $k.Close()

        Write-Done "Take Ownership added to context menu (files, folders, drives)"
    } else {
        Write-Skip "Skipping Take Ownership context menu"
    }
}

# ============================================================
# 12. DARK MODE & APPEARANCE
# ============================================================
Write-Header "Dark Mode & Appearance"
$themes = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$tp     = Get-ItemProperty $themes -EA SilentlyContinue
$dwmP   = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\DWM" -EA SilentlyContinue
$deskP  = Get-ItemProperty "HKCU:\Control Panel\Desktop" -EA SilentlyContinue
if ($tp.AppsUseLightTheme -eq 0 -and $tp.SystemUsesLightTheme -eq 0 -and
    $tp.ColorPrevalence -eq 1 -and $dwmP.ColorPrevalence -eq 1 -and
    $deskP.AutoColorization -eq 1) {
    Write-Skip "Dark mode and accent settings already applied"
} else {
    Write-Host "  Will set:" -ForegroundColor White
    Write-Host "    - Windows mode: Dark" -ForegroundColor Gray
    Write-Host "    - App mode: Dark" -ForegroundColor Gray
    Write-Host "    - Accent color on taskbar and Start: On" -ForegroundColor Gray
    Write-Host "    - Accent color on title bars and borders: On" -ForegroundColor Gray
    Write-Host "    - Accent colour source: automatically picked from wallpaper" -ForegroundColor Gray
    $doDark = Read-Host "  Set Brad's dark mode settings? [Y/n]"
    if ($doDark -notmatch '^[Nn]') {
        Write-Step "Enabling dark mode for Windows and apps..."
        Set-Reg $themes "AppsUseLightTheme"    0
        Set-Reg $themes "SystemUsesLightTheme" 0

        Write-Step "Showing accent color on taskbar/Start and title bars/borders..."
        Set-Reg $themes "ColorPrevalence" 1
        Set-Reg "HKCU:\Software\Microsoft\Windows\DWM" "ColorPrevalence" 1

        Write-Step "Setting accent color to auto-pick from wallpaper..."
        Set-Reg "HKCU:\Control Panel\Desktop" "AutoColorization" 1

        Write-Done "Dark mode and accent settings applied"
    } else {
        Write-Skip "Skipping appearance settings"
    }
}

# ============================================================
# 13. EXPLORER SETTINGS
# ============================================================
Write-Header "Explorer Settings"
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$ap  = Get-ItemProperty $adv -EA SilentlyContinue
if ($ap.Hidden -eq 1 -and $ap.HideFileExt -eq 0 -and $ap.SeparateProcess -eq 1 -and $ap.LaunchTo -eq 1) {
    Write-Skip "Explorer settings already applied"
} else {
    Write-Host "  Will set:" -ForegroundColor White
    Write-Host "    - Show hidden files and folders: On" -ForegroundColor Gray
    Write-Host "    - Show file extensions: On" -ForegroundColor Gray
    Write-Host "    - Launch folder windows in a separate process: On" -ForegroundColor Gray
    Write-Host "    - Open Explorer to: This PC (not Quick Access)" -ForegroundColor Gray
    $doExplorer = Read-Host "  Apply Explorer settings? [Y/n]"
    if ($doExplorer -notmatch '^[Nn]') {
        Write-Step "Show hidden files and folders..."
        Set-Reg $adv "Hidden" 1

        Write-Step "Show file extensions..."
        Set-Reg $adv "HideFileExt" 0

        Write-Step "Launch folders in a separate process..."
        Set-Reg $adv "SeparateProcess" 1

        Write-Step "Set Explorer to open at This PC..."
        Set-Reg $adv "LaunchTo" 1

        Write-Step "Restarting Explorer to apply changes..."
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        Start-Process explorer

        Write-Done "Explorer settings applied"
    } else {
        Write-Skip "Skipping Explorer settings"
    }
}

# ============================================================
# 14. CHRIS TITUS TECH WINUTIL
# ============================================================
if ($preUpdatePass) { Skip-Flaky "Chris Titus Tech WinUtil" } else {
Write-Header "Chris Titus Tech WinUtil"
Write-Host "  WinUtil is an interactive GUI for tweaks, debloating, and software install." -ForegroundColor White
Write-Host "  It opens in its own window - close it when done and come back here." -ForegroundColor DarkGray
$runCTT = Read-Host "  Launch WinUtil now? [y/N]"
if ($runCTT -match '^[Yy]') {
    Write-Step "Launching WinUtil (requires internet)..."
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm christitus.com/win | iex`"" `
        -Verb RunAs -Wait
    Write-Done "WinUtil closed"
} else {
    Write-Skip "Skipping WinUtil"
    Write-Host "  Run it later with:  irm christitus.com/win | iex" -ForegroundColor DarkGray
}
}

# ============================================================
# 15. EXTRA UI & SYSTEM TWEAKS
# ============================================================
if ($preUpdatePass) { Skip-Flaky "Extra UI & System Tweaks" } else {
Write-Header "Extra UI & System Tweaks"
Write-Host "  Will apply:" -ForegroundColor White
Write-Host "    - Taskbar search box hidden" -ForegroundColor Gray
Write-Host "    - 'End Task' added to taskbar right-click menu" -ForegroundColor Gray
Write-Host "    - Start menu pins emptied" -ForegroundColor Gray
Write-Host "    - Window transparency on" -ForegroundColor Gray
Write-Host "    - Edge desktop shortcut removed" -ForegroundColor Gray
Write-Host "    - Device metadata download and driver co-installers blocked" -ForegroundColor Gray
Write-Host "    - Internet Explorer feature removed" -ForegroundColor Gray
$searchBox = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -EA SilentlyContinue).SearchboxTaskbarMode
if ($searchBox -eq 0) {
    Write-Skip "Extra UI & system tweaks already applied"
} else {
    $doExtra = Read-Host "  Apply these tweaks? [y/N]"
    if ($doExtra -match '^[Yy]') {
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

        Write-Step "Hiding taskbar search box..."
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0

        Write-Step "Adding 'End Task' to taskbar right-click menu..."
        Set-Reg "$adv\TaskbarDeveloperSettings" "TaskbarEndTask" 1

        Write-Step "Emptying Start menu pins..."
        Set-RegStr "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" "ConfigureStartPins" '{"pinnedList":[]}'

        Write-Step "Enabling window transparency..."
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 1

        Write-Step "Removing Edge desktop shortcut..."
        Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force -EA SilentlyContinue

        Write-Step "Blocking device metadata download and driver co-installers..."
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "PreventDeviceMetadataFromNetwork" 1
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" "DisableCoInstallers" 1

        Write-Step "Removing Internet Explorer feature..."
        Get-WindowsCapability -Online -EA SilentlyContinue |
            Where-Object { $_.Name -like 'Browser.InternetExplorer*' -and $_.State -eq 'Installed' } |
            ForEach-Object { Remove-WindowsCapability -Online -Name $_.Name -EA SilentlyContinue | Out-Null }

        Write-Done "Extra UI & system tweaks applied"
        $restartReasons += "Extra UI & system tweaks - some take effect after restart"
    } else {
        Write-Skip "Skipping extra UI & system tweaks"
    }
}
}

# ============================================================
# FINISH
# ============================================================
Write-Header "All Done"

if ($preUpdatePass) {
    Write-Step "Scheduling this menu to re-open after your next sign-in..."
    $ro = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    if (-not (Test-Path $ro)) { New-Item -Path $ro -Force | Out-Null }
    $resumeCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"irm $BootstrapUrl | iex`""
    Set-ItemProperty $ro -Name "Win11PostInstallResume" -Value $resumeCmd -Force
    Write-Done "Menu will re-open once after reboot (needs internet and a UAC prompt at that sign-in)"
    Write-Host ""
    Write-Host "  Safe tweaks are applied and the guard is in place. Now: let Windows Updates" -ForegroundColor Cyan
    Write-Host "  finish, then REBOOT. After you sign back in, this menu re-opens to run the" -ForegroundColor Cyan
    Write-Host "  deferred steps (bloatware, Brave, WinUtil, extra UI)." -ForegroundColor Cyan
    Write-Host ""
    $restart = Read-Host "  Reboot now? [y/N]"
    if ($restart -match '^[Yy]') {
        Restart-Computer -Force
    } else {
        Write-Host "  Reboot once Windows Updates are done." -ForegroundColor Yellow
    }
    return
}

if ($restartReasons.Count -gt 0) {
    Write-Host "  The following changes require a restart to take full effect:" -ForegroundColor White
    foreach ($r in $restartReasons) { Write-Host "    - $r" -ForegroundColor Gray }
    Write-Host ""
    $restart = Read-Host "  Restart now? [y/N]"
    if ($restart -match '^[Yy]') {
        Restart-Computer -Force
    } else {
        Write-Host "  Restart when you're ready." -ForegroundColor Yellow
    }
} else {
    Write-Host "  No restart required - all changes took immediate effect." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Reminder:" -ForegroundColor White
Write-Host "  If you have drives from a previous Windows install, they may show as" -ForegroundColor Gray
Write-Host "  inaccessible or locked. Right-click each drive in Explorer and select" -ForegroundColor Gray
Write-Host "  'Take Ownership' to reclaim full access." -ForegroundColor Gray
