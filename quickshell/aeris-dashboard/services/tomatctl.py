#!/usr/bin/python3
"""Small JSON adapter for the pinned Tomat 2.13 Unix-socket protocol."""
import argparse
import json
import os
from pathlib import Path
import socket
import time
import pomodoro_templates as templates


def request(command, args=None):
    runtime = os.environ.get("TOMAT_RUNTIME_DIR") or os.environ.get("XDG_RUNTIME_DIR")
    path = Path(runtime or f"/run/user/{os.getuid()}") / "tomat.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(2)
        connection.connect(str(path))
        connection.sendall((json.dumps({"command": command, "args": args or {}}) + "\n").encode())
        with connection.makefile("rb") as stream:
            response = json.loads(stream.readline(65536))
    if response.get("success") is not True:
        raise ValueError(response.get("message", "Tomat request failed"))
    return response.get("data")


def status():
    data = request("status")
    phase = data["phase"]
    if phase not in ("Idle", "Work", "Break", "LongBreak"):
        raise ValueError(f"Unsupported timer phase: {phase}")
    remaining = max(0, int(data["remaining_seconds"]))
    duration = max(1, round(float(data["duration_minutes"]) * 60))
    return {"ok": True, "phase": phase, "paused": bool(data["is_paused"]),
            "remaining": remaining, "duration": duration,
            "session": max(1, int(data["current_session"])),
            "sessions": max(1, int(data["sessions_until_long_break"])),
            "progress": 0 if phase == "Idle" else max(0, min(1, 1 - remaining / duration))}


def execute(action, identifier=None, mode=None):
    try:
        if action not in ("status", "watch"):
            templates.action(action, status(), request, identifier, mode)
        observed_at = time.monotonic()
        return templates.enrich(status(), observed_at)
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {"ok": False, "error": str(error)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "watch", "toggle", "pause", "resume", "reset", "skip", "select"))
    parser.add_argument("identifier", nargs="?")
    parser.add_argument("mode", nargs="?", choices=("next", "now"))
    args = parser.parse_args()
    action = args.action
    while True:
        result = execute(action, args.identifier, args.mode)
        print(json.dumps(result, separators=(",", ":")), flush=True)
        if action != "watch":
            return 0 if result["ok"] else 1
        time.sleep(0.5 if result["ok"] else 2)


if __name__ == "__main__":
    raise SystemExit(main())
