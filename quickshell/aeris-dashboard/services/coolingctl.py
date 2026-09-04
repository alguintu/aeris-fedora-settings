#!/usr/bin/env python3
"""Query or change the active Aeris CoolerControl mode."""

import argparse
import http.client
import json
import re
import signal
import ssl
import time
from pathlib import Path


COOLERCONTROL_HOST = "127.0.0.1"
COOLERCONTROL_PORT = 11987
COOLERCONTROL_CONFIG = (
    Path.home() / ".config/org.coolercontrol.CoolerControl/CoolerControl.conf"
)

MODE_UIDS = {
    "default": "c156cd38-8428-4e6e-8c98-3ac7699c8bd8",
    "quiet": "013d1402-c9d8-4770-bf1a-fe52a20467e5",
    "performance": "0d23d4f7-13e8-49bd-95f2-410134ea5752",
    "firmware": "85327be8-d445-4397-b62a-df285c97326f",
}
UID_MODES = {uid: mode for mode, uid in MODE_UIDS.items()}


def session_cookie():
    config = COOLERCONTROL_CONFIG.read_text(encoding="utf-8")
    match = re.search(
        r'^networkCookies="@ByteArray\((cc=[^;]+);', config, re.MULTILINE
    )
    if not match:
        raise RuntimeError("CoolerControl session is unavailable")
    return match.group(1)


def api_request(method, path):
    # CoolerControl serves a local self-signed certificate. This connection is
    # deliberately fixed to loopback and never accepts a caller-provided host.
    context = ssl._create_unverified_context()
    connection = http.client.HTTPSConnection(
        COOLERCONTROL_HOST,
        COOLERCONTROL_PORT,
        context=context,
        timeout=1.5,
    )
    body = b"{}" if method == "POST" else None
    headers = {
        "Accept": "application/json",
        "Cookie": session_cookie(),
    }
    if body is not None:
        headers["Content-Type"] = "application/json"

    try:
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        payload = response.read()
        if response.status >= 400:
            raise RuntimeError(f"CoolerControl returned HTTP {response.status}")
        return json.loads(payload.decode("utf-8")) if payload else {}
    finally:
        connection.close()


def status():
    payload = api_request("GET", "/modes-active")
    uid = payload.get("current_mode_uid")
    return {
        "ok": True,
        "mode": UID_MODES.get(uid, "unknown"),
        "uid": uid or "",
        "error": "" if uid in UID_MODES else "No recognized cooling mode is active",
    }


def set_mode(mode):
    api_request("POST", f"/modes-active/{MODE_UIDS[mode]}")
    result = status()
    if result["mode"] != mode:
        raise RuntimeError(f"CoolerControl did not activate {mode}")
    return result


def safe_call(callback):
    try:
        return callback()
    except (OSError, RuntimeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return {"ok": False, "mode": "unknown", "uid": "", "error": str(exc)}


def emit(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    watch_parser = subparsers.add_parser("watch")
    watch_parser.add_argument("--interval", type=float, default=1.0)
    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("mode", choices=tuple(MODE_UIDS))
    args = parser.parse_args()

    if args.command == "watch":
        if args.interval < 0.25:
            parser.error("watch interval must be at least 0.25 seconds")
        try:
            while True:
                emit(safe_call(status))
                time.sleep(args.interval)
        except KeyboardInterrupt:
            return 0

    callback = status
    if args.command == "set":
        callback = lambda: set_mode(args.mode)

    response = safe_call(callback)
    emit(response)
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
