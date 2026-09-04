#!/usr/bin/env python3
"""Control Plasma's native manual sleep/screen-lock toggle through its bridge."""

import argparse
import json
import signal
import time
import uuid

import dbus

_bus = None


def session_bus():
    global _bus
    if _bus is None:
        _bus = dbus.SessionBus()
    return _bus


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
    return str(session_bus().call_blocking(
        "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell",
        "evaluateScript", "s", (script,), timeout=8))


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
            dbus.DBusException) as error:
        return {"ok": False, "active": False, "error": str(error)}


class StateWatcher:
    """Signals prompt a debounced read of the tray's own confirmed state."""

    def __init__(self, scheduler, emit, read_status=status):
        self.scheduler, self.emit, self.read_status = scheduler, emit, read_status
        self.pending = self.fallback = 0

    def changed(self, *args):
        if not self.pending:
            # PowerDevil signals can precede the Plasma bridge's config update.
            self.pending = self.scheduler.timeout_add(200, self.refresh)

    def refresh(self):
        if self.pending:
            self.scheduler.source_remove(self.pending)
            self.pending = 0
        if self.fallback:
            self.scheduler.source_remove(self.fallback)
        result = safe_call(self.read_status)
        self.emit(result)
        self.fallback = self.scheduler.timeout_add_seconds(30 if result["ok"] else 2,
                                                           self.fallback_check)
        return False

    def fallback_check(self):
        self.fallback = 0
        return self.refresh()


def watch():
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = session_bus()
    watcher = StateWatcher(GLib, lambda result: print(json.dumps(result), flush=True))
    bus.add_signal_receiver(watcher.changed, signal_name="PropertiesChanged",
                            dbus_interface="org.freedesktop.DBus.Properties",
                            bus_name="org.kde.Solid.PowerManagement",
                            path="/org/kde/Solid/PowerManagement/PolicyAgent",
                            arg0="org.kde.Solid.PowerManagement.PolicyAgent")
    for name in ("org.kde.plasmashell", "org.kde.Solid.PowerManagement"):
        bus.add_signal_receiver(watcher.changed, signal_name="NameOwnerChanged",
                                dbus_interface="org.freedesktop.DBus", arg0=name)
    # Also supported by older PowerDevil versions without the properties above.
    bus.add_signal_receiver(watcher.changed, signal_name="InhibitionsChanged",
                            dbus_interface="org.kde.Solid.PowerManagement.PolicyAgent",
                            bus_name="org.kde.Solid.PowerManagement",
                            path="/org/kde/Solid/PowerManagement/PolicyAgent")
    loop = GLib.MainLoop()
    bus.call_on_disconnection(lambda connection: loop.quit())
    watcher.refresh()
    loop.run()


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
        watch()
        return 0
    callback = attach_bridge if args.command == "attach-bridge" else status
    if args.command == "set":
        callback = lambda: set_mode(args.mode == "on")
    response = safe_call(callback)
    print(json.dumps(response), flush=True)
    return 0 if response["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
