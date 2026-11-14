"""helper/ismoil-fans-max on fake /sys, /proc and /run (a copy with those paths swapped in)."""
import os
import shutil
import subprocess
import tempfile
import unittest

HELPER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "helper", "ismoil-fans-max")


class Helper(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        self.sys, self.proc, self.run_dir = (os.path.join(self.root, n) for n in ("sys", "proc", "run/ismoil-fans"))
        os.makedirs(self.sys); os.makedirs(self.proc)
        src = open(HELPER).read()
        src = src.replace("SYS=/sys", "SYS=" + self.sys).replace("PROC=/proc", "PROC=" + self.proc).replace("RUN=/run/ismoil-fans", "RUN=" + self.run_dir)
        self.helper = os.path.join(self.root, "helper")
        with open(self.helper, "w") as f:
            f.write(src)
        os.chmod(self.helper, 0o755)

    def put(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def get(self, rel):
        with open(os.path.join(self.root, rel)) as f:
            return f.read().strip()

    def call(self, *args):
        return subprocess.run([self.helper, *args], capture_output=True, text=True)

    def marker(self):
        return os.path.exists(os.path.join(self.run_dir, "max"))

    def test_hp_full_speed_and_back(self):
        self.put("sys/class/hwmon/hwmon5/name", "hp\n"); self.put("sys/class/hwmon/hwmon5/pwm1_enable", "2\n")
        self.assertEqual(self.call("max").returncode, 0)
        self.assertEqual(self.get("sys/class/hwmon/hwmon5/pwm1_enable"), "0")
        self.assertTrue(self.marker())
        self.assertEqual(self.get("run/ismoil-fans/max"), "on")
        self.assertEqual(self.call("auto").returncode, 0)
        self.assertEqual(self.get("sys/class/hwmon/hwmon5/pwm1_enable"), "2")
        self.assertFalse(self.marker())

    def test_a_desktop_board_gets_its_own_settings_back(self):
        self.put("sys/class/hwmon/hwmon3/name", "nct6798\n")
        self.put("sys/class/hwmon/hwmon3/pwm1_enable", "5\n"); self.put("sys/class/hwmon/hwmon3/pwm2_enable", "2\n")
        self.put("sys/class/hwmon/hwmon4/name", "amdgpu\n"); self.put("sys/class/hwmon/hwmon4/pwm1_enable", "2\n")
        self.call("max")
        self.call("max")  # twice: the first, real values must survive
        self.assertEqual([self.get("sys/class/hwmon/hwmon3/pwm%d_enable" % i) for i in (1, 2)], ["0", "0"])
        self.assertEqual(self.get("sys/class/hwmon/hwmon4/pwm1_enable"), "2", "a GPU is left alone")
        self.call("auto")
        self.assertEqual([self.get("sys/class/hwmon/hwmon3/pwm%d_enable" % i) for i in (1, 2)], ["5", "2"])

    def test_after_a_reboot_auto_only_touches_known_drivers(self):
        self.put("sys/class/hwmon/hwmon5/name", "hp\n"); self.put("sys/class/hwmon/hwmon5/pwm1_enable", "0\n")
        self.put("sys/class/hwmon/hwmon3/name", "nct6798\n"); self.put("sys/class/hwmon/hwmon3/pwm1_enable", "0\n")
        self.call("auto")
        self.assertEqual(self.get("sys/class/hwmon/hwmon5/pwm1_enable"), "2")
        self.assertEqual(self.get("sys/class/hwmon/hwmon3/pwm1_enable"), "0", "unknown automatic value: untouched")

    def test_thinkpad_and_msi(self):
        self.put("proc/acpi/ibm/fan", "status:\t\tenabled\nlevel:\t\tauto\ncommands:\tlevel <level> (<level> is 0-7, auto, disengaged, full-speed)\n")
        self.put("sys/devices/platform/msi-ec/cooler_boost", "off\n")
        self.assertEqual(self.call("max").returncode, 0)
        self.assertEqual(self.get("proc/acpi/ibm/fan"), "level full-speed")
        self.assertEqual(self.get("sys/devices/platform/msi-ec/cooler_boost"), "on")

    def test_nothing_to_control_is_an_error_and_no_marker(self):
        self.put("sys/class/hwmon/hwmon0/name", "coretemp\n")
        p = self.call("max")
        self.assertEqual(p.returncode, 1)
        self.assertFalse(self.marker())

    def test_only_two_words(self):
        for args in ([], ["MAX"], ["max", "x"][1:], ["../../etc"]):
            self.assertEqual(self.call(*args).returncode, 2, args)


if __name__ == "__main__":
    unittest.main()
