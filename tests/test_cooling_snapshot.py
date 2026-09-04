import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("validate_cooling", ROOT / "scripts/validate-cooling.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class CoolingSnapshotTests(unittest.TestCase):
    def test_snapshot_is_self_consistent(self):
        self.assertEqual(validator.validate()["coolercontrol"], "4.3.1")

    def test_matching_discovery_passes(self):
        validator.validate(device_config=validator.SNAPSHOT / "config.toml")

    def test_dashboard_mode_ids_match_snapshot(self):
        helper_spec = importlib.util.spec_from_file_location("coolingctl", ROOT /
            "quickshell/aeris-dashboard/services/coolingctl.py")
        helper = importlib.util.module_from_spec(helper_spec)
        helper_spec.loader.exec_module(helper)
        modes = json.loads((validator.SNAPSHOT / "modes.json").read_text())
        self.assertEqual(set(helper.MODE_UIDS.values()), {m['uid'] for m in modes['modes']})

    def test_wrong_hardware_ids_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            config.write_text('[devices]\nother = "nct6687"\n')
            with self.assertRaisesRegex(ValueError, "Device UID/name mismatch"):
                validator.validate(device_config=config)

    def test_tampered_data_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "snapshot"
            shutil.copytree(validator.SNAPSHOT, target)
            (target / "modes.json").write_text('{}\n')
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                validator.validate(snapshot=target)

    def test_snapshot_has_no_authentication_fields(self):
        def inspect(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    self.assertFalse(any(word in key.lower() for word in
                        ("password", "passwd", "cookie", "token", "secret", "private_key")), key)
                    inspect(child)
            elif isinstance(value, list):
                for child in value:
                    inspect(child)
        for path in validator.SNAPSHOT.iterdir():
            if path.suffix == ".toml":
                inspect(validator.tomllib.loads(path.read_text()))
            elif path.suffix == ".json":
                inspect(json.loads(path.read_text()))


if __name__ == "__main__":
    unittest.main()
