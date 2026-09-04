import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "quickshell/aeris-dashboard/services"))
import pomodoro_templates as routines


class TemplateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aeris-routine-test-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name) / "notes"
        self.folder.mkdir()
        for path in (ROOT / "tomat/templates").glob("*.md"):
            (self.folder / path.name).write_text(path.read_text())
        env = patch.dict(os.environ, {"AERIS_TOMAT_TEMPLATE_DIR": str(self.folder),
                                     "AERIS_TOMAT_STATE_DIR": self.temp.name + "/state"})
        env.start()
        self.addCleanup(env.stop)
        self.catalog = routines.catalog(force=True)
        self.classic = routines.find("classic", self.catalog["templates"])

    def state(self, phase="Work", session=1):
        return {"ok": True, "phase": phase, "session": session,
                "duration": 1500, "remaining": 1400, "sessions": 4, "progress": .067}

    def test_seed_catalog_and_validation(self):
        self.assertEqual(len(self.catalog["templates"]), 3)
        self.assertEqual(self.catalog["templateErrors"], [])
        raw = {**self.classic, "type": "aeris-pomodoro"}
        for field, value in [("work_minutes", False), ("work_minutes", float("nan")),
                             ("sessions", 9), ("auto_advance", "sometimes"),
                             ("quotes", ["x" * 73]), ("command", "rm anything")]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                routines.validate({**raw, field: value})

    def test_unsafe_yaml_and_all_duplicate_ids_rejected(self):
        content = (self.folder / "Classic.md").read_text()
        (self.folder / "Copy 1.md").write_text(content)
        (self.folder / "Copy 2.md").write_text(content)
        (self.folder / "Unsafe.md").write_text("---\n!!python/object/apply:os.system ['false']\n---\n")
        data = routines.catalog(force=True)
        self.assertNotIn("classic", [r["id"] for r in data["templates"]])
        self.assertEqual(len(data["templateErrors"]), 3)

    def test_snapshot_survives_note_edit_and_deletion(self):
        routines.action("toggle", self.state("Idle"), Mock())
        before = routines.enrich(self.state())
        path = self.folder / "Classic.md"
        path.write_text(path.read_text().replace("work_label: WORK", "work_label: EDITED"))
        routines.catalog(force=True)
        self.assertEqual(routines.enrich(self.state())["stageLabel"], "WORK")
        path.unlink()
        routines.catalog(force=True)
        after = routines.enrich(self.state())
        self.assertEqual(after["activeId"], "classic")
        self.assertEqual(after["quote"], before["quote"])
        self.assertTrue(after["templateErrors"])
        with self.assertRaises(ValueError):
            routines.action("toggle", self.state("Idle"), Mock())

    def test_next_never_sends_timer_command(self):
        request = Mock()
        routines.action("select", self.state(), request, "deep-work", "next")
        request.assert_not_called()
        self.assertEqual(routines.load()["selected"], "deep-work")

    def test_snapshot_boot_and_stale_idle_guard(self):
        observed = time.monotonic()
        routines.action("toggle", self.state("Idle"), Mock())
        routines.enrich(self.state("Idle"), observed)
        self.assertIn("active", routines.load())
        with patch.object(routines, "boot_id", return_value="another-boot"):
            self.assertEqual(routines.enrich(self.state())["activeId"], "")

    def test_corrupt_selection_does_not_hide_running_timer(self):
        path = routines.state_path()
        path.parent.mkdir()
        path.write_text("not json")
        state = routines.enrich(self.state())
        self.assertTrue(state["ok"])
        self.assertTrue(state["templateErrors"])
        request = Mock()
        routines.action("toggle", self.state(), request)
        request.assert_called_once_with("toggle")
        routines.action("select", self.state(), Mock(), "deep-work", "next")
        self.assertEqual(routines.load()["selected"], "deep-work")

    def test_failed_start_does_not_change_selection(self):
        routines.save({"selected": "classic"})
        request = Mock(side_effect=ValueError("offline"))
        with self.assertRaises(ValueError):
            routines.action("select", self.state(), request, "deep-work", "now")
        self.assertEqual(routines.load(), {"selected": "classic"})


if __name__ == "__main__":
    unittest.main()
