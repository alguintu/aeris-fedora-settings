"""Private-bus stand-ins: never address the real Plasma/PowerDevil session."""
import json
from pathlib import Path
import re
import subprocess
import sys
import threading

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
plasma_name = dbus.service.BusName("org.kde.plasmashell", bus)
power_name = dbus.service.BusName("org.kde.Solid.PowerManagement", bus)
states = []
active = False
failure = "Timed out waiting for inhibition change"
control_thread = None
loop = GLib.MainLoop()


class Plasma(dbus.service.Object):
    @dbus.service.method("org.kde.PlasmaShell", in_signature="s", out_signature="s")
    def evaluateScript(self, script):
        global active
        if "writeConfig('requested'" in script:
            assert "writeConfig('requestSerial'" in script
            active = re.search(r"writeConfig\('requested', (true|false)\)", script)[1] == "true"
            return ""
        assert "readConfig('active'" in script
        return json.dumps({"active": active})


class Power(dbus.service.Object):
    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, changes, invalidated):
        pass


plasma = Plasma(bus, "/PlasmaShell")
power = Power(bus, "/org/kde/Solid/PowerManagement/PolicyAgent")
script = Path(__file__).resolve().parents[2] / "quickshell/aeris-dashboard/services/sleepctl.py"
command = [sys.argv[1], "sleep", "watch"] if len(sys.argv) > 1 else [sys.executable, str(script), "watch"]
watcher = subprocess.Popen(command, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)


def receive(source, condition):
    global active, failure, control_thread
    line = source.readline()
    if not line:
        failure = "Watcher exited unexpectedly"
        loop.quit()
        return False
    state = json.loads(line)
    if not state["ok"]:
        failure = state["error"]
        loop.quit()
        return False
    states.append(state["active"])
    if len(states) == 3:
        failure = ""
        # Native command confirmations run while the mock desktop's event loop
        # remains responsive. This bus can never mutate the real awake switch.
        if len(sys.argv) > 1:
            control_thread = threading.Thread(target=check_controls)
            control_thread.start()
        else:
            loop.quit()
        return False
    active = not active
    power.PropertiesChanged("org.kde.Solid.PowerManagement.PolicyAgent",
                            {"ActiveInhibitions": dbus.Array([], signature="(ssssu)")}, [])
    return True


def check_controls():
    global failure
    try:
        for mode in ("on", "on", "off"):
            result = subprocess.run([sys.argv[1], "sleep", "set", mode],
                                    capture_output=True, text=True, timeout=3, check=True)
            assert json.loads(result.stdout)["active"] == (mode == "on")
    except Exception as error:
        failure = "Native sleep command failed: " + str(error)
    finally:
        GLib.idle_add(loop.quit)


GLib.io_add_watch(watcher.stdout, GLib.IO_IN | GLib.IO_HUP, receive)
GLib.timeout_add_seconds(6, lambda: loop.quit())
try:
    loop.run()
finally:
    watcher.terminate()
    _, errors = watcher.communicate(timeout=2)
    if control_thread:
        control_thread.join(timeout=4)
if failure:
    raise SystemExit(failure + errors)
print(json.dumps(states))
