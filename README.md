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

<!-- TODO: remove this block before merging - test command for the nag-removal-and-remote-testing branch -->
```powershell
$RepoRaw='https://raw.githubusercontent.com/b-hayes/win11-postinstall/nag-removal-and-remote-testing'; irm $RepoRaw/bootstrap.ps1 | iex
```

The bootstrap self-elevates, downloads the scripts, and launches the menu.

## New machine flow

Install Windows, connect to the internet, and let Windows Updates fully finish and
reboot before the one-off installers run. The script asks up front whether this is a
new machine with updates unfinished (pre-filled yes if it detects a pending reboot or
active update). In that pre-update pass it applies only the safe, durable tweaks plus
the guard, skips the flaky steps (bloatware, Brave, WinUtil, extra UI), and
registers a one-time RunOnce so the menu re-opens after the next reboot to finish them.

## Standalone modules

Run any of these directly from an elevated shell (each self-elevates if needed):

- `bin/copilot-removal.ps1` - remove Copilot and Windows Recall
- `bin/nag-removal.ps1` - disable all system nags, ads, suggestions, setup prompts
- `bin/debloat.ps1` - uninstall built-in and pushed bloatware apps
- `bin/remove-onedrive.ps1` - fully uninstall OneDrive + remove its File Explorer icon
- `bin/gaming-tweaks.ps1` - gaming performance tweaks + optional VBS/HVCI disable.
  Hardware-Accelerated GPU Scheduling (HAGS) is its own question (`-HagsOnly` asks
  only that). It moves GPU work scheduling from the CPU to the GPU: better frame
  timing and DLSS frame generation, at the cost of input latency and stutter. Nvidia
  DLSS frame gen requires it. AMD FSR frame gen works without it, but because AMD
  recommends it some games grey the option out when it is off. Off otherwise.
- `bin/theme-schedule.ps1` - automatic light/dark theme switching, by sunrise/sunset or fixed times
- `bin/guard.ps1` - register the daily guard task (re-runs copilot-removal + nag-removal)

Theme schedule: `theme-schedule` asks which mode you want.

- `-Sun` follows local sunrise/sunset. Latitude and longitude come from the Windows
  timezone's city (IDs are city based, so `Tasmania Standard Time` -> Hobart), computed
  offline with no location permission and no network. Override with
  `-Latitude <deg> -Longitude <deg>` if your zone spans a wide latitude (Perth vs
  Broome). One task polls every 15 minutes, so it tracks the seasons and corrects
  itself after sleep.
- `-LightAt HH:mm -DarkAt HH:mm` uses fixed times instead (default 07:00 / 19:00).

`-NightLight` also ramps Windows night light around the switches: 15% at sunset-75
min, 30% at -45, 40% at -15, holding overnight, then 40% at sunrise, 30% at +15,
15% at +45, off at +75. Stages are stored in the config file and can be edited
there. Windows exposes no API for night light, so this writes the undocumented
CloudStore blob; the script bails out instead of writing if the format is not what
it expects, which a Windows feature update could change.

Appearance settings are left alone: wallpaper-derived accent colour, accent on title
bars/borders and your wallpaper are untouched. The one exception is 'accent colour on
Start and taskbar', which Windows clears on the way to light mode and never restores -
the schedule remembers it and puts it back (`-DarkAccent on|off|keep`).

Secondary-monitor taskbars can keep the old colours until Explorer restarts; add
`-RestartExplorer` if that bothers you (it closes open File Explorer windows).

`theme-schedule -Status` shows the mode and today's sun times, `-Unregister` removes it.
No admin needed - the theme is per-user.

Guard control: `guard` registers it, `guard -Hidden` makes it run silently,
`guard -Unregister` removes it.

## Layout

- `cli/setup/Win11PostInstall.ps1` - main interactive orchestrator
- `bin/*.ps1` - standalone per-concern modules (above)
- `bootstrap.ps1` - downloads everything and runs the main script
- `test/remote-controlled/` - testing-only notes for driving scripts over SSH (not for end users)
