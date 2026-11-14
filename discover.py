#!/usr/bin/env python3
"""Finds the fans and temperature sensors of this machine for the Cooling widget.

Run once at start (and when the popup opens); the widget then re-reads the
files it lists in place, with no process per tick. Prints one JSON object, no
human words:

  fans      [{path, driver, index}]                 fanN_input files, RPM
  temps     [{path, driver, group, label, crit}]    tempN_input files, millidegrees
            group: cpu / gpu / ssd / board / other; crit in degrees or null
  gpus      [{vendor, runtime}]                     discrete GPUs: runtime is the
            power/runtime_status file ("suspended" = asleep, do not wake it)
  profiles  bool                                    power-profiles-daemon is there

  discover.py [SYSFS_ROOT]     (a fake /sys for tests)
"""
import json
import os
import shutil
import sys

GROUPS = {
    "coretemp": "cpu", "k10temp": "cpu", "zenpower": "cpu", "cpu_thermal": "cpu", "x86_pkg_temp": "cpu",
    "amdgpu": "gpu", "nouveau": "gpu", "radeon": "gpu", "i915": "gpu", "xe": "gpu",
    "nvme": "ssd", "drivetemp": "ssd",
    "acpitz": "board", "pch_cannonlake": "board", "pch_skylake": "board", "thinkpad": "board", "dell_smm": "board",
}
# Not about cooling.
SKIP = {"BAT0", "BAT1", "ADP1", "AC", "ucsi_source_psy_USBC000:001"}
VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def number(path):
    try:
        return int(read(path))
    except ValueError:
        return None


def discover(root="/sys"):
    fans, temps = [], []
    base = os.path.join(root, "class", "hwmon")
    try:
        hwmons = sorted(os.listdir(base), key=lambda n: (len(n), n))
    except OSError:
        hwmons = []
    for hw in hwmons:
        d = os.path.join(base, hw)
        driver = read(os.path.join(d, "name"))
        if not driver or driver in SKIP or driver.startswith("ucsi"):
            continue
        try:
            files = sorted(os.listdir(d))
        except OSError:
            continue
        for f in files:
            if not f.endswith("_input"):
                continue
            stem = f[:-len("_input")]
            path = os.path.join(d, f)
            if stem.startswith("fan") and stem[3:].isdigit():
                if number(path) is not None:
                    fans.append({"path": path, "driver": driver, "index": int(stem[3:])})
            elif stem.startswith("temp") and stem[4:].isdigit():
                value = number(path)
                if value is None or value <= 0:
                    continue
                crit = number(os.path.join(d, stem + "_crit")) or number(os.path.join(d, stem + "_max"))
                temps.append({
                    "path": path, "driver": driver, "group": GROUPS.get(driver, "other"),
                    "label": read(os.path.join(d, stem + "_label")) or driver,
                    # A limit past 150 °C is a placeholder, not a limit.
                    "crit": crit // 1000 if crit and 0 < crit // 1000 <= 150 else None,
                })
    # acpi_fan repeats a fan a real driver already reports: only alone does it count.
    if any(f["driver"] != "acpi_fan" for f in fans):
        fans = [f for f in fans if f["driver"] != "acpi_fan"]

    gpus = []
    pci = os.path.join(root, "bus", "pci", "devices")
    try:
        devices = sorted(os.listdir(pci))
    except OSError:
        devices = []
    for dev in devices:
        d = os.path.join(pci, dev)
        if not read(os.path.join(d, "class")).startswith("0x03"):
            continue
        vendor = VENDORS.get(read(os.path.join(d, "vendor")), "other")
        # The integrated GPU shares the CPU's sensors; only a discrete one is listed.
        if vendor == "intel":
            continue
        gpus.append({"vendor": vendor, "runtime": os.path.join(d, "power", "runtime_status")})

    return {"fans": fans, "temps": temps, "gpus": gpus, "profiles": shutil.which("powerprofilesctl") is not None}


if __name__ == "__main__":
    print(json.dumps(discover(sys.argv[1] if len(sys.argv) > 1 else "/sys")))
