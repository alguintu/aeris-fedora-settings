#!/usr/bin/env python3
"""Query or change the volatile Aeris OpenRGB daemon mode."""

import argparse
import json
import os
import signal
import socket
import time
from pathlib import Path


MODES = ("work", "night", "day", "off", "party")


def control_path():
    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    return runtime_dir / "aeris-openrgb.sock"


def request(payload):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(0.75)
        client.connect(str(control_path()))
        client.sendall(json.dumps(payload).encode("utf-8"))
        response = b""
        while b"\n" not in response:
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
        if not response:
            raise RuntimeError("lighting daemon returned no status")
        return json.loads(response.decode("utf-8"))
    finally:
        client.close()


def safe_request(payload):
    try:
        return request(payload)
    except (OSError, RuntimeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return {"ok": False, "mode": "unknown", "error": str(exc)}


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    watch_parser = subparsers.add_parser("watch")
    watch_parser.add_argument("--interval", type=float, default=1.0)
    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("mode", choices=MODES)
    args = parser.parse_args()

    if args.command == "watch":
        if args.interval < 0.25:
            parser.error("watch interval must be at least 0.25 seconds")
        try:
            while True:
                print(
                    json.dumps(safe_request({"command": "status"}), separators=(",", ":")),
                    flush=True,
                )
                time.sleep(args.interval)
        except KeyboardInterrupt:
            return 0

    payload = {"command": "status"}
    if args.command == "set":
        payload = {"command": "set", "mode": args.mode}

    response = safe_request(payload)

    print(json.dumps(response, separators=(",", ":")), flush=True)
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
