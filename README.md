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
- **Power mode**: Quiet / Balanced / Performance through power-profiles-daemon — no root.
  Right click on the bar steps through them.
- Colours: cool, warm from 75°, hot near the processor's limit (or 90°).

## Light on the system

`discover.py` finds the sensors once (and when the popup opens); after that the sensor files are
re-read in place every `interval` seconds, with no process.

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
NVIDIA GPU. The widget never writes to `/sys` and needs no root.

## Tests

```bash
tests/run.sh   # discover.py against a fake /sys; Model.js and Strings.js in Node; omarchy plugin validate
```

## License

MIT
