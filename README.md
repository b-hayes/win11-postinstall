# win11-postinstall

Interactive post-install setup for a fresh Windows 11 install: telemetry/privacy
tweaks, Cortana/web search off, Copilot & Recall removal (with a scheduled task to
keep them off after updates), bloatware removal, gaming performance tweaks, and more.
Every step prompts before acting and skips work already done.

## Run

Elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/b-hayes/win11-postinstall/main/bootstrap.ps1 | iex
```

The bootstrap self-elevates, downloads the scripts, and launches the menu.

## Layout

- `cli/setup/Win11PostInstall.ps1` - main interactive script
- `bin/copilot-removal.ps1` - Copilot/Recall removal + reinstall-guard task (called by the main script)
- `bootstrap.ps1` - downloads both and runs the main script
