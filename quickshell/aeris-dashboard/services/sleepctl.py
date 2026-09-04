#!/usr/bin/env python3
"""Control Plasma's native manual sleep/screen-lock toggle through its bridge."""

import argparse
import json
import signal
import subprocess
import time
import uuid


FIND_BRIDGE = """
var ds = desktops();
var bridge = null;
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === 'org.aeris.sleepbridge') bridge = ws[j];
    }
}
if (!bridge) throw new Error('Aeris sleep bridge is not attached to the desktop');
bridge.currentConfigGroup = ['General'];
"""


def plasma_script(script):
    result = subprocess.run([
        "busctl", "--user", "--json=short", "call", "org.kde.plasmashell",
        "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", "s", script,
    ], capture_output=True, text=True, timeout=8)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Unable to contact Plasma")
    return json.loads(result.stdout)["data"][0]


def status():
    result = plasma_script(FIND_BRIDGE + """
print(JSON.stringify({active: bridge.readConfig('active', false)}));
""")
    data = json.loads(result)
    return {"ok": True, "active": data["active"] is True, "error": ""}


def set_mode(enabled):
    current = status()
    if current["active"] == enabled:
        return current
    plasma_script(FIND_BRIDGE + f"""
bridge.writeConfig('requested', {json.dumps(enabled)});
bridge.writeConfig('requestSerial', {json.dumps(str(uuid.uuid4()))});
""")
    for _ in range(30):
        current = status()
        if current["active"] == enabled:
            return current
        time.sleep(0.1)
    raise RuntimeError("KDE's manual sleep toggle did not reach the requested state")


def attach_bridge():
    plasma_script("""
var ds = desktops();
var found = false;
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === 'org.aeris.sleepbridge') found = true;
    }
}
if (!found) {
    if (!ds.length) throw new Error('No Plasma desktop available');
    ds[0].addWidget('org.aeris.sleepbridge');
}
""")
    return {"ok": True, "error": ""}


def safe_call(callback):
    try:
        return callback()
    except (OSError, ValueError, KeyError, IndexError, TypeError, RuntimeError,
            subprocess.TimeoutExpired) as error:
        return {"ok": False, "active": False, "error": str(error)}


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("watch")
    commands.add_parser("attach-bridge")
    setter = commands.add_parser("set")
    setter.add_argument("mode", choices=("on", "off"))
    args = parser.parse_args()
    if args.command == "watch":
        while True:
            print(json.dumps(safe_call(status)), flush=True)
            time.sleep(1)
    callback = attach_bridge if args.command == "attach-bridge" else status
    if args.command == "set":
        callback = lambda: set_mode(args.mode == "on")
    response = safe_call(callback)
    print(json.dumps(response), flush=True)
    return 0 if response["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
