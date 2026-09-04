"""Connection reuse and event-driven status checks, without changing hardware."""
import http.client
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "quickshell/aeris-dashboard/services"))
import coolingctl
import sleepctl


def response(status=200, close=False):
    return Mock(status=status, will_close=close, read=Mock(return_value=b'{"current_mode_uid":"test"}'))


class CoolingTests(unittest.TestCase):
    def setUp(self):
        self.client = coolingctl.CoolerClient()
        self.connection = Mock()
        self.connection.getresponse.return_value = response()
        self.factory = patch.object(coolingctl.http.client, "HTTPSConnection", return_value=self.connection).start()
        patch.object(self.client, "cookie", return_value="cc=test-only").start()
        self.addCleanup(patch.stopall)

    def test_reuses_connection_and_consumes_response(self):
        for _ in range(3):
            self.client.request("GET", "/modes-active")
        self.factory.assert_called_once()
        self.assertEqual(self.connection.getresponse.return_value.read.call_count, 3)
        self.connection.close.assert_not_called()

    def test_dead_keepalive_retries_get_on_new_connection(self):
        fresh = Mock(getresponse=Mock(return_value=response()))
        self.factory.side_effect = [self.connection, fresh]
        self.connection.request.side_effect = http.client.RemoteDisconnected()
        self.client.request("GET", "/modes-active")
        self.assertEqual(self.factory.call_count, 2)
        self.connection.close.assert_called_once()
        fresh.request.assert_called_once()

    def test_does_not_replay_post_after_ambiguous_failure(self):
        self.connection.getresponse.side_effect = http.client.RemoteDisconnected()
        with self.assertRaises(http.client.RemoteDisconnected):
            self.client.request("POST", "/modes-active/test")
        self.connection.request.assert_called_once()
        self.factory.assert_called_once()

    def test_auth_failure_invalidates_cached_cookie_and_retries_get_once(self):
        self.client.cookie_key = "old"
        self.connection.getresponse.side_effect = [response(401), response()]
        self.client.request("GET", "/modes-active")
        self.assertIsNone(self.client.cookie_key)
        self.assertEqual(self.client.cookie.call_count, 2)
        self.assertEqual(self.factory.call_count, 2)

    def test_server_close_discards_connection(self):
        self.connection.getresponse.return_value = response(close=True)
        self.client.request("GET", "/modes-active")
        self.assertIsNone(self.client.connection)
        self.connection.close.assert_called_once()

    def test_cookie_content_only_read_when_file_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.conf"
            path.write_text('networkCookies="@ByteArray(cc=test-one;)"')
            client = coolingctl.CoolerClient()
            with patch.object(coolingctl, "COOLERCONTROL_CONFIG", path), \
                    patch.object(Path, "read_text", autospec=True, side_effect=Path.read_text) as read:
                self.assertEqual(client.cookie(), "cc=test-one")
                client.cookie()
                self.assertEqual(read.call_count, 1)
                path.write_text('networkCookies="@ByteArray(cc=test-two-longer;)"')
                self.assertEqual(client.cookie(), "cc=test-two-longer")
                self.assertEqual(read.call_count, 2)


class SleepTests(unittest.TestCase):
    def test_direct_bus_call_keeps_native_bridge(self):
        bus = Mock(call_blocking=Mock(return_value='{"active":true}'))
        with patch.object(sleepctl, "session_bus", return_value=bus):
            self.assertTrue(sleepctl.status()["active"])
        args = bus.call_blocking.call_args.args
        self.assertEqual(args[:4], ("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript"))
        self.assertIn("org.aeris.sleepbridge", args[5][0])

    def test_event_burst_is_coalesced_with_slow_fallback_and_fast_recovery(self):
        scheduler = Mock()
        scheduler.timeout_add.return_value = 1
        scheduler.timeout_add_seconds.return_value = 2
        emit = Mock()
        read = Mock(return_value={"ok": True, "active": False})
        watcher = sleepctl.StateWatcher(scheduler, emit, read)
        watcher.refresh()
        self.assertEqual(scheduler.timeout_add_seconds.call_args.args[0], 30)
        for _ in range(5):
            watcher.changed()
        scheduler.timeout_add.assert_called_once()
        watcher.refresh()
        self.assertEqual(read.call_count, 2)
        read.side_effect = RuntimeError("Plasma restarting")
        watcher.fallback_check()
        self.assertEqual(scheduler.timeout_add_seconds.call_args.args[0], 2)
        self.assertFalse(emit.call_args.args[0]["ok"])

    @unittest.skipUnless(shutil.which("dbus-run-session"), "Private D-Bus test needs dbus-run-session")
    def test_real_signals_on_private_bus(self):
        result = subprocess.run(["dbus-run-session", "--", sys.executable,
                                 str(ROOT / "tests/fixtures/sleep-bus-check.py")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), [False, True, False])


if __name__ == "__main__":
    unittest.main()
