# win11-postinstall

Interactive post-install setup for a fresh Windows 11 install: telemetry/privacy
tweaks, Cortana/web search off, Copilot & Recall removal, system nag/ad removal,
bloatware removal, gaming performance tweaks, and more. A single scheduled guard
re-applies Copilot and nag removal after feature updates reset them. Every step
prompts before acting and skips work already done.

Each concern is a standalone, self-elevating, idempotent script in `bin/` that can
be run on its own. The main script orchestrates them and keeps the one-off tweaks
(locale, dark mode, Explorer, etc.) inline.

## Run

Elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/b-hayes/win11-postinstall/main/bootstrap.ps1 | iex
```

The bootstrap self-elevates, downloads the scripts, and launches the menu.

## Standalone modules

Run any of these directly from an elevated shell (each self-elevates if needed):

- `bin/copilot-removal.ps1` - remove Copilot and Windows Recall
- `bin/nag-removal.ps1` - disable all system nags, ads, suggestions, setup prompts
- `bin/debloat.ps1` - uninstall built-in and pushed bloatware apps
- `bin/gaming-tweaks.ps1` - gaming performance tweaks + optional VBS/HVCI disable
- `bin/guard.ps1` - register the daily guard task (re-runs copilot-removal + nag-removal)

Guard control: `guard` registers it, `guard -Hidden` makes it run silently,
`guard -Unregister` removes it.

## Layout

- `cli/setup/Win11PostInstall.ps1` - main interactive orchestrator
- `bin/*.ps1` - standalone per-concern modules (above)
- `bootstrap.ps1` - downloads everything and runs the main script
- `test/remote-controlled/` - testing-only notes for driving scripts over SSH (not for end users)
