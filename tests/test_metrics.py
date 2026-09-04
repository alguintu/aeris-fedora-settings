import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


MODULE = Path(__file__).resolve().parents[1] / "quickshell/aeris-dashboard/services/metrics.py"
spec = importlib.util.spec_from_file_location("metrics", MODULE)
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class TemperatureTests(unittest.TestCase):
    def test_idle_busy_and_cooldown_cadences(self):
        poll = metrics.TemperaturePoll()
        with patch.object(metrics, "read_number", return_value=42) as read:
            paths = {"cpuTemp": Path("/temperature")}
            for now in range(4):
                self.assertEqual(poll.sample(now, False, paths), {"cpuTemp": 42})
            self.assertEqual(read.call_count, 2)  # 0 and 3, not every second
            poll.sample(4, True, paths)
            self.assertEqual(read.call_count, 3)  # immediate ramp to 1 Hz
            for now in range(5, 11):
                poll.sample(now, False, paths)
            self.assertEqual(read.call_count, 9)  # six-second cooldown hold
            poll.sample(11, False, paths)
            poll.sample(12, False, paths)
            self.assertEqual(read.call_count, 9)
            poll.sample(13, False, paths)
            self.assertEqual(read.call_count, 10)

    def test_failed_read_clears_old_value(self):
        poll = metrics.TemperaturePoll()
        with patch.object(metrics, "read_number", side_effect=[42, None]):
            poll.sample(0, False, {"cpuTemp": Path("/temperature")})
            self.assertIsNone(poll.sample(3, False, {"cpuTemp": Path("/temperature")})["cpuTemp"])


class DiskTests(unittest.TestCase):
    def test_deduplicates_subvolumes_and_leaves_unmounted_drive_unknown(self):
        mounts = ("1 0 0:1 / / rw - btrfs /dev/a rw\n"
                  "2 0 0:1 /home /home rw - btrfs /dev/a rw\n"
                  "3 0 0:2 / /mnt/workspace rw - ext4 /dev/b rw\n"
                  "4 0 0:3 / /mnt/other\\040disk rw - ext4 /dev/c rw\n"
                  "5 0 0:4 / /proc rw - proc proc rw\n")
        stats = SimpleNamespace(f_blocks=100, f_bfree=40, f_bavail=35, f_frsize=4096)
        with patch.object(Path, "read_text", return_value=mounts), \
                patch.object(metrics.os, "statvfs", return_value=stats) as read:
            result = metrics.disk_snapshot()
        self.assertEqual(read.call_count, 3)
        self.assertEqual(read.call_args_list[-1].args, ("/mnt/other disk",))
        self.assertEqual(result["mountedDiskTotal"], 3 * 100 * 4096)
        self.assertEqual(result["mountedDiskFree"], 3 * 35 * 4096)
        self.assertEqual(result["drives"][0]["used"], 60 * 4096)
        self.assertIsNone(result["drives"][2]["used"])

    def test_mount_failure_does_not_report_partial_total_as_whole(self):
        with patch.object(Path, "read_text", return_value="1 0 0:1 / / rw - ext4 /dev/a rw\n"), \
                patch.object(metrics.os, "statvfs", side_effect=OSError):
            result = metrics.disk_snapshot()
        self.assertIsNone(result["mountedDiskTotal"])
        self.assertIsNone(result["mountedDiskFree"])
        self.assertIsNone(result["drives"][0]["total"])


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.collector = metrics.MetricsCollector()
        self.collector.needs_discovery = False
        self.collector.next_discovery = 30
        self.collector.cpu_paths = {"cpuTemp": Path("/cpu/temp")}
        self.collector.gpu_paths = {"gpuTemp": Path("/gpu/edge"), "gpuHotspot": Path("/gpu/hotspot")}
        self.collector.device = Path("/gpu")
        self.collector.vram_total = 16 * 1024**3
        self.collector.clock_paths = {0: Path("/cpu0/clock"), 1: Path("/cpu1/clock")}
        self.previous = {"cpu": (1000, 900), 0: (100, 90), 1: (100, 90)}
        self.idle = {"cpu": (1100, 998), 0: (200, 188), 1: (200, 185)}
        self.read = patch.object(metrics, "read_number", side_effect=self.number).start()
        self.disks = patch.object(metrics, "disk_snapshot", return_value={"drives": []}).start()
        patch.object(metrics, "memory_bytes", return_value=(1024, 4096)).start()
        self.addCleanup(patch.stopall)

    @staticmethod
    def number(path, divisor=1):
        return {"/cpu0/clock": 3400000, "/cpu1/clock": 4500000,
                "/cpu/temp": 44000, "/gpu/edge": 45000, "/gpu/hotspot": 55000,
                "/gpu/gpu_busy_percent": 1, "/gpu/mem_info_vram_used": 1000}[str(path)] / divisor

    def test_one_busiest_core_clock_read_and_cached_disk_snapshot(self):
        for now in range(60):
            result = self.collector.collect(self.previous, self.idle, now)
        clock_reads = [call for call in self.read.call_args_list if str(call.args[0]).endswith("clock")]
        self.assertEqual(len(clock_reads), 60)
        self.assertTrue(all(call.args[0] == Path("/cpu1/clock") for call in clock_reads))
        self.assertEqual(result["cpuClock"], 4.5)
        self.assertEqual(self.disks.call_count, 1)
        self.collector.collect(self.previous, self.idle, 60)
        self.assertEqual(self.disks.call_count, 2)
        for field in ("rootUsed", "rootTotal", "physicalDiskTotal"):
            self.assertNotIn(field, result)
        self.assertEqual(result["gpuHotspot"], 55)

    def test_one_busy_thread_accelerates_cpu_but_not_gpu_temperature(self):
        self.collector.collect(self.previous, self.idle, 0)
        self.read.reset_mock()
        busy = {**self.idle, 0: (200, 100)}  # 90% thread, still 2% aggregate
        self.collector.collect(self.previous, busy, 1)
        paths = [call.args[0] for call in self.read.call_args_list]
        self.assertIn(Path("/cpu/temp"), paths)
        self.assertNotIn(Path("/gpu/edge"), paths)

    def test_missing_clock_recovers_with_bounded_discovery(self):
        self.read.side_effect = lambda path, divisor=1: None if str(path).endswith("clock") else self.number(path, divisor)
        with patch.object(self.collector, "discover") as discover:
            for now in range(30):
                self.assertIsNone(self.collector.collect(self.previous, self.idle, now)["cpuClock"])
            discover.assert_not_called()
            self.collector.collect(self.previous, self.idle, 30)
            discover.assert_called_once_with(30)

    def test_gpu_load_accelerates_both_gpu_sensors_not_cpu(self):
        self.collector.collect(self.previous, self.idle, 0)
        self.read.reset_mock()
        self.read.side_effect = lambda path, divisor=1: 99 if path.name == "gpu_busy_percent" else self.number(path, divisor)
        self.collector.collect(self.previous, self.idle, 1)
        paths = [call.args[0] for call in self.read.call_args_list]
        self.assertIn(Path("/gpu/edge"), paths)
        self.assertIn(Path("/gpu/hotspot"), paths)
        self.assertNotIn(Path("/cpu/temp"), paths)

    def test_frequency_discovery_prefers_hardware_feedback_and_has_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for cpu, names in ((0, ("cpuinfo_avg_freq", "scaling_cur_freq")), (1, ("scaling_cur_freq",))):
                folder = root / f"cpu{cpu}/cpufreq"
                folder.mkdir(parents=True)
                for name in names:
                    (folder / name).touch()
            with patch.object(metrics, "CPU_ROOT", root), \
                    patch.object(metrics, "hwmon_dir", return_value=None), \
                    patch.object(metrics, "gpu_device", return_value=None):
                self.collector.discover(0)
            self.assertEqual(self.collector.clock_paths[0].name, "cpuinfo_avg_freq")
            self.assertEqual(self.collector.clock_paths[1].name, "scaling_cur_freq")
            self.read.assert_not_called()  # discovery only resolves paths


if __name__ == "__main__":
    unittest.main()
