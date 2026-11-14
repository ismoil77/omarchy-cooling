# Changelog

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
