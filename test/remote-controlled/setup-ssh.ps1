<#
.SYNOPSIS
    TESTING ONLY. Set up OpenSSH Server on a disposable test machine so the
    win11-postinstall scripts can be driven remotely over the LAN.

    Run from the test branch:
        irm https://raw.githubusercontent.com/b-hayes/win11-postinstall/nag-removal-and-remote-testing/test/remote-controlled/setup-ssh.ps1 | iex

    Installs sshd, enables it, adds a LAN-only (Private profile) firewall rule,
    sets PowerShell as the default SSH shell, installs the remote-test public key
    with the correct ACL, and prints this machine's LAN IP + username.

    Not for end users. Remove the key + sshd when done (see bottom of this file).
#>

$ErrorActionPreference = 'Stop'
$KeyUrl = 'https://raw.githubusercontent.com/b-hayes/win11-postinstall/nag-removal-and-remote-testing/test/remote-controlled/win11test.pub'
$SelfUrl = 'https://raw.githubusercontent.com/b-hayes/win11-postinstall/nag-removal-and-remote-testing/test/remote-controlled/setup-ssh.ps1'

function Write-Step { param([string]$T); Write-Host "  [*] $T" -ForegroundColor Yellow }
function Write-Done { param([string]$T); Write-Host "  [+] $T" -ForegroundColor Green }

# Self-elevate if not already admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', "irm $SelfUrl | iex"
    )
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "  Remote-test SSH setup (LAN only)" -ForegroundColor Cyan
Write-Host ""

# 1. Install OpenSSH Server
Write-Step "Installing OpenSSH Server (if missing)..."
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    Write-Done "OpenSSH Server installed"
} else {
    Write-Done "OpenSSH Server already installed"
}

# 2. Start + auto-start the service
Write-Step "Starting sshd and setting it to start automatically..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Done "sshd running"

# 3. LAN-only firewall rule (Private profile)
Write-Step "Adding LAN-only firewall rule for port 22 (Private profile)..."
Get-NetFirewallRule -Name 'sshd-win11test' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -Name 'sshd-win11test' -DisplayName 'OpenSSH Server (win11-postinstall test, LAN only)' `
    -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Private | Out-Null
Write-Done "Firewall rule added (Private networks only - not Public/internet)"

# 4. Default SSH shell = PowerShell
Write-Step "Setting default SSH shell to PowerShell..."
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
Write-Done "Default shell set to PowerShell"

# 5. Install the remote-test public key for admins, with correct ACL
Write-Step "Installing remote-test public key..."
$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
$key = (irm $KeyUrl).Trim()
$existing = if (Test-Path $f) { Get-Content $f -Raw } else { '' }
if ($existing -notmatch [regex]::Escape($key)) {
    Add-Content -Path $f -Value $key -Encoding ascii
    Write-Done "Public key added"
} else {
    Write-Done "Public key already present"
}
# administrators_authorized_keys must be owned by admins/SYSTEM only, or sshd ignores it
icacls $f /inheritance:r | Out-Null
icacls $f /grant 'Administrators:F' 'SYSTEM:F' | Out-Null
Write-Done "ACL set (Administrators + SYSTEM only)"

# 6. Report IP + username for the controller
Write-Host ""
Write-Host "  Done. Give these to the controller:" -ForegroundColor Cyan
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' }
foreach ($ip in $ips) {
    Write-Host ("    IP:   {0}  ({1})" -f $ip.IPAddress, $ip.InterfaceAlias) -ForegroundColor White
}
Write-Host ("    User: {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -ForegroundColor White
Write-Host ""
Write-Host "  Password auth is left ENABLED (default). It's LAN-only; a router port-forward" -ForegroundColor DarkGray
Write-Host "  would be required to expose it, which is not configured." -ForegroundColor DarkGray
Write-Host ""

<#
  CLEANUP when done testing:
    Get-Content C:\ProgramData\ssh\administrators_authorized_keys   # review
    Remove-Item C:\ProgramData\ssh\administrators_authorized_keys   # or edit out the test key
    Stop-Service sshd; Set-Service sshd -StartupType Disabled
    Remove-NetFirewallRule -Name 'sshd-win11test'
    Remove-WindowsCapability -Online -Name (Get-WindowsCapability -Online | ? { $_.Name -like 'OpenSSH.Server*' }).Name
#>
