#!/usr/bin/env python3
"""Validate the reinstall snapshot and optionally compare discovered device IDs."""

import argparse
import hashlib
import json
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "cooling/snapshot"
BOARD_UID = "7bfee7e15e0af819a1c74ac2f088d69197bdae5f361d2af4da2960c931be3cc7"
FILES = {"config.toml", "modes.json", "calibrations.json", "config-ui.json", "alerts.json"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(snapshot=SNAPSHOT, device_config=None):
    manifest = json.loads((snapshot / "manifest.json").read_text())
    require(set(manifest["files"]) == FILES, "Unexpected snapshot file set")
    for name, checksum in manifest["files"].items():
        require(hashlib.sha256((snapshot / name).read_bytes()).hexdigest() == checksum,
                f"Snapshot checksum mismatch: {name}")
    config = tomllib.loads((snapshot / "config.toml").read_text())
    modes = json.loads((snapshot / "modes.json").read_text())
    calibrations = json.loads((snapshot / "calibrations.json").read_text())
    ui = json.loads((snapshot / "config-ui.json").read_text())
    json.loads((snapshot / "alerts.json").read_text())
    require(isinstance(ui, dict), "Invalid UI configuration")
    profiles = {p["uid"]: p for p in config["profiles"]}
    functions = {f["uid"] for f in config["functions"]}
    required_devices = {BOARD_UID}
    for profile in profiles.values():
        require(profile.get("function_uid", profile.get("function", "0")) in functions,
                f"Missing function for {profile['name']}")
        for member in profile.get("member_profile_uids", []):
            require(member in profiles, f"Missing mix member: {member}")
        if "temp_source" in profile:
            required_devices.add(profile["temp_source"]["device_uid"])
    expected_modes = {"Default", "Quiet", "Performance", "BIOS / Firmware"}
    require({m["name"] for m in modes["modes"]} == expected_modes, "Missing cooling modes")
    by_uid = {m["uid"]: m for m in modes["modes"]}
    require(modes["current_active_mode"] == manifest["default_mode"], "Snapshot must start in Default")
    require(by_uid[manifest["default_mode"]]["name"] == "Default", "Default UID mismatch")
    for mode in modes["modes"]:
        devices = mode["all_device_settings"]
        required_devices.update(devices)
        channels = devices[BOARD_UID]
        require(set(channels) == (set() if mode["name"] == "BIOS / Firmware"
                                else {f"fan{i}" for i in range(1, 6)}),
                f"Unexpected motherboard channels in {mode['name']}")
        for device_channels in devices.values():
            for setting in device_channels.values():
                require(setting["profile_uid"] in profiles, "Missing mode profile")
        if channels:
            pump = profiles[channels["fan2"]["profile_uid"]]
            require(pump.get("speed_fixed") == 100, "Pump must stay at 100%")
    default_settings = by_uid[manifest["default_mode"]]["all_device_settings"]
    for uid, channels in config["device-settings"].items():
        require({key: val["profile_uid"] for key, val in channels.items()} ==
                {key: val["profile_uid"] for key, val in default_settings[uid].items()},
                "Startup assignments differ from Default mode")
    calibrated = {c["channel_name"] for c in calibrations["calibrations"]
                  if c["device_uid"] == BOARD_UID and c["calibration"]["rpm_max"] > 0}
    require({"fan1", "fan3", "fan4", "fan5"}.issubset(calibrated), "Missing fan calibrations")
    require(required_devices.issubset(config["devices"]), "Unknown snapshot device UID")
    if device_config:
        discovered = tomllib.loads(Path(device_config).read_text())["devices"]
        for uid in required_devices:
            require(discovered.get(uid) == config["devices"][uid],
                    f"Device UID/name mismatch for {config['devices'][uid]}; do not restore blindly")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-config", type=Path,
                        help="Fresh daemon config.toml whose detected devices must match")
    args = parser.parse_args()
    try:
        validate(device_config=args.device_config)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, f"FAIL: {exc}\n")
    print("PASS: checksums, curves, functions, modes, calibrations, and device references")


if __name__ == "__main__":
    main()
