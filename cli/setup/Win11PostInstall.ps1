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
Write-Host "  [3b] Copilot & Recall     - offer to run bin/copilot-removal (Copilot, Recall, reinstall guard)" -ForegroundColor Gray
Write-Host "  [4]  Win11 Adware Tweaks  - widgets off, Teams chat icon off, tip notifications off" -ForegroundColor Gray
Write-Host "  [5]  Bloatware Removal    - uninstall built-in Microsoft/third-party apps" -ForegroundColor Gray
Write-Host "  [6]  Hibernation          - optional: disable hiberfil.sys and reclaim disk space" -ForegroundColor Gray
Write-Host "  [7]  Locale / Region      - restore your real language, region and timezone" -ForegroundColor Gray
Write-Host "  [8]  Gaming Performance   - Game Mode, MMCSS, DVR off, FSO off, power plan, HAGS" -ForegroundColor Gray
Write-Host "  [9]  VBS / HVCI           - optional: disable for 5-10% FPS gain, fixes OC tool compat" -ForegroundColor Gray
Write-Host "  [10] Brave Browser        - optional install via winget + set as default browser" -ForegroundColor Gray
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
        # Start menu suggestions / promoted apps
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",                                      "SubscribedContent-338388Enabled",              0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",                                      "SubscribedContent-338389Enabled",              0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",                                      "SystemPaneSuggestionsEnabled",                 0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",                                      "SoftLandingEnabled",                           0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",                                      "SubscribedContent-310093Enabled",              0),
        # Tailored experiences
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy",                                                     "TailoredExperiencesWithDiagnosticDataEnabled", 0),
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
        @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer",             "DisableSearchBoxSuggestions",    1),
        # Block silent reinstallation of pushed apps
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SilentInstalledAppsEnabled",  0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "ContentDeliveryAllowed",      0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "OemPreInstalledAppsEnabled",  0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "PreInstalledAppsEnabled",     0),
        @("HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContentEnabled",    0)
    )
    Write-Step "Applying registry tweaks..."
    foreach ($t in $cortanaTweaks) { Set-Reg $t[0] $t[1] $t[2] }

    Write-Done "Cortana and Start menu web search disabled"
}

# ============================================================
# 3b. COPILOT & RECALL REMOVAL
#     Delegated to bin/copilot-removal.ps1 - the single source of truth for
#     Copilot/Recall policies, package uninstall, and the reinstall guard task.
# ============================================================
Write-Header "Copilot & Recall Removal"
$copilotScript = Join-Path $PSScriptRoot "..\..\bin\copilot-removal.ps1"
if (-not (Test-Path $copilotScript)) {
    Write-Host "  bin/copilot-removal.ps1 not found next to devtools - skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Runs bin/copilot-removal: removes Copilot and Windows Recall, and can register" -ForegroundColor White
    Write-Host "  a scheduled task that re-applies removal after feature updates." -ForegroundColor Gray
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
# 4. WIN11 ADWARE TWEAKS
# ============================================================
Write-Header "Windows 11 Adware Tweaks"
$adwareCheck = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -EA SilentlyContinue).AllowNewsAndInterests
if ($adwareCheck -eq 0) {
    Write-Skip "Win11 adware tweaks already applied"
} else {
    Write-Step "Removing adware and telemetry features..."
    $explorer = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    # Widgets - news feed sends usage data to Microsoft
    Set-Reg $explorer "TaskbarDa" 0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0

    # Chat / Teams icon on taskbar - Microsoft pushing their product
    Set-Reg $explorer "TaskbarMn" 0

    # Tips and suggestions notifications - Microsoft ads in notification area
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338393Enabled" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" 0

    Write-Done "Widgets off, Teams chat icon off, tip notifications off"
}

# ============================================================
# 5. BLOATWARE REMOVAL
# ============================================================
Write-Header "Removing Built-in Bloatware"
$bloatCanary = @('Microsoft.BingNews','Microsoft.MicrosoftSolitaireCollection','Clipchamp.Clipchamp','Microsoft.Copilot') |
    Where-Object { Get-AppxPackage -Name $_ -AllUsers -EA SilentlyContinue }
if (-not $bloatCanary) {
    Write-Skip "Bloatware already removed"
} else {
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
# 8. GAMING PERFORMANCE
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
    $doGaming = Read-Host "  Apply gaming performance tweaks? [Y/n]"
    if ($doGaming -notmatch '^[Nn]') {
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
        $hags = Read-Host "  Enable HAGS? [Y/n]"
        if ($hags -notmatch '^[Nn]') {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
            Write-Done "HAGS enabled"
        } else {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 1
            Write-Done "HAGS disabled"
        }
        $restartReasons += "HAGS setting changed - takes effect after restart"

        Write-Done "Gaming performance tweaks applied"
    } else {
        Write-Skip "Skipping gaming tweaks"
    }
}

# ============================================================
# 9. VBS / HVCI
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
    $disableVbs = Read-Host "  Disable VBS/HVCI? [Y/n]"
    if ($disableVbs -notmatch '^[Nn]') {
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
        $restartReasons += "VBS / Memory Integrity disabled - takes effect after restart"
    } else {
        Write-Skip "VBS/HVCI left enabled"
    }
}

# ============================================================
# 10. BRAVE BROWSER
# ============================================================
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

# ============================================================
# 15. EXTRA UI & SYSTEM TWEAKS
# ============================================================
Write-Header "Extra UI & System Tweaks"
Write-Host "  Will apply:" -ForegroundColor White
Write-Host "    - Taskbar search box hidden" -ForegroundColor Gray
Write-Host "    - 'End Task' added to taskbar right-click menu" -ForegroundColor Gray
Write-Host "    - Start menu pins emptied" -ForegroundColor Gray
Write-Host "    - Window transparency on" -ForegroundColor Gray
Write-Host "    - Sticky Keys shortcut disabled" -ForegroundColor Gray
Write-Host "    - Edge desktop shortcut removed" -ForegroundColor Gray
Write-Host "    - Lock screen after update sign-in prompt disabled" -ForegroundColor Gray
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

        Write-Step "Disabling Sticky Keys shortcut..."
        Set-RegStr "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506"

        Write-Step "Removing Edge desktop shortcut..."
        Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force -EA SilentlyContinue

        Write-Step "Disabling lock screen after update sign-in prompt..."
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DisableAutomaticRestartSignOn" 1

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

# ============================================================
# FINISH
# ============================================================
Write-Header "All Done"
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
