# Changelog

## 1.2.1

- Max never asks for the password again because of a helper version: any installed helper is used,
  and only a missing one, or one that just failed, is installed anew.
- Manifest description within the marketplace's 500 characters (a test keeps it there).

## 1.2.0

- Max on any machine the helper knows: every hwmon fan (hp-wmi, asus-wmi, dell-smm, nct6775, it87 …)
  through the kernel's `pwmN_enable = 0`, ThinkPad (`/proc/acpi/ibm/fan`), MSI (`msi-ec cooler_boost`).
  The settings from before Max are saved and put back exactly; GPU fans are never touched; without any
  of these the Max button does not appear.
- Max's state comes from `/run/ismoil-fans/max`, written by the helper, so it reads the same on any hardware.
- Helper version 3 (the widget updates an older one on the next Max click). Tests run it on fake
  `/sys`, `/proc` and `/run`.

## 1.1.2

- Max installs what it needs by itself: when the helper is missing or older than the widget needs
  (its version is read from the helper file, readable without root), clicking Max opens the installer
  — the password is the only thing to type — and Max turns on as soon as the helper is in place. No
  command to run, no Install button. Gives up waiting after 3 minutes if the window is closed.

## 1.1.1

- A clicked mode lights up at once and stays lit until the system shows it (powerprofilesctl returns
  before the profile is applied, so the popup used to show the previous mode — one step behind).
- Max works from the shell: the shell runs in the user's systemd manager, outside the login session,
  where polkit has no agent to ask for a password. `helper/install.sh` adds a polkit rule letting wheel
  users run this one helper (full speed or automatic only) without one. When Max fails, the popup
  offers to update the helper.

## 1.1.0

- Modes are whatever this computer offers (any power-profiles-daemon profile, quietest first),
  plus **Auto** (default: quiet at rest, medium at work, never the loudest, 20 s hysteresis) and
  **Max** where a full-speed switch exists (hp-wmi), through an optional root helper installed only
  on the user's click (`helper/install.sh`, polkit `auth_admin_keep`, reset to auto at boot).
- The mode shown is read from `platform_profile` every poll: it can no longer show a stale mode.
- IPC `state` tells what the widget sees.

## 1.0.1

- The power mode switches from any bar: the bar on another monitor (which never opened its popup) no longer ignores a click or `mode`/`nextMode` IPC; powerprofilesctl decides what exists, and a failed switch is logged.

## 1.0.0 — 2026-11-14

First release: fans and temperatures from hwmon, NVIDIA without waking it, power-profiles-daemon modes; family look (kit 2.0.3); en/ru.
