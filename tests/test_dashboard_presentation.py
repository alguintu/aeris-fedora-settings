"""Exercise QML timers offscreen without starting the real dashboard services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PresentationTests(unittest.TestCase):
    def test_chromatic_time(self):
        self.run_qml("ChromaticTime.qml", "CHROMATIC_TIME_TEST")

    def test_chromatic_media_pulse(self):
        self.run_qml("ChromaticPulse.qml", "CHROMATIC_PULSE_TEST")

    def test_specs_page_layout(self):
        self.run_qml("SpecsPage.qml", "SPECS_PAGE_TEST")

    def test_presentation_lifecycle(self):
        self.run_qml("Presentation.qml", "PRESENTATION_TEST")

    def test_native_backend_routing(self):
        self.run_qml("Backend.qml", "BACKEND_TEST")

    def test_page_gutters_and_clipping(self):
        self.run_qml("Paging.qml", "PAGING_TEST")

    def test_slide_reveal_lifecycle(self):
        self.run_qml("Slide.qml", "SLIDE_TEST")

    def test_timer_seek_gestures(self):
        self.run_qml("TimerSeek.qml", "TIMER_SEEK_TEST")

    def run_qml(self, fixture, marker):
        runtime = Path.home() / ".local/opt/quickshell-fedora-0.2.1/usr"
        binary = shutil.which("quickshell") or str(runtime / "bin/quickshell")
        if not Path(binary).is_file():
            self.skipTest("Quickshell runtime is not installed")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   QT_QPA_PLATFORMTHEME="", QS_NO_RELOAD_POPUP="1", AERIS_DASHBOARD_BACKEND="rust")
        # Opt-in real shader check; default suite stays isolated/offscreen.
        if env.get("AERIS_TEST_RHI") in ("vulkan", "opengl"):
            env["QT_QPA_PLATFORM"] = "wayland"
            env["QSG_RHI_BACKEND"] = env["AERIS_TEST_RHI"]
            env.pop("QT_QUICK_BACKEND", None)
        if binary.startswith(str(runtime)):
            env["LD_LIBRARY_PATH"] = str(runtime / "lib64")
            env["QT_PLUGIN_PATH"] = str(runtime / "lib64/qt6/plugins")
            env["QML2_IMPORT_PATH"] = str(runtime / "lib64/qt6/qml")
        # Quickshell deliberately restricts imports to the selected config root.
        # Copy only presentation assets into an isolated config; no live shell.qml.
        with tempfile.TemporaryDirectory(prefix="aeris-presentation-test-") as folder:
            config = Path(folder)
            shutil.copy2(ROOT / "tests/qml" / fixture, config / "shell.qml")
            for name in ("components", "assets", "shaders"):
                shutil.copytree(ROOT / "quickshell/aeris-dashboard" / name, config / name)
            if fixture == "SpecsPage.qml":
                shutil.copytree(ROOT / "quickshell/aeris-dashboard/pages", config / "pages")
            result = subprocess.run([binary, "--verbose", "--path", folder],
                                    env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn(marker + "_PASSED", output)
        self.assertNotIn(marker + "_FAILED", output)


if __name__ == "__main__":
    unittest.main()
