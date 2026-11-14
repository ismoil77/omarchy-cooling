# Cooling for the Omarchy bar

[Русский](README.ru.md)

Fans and temperatures for any machine: the processor's temperature in the bar, coloured as it heats,
and a popup with every fan the kernel reports and its speed, temperatures by group, and the power mode.

![preview](preview.png)

- **Fans**: every `fanN_input` hwmon reports (hp-wmi, thinkpad_acpi, asus-wmi, dell-smm, nct6775,
  it87, acpi_fan…), their speed against the fastest one, a spinning icon while the popup is open.
  When Linux sees no fan, it says so.
- **Temperatures**: processor (package and the hottest core), graphics, SSD, board.
  A discrete NVIDIA GPU is read with `nvidia-smi` only while the popup is open, and only when it is
  awake: a sleeping GPU is never woken (that would drain the battery).
- **Modes — whatever this computer offers**, never a fixed list:
  - every profile power-profiles-daemon has (no root), quietest first, with plain names
    (power-saver → Quiet, balanced → Medium, performance → Powerful; an unknown name as it is);
  - **Auto** (the default, when there are two or more): the quietest profile while the computer rests,
    medium while it works (load or 70°+), never the loudest; it changes only after its reason held 20 s;
  - **Max**, only where a full-speed fan switch exists (hp-wmi today): fans at full speed. It needs a
    one-time install of a root helper — the widget offers it, nothing is installed until you click
    *Install* and type your password. Fans go back to automatic at every boot.
  - The mode shown is read from `platform_profile`, so it is always the one in force.
  - Right click on the bar steps through the modes (Max left out).
- Colours: cool, warm from 75°, hot near the processor's limit (or 90°).

## Light on the system

`discover.py` finds the sensors once (and when the popup opens); after that the sensor files are
re-read in place every `interval` seconds, with no process.

## The Max helper (optional)

`helper/install.sh` puts three files in place (and `helper/install.sh remove` takes them out):

- `/usr/local/libexec/ismoil-fans-max` — writes `0` (full speed) or `2` (auto) to hp-wmi's
  `pwm1_enable`; it takes no path or number from its caller;
- a polkit action for it, and a rule letting administrators (`wheel`) run this one helper without a
  password: the shell runs outside the login session, where polkit has no agent to ask one;
- `ismoil-fans-auto.service`, which sets the fans back to automatic at boot.

## Install

```bash
omarchy plugin add https://github.com/ismoil77/omarchy-cooling --enable
```

Update with `omarchy plugin update ismoil.fans`.

## Remove

```bash
omarchy plugin remove ismoil.fans
```

Nothing is left behind.

## Settings

| Setting | Default | |
|---|---|---|
| `interval` | 3 | seconds between reads |
| `language` | auto | `en`, `ru`, or the system locale |
| `textSize` | Normal | Normal, Large, Extra large |
| `animations` | true | spinning fan icons |

## Requirements

`python3` (stdlib only). Optional: `power-profiles-daemon` for the mode switch, `nvidia-smi` for an
NVIDIA GPU. The widget itself never writes to `/sys` and needs no root; only the optional helper does,
through polkit.

## Tests

```bash
tests/run.sh   # discover.py against a fake /sys; Model.js and Strings.js in Node; omarchy plugin validate
```

## License

MIT
