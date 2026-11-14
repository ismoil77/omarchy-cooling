# Changelog

## 1.3.2

- A landscape banner as the marketplace preview (the card crops a strip from the centre, a tall popup
  screenshot showed only its blurred top); a shorter description that says what the widget is first;
  the README shows the popup in both languages.

## 1.3.1

- Security (marketplace review), helper 5: the root helper sets its own `umask 022` and `PATH`; its
  state folder `/run/ismoil-fans` must be a real folder owned by root and writable by nobody else, or it
  is removed and made anew, its contents untrusted; links in place of its files are dropped, never
  followed. The saved state holds driver names and numbers only, never a path.
  Installed an older helper? Run `helper/install.sh` once to replace it.

## 1.3.0 — audit

- The popup is built the first time it opens, not at shell start on every monitor.
- Closed, only the processor's sensors are read; fans, SSD and board (slow files, read on the GUI
  thread) wait for the popup. The helper file is read only when Max is clicked.
- Fan rows are kept between readings: the icons spin evenly instead of restarting every 2 s.
- A second mode click while one is being applied is queued instead of lost. `nvidia-smi` runs every 5 s
  while open, not every poll. Two bars no longer both switch the profile in Auto.
- A failed "back to automatic" never opens the installer; IPC `mode` ignores names this machine lacks.
- Helper 4: `pwmN_enable = 0` only on drivers that document it as full speed (hp, asus, nct67xx, it87,
  f718xx, w836xx); other drivers get manual mode at 255 (0 turns a `pwm-fan` off). Settings are saved by
  driver name, so they come back after hwmon renumbering.
- The installer path is quoted for both shells that parse it.
- README: remove the helper before the plugin; the `mode` setting; what runs in the background.

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
