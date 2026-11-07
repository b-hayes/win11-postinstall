# Remote-Controlled Test Folder

DO NOT USE THIS FOLDER. It is not part of the post-install tool.

It exists only to test and diagnose the PowerShell scripts remotely across
multiple machines over SSH. Nothing here is meant to be run by an end user.

## Purpose

The setup scripts are interactive and change system state, so they must be
verified on a real Windows machine before release. This folder documents how
to expose a test machine over SSH so a script can be driven remotely, each
step applied, and each registry key or service queried back to confirm the
effect.

## Enable OpenSSH Server on the test machine

Run in an elevated PowerShell session on the Windows test machine:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

Set the default SSH shell to PowerShell so remote sessions land in pwsh:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

## Key-based auth note

Members of the Administrators group do NOT read `~/.ssh/authorized_keys`.
Their keys go in `C:\ProgramData\ssh\administrators_authorized_keys`, which
must be owned by Administrators/SYSTEM with no other principals granted
access, or sshd silently ignores it.

```powershell
$key = 'ssh-ed25519 AAAA... your-public-key'
$f   = 'C:\ProgramData\ssh\administrators_authorized_keys'
Add-Content -Path $f -Value $key
icacls $f /inheritance:r
icacls $f /grant 'Administrators:F' 'SYSTEM:F'
```

## Driving a script remotely

From the controlling machine, issue discrete commands over SSH. Each command
is one-shot, so interactive scripts (`Read-Host`, `ReadKey`) will hang - run
the script in an unattended mode, or apply and verify sections individually.

```sh
ssh <user>@<test-machine-ip> 'powershell -NoProfile -Command "reg query \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" /v Hidden"'
```

The most reliable verification is to apply a section, then query the keys and
services it touched and confirm the expected values.

## Rules

- No machine-specific details in this repo (it is public). Use placeholders
  like `<user>` and `<test-machine-ip>`.
- Test machines are disposable. Never point remote script runs at a machine
  whose state you care about.
