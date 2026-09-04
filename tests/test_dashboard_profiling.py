"""Check the replay fixture without touching the live dashboard."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ablate", ROOT / "scripts/ablate-dashboard.py")
ABLATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ABLATE)


class ReplayTests(unittest.TestCase):
    def test_identical_gpu_cycle_in_each_case(self):
        samples = [{"gpuUsage": 2, "cpuUsage": 3}]
        self.assertEqual([json.loads(ABLATE.frame(samples, n))["gpuUsage"]
                          for n in (0, 5, 10, 15, 20)], [99, 45, 90, 15, 99])

    def test_recorded_cpu_is_replayed_without_modifying_fixture(self):
        samples = [{"gpuUsage": 2, "cpuUsage": 3}, {"gpuUsage": 4, "cpuUsage": 7}]
        self.assertEqual(json.loads(ABLATE.frame(samples, 3))["cpuUsage"], 7)
        self.assertEqual(samples[1]["gpuUsage"], 4)

    def test_warmup_is_sustained_99_percent(self):
        self.assertEqual(json.loads(ABLATE.frame([{"gpuUsage": 0}], 15, False))["gpuUsage"], 99)


if __name__ == "__main__":
    unittest.main()
