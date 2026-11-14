"""discover.py against a fake /sys."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import discover  # noqa: E402


def put(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


class Discover(unittest.TestCase):
    def sysfs(self):
        root = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(root))
        h = "class/hwmon/"
        put(root, h + "hwmon1/name", "acpi_fan\n"); put(root, h + "hwmon1/fan1_input", "5085\n")
        put(root, h + "hwmon5/name", "hp\n"); put(root, h + "hwmon5/fan1_input", "5085\n"); put(root, h + "hwmon5/fan2_input", "4427\n")
        put(root, h + "hwmon6/name", "coretemp\n"); put(root, h + "hwmon6/temp1_input", "88000\n")
        put(root, h + "hwmon6/temp1_label", "Package id 0\n"); put(root, h + "hwmon6/temp1_crit", "100000\n")
        put(root, h + "hwmon4/name", "nvme\n"); put(root, h + "hwmon4/temp2_input", "72850\n"); put(root, h + "hwmon4/temp2_max", "65261850\n")
        put(root, h + "hwmon3/name", "BAT0\n"); put(root, h + "hwmon3/temp1_input", "30000\n")
        put(root, h + "hwmon10/name", "mystery\n"); put(root, h + "hwmon10/temp1_input", "0\n")
        put(root, "bus/pci/devices/0000:01:00.0/class", "0x030000\n"); put(root, "bus/pci/devices/0000:01:00.0/vendor", "0x10de\n")
        put(root, "bus/pci/devices/0000:00:02.0/class", "0x030000\n"); put(root, "bus/pci/devices/0000:00:02.0/vendor", "0x8086\n")
        return root

    def test_fans_temps_and_gpus(self):
        d = discover.discover(self.sysfs())
        self.assertEqual([(f["driver"], f["index"]) for f in d["fans"]], [("hp", 1), ("hp", 2)])
        temps = {t["driver"]: t for t in d["temps"]}
        self.assertEqual(set(temps), {"coretemp", "nvme"})       # battery skipped, a 0 reading skipped
        self.assertEqual((temps["coretemp"]["group"], temps["coretemp"]["label"], temps["coretemp"]["crit"]), ("cpu", "Package id 0", 100))
        self.assertIsNone(temps["nvme"]["crit"])                  # 65261 °C is a placeholder
        self.assertEqual([g["vendor"] for g in d["gpus"]], ["nvidia"])
        self.assertTrue(d["gpus"][0]["runtime"].endswith("0000:01:00.0/power/runtime_status"))
        self.assertIsNone(d["platform"])
        self.assertIsNone(d["maxFan"])
        self.assertIn("helper", d)

    def test_hp_full_speed_switch_and_platform_profile(self):
        root = self.sysfs()
        put(root, "class/hwmon/hwmon5/pwm1_enable", "2\n")
        put(root, "firmware/acpi/platform_profile", "balanced\n")
        d = discover.discover(root)
        self.assertTrue(d["maxFan"].endswith("hwmon5/pwm1_enable"))
        self.assertTrue(d["platform"].endswith("firmware/acpi/platform_profile"))

    def test_acpi_fan_alone_still_counts(self):
        root = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(root))
        put(root, "class/hwmon/hwmon0/name", "acpi_fan\n"); put(root, "class/hwmon/hwmon0/fan1_input", "1200\n")
        self.assertEqual([f["driver"] for f in discover.discover(root)["fans"]], ["acpi_fan"])

    def test_no_sysfs_means_nothing_not_a_crash(self):
        d = discover.discover("/nonexistent")
        self.assertEqual((d["fans"], d["temps"], d["gpus"]), ([], [], []))


if __name__ == "__main__":
    unittest.main()
