"""Run with python3 -m unittest discover -s tests -p test_tomatctl.py."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "quickshell/aeris-dashboard/services"))
spec = importlib.util.spec_from_file_location("tomatctl", ROOT / "quickshell/aeris-dashboard/services/tomatctl.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.staging = tempfile.TemporaryDirectory(prefix="aeris-routine-test-")
        self.addCleanup(self.staging.cleanup)
        self.env = patch.dict(os.environ, {"AERIS_TOMAT_STATE_DIR": self.staging.name,
            "AERIS_TOMAT_TEMPLATE_DIR": str(ROOT / "tomat/templates")})
        self.env.start()
        self.addCleanup(self.env.stop)
        adapter.templates.catalog(force=True)

    def test_progress_and_session(self):
        with patch.object(adapter, "request", return_value={"phase": "Work", "is_paused": True,
                "remaining_seconds": 750, "duration_minutes": 25, "current_session": 2,
                "sessions_until_long_break": 4}):
            state = adapter.status()
            self.assertEqual(state["progress"], 0.5)
            self.assertEqual(state["session"], 2)
            self.assertTrue(state["paused"])

    def test_unavailable_and_invalid(self):
        for error in (OSError("offline"), ValueError("malformed"), KeyError("phase")):
            with patch.object(adapter, "request", side_effect=error):
                self.assertFalse(adapter.execute("status")["ok"])

    def test_reset_is_stop(self):
        with patch.object(adapter, "request") as request, patch.object(adapter, "status", return_value={"ok": True,
                "phase": "Idle", "session": 1}):
            adapter.execute("reset")
            request.assert_called_once_with("stop")


@unittest.skipUnless((Path.home() / ".local/bin/tomat").exists(), "Tomat not installed")
class DaemonTests(unittest.TestCase):
    def test_isolated_cycle(self):
        binary = str(Path.home() / ".local/bin/tomat")
        with tempfile.TemporaryDirectory(prefix="aeris-tomat-check-") as runtime, patch.dict(os.environ, {
                "TOMAT_RUNTIME_DIR": runtime,
                "AERIS_TOMAT_STATE_DIR": runtime + "/selection",
                "AERIS_TOMAT_TEMPLATE_DIR": str(ROOT / "tomat/templates"),
                "TOMAT_CONFIG": str(ROOT / "tests/fixtures/tomat-silent.toml")}):
            daemon = subprocess.Popen([binary, "daemon", "run"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                for _ in range(40):
                    if adapter.execute("status")["ok"]:
                        break
                    time.sleep(.1)
                self.assertEqual(adapter.status()["phase"], "Idle")
                subprocess.run([binary, "start", "--work", "0.1", "--break", "0.05",
                                "--long-break", "0.05", "--sessions", "2", "--auto-advance", "none"],
                               check=True, stdout=subprocess.DEVNULL)
                self.assertEqual(adapter.status()["phase"], "Work")
                paused = adapter.execute("pause")
                time.sleep(1.1)
                self.assertEqual(adapter.status()["remaining"], paused["remaining"])
                self.assertFalse(adapter.execute("resume")["paused"])
                self.assertEqual(adapter.execute("skip")["phase"], "Break")
                self.assertTrue(adapter.status()["paused"])
                self.assertEqual(adapter.execute("skip")["phase"], "Work")
                self.assertEqual(adapter.status()["session"], 2)
                self.assertEqual(adapter.execute("skip")["phase"], "LongBreak")
                self.assertEqual(adapter.execute("reset")["phase"], "Idle")
                subprocess.run([binary, "start", "--work", "0.02", "--break", "0.1",
                                "--auto-advance", "all"], check=True, stdout=subprocess.DEVNULL)
                time.sleep(2.5)
                self.assertEqual(adapter.status()["phase"], "Break")
                adapter.execute("reset")
                # Template starts, safe queued selection, and explicit replacement.
                chosen = adapter.execute("select", "deep-work", "next")
                self.assertEqual(chosen["phase"], "Idle")
                self.assertEqual(chosen["remaining"], 2700)
                started = adapter.execute("toggle")
                self.assertEqual(started["activeId"], "deep-work")
                self.assertEqual(started["stageLabel"], "DEEP WORK")
                self.assertEqual(started["duration"], 2700)
                quote = started["quote"]
                queued = adapter.execute("select", "light-work", "next")
                self.assertEqual(queued["activeId"], "deep-work")
                self.assertEqual(queued["selectedId"], "light-work")
                self.assertEqual(queued["duration"], 2700)
                self.assertEqual(queued["quote"], quote)
                self.assertEqual(adapter.execute("skip")["stageLabel"], "STRETCH")
                adapter.execute("skip")
                self.assertEqual(adapter.execute("skip")["stageLabel"], "WALK")
                restarted = adapter.execute("select", "classic", "now")
                self.assertEqual(restarted["activeId"], "classic")
                self.assertEqual(restarted["duration"], 1500)
                self.assertEqual(restarted["session"], 1)
                adapter.execute("select", "light-work", "next")
                reset = adapter.execute("reset")
                self.assertEqual(reset["remaining"], 1200)
                self.assertEqual(adapter.execute("toggle")["activeId"], "light-work")
                adapter.execute("reset")
            finally:
                daemon.terminate()
                daemon.wait(timeout=5)
            self.assertFalse(adapter.execute("status")["ok"])


if __name__ == "__main__":
    unittest.main()
