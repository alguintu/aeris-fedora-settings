#!/usr/bin/env python3
"""Fail-closed detector policy for Aeris's OpenRGB configuration."""

import argparse
import json
import os
import tempfile
from pathlib import Path


DEFAULT_CONFIG = Path.home() / ".config/OpenRGB/OpenRGB.json"
AERIS_ALLOWLIST = {
    "MSI Mystic Light MS_7C94",
    "ENE SMBus DRAM",
    "ASUS TUF Radeon RX 6900 XT Gaming OC",
}


def load_detectors(config):
    data = json.loads(config.read_text(encoding="utf-8"))
    try:
        detectors = data["Detectors"]["detectors"]
    except (KeyError, TypeError) as exc:
        raise SystemExit(f"{config} has no OpenRGB detector map") from exc
    return data, detectors


def write_config(data, config):
    config.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix="OpenRGB.", suffix=".json", dir=config.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            json.dump(data, temporary, indent=4)
            temporary.write("\n")
        os.chmod(temporary_name, config.stat().st_mode)
        os.replace(temporary_name, config)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--require-aeris", action="store_true")
    action.add_argument("--quarantine", action="store_true")
    action.add_argument("--allow-aeris", action="store_true")
    args = parser.parse_args()

    data, detectors = load_detectors(args.config)
    enabled = {name for name, value in detectors.items() if value}
    missing = AERIS_ALLOWLIST - set(detectors)

    if args.check:
        if not enabled:
            print("QUARANTINED: all OpenRGB hardware detectors are disabled")
            return 0
        if enabled == AERIS_ALLOWLIST:
            print("ALLOWLISTED: only Aeris's three audited detector families are enabled")
            return 0
        unexpected = sorted(enabled - AERIS_ALLOWLIST)
        print(f"UNSAFE: {len(unexpected)} unexpected OpenRGB detectors are enabled")
        for name in unexpected[:20]:
            print(f"  {name}")
        if len(unexpected) > 20:
            print(f"  ... and {len(unexpected) - 20} more")
        return 1

    if args.require_aeris:
        if enabled != AERIS_ALLOWLIST:
            print("UNSAFE: OpenRGB runtime detector allowlist is not exact")
            print(f"  expected: {', '.join(sorted(AERIS_ALLOWLIST))}")
            print(f"  enabled: {', '.join(sorted(enabled)) if enabled else '(none)'}")
            return 1
        print("ALLOWLISTED: exactly Aeris's three audited detector families are enabled")
        return 0

    if args.allow_aeris and missing:
        raise SystemExit(
            "OpenRGB detector map does not match the audited build; missing: "
            + ", ".join(sorted(missing))
        )

    allowed = AERIS_ALLOWLIST if args.allow_aeris else set()
    for name in detectors:
        detectors[name] = name in allowed
    write_config(data, args.config)
    print(
        "OpenRGB detector policy: "
        + ("Aeris allowlist enabled" if allowed else "all detectors quarantined")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
