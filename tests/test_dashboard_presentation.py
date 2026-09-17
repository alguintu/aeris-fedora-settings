"""Exercise QML timers offscreen without starting the real dashboard services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PresentationTests(unittest.TestCase):
    def test_combined_ai_hub(self):
        self.run_qml("AiHub.qml", "AI_HUB_TEST")

    def test_merged_page_navigation(self):
        shell = (ROOT / "quickshell/aeris-dashboard/shell.qml").read_text()
        self.assertIn('["PC SPECS", "IDLE", "AERIS AI", "GRID PREVIEW"]', shell)
        self.assertNotIn("Pages.AiFocusPage", shell)
        self.assertEqual(shell.count("Pages.WorkPage {"), 1)
        self.assertEqual(shell.count("Pages.GridPreviewPage {"), 1)

    def test_compositor_backdrop_lifecycle(self):
        self.run_qml("Backdrop.qml", "BACKDROP_TEST")

    def test_download_slots(self):
        self.run_qml("Downloads.qml", "DOWNLOADS_TEST")

    def test_downloads_use_explicit_window_open(self):
        source = (ROOT / "quickshell/aeris-dashboard/pages/IdlePage.qml").read_text()
        self.assertIn('onOpenRequested: Quickshell.execDetached(BackendService.command("fdm", ["open"]))', source)

    def test_home_grid_geometry(self):
        self.run_qml("HomeGrid.qml", "HOME_GRID_TEST")

    def test_network_activity(self):
        self.run_qml("Network.qml", "NETWORK_TEST")

    def test_grid_preview_geometry(self):
        self.run_qml("GridPreview.qml", "GRID_PREVIEW_TEST")

    def test_media_page_visibility(self):
        self.run_qml("MediaVisibility.qml", "MEDIA_VISIBILITY_TEST")

    def test_chromatic_time(self):
        self.run_qml("ChromaticTime.qml", "CHROMATIC_TIME_TEST")

    def test_chromatic_media_pulse(self):
        self.run_qml("ChromaticPulse.qml", "CHROMATIC_PULSE_TEST")

    def test_specs_page_layout(self):
        self.run_qml("SpecsPage.qml", "SPECS_PAGE_TEST")

    def test_specs_page_visibility(self):
        self.run_qml("SpecsVisibility.qml", "SPECS_VISIBILITY_TEST")

    def test_presentation_lifecycle(self):
        self.run_qml("Presentation.qml", "PRESENTATION_TEST")

    def test_native_backend_routing(self):
        self.run_qml("Backend.qml", "BACKEND_TEST")

    def test_three_position_awake(self):
        self.run_qml("Awake.qml", "AWAKE_TEST")

    def test_page_gutters_and_clipping(self):
        self.run_qml("Paging.qml", "PAGING_TEST")

    def test_slide_reveal_lifecycle(self):
        self.run_qml("Slide.qml", "SLIDE_TEST")

    def test_timer_seek_gestures(self):
        self.run_qml("TimerSeek.qml", "TIMER_SEEK_TEST")

    def test_compact_pomodoro(self):
        self.run_qml("CompactPomodoro.qml", "COMPACT_POMODORO_TEST")

    def test_compact_routine_picker(self):
        self.run_qml("CompactRoutinePicker.qml", "COMPACT_ROUTINE_TEST")

    def run_qml(self, fixture, marker):
        binary = shutil.which("quickshell")
        if not binary:
            self.skipTest("Quickshell 0.3+ runtime is not installed")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   QT_QPA_PLATFORMTHEME="", QS_NO_RELOAD_POPUP="1", AERIS_DASHBOARD_BACKEND="rust")
        # Opt-in real shader check; default suite stays isolated/offscreen.
        if env.get("AERIS_TEST_RHI") in ("vulkan", "opengl"):
            env["QT_QPA_PLATFORM"] = "wayland"
            env["QSG_RHI_BACKEND"] = env["AERIS_TEST_RHI"]
            env.pop("QT_QUICK_BACKEND", None)
        if fixture == "Backdrop.qml":
            # PanelWindow has no offscreen backend. This fixture keeps its
            # window invisible and only checks the attached protocol region.
            if not env.get("WAYLAND_DISPLAY"):
                self.skipTest("Wayland is required for the backdrop attachment test")
            env["QT_QPA_PLATFORM"] = "wayland"
        # Quickshell deliberately restricts imports to the selected config root.
        # Copy only presentation assets into an isolated config; no live shell.qml.
        with tempfile.TemporaryDirectory(prefix="aeris-presentation-test-") as folder:
            config = Path(folder)
            shutil.copy2(ROOT / "tests/qml" / fixture, config / "shell.qml")
            for name in ("components", "assets", "shaders"):
                shutil.copytree(ROOT / "quickshell/aeris-dashboard" / name, config / name)
            if fixture in ("SpecsPage.qml", "SpecsVisibility.qml", "GridPreview.qml", "HomeGrid.qml", "AiHub.qml"):
                shutil.copytree(ROOT / "quickshell/aeris-dashboard/pages", config / "pages")
            command = [binary, "--verbose", "--path", folder]
            if fixture in ("MediaVisibility.qml", "HomeGrid.qml"):
                # Exercise real MPRIS components without attaching to desktop players.
                if not shutil.which("dbus-run-session"):
                    self.skipTest("dbus-run-session is required for isolated media testing")
                command = ["dbus-run-session", "--"] + command
            result = subprocess.run(command,
                                    env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn(marker + "_PASSED", output)
        self.assertNotIn(marker + "_FAILED", output)


if __name__ == "__main__":
    unittest.main()
