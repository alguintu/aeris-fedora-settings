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


class CoolerClient:
    """One reusable loopback connection; retry reads, never replay a mode change."""

    def __init__(self):
        self.connection = self.context = None
        self.cookie_key = self.cookie_value = None

    def cookie(self):
        stat = COOLERCONTROL_CONFIG.stat()
        key = (str(COOLERCONTROL_CONFIG), stat.st_ino, stat.st_mtime_ns, stat.st_size)
        if key != self.cookie_key:
            config = COOLERCONTROL_CONFIG.read_text(encoding="utf-8")
            match = re.search(r'^networkCookies="@ByteArray\((cc=[^;]+);', config, re.MULTILINE)
            if not match:
                raise RuntimeError("CoolerControl session is unavailable")
            self.cookie_value, self.cookie_key = match.group(1), key
        return self.cookie_value

    def close(self):
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def request(self, method, path):
        attempts = 2 if method == "GET" else 1
        for attempt in range(attempts):
            headers = {"Accept": "application/json", "Cookie": self.cookie()}
            body = b"{}" if method == "POST" else None
            if body is not None:
                headers["Content-Type"] = "application/json"
            if self.connection is None:
                # Local self-signed certificate, fixed loopback endpoint only.
                if self.context is None:
                    self.context = ssl._create_unverified_context()
                self.connection = http.client.HTTPSConnection(
                    COOLERCONTROL_HOST, COOLERCONTROL_PORT, context=self.context, timeout=1.5)
            try:
                self.connection.request(method, path, body=body, headers=headers)
                response = self.connection.getresponse()
                payload = response.read()  # fully consume before reusing the connection
                if response.will_close:
                    self.close()
                if response.status in (401, 403):
                    self.cookie_key = None
                    self.close()
                    if attempt + 1 < attempts:
                        continue
                if response.status >= 400:
                    raise RuntimeError(f"CoolerControl returned HTTP {response.status}")
                return json.loads(payload.decode("utf-8")) if payload else {}
            except (OSError, http.client.HTTPException):
                self.close()
                if attempt + 1 == attempts:
                    raise


_client = CoolerClient()


def api_request(method, path):
    return _client.request(method, path)


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
    except (OSError, http.client.HTTPException, RuntimeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
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
        finally:
            _client.close()

    callback = status
    if args.command == "set":
        callback = lambda: set_mode(args.mode)

    response = safe_call(callback)
    emit(response)
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
