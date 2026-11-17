#Requires -Version 5.1
<#
.SYNOPSIS
    Schedule automatic light/dark theme switching, by sunrise/sunset or fixed times.

.DESCRIPTION
    Windows 11 has no day/night theme schedule. This registers scheduled tasks for
    the current user that flip the Windows + app theme between light and dark.

    Two modes:
      Sun   - follows local sunrise/sunset, computed offline. Latitude and longitude
              come from the Windows timezone's representative city (timezone IDs are
              city based, e.g. 'Tasmania Standard Time' -> Hobart), overridable with
              -Latitude/-Longitude. One task polls every 15 minutes and applies
              whichever theme matches the current time, so it tracks the seasons and
              self-corrects after sleep or a missed switch.
      Fixed - two daily tasks at times you pick (-LightAt / -DarkAt).

    The theme lives in HKCU, so the tasks run as the current user and no admin
    rights are needed. The change applies instantly - no restart or sign-out.

    Safe to re-run - registering either mode clears the other one's tasks.

.PARAMETER Sun
    Register sun mode (sunrise/sunset located from the Windows timezone).

.PARAMETER Latitude
    Override the latitude used by sun mode. Decimal degrees, north positive.

.PARAMETER Longitude
    Override the longitude used by sun mode. Decimal degrees, east positive.

.PARAMETER LightAt
    Fixed mode: time of day to switch to light. Default 07:00.

.PARAMETER DarkAt
    Fixed mode: time of day to switch to dark. Default 19:00.

.PARAMETER NightLight
    Sun mode: also ramp Windows night light. Evening warms in stages before sunset
    (15% at -75 min, 30% at -45, 40% at -15), holds overnight, then unwinds after
    sunrise (40% at sunrise, 30% at +15, 15% at +45, off at +75). The stages are
    stored in the config file and can be edited there.

.PARAMETER NoNightLight
    Never touch night light (and clear it from a stored config).

.PARAMETER DarkBefore
    Sun mode: go dark this many minutes BEFORE sunset. A long summer evening is
    still bright at sunset, so 60-90 is a reasonable amount to take off the end.

.PARAMETER LightAfter
    Sun mode: wait this many minutes AFTER sunrise before going light.

.PARAMETER DarkAccent
    What 'accent colour on Start and taskbar' should be in dark mode: on, off, or
    keep (default - remember whatever it was last time dark mode was active).
    Windows clears that setting when the system goes light and never restores it,
    so the schedule puts it back. Wallpaper-derived accent colour, accent on title
    bars and borders, and your wallpaper itself are never touched.

.PARAMETER RestartExplorer
    Restart Explorer on each actual theme change. Secondary-monitor taskbars often
    keep the old colours until it does. Closes open File Explorer windows.

.PARAMETER Apply
    Apply the theme for the current time in sun mode and exit (what the sun task
    invokes). Reads the stored coordinates.

.PARAMETER SetLight
    Apply light mode now and exit (what the fixed morning task invokes).

.PARAMETER SetDark
    Apply dark mode now and exit (what the fixed evening task invokes).

.PARAMETER Status
    Show the mode, schedule and today's sun times, then exit.

.PARAMETER Unregister
    Remove all theme schedule tasks and exit.

.PARAMETER NoConfirm
    Interactive, but skip the final "register it?" confirmation - picking a mode in
    the sun/fixed/skip question is answer enough. Used by the main setup script so
    the schedule is one question, not three.

.PARAMETER Yes
    Accept all prompts (non-interactive). With no mode switch, picks sun mode.

.PARAMETER Help
    Show usage and exit.

.EXAMPLE
    .\theme-schedule.ps1
.EXAMPLE
    .\theme-schedule.ps1 -Sun -Yes
.EXAMPLE
    .\theme-schedule.ps1 -LightAt 07:00 -DarkAt 18:00 -Yes
.EXAMPLE
    .\theme-schedule.ps1 -Sun -Latitude -17.96 -Longitude 122.24 -Yes
.EXAMPLE
    .\theme-schedule.ps1 -Status
#>
param(
    [switch]$Sun,
    [double]$Latitude  = [double]::NaN,
    [double]$Longitude = [double]::NaN,
    [string]$LightAt,
    [string]$DarkAt,
    [ValidateSet('on','off','keep')]
    [string]$DarkAccent = 'keep',
    [switch]$RestartExplorer,
    [int]$DarkBefore = 0,
    [int]$LightAfter = 0,
    [switch]$NightLight,
    [switch]$NoNightLight,
    [switch]$NoConfirm,
    [switch]$Apply,
    [switch]$SetLight,
    [switch]$SetDark,
    [switch]$Status,
    [switch]$Unregister,
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

$LightTask   = 'Win11PostInstallThemeLight'
$DarkTask    = 'Win11PostInstallThemeDark'
$SunTask     = 'Win11PostInstallThemeSun'
$AllTasks    = @($LightTask, $DarkTask, $SunTask)
$InstallDir  = "$env:LOCALAPPDATA\Win11PostInstall"
$Installed   = Join-Path $InstallDir 'theme-schedule.ps1'
$ConfigPath  = Join-Path $InstallDir 'theme-schedule.json'
$Launcher    = Join-Path $InstallDir 'theme-schedule-hidden.vbs'
$ThemeKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$PollMinutes = 15

# Representative city per Windows timezone ID (lat, long, label), from the CLDR
# windowsZones mapping plus the IANA zone coordinates. Timezone IDs are city based,
# so this pins latitude well enough for sunrise/sunset. Zones spanning a wide
# latitude (W. Australia covers Perth AND Broome, Central covers Chicago AND
# Houston) are where -Latitude earns its keep.
$ZoneCities = @{
    'AUS Eastern Standard Time'        = @(-33.87, 151.21, 'Sydney')
    'AUS Central Standard Time'        = @(-12.46, 130.84, 'Darwin')
    'Aus Central W. Standard Time'     = @(-31.68, 128.88, 'Eucla')
    'Cen. Australia Standard Time'     = @(-34.93, 138.60, 'Adelaide')
    'E. Australia Standard Time'       = @(-27.47, 153.03, 'Brisbane')
    'W. Australia Standard Time'       = @(-31.95, 115.86, 'Perth')
    'Tasmania Standard Time'           = @(-42.88, 147.33, 'Hobart')
    'Lord Howe Standard Time'          = @(-31.55, 159.08, 'Lord Howe Island')
    'Norfolk Standard Time'            = @(-29.05, 167.97, 'Norfolk Island')
    'New Zealand Standard Time'        = @(-36.85, 174.76, 'Auckland')
    'Chatham Islands Standard Time'    = @(-43.95, -176.55, 'Chatham Islands')
    'Fiji Standard Time'               = @(-18.14, 178.44, 'Suva')
    'Tonga Standard Time'              = @(-21.13, -175.20, 'Nukualofa')
    'Samoa Standard Time'              = @(-13.83, -171.77, 'Apia')
    'West Pacific Standard Time'       = @(-9.48, 147.15, 'Port Moresby')
    'Bougainville Standard Time'       = @(-6.22, 155.63, 'Bougainville')
    'Central Pacific Standard Time'    = @(-9.43, 159.95, 'Guadalcanal')
    'Tokyo Standard Time'              = @(35.68, 139.69, 'Tokyo')
    'Korea Standard Time'              = @(37.57, 126.98, 'Seoul')
    'North Korea Standard Time'        = @(39.02, 125.75, 'Pyongyang')
    'China Standard Time'              = @(31.23, 121.47, 'Shanghai')
    'Taipei Standard Time'             = @(25.03, 121.57, 'Taipei')
    'Ulaanbaatar Standard Time'        = @(47.92, 106.92, 'Ulaanbaatar')
    'Singapore Standard Time'          = @(1.35, 103.82, 'Singapore')
    'SE Asia Standard Time'            = @(13.75, 100.50, 'Bangkok')
    'Myanmar Standard Time'            = @(16.80, 96.15, 'Yangon')
    'Bangladesh Standard Time'         = @(23.81, 90.41, 'Dhaka')
    'India Standard Time'              = @(22.57, 88.36, 'Kolkata')
    'Sri Lanka Standard Time'          = @(6.93, 79.86, 'Colombo')
    'Nepal Standard Time'              = @(27.72, 85.32, 'Kathmandu')
    'Pakistan Standard Time'           = @(24.86, 67.01, 'Karachi')
    'Afghanistan Standard Time'        = @(34.53, 69.17, 'Kabul')
    'Central Asia Standard Time'       = @(43.24, 76.89, 'Almaty')
    'Qyzylorda Standard Time'          = @(44.85, 65.51, 'Qyzylorda')
    'West Asia Standard Time'          = @(41.30, 69.24, 'Tashkent')
    'Arabian Standard Time'            = @(25.20, 55.27, 'Dubai')
    'Arab Standard Time'               = @(24.71, 46.68, 'Riyadh')
    'Arabic Standard Time'             = @(33.31, 44.37, 'Baghdad')
    'Iran Standard Time'               = @(35.69, 51.39, 'Tehran')
    'Israel Standard Time'             = @(31.78, 35.22, 'Jerusalem')
    'West Bank Standard Time'          = @(31.50, 34.47, 'Gaza')
    'Jordan Standard Time'             = @(31.95, 35.93, 'Amman')
    'Middle East Standard Time'        = @(33.89, 35.50, 'Beirut')
    'Syria Standard Time'              = @(33.51, 36.29, 'Damascus')
    'Turkey Standard Time'             = @(41.01, 28.98, 'Istanbul')
    'Georgian Standard Time'           = @(41.72, 44.79, 'Tbilisi')
    'Caucasus Standard Time'           = @(40.18, 44.51, 'Yerevan')
    'Azerbaijan Standard Time'         = @(40.40, 49.87, 'Baku')
    'Russian Standard Time'            = @(55.76, 37.62, 'Moscow')
    'Belarus Standard Time'            = @(53.90, 27.57, 'Minsk')
    'Kaliningrad Standard Time'        = @(54.71, 20.45, 'Kaliningrad')
    'Volgograd Standard Time'          = @(48.71, 44.50, 'Volgograd')
    'Astrakhan Standard Time'          = @(46.35, 48.04, 'Astrakhan')
    'Saratov Standard Time'            = @(51.56, 46.03, 'Saratov')
    'Russia Time Zone 3'               = @(53.20, 50.15, 'Samara')
    'Ekaterinburg Standard Time'       = @(56.84, 60.65, 'Yekaterinburg')
    'Omsk Standard Time'               = @(54.99, 73.37, 'Omsk')
    'N. Central Asia Standard Time'    = @(55.03, 82.92, 'Novosibirsk')
    'Altai Standard Time'              = @(53.36, 83.76, 'Barnaul')
    'Tomsk Standard Time'              = @(56.50, 84.97, 'Tomsk')
    'North Asia Standard Time'         = @(56.01, 92.87, 'Krasnoyarsk')
    'North Asia East Standard Time'    = @(52.29, 104.30, 'Irkutsk')
    'Transbaikal Standard Time'        = @(52.03, 113.50, 'Chita')
    'Yakutsk Standard Time'            = @(62.03, 129.73, 'Yakutsk')
    'Vladivostok Standard Time'        = @(43.12, 131.89, 'Vladivostok')
    'Sakhalin Standard Time'           = @(46.96, 142.73, 'Yuzhno-Sakhalinsk')
    'Magadan Standard Time'            = @(59.57, 150.80, 'Magadan')
    'Russia Time Zone 10'              = @(67.46, 153.71, 'Srednekolymsk')
    'Russia Time Zone 11'              = @(53.02, 158.65, 'Kamchatka')
    'E. Europe Standard Time'          = @(47.01, 28.86, 'Chisinau')
    'FLE Standard Time'                = @(50.45, 30.52, 'Kyiv')
    'GTB Standard Time'                = @(37.98, 23.73, 'Athens')
    'Central Europe Standard Time'     = @(47.50, 19.04, 'Budapest')
    'Central European Standard Time'   = @(52.23, 21.01, 'Warsaw')
    'W. Europe Standard Time'          = @(52.52, 13.40, 'Berlin')
    'Romance Standard Time'            = @(48.86, 2.35, 'Paris')
    'GMT Standard Time'                = @(51.51, -0.13, 'London')
    'Greenwich Standard Time'          = @(5.32, -4.03, 'Abidjan')
    'W. Central Africa Standard Time'  = @(6.52, 3.38, 'Lagos')
    'South Africa Standard Time'       = @(-26.20, 28.05, 'Johannesburg')
    'Namibia Standard Time'            = @(-22.56, 17.08, 'Windhoek')
    'E. Africa Standard Time'          = @(-1.29, 36.82, 'Nairobi')
    'South Sudan Standard Time'        = @(4.85, 31.58, 'Juba')
    'Sudan Standard Time'              = @(15.50, 32.56, 'Khartoum')
    'Egypt Standard Time'              = @(30.04, 31.24, 'Cairo')
    'Libya Standard Time'              = @(32.89, 13.19, 'Tripoli')
    'Morocco Standard Time'            = @(33.57, -7.59, 'Casablanca')
    'Mauritius Standard Time'          = @(-20.17, 57.50, 'Port Louis')
    'Azores Standard Time'             = @(37.74, -25.68, 'Azores')
    'Cape Verde Standard Time'         = @(14.92, -23.51, 'Praia')
    'Greenland Standard Time'          = @(64.18, -51.72, 'Nuuk')
    'E. South America Standard Time'   = @(-23.55, -46.63, 'Sao Paulo')
    'Bahia Standard Time'              = @(-12.97, -38.50, 'Salvador')
    'Tocantins Standard Time'          = @(-7.19, -48.20, 'Araguaina')
    'Central Brazilian Standard Time'  = @(-15.60, -56.10, 'Cuiaba')
    'Argentina Standard Time'          = @(-34.60, -58.38, 'Buenos Aires')
    'Montevideo Standard Time'         = @(-34.90, -56.19, 'Montevideo')
    'Paraguay Standard Time'           = @(-25.30, -57.63, 'Asuncion')
    'Pacific SA Standard Time'         = @(-33.45, -70.67, 'Santiago')
    'Magallanes Standard Time'         = @(-53.15, -70.92, 'Punta Arenas')
    'Easter Island Standard Time'      = @(-27.15, -109.43, 'Easter Island')
    'SA Eastern Standard Time'         = @(4.93, -52.33, 'Cayenne')
    'SA Western Standard Time'         = @(-16.50, -68.15, 'La Paz')
    'SA Pacific Standard Time'         = @(4.71, -74.07, 'Bogota')
    'Venezuela Standard Time'          = @(10.50, -66.92, 'Caracas')
    'Cuba Standard Time'               = @(23.13, -82.38, 'Havana')
    'Haiti Standard Time'              = @(18.54, -72.34, 'Port-au-Prince')
    'Turks And Caicos Standard Time'   = @(21.46, -71.14, 'Grand Turk')
    'Central America Standard Time'    = @(14.63, -90.51, 'Guatemala City')
    'Atlantic Standard Time'           = @(44.65, -63.57, 'Halifax')
    'Newfoundland Standard Time'       = @(47.56, -52.71, 'St Johns')
    'Eastern Standard Time'            = @(40.71, -74.01, 'New York')
    'US Eastern Standard Time'         = @(39.77, -86.16, 'Indianapolis')
    'Eastern Standard Time (Mexico)'   = @(21.17, -86.85, 'Cancun')
    'Central Standard Time'            = @(41.88, -87.63, 'Chicago')
    'Central Standard Time (Mexico)'   = @(19.43, -99.13, 'Mexico City')
    'Canada Central Standard Time'     = @(50.45, -104.62, 'Regina')
    'Mountain Standard Time'           = @(39.74, -104.98, 'Denver')
    'Mountain Standard Time (Mexico)'  = @(28.63, -106.07, 'Chihuahua')
    'US Mountain Standard Time'        = @(33.45, -112.07, 'Phoenix')
    'Pacific Standard Time'            = @(34.05, -118.24, 'Los Angeles')
    'Pacific Standard Time (Mexico)'   = @(32.53, -117.02, 'Tijuana')
    'Yukon Standard Time'              = @(60.72, -135.05, 'Whitehorse')
    'Alaskan Standard Time'            = @(61.22, -149.90, 'Anchorage')
    'Aleutian Standard Time'           = @(51.88, -176.66, 'Adak')
    'Hawaiian Standard Time'           = @(21.31, -157.86, 'Honolulu')
}

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
function Write-Fail { param([string]$T); Write-Host "  [x] $T" -ForegroundColor Red }

function Confirm-Default-Yes {
    param([string]$Prompt)
    if ($Yes -or $NoConfirm) { return $true }
    $ans = Read-Host "  $Prompt [Y/n]"
    return ($ans -notmatch '^[Nn]')
}

function Show-Usage {
    Write-Host ""
    Write-Host "  theme-schedule - automatic light/dark theme switching" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage: theme-schedule [-Sun] [-Latitude <deg>] [-Longitude <deg>]" -ForegroundColor White
    Write-Host "                        [-LightAt HH:mm] [-DarkAt HH:mm]" -ForegroundColor White
    Write-Host "                        [-Status] [-Unregister] [-Yes] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "    (no args)     Ask which mode to use, then register it" -ForegroundColor Gray
    Write-Host "    -Sun          Sunrise/sunset mode, located from the Windows timezone" -ForegroundColor Gray
    Write-Host "    -Latitude     Override sun mode latitude (decimal, north positive)" -ForegroundColor Gray
    Write-Host "    -Longitude    Override sun mode longitude (decimal, east positive)" -ForegroundColor Gray
    Write-Host "    -LightAt      Fixed mode: time to go light, 24h HH:mm (default 07:00)" -ForegroundColor Gray
    Write-Host "    -DarkAt       Fixed mode: time to go dark, 24h HH:mm (default 19:00)" -ForegroundColor Gray
    Write-Host "    -NightLight        Sun mode: also ramp night light around the switches" -ForegroundColor Gray
    Write-Host "    -NoNightLight      Never touch night light" -ForegroundColor Gray
    Write-Host "    -DarkBefore   Sun mode: go dark N minutes before sunset (default 0)" -ForegroundColor Gray
    Write-Host "    -LightAfter   Sun mode: go light N minutes after sunrise (default 0)" -ForegroundColor Gray
    Write-Host "    -DarkAccent   Accent on Start/taskbar in dark mode: on|off|keep (default keep)" -ForegroundColor Gray
    Write-Host "    -RestartExplorer  Restart Explorer on each switch (fixes 2nd monitor taskbar)" -ForegroundColor Gray
    Write-Host "    -Apply        Apply the right theme for now, sun mode (used by the task)" -ForegroundColor Gray
    Write-Host "    -SetLight     Apply light mode now and exit (used by the task)" -ForegroundColor Gray
    Write-Host "    -SetDark      Apply dark mode now and exit (used by the task)" -ForegroundColor Gray
    Write-Host "    -Status       Show mode, schedule and today's sun times, then exit" -ForegroundColor Gray
    Write-Host "    -Unregister   Remove all theme schedule tasks and exit" -ForegroundColor Gray
    Write-Host "    -NoConfirm    Ask which mode, then just do it (no extra confirmation)" -ForegroundColor Gray
    Write-Host "    -Yes          Accept all prompts (non-interactive; defaults to sun mode)" -ForegroundColor Gray
    Write-Host "    -Help         Show this help and exit" -ForegroundColor Gray
    Write-Host ""
}

function Get-TimeOrNull {
    param([string]$Text)
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($Text, [string[]]@('HH:mm','H:mm'), [cultureinfo]::InvariantCulture, 'None', [ref]$parsed)
    if ($ok) { return $parsed }
    return $null
}

function Get-ZoneLocation {
    $id = (Get-TimeZone).Id
    if (-not $ZoneCities.ContainsKey($id)) { return $null }
    $c = $ZoneCities[$id]
    return [pscustomobject]@{ ZoneId = $id; Latitude = [double]$c[0]; Longitude = [double]$c[1]; City = [string]$c[2] }
}

# Sunrise/sunset for a date at a lat/long, in local time. Standard sunrise equation
# (NOAA/Almanac), accurate to about a minute - plenty for switching a colour scheme.
# Sunrise or Sunset comes back $null when the sun never crosses the horizon that day
# (polar summer/winter).
function Get-SunTimes {
    param([datetime]$Date, [double]$Lat, [double]$Lon)
    $rad       = [math]::PI / 180.0
    $zenith    = 90.833            # geometric horizon plus atmospheric refraction
    $dayOfYear = $Date.DayOfYear
    $lngHour   = $Lon / 15.0
    $out = @{}
    foreach ($kind in @('Sunrise','Sunset')) {
        $baseHour = if ($kind -eq 'Sunrise') { 6.0 } else { 18.0 }
        $t = $dayOfYear + (($baseHour - $lngHour) / 24.0)
        $m = (0.9856 * $t) - 3.289
        $l = $m + (1.916 * [math]::Sin($m * $rad)) + (0.020 * [math]::Sin(2 * $m * $rad)) + 282.634
        $l = $l % 360.0; if ($l -lt 0) { $l += 360.0 }
        $ra = [math]::Atan(0.91764 * [math]::Tan($l * $rad)) / $rad
        $ra = $ra % 360.0; if ($ra -lt 0) { $ra += 360.0 }
        # Put right ascension in the same quadrant as the sun's true longitude
        $ra = $ra + ([math]::Floor($l / 90.0) * 90.0) - ([math]::Floor($ra / 90.0) * 90.0)
        $ra = $ra / 15.0
        $sinDec = 0.39782 * [math]::Sin($l * $rad)
        $cosDec = [math]::Cos([math]::Asin($sinDec))
        $cosH   = ([math]::Cos($zenith * $rad) - ($sinDec * [math]::Sin($Lat * $rad))) / ($cosDec * [math]::Cos($Lat * $rad))
        if ($cosH -gt 1 -or $cosH -lt -1) { $out[$kind] = $null; continue }
        $h = [math]::Acos($cosH) / $rad
        if ($kind -eq 'Sunrise') { $h = 360.0 - $h }
        $h = $h / 15.0
        $localMeanTime = $h + $ra - (0.06571 * $t) - 6.622
        $ut = $localMeanTime - $lngHour
        $ut = $ut % 24.0; if ($ut -lt 0) { $ut += 24.0 }
        $utc   = [datetime]::SpecifyKind($Date.Date, 'Utc').AddHours($ut)
        $local = $utc.ToLocalTime()
        # The UT the equation gives belongs to the UTC day, which can land on the
        # day either side of the local date (far east/west longitudes). Sun times
        # shift only minutes per day, so snap the result onto the local date asked for.
        $shift = ($Date.Date - $local.Date).Days
        if ($shift -ne 0) { $local = $local.AddDays($shift) }
        $out[$kind] = $local
    }
    return [pscustomobject]@{ Sunrise = $out['Sunrise']; Sunset = $out['Sunset'] }
}

function Test-DaylightNow {
    # DarkBefore/LightAfter shrink the light window at each end. Sunset is when the
    # sun goes down, not when a bright UI stops hurting - on a long summer evening
    # the screen is too white well before then.
    param([double]$Lat, [double]$Lon, [int]$DarkBefore = 0, [int]$LightAfter = 0)
    $now = Get-Date
    $sun = Get-SunTimes -Date $now -Lat $Lat -Lon $Lon
    # Polar day/night: no horizon crossing at all, so go by the hemisphere's season
    if ($null -eq $sun.Sunrise -or $null -eq $sun.Sunset) {
        $summer = ($now.Month -ge 4 -and $now.Month -le 9)
        if ($Lat -lt 0) { $summer = -not $summer }
        return $summer
    }
    $lightFrom  = $sun.Sunrise.AddMinutes($LightAfter)
    $darkFrom   = $sun.Sunset.AddMinutes(-$DarkBefore)
    if ($darkFrom -le $lightFrom) { return $false }   # offsets swallowed the whole day
    return ($now -ge $lightFrom -and $now -lt $darkFrom)
}

function Set-Theme {
    param([bool]$Light)
    $value   = if ($Light) { 1 } else { 0 }
    $wasDark = ((Get-CurrentTheme) -eq 'dark')
    if (-not (Test-Path $ThemeKey)) { New-Item -Path $ThemeKey -Force | Out-Null }

    # 'Accent colour on Start and taskbar' is only supported in dark mode, so Windows
    # zeroes Personalize\ColorPrevalence when the system goes light and does NOT put it
    # back on the way to dark. Remember the dark-mode preference and restore it, or the
    # accent on the taskbar is lost the first time the schedule runs.
    if ($wasDark -and $Light) {
        $cur = (Get-ItemProperty $ThemeKey -ErrorAction SilentlyContinue).ColorPrevalence
        if ($null -ne $cur) { Save-ConfigValue -Name 'DarkAccentOnTaskbar' -Value ([int]$cur) }
    }

    Set-ItemProperty -Path $ThemeKey -Name 'AppsUseLightTheme'    -Value $value -Type DWord -Force
    Set-ItemProperty -Path $ThemeKey -Name 'SystemUsesLightTheme' -Value $value -Type DWord -Force

    if (-not $Light) {
        $pref = (Get-Config).DarkAccentOnTaskbar
        if ($null -ne $pref) {
            Set-ItemProperty -Path $ThemeKey -Name 'ColorPrevalence' -Value ([int]$pref) -Type DWord -Force
        }
    }

    # Tell running apps the colour scheme changed so they repaint without a restart
    if (-not ('Win32.BroadcastSetting' -as [type])) {
        Add-Type -Namespace Win32 -Name BroadcastSetting -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@
    }
    $result = [System.IntPtr]::Zero
    # HWND_BROADCAST, SMTO_ABORTIFHUNG, 1s timeout. WM_SETTINGCHANGE/ImmersiveColorSet
    # is what the Settings app sends; WM_THEMECHANGED and WM_SYSCOLORCHANGE nudge the
    # older controls that ignore it.
    foreach ($msg in @(0x001A, 0x031A, 0x0015)) {
        $null = [Win32.BroadcastSetting]::SendMessageTimeout([System.IntPtr]0xffff, $msg, [System.IntPtr]::Zero, 'ImmersiveColorSet', 2, 1000, [ref]$result)
    }

    # Secondary-monitor taskbars often keep the old colours until Explorer restarts -
    # opt in with -RestartExplorer (stored in the config so the task does it too).
    $restart = $RestartExplorer -or ((Get-Config).RestartExplorer -eq $true)
    if ($restart -and ($wasDark -eq $Light)) {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    }
}

# ------------------------------------------------------------
# NIGHT LIGHT
# Windows exposes no API for this. The on/off state lives in an undocumented
# CloudStore blob, so it is written byte for byte from templates captured from a
# real toggle on this build. Byte 18 is the marker (0x05 off / 0x15 on) and bytes
# 10-14 are a unix-time varint that MUST be refreshed, or Windows ignores the
# write and the Settings page shows stale state. Undocumented: a feature update
# can change the format, so every call checks the blob it read first and bails
# out instead of writing garbage.
# ------------------------------------------------------------
$NightLightKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default`$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate"

function Get-UnixVarint {
    $t = [int][double]::Parse((Get-Date -UFormat %s))
    $v = @()
    $x = $t
    for ($i = 0; $i -lt 5; $i++) {
        $b = $x -band 0x7F
        $x = $x -shr 7
        if ($i -lt 4) { $b = $b -bor 0x80 }
        $v += [byte]$b
    }
    return ,$v
}

# Byte 18 markers seen in the wild: 0x15 on, 0x13 off (blob that has been configured),
# 0x05 off (blob that has never been turned on). Anything else is unrecognised.
function Get-NightLightState {
    $d = (Get-ItemProperty -Path $NightLightKey -Name Data -ErrorAction SilentlyContinue).Data
    if ($null -eq $d -or $d.Length -lt 19) { return 'unknown' }
    if ($d[18] -eq 0x15) { return 'on' }
    if ($d[18] -eq 0x13 -or $d[18] -eq 0x05) { return 'off' }
    return 'unknown'
}

# The on and off blobs differ by exactly two things: byte 18 (0x15 vs 0x13) and a
# two-byte 0x10 0x00 block inserted right after the second "CB 01 00" header at
# index 19-22. So edit the live blob rather than writing a captured template - that
# keeps every other field (including the trailing timestamps) as Windows left it.
function Set-NightLight {
    param([bool]$On)
    $current = Get-NightLightState
    if ($current -eq 'unknown') {
        Write-Warn "Night light blob is not in the expected format - leaving it alone"
        return $false
    }
    if (($current -eq 'on') -eq $On) { return $true }
    $d = (Get-ItemProperty -Path $NightLightKey -Name Data).Data
    $hasBlock = ($d.Length -ge 25 -and $d[23] -eq 0x10 -and $d[24] -eq 0x00)
    if ($On) {
        $new = if ($hasBlock) { @($d) } else { @($d[0..22]) + @([byte]0x10, [byte]0x00) + @($d[23..($d.Length-1)]) }
        $new[18] = [byte]0x15
    } else {
        $new = if ($hasBlock) { @($d[0..22]) + @($d[25..($d.Length-1)]) } else { @($d) }
        $new[18] = [byte]0x13
    }
    $ts = Get-UnixVarint
    for ($i = 0; $i -lt 5; $i++) { $new[10 + $i] = $ts[$i] }   # refresh or Windows ignores it
    try {
        Set-ItemProperty -Path $NightLightKey -Name Data -Value ([byte[]]$new) -Type Binary -ErrorAction Stop
    } catch {
        Write-Fail "Could not write night light state: $($_.Exception.Message)"
        return $false
    }
    return $true
}

# Night light strength lives in the settings blob, as a two-byte varint right after
# a 0xCF 0x28 marker. The value is colour temperature in Kelvin doubled, and the
# Settings slider is linear: Kelvin = 6500 - 53 * percent. Verified against three
# captures (15% = 5705K, 25% = 5175K, 30% = 4910K).
$NightLightSettingsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default`$windows.data.bluelightreduction.settings\windows.data.bluelightreduction.settings"

function ConvertTo-Varint2 {
    param([int]$Value)
    return ,@([byte](($Value -band 0x7F) -bor 0x80), [byte](($Value -shr 7) -band 0x7F))
}

function Get-NightLightStrength {
    $d = (Get-ItemProperty -Path $NightLightSettingsKey -Name Data -ErrorAction SilentlyContinue).Data
    if ($null -eq $d) { return $null }
    for ($i = 0; $i -lt $d.Length - 3; $i++) {
        if ($d[$i] -eq 0xCF -and $d[$i+1] -eq 0x28) {
            $value  = ($d[$i+2] -band 0x7F) + (($d[$i+3] -band 0x7F) -shl 7)
            $kelvin = [int]($value / 2)
            return [int][math]::Round((6500 - $kelvin) / 53.0)
        }
    }
    return $null
}

function Set-NightLightStrength {
    param([int]$Percent)
    if ($Percent -lt 0 -or $Percent -gt 100) { Write-Fail "Night light strength must be 0-100"; return $false }
    $d = (Get-ItemProperty -Path $NightLightSettingsKey -Name Data -ErrorAction SilentlyContinue).Data
    if ($null -eq $d) { Write-Warn "No night light settings blob - leaving it alone"; return $false }
    $at = -1
    for ($i = 0; $i -lt $d.Length - 3; $i++) {
        if ($d[$i] -eq 0xCF -and $d[$i+1] -eq 0x28) { $at = $i + 2; break }
    }
    if ($at -lt 0) {
        Write-Warn "Night light settings blob is not in the expected format - leaving it alone"
        return $false
    }
    $kelvin = 6500 - (53 * $Percent)
    $bytes  = ConvertTo-Varint2 ($kelvin * 2)
    $new    = @($d)
    $new[$at]   = $bytes[0]
    $new[$at+1] = $bytes[1]
    $ts = Get-UnixVarint
    for ($i = 0; $i -lt 5; $i++) { $new[10 + $i] = $ts[$i] }   # refresh or Windows ignores it
    try {
        Set-ItemProperty -Path $NightLightSettingsKey -Name Data -Value ([byte[]]$new) -Type Binary -ErrorAction Stop
    } catch {
        Write-Fail "Could not write night light strength: $($_.Exception.Message)"
        return $false
    }
    return $true
}

# Night light ramp. Evening warms up in stages as sunset approaches, holds overnight,
# then unwinds after sunrise. Minutes are relative to sunset (evening, before) and
# sunrise (morning, after); strength 0 means off. Defaults match the staging asked
# for; the stored config can be edited to change them.
$DefaultEveningRamp = @(@(75,15), @(45,30), @(15,40))
$DefaultMorningRamp = @(@(0,40), @(15,30), @(45,15), @(75,0))

function Get-RampFromConfig {
    param($Raw, $Fallback)
    if ($null -eq $Raw) { return $Fallback }
    $out = @()
    foreach ($pair in $Raw) { $out += ,@([int]$pair[0], [int]$pair[1]) }
    if ($out.Count -eq 0) { return $Fallback }
    return $out
}

# What night light strength should be active right now (0 = off)
function Get-NightLightTarget {
    param([datetime]$Now, [datetime]$Sunrise, [datetime]$Sunset, $EveningRamp, $MorningRamp)
    # Evening first: nearest stage to sunset wins, so walk it from latest to earliest
    foreach ($stage in ($EveningRamp | Sort-Object { $_[0] })) {
        $at = $Sunset.AddMinutes(-$stage[0])
        if ($Now -ge $at) { return [int]$stage[1] }
    }
    # Morning: latest stage already reached wins
    $result = $null
    foreach ($stage in ($MorningRamp | Sort-Object { $_[0] })) {
        $at = $Sunrise.AddMinutes($stage[0])
        if ($Now -ge $at) { $result = [int]$stage[1] }
    }
    if ($null -ne $result) { return $result }
    # Before the morning ramp starts - still the overnight level (evening's last stage)
    $last = ($EveningRamp | Sort-Object { $_[0] } | Select-Object -First 1)
    return [int]$last[1]
}

function Update-NightLight {
    param([int]$Target)
    if ($Target -le 0) {
        if (Set-NightLight -On $false) { Write-Done "Night light off" }
        return
    }
    $current = Get-NightLightStrength
    if ($current -ne $Target) {
        if (Set-NightLightStrength -Percent $Target) { Write-Done "Night light strength $Target%" }
    }
    if ((Get-NightLightState) -ne 'on') {
        if (Set-NightLight -On $true) { Write-Done "Night light on ($Target%)" }
    }
}

function Get-CurrentTheme {
    $tp = Get-ItemProperty $ThemeKey -ErrorAction SilentlyContinue
    if ($null -eq $tp -or $null -eq $tp.AppsUseLightTheme) { return 'unknown' }
    if ($tp.AppsUseLightTheme -eq 1) { return 'light' }
    return 'dark'
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Save-Config {
    param([hashtable]$Data)
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    $Data | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

# Merge a single value into the stored config without disturbing the rest
function Save-ConfigValue {
    param([string]$Name, $Value)
    $cfg  = Get-Config
    $data = @{}
    if ($cfg) { foreach ($p in $cfg.PSObject.Properties) { $data[$p.Name] = $p.Value } }
    $data[$Name] = $Value
    Save-Config $data
}

# Keep a stable copy so the tasks keep working after a temp download folder goes
function Install-Self {
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    if ($PSCommandPath -ne $Installed) { Copy-Item -Path $PSCommandPath -Destination $Installed -Force }
    Install-Launcher
}

function Remove-ThemeTasks {
    param([switch]$Quiet)
    foreach ($name in $AllTasks) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            try {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
                if (-not $Quiet) { Write-Done "Scheduled task '$name' removed" }
            } catch {
                Write-Fail "Could not remove '$name': $($_.Exception.Message)"
                Write-Warn "A task registered from an elevated shell needs an elevated shell to change."
                return $false
            }
        } elseif (-not $Quiet) {
            Write-Skip "No scheduled task '$name' found"
        }
    }
    return $true
}

# The theme is per-user and only matters while someone is logged in, so these run
# interactively rather than S4U
function New-ThemePrincipal {
    New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
}
function New-ThemeSettings {
    New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
}
# powershell.exe -WindowStyle Hidden still creates a console host first, so the task
# flashes a black window every time it fires - every 15 minutes, in sun mode. Going
# through wscript.exe with window style 0 means no window is ever created. (S4U would
# also avoid it, but then the task runs outside the desktop session and the repaint
# broadcast never reaches the running apps.)
function Install-Launcher {
    $vbs = @"
' Launches the theme script with no window at all. Written by theme-schedule.ps1.
Set shell = CreateObject("WScript.Shell")
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$Installed""" & args, 0, False
"@
    Set-Content -Path $Launcher -Value $vbs -Encoding ASCII
}

function New-ThemeAction {
    param([string]$ScriptArgs)
    New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$Launcher`" $ScriptArgs"
}

function Register-FixedTask {
    param([string]$TaskName, [datetime]$At, [string]$Mode)
    $action  = New-ThemeAction "-Set$Mode"
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal (New-ThemePrincipal) -Settings (New-ThemeSettings) -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Fail "Could not register '$TaskName': $($_.Exception.Message)"
        return $false
    }
}

function Register-SunTask {
    $action = New-ThemeAction '-Apply'
    # Poll instead of firing at the exact sun times: sunrise/sunset move every day,
    # and polling also fixes the theme up after sleep or a missed window.
    $poll  = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $PollMinutes)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    try {
        Register-ScheduledTask -TaskName $SunTask -Action $action -Trigger @($poll, $logon) -Principal (New-ThemePrincipal) -Settings (New-ThemeSettings) -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Fail "Could not register '$SunTask': $($_.Exception.Message)"
        return $false
    }
}

if ($Help) { Show-Usage; return }

# Persist the appearance preferences so the scheduled task (which only ever passes
# -Apply / -SetLight / -SetDark) honours them too
if ($DarkAccent -ne 'keep') {
    Save-ConfigValue -Name 'DarkAccentOnTaskbar' -Value $(if ($DarkAccent -eq 'on') { 1 } else { 0 })
}
if ($RestartExplorer) { Save-ConfigValue -Name 'RestartExplorer' -Value $true }

# ============================================================
# APPLY MODES (invoked by the scheduled tasks)
# ============================================================
if ($SetLight) { Set-Theme -Light $true;  Write-Done "Light mode applied"; return }
if ($SetDark)  { Set-Theme -Light $false; Write-Done "Dark mode applied";  return }

if ($Apply) {
    $cfg = Get-Config
    if ($null -eq $cfg -or $null -eq $cfg.Latitude) {
        Write-Fail "No stored coordinates - run theme-schedule -Sun to set up sun mode"
        return
    }
    $db = if ($null -ne $cfg.DarkBefore) { [int]$cfg.DarkBefore } else { 0 }
    $la = if ($null -ne $cfg.LightAfter) { [int]$cfg.LightAfter } else { 0 }
    $light = Test-DaylightNow -Lat ([double]$cfg.Latitude) -Lon ([double]$cfg.Longitude) -DarkBefore $db -LightAfter $la

    # Only assert the theme when the sun has actually crossed a boundary (sunrise or
    # sunset) since the last check. Between boundaries, leave whatever theme is set,
    # so a manual flip during the day or night is respected until the next natural
    # change. A missed switch (sleep, powered off over the boundary) still corrects
    # itself, because the stored 'desired' state won't match and counts as a crossing.
    $desired = if ($light) { 'light' } else { 'dark' }
    if ($null -eq $cfg.LastDesired -or $cfg.LastDesired -ne $desired) {
        Set-Theme -Light $light
        Write-Done "Theme set to $desired"
        Save-ConfigValue -Name 'LastDesired' -Value $desired
    } else {
        Write-Skip "No sun boundary since last check - leaving the theme as it is"
    }

    if ($cfg.NightLight -eq $true) {
        $sunNow = Get-SunTimes -Date (Get-Date) -Lat ([double]$cfg.Latitude) -Lon ([double]$cfg.Longitude)
        if ($sunNow.Sunrise -and $sunNow.Sunset) {
            $target = Get-NightLightTarget -Now (Get-Date) -Sunrise $sunNow.Sunrise -Sunset $sunNow.Sunset `
                        -EveningRamp (Get-RampFromConfig $cfg.EveningRamp $DefaultEveningRamp) `
                        -MorningRamp (Get-RampFromConfig $cfg.MorningRamp $DefaultMorningRamp)
            Update-NightLight -Target $target
        }
    }
    return
}

# ============================================================
# STATUS MODE
# ============================================================
if ($Status) {
    Write-Header "Theme Schedule Status"
    Write-Host "  Current theme: $(Get-CurrentTheme)" -ForegroundColor Cyan
    $cfg = Get-Config
    if (Get-ScheduledTask -TaskName $SunTask -ErrorAction SilentlyContinue) {
        Write-Done "Mode: sun (checked every $PollMinutes minutes)"
        if ($cfg) {
            Write-Host "  Location: $($cfg.City) ($($cfg.Latitude), $($cfg.Longitude)) from $($cfg.ZoneId)" -ForegroundColor Cyan
            $sunToday = Get-SunTimes -Date (Get-Date) -Lat ([double]$cfg.Latitude) -Lon ([double]$cfg.Longitude)
            $rise = if ($sunToday.Sunrise) { $sunToday.Sunrise.ToString('HH:mm') } else { 'none today' }
            $set  = if ($sunToday.Sunset)  { $sunToday.Sunset.ToString('HH:mm')  } else { 'none today' }
            Write-Host "  Today: sunrise $rise, sunset $set" -ForegroundColor Cyan
            $cdb = if ($null -ne $cfg.DarkBefore) { [int]$cfg.DarkBefore } else { 0 }
            $cla = if ($null -ne $cfg.LightAfter) { [int]$cfg.LightAfter } else { 0 }
            if ($sunToday.Sunrise -and $sunToday.Sunset) {
                $lightAt = $sunToday.Sunrise.AddMinutes($cla).ToString('HH:mm')
                $darkAt  = $sunToday.Sunset.AddMinutes(-$cdb).ToString('HH:mm')
                Write-Host "  Switches: light $lightAt, dark $darkAt (offsets +$cla / -$cdb min)" -ForegroundColor Cyan
                if ($cfg.NightLight -eq $true) {
                    Write-Host "  Night light: managed (currently $(Get-NightLightState), $(Get-NightLightStrength)%)" -ForegroundColor Cyan
                    foreach ($stage in (Get-RampFromConfig $cfg.EveningRamp $DefaultEveningRamp | Sort-Object { -$_[0] })) {
                        Write-Host "    $($sunToday.Sunset.AddMinutes(-$stage[0]).ToString('HH:mm'))  $($stage[1])%" -ForegroundColor Gray
                    }
                    Write-Host "    $darkAt  dark mode" -ForegroundColor Gray
                    foreach ($stage in (Get-RampFromConfig $cfg.MorningRamp $DefaultMorningRamp | Sort-Object { $_[0] })) {
                        $label = if ($stage[1] -le 0) { 'off' } else { "$($stage[1])%" }
                        Write-Host "    $($sunToday.Sunrise.AddMinutes($stage[0]).ToString('HH:mm'))  $label" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  Night light: not managed (currently $(Get-NightLightState), $(Get-NightLightStrength)%)" -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Warn "Sun task registered but no stored coordinates - re-run with -Sun"
        }
        return
    }
    $any = $false
    foreach ($pair in @(@($LightTask, 'Light'), @($DarkTask, 'Dark'))) {
        $task = Get-ScheduledTask -TaskName $pair[0] -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        $any  = $true
        $time = ($task.Triggers | Select-Object -First 1).StartBoundary
        $when = if ($time) { ([datetime]$time).ToString('HH:mm') } else { 'unknown' }
        Write-Done "$($pair[1]): daily at $when (fixed mode)"
    }
    if (-not $any) { Write-Skip "No theme schedule registered" }
    return
}

# ============================================================
# UNREGISTER MODE
# ============================================================
if ($Unregister) {
    Write-Header "Remove Theme Schedule"
    Remove-ThemeTasks
    return
}

# ============================================================
# REGISTER MODE (default)
# ============================================================
Write-Header "Light / Dark Theme Schedule"

$zone       = Get-ZoneLocation
$fixedAsked = $PSBoundParameters.ContainsKey('LightAt') -or $PSBoundParameters.ContainsKey('DarkAt')
if (-not $LightAt) { $LightAt = '07:00' }
if (-not $DarkAt)  { $DarkAt  = '19:00' }

if ($Sun -and $fixedAsked) {
    Write-Fail "Pick one mode: -Sun, or -LightAt/-DarkAt - not both"
    Show-Usage
    return
}

# Which mode? Switches win; otherwise ask, defaulting to sun when we know where we are
$useSun = $false
if ($Sun) {
    $useSun = $true
} elseif ($fixedAsked) {
    $useSun = $false
} else {
    Write-Host "  Windows 11 has no day/night theme schedule, so this adds scheduled" -ForegroundColor Cyan
    Write-Host "  tasks for your user that switch the Windows + app theme for you." -ForegroundColor Cyan
    Write-Host ""
    if ($zone) {
        Write-Host "    [1] Follow the sun - sunrise/sunset for $($zone.City), worked out offline" -ForegroundColor Gray
        Write-Host "        from your Windows timezone ($($zone.ZoneId)). Tracks the seasons." -ForegroundColor Gray
    } else {
        Write-Host "    [1] Follow the sun - unavailable: no known city for timezone" -ForegroundColor DarkGray
        Write-Host "        '$((Get-TimeZone).Id)'. Use -Sun -Latitude <deg> -Longitude <deg>." -ForegroundColor DarkGray
    }
    Write-Host "    [2] Fixed times    - light and dark at times you pick" -ForegroundColor Gray
    Write-Host "    [3] Skip" -ForegroundColor Gray
    Write-Host ""
    if ($Yes) {
        $choice = if ($zone) { '1' } else { '2' }
    } else {
        $default = if ($zone) { '1' } else { '2' }
        $choice  = Read-Host "  Which one? [$default]"
        if (-not $choice) { $choice = $default }
    }
    if ($choice -eq '3') { Write-Skip "Skipping theme schedule"; return }
    if ($choice -eq '1' -and -not $zone) {
        Write-Warn "No coordinates for your timezone - falling back to fixed times"
        $choice = '2'
    }
    $useSun = ($choice -eq '1')
    if (-not $useSun -and -not $Yes) {
        $ansLight = Read-Host "  Light mode at (24h HH:mm) [$LightAt]"
        if ($ansLight) { $LightAt = $ansLight }
        $ansDark = Read-Host "  Dark mode at (24h HH:mm) [$DarkAt]"
        if ($ansDark) { $DarkAt = $ansDark }
    }
}

# ------------------------------------------------------------
# SUN MODE
# ------------------------------------------------------------
if ($useSun) {
    $lat    = $Latitude
    $lon    = $Longitude
    $city   = 'manual'
    $zoneId = (Get-TimeZone).Id
    if ([double]::IsNaN($lat) -or [double]::IsNaN($lon)) {
        if (-not $zone) {
            Write-Fail "No known city for timezone '$zoneId' - pass -Latitude and -Longitude"
            return
        }
        $lat = $zone.Latitude; $lon = $zone.Longitude; $city = $zone.City
    }
    if ($lat -lt -90 -or $lat -gt 90)   { Write-Fail "-Latitude must be between -90 and 90";   return }
    if ($lon -lt -180 -or $lon -gt 180) { Write-Fail "-Longitude must be between -180 and 180"; return }

    $sunToday = Get-SunTimes -Date (Get-Date) -Lat $lat -Lon $lon
    $rise = if ($sunToday.Sunrise) { $sunToday.Sunrise.ToString('HH:mm') } else { 'none today' }
    $set  = if ($sunToday.Sunset)  { $sunToday.Sunset.ToString('HH:mm')  } else { 'none today' }
    Write-Host "  Will set:" -ForegroundColor White
    Write-Host "    - Light at sunrise, dark at sunset, for $city ($lat, $lon)" -ForegroundColor Gray
    Write-Host "    - Today that is sunrise $rise, sunset $set" -ForegroundColor Gray
    if ($sunToday.Sunrise -and $sunToday.Sunset) {
        $lightAt = $sunToday.Sunrise.AddMinutes($LightAfter).ToString('HH:mm')
        $darkAt  = $sunToday.Sunset.AddMinutes(-$DarkBefore).ToString('HH:mm')
        Write-Host "    - So today: light at $lightAt, dark at $darkAt (offsets +$LightAfter / -$DarkBefore min)" -ForegroundColor Gray
    }
    Write-Host "    - Checked every $PollMinutes minutes, so it follows the seasons" -ForegroundColor Gray
    Write-Host "  Wrong city for your area? Re-run with -Latitude and -Longitude." -ForegroundColor DarkGray
    if (-not (Confirm-Default-Yes "Register sun-based theme switching?")) {
        Write-Skip "Skipping theme schedule"
        return
    }
    Install-Self
    $prev   = Get-Config
    $useNl  = if ($NoNightLight) { $false } elseif ($NightLight) { $true } elseif ($prev) { $prev.NightLight -eq $true } else { $false }
    $evRamp = Get-RampFromConfig ($(if ($prev) { $prev.EveningRamp })) $DefaultEveningRamp
    $moRamp = Get-RampFromConfig ($(if ($prev) { $prev.MorningRamp })) $DefaultMorningRamp
    Save-Config @{ Mode = 'sun'; Latitude = $lat; Longitude = $lon; City = $city; ZoneId = $zoneId
                   DarkBefore = $DarkBefore; LightAfter = $LightAfter
                   NightLight = $useNl; EveningRamp = $evRamp; MorningRamp = $moRamp }
    Remove-ThemeTasks -Quiet
    Write-Step "Registering '$SunTask' (every $PollMinutes minutes)..."
    if (-not (Register-SunTask)) {
        Write-Fail "Theme schedule NOT registered - re-run this from an elevated shell"
        return
    }
    Write-Done "Sun-based theme schedule registered"
    Write-Step "Applying the right theme for right now..."
    $light = Test-DaylightNow -Lat $lat -Lon $lon -DarkBefore $DarkBefore -LightAfter $LightAfter
    Set-Theme -Light $light
    Save-ConfigValue -Name 'LastDesired' -Value $(if ($light) { 'light' } else { 'dark' })
    Write-Done ("Theme set to " + $(if ($light) { 'light' } else { 'dark' }))
    if ($useNl -and $sunToday.Sunrise -and $sunToday.Sunset) {
        $target = Get-NightLightTarget -Now (Get-Date) -Sunrise $sunToday.Sunrise -Sunset $sunToday.Sunset `
                    -EveningRamp $evRamp -MorningRamp $moRamp
        Update-NightLight -Target $target
    }
    Write-Host "  Check it any time with: theme-schedule -Status   Remove it with: theme-schedule -Unregister" -ForegroundColor DarkGray
    return
}

# ------------------------------------------------------------
# FIXED MODE
# ------------------------------------------------------------
$lightTime = Get-TimeOrNull $LightAt
$darkTime  = Get-TimeOrNull $DarkAt
if (-not $lightTime) { Write-Fail "-LightAt '$LightAt' is not a valid 24h time (HH:mm)"; Show-Usage; return }
if (-not $darkTime)  { Write-Fail "-DarkAt '$DarkAt' is not a valid 24h time (HH:mm)";  Show-Usage; return }

Write-Host "  Will set:" -ForegroundColor White
Write-Host "    - Light mode daily at $($lightTime.ToString('HH:mm'))" -ForegroundColor Gray
Write-Host "    - Dark mode daily at $($darkTime.ToString('HH:mm'))" -ForegroundColor Gray
Write-Host "  Change the times with: theme-schedule -LightAt 06:30 -DarkAt 18:00" -ForegroundColor DarkGray

if (-not (Confirm-Default-Yes "Register the light/dark schedule?")) {
    Write-Skip "Skipping theme schedule"
    return
}

Install-Self
Save-Config @{ Mode = 'fixed'; LightAt = $lightTime.ToString('HH:mm'); DarkAt = $darkTime.ToString('HH:mm') }
Remove-ThemeTasks -Quiet
Write-Step "Registering '$LightTask' (light at $($lightTime.ToString('HH:mm')))..."
$okLight = Register-FixedTask -TaskName $LightTask -At $lightTime -Mode 'Light'
Write-Step "Registering '$DarkTask' (dark at $($darkTime.ToString('HH:mm')))..."
$okDark  = Register-FixedTask -TaskName $DarkTask -At $darkTime -Mode 'Dark'
if (-not ($okLight -and $okDark)) {
    Write-Fail "Theme schedule NOT fully registered - re-run this from an elevated shell"
    return
}
Write-Done "Theme schedule registered"

# Apply whichever side of the schedule we are currently in, so the theme is right now
$now        = Get-Date
$lightToday = $now.Date.Add($lightTime.TimeOfDay)
$darkToday  = $now.Date.Add($darkTime.TimeOfDay)
$wantLight  = if ($lightToday -le $darkToday) {
    ($now -ge $lightToday -and $now -lt $darkToday)
} else {
    # Dark window wraps past midnight (dark time earlier in the day than light time)
    -not ($now -ge $darkToday -and $now -lt $lightToday)
}
Write-Step "Applying the current period now..."
Set-Theme -Light $wantLight
Write-Done ("Theme set to " + $(if ($wantLight) { 'light' } else { 'dark' }))
Write-Host "  Check it any time with: theme-schedule -Status   Remove it with: theme-schedule -Unregister" -ForegroundColor DarkGray
