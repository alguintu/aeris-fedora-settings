"""Run under dbus-run-session. Fake logind/systemd/socket, no hardware writes.

The guarded start still checks Aeris's existing USB/HID sysfs identity read-only.
This fixture is an explicit on-Aeris integration check, not a portable unit test.
"""
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile
import threading
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

# Refuse an ordinary desktop bus: the harness must supply a private bus.
assert os.environ.get('AERIS_RGB_PRIVATE_BUS_TEST') == '1'
assert os.environ['DBUS_SESSION_BUS_ADDRESS'] != f'unix:path=/run/user/{os.getuid()}/bus'
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
login_name = dbus.service.BusName('org.freedesktop.login1', bus)
manager_name = dbus.service.BusName('org.freedesktop.systemd1', bus)
units = {}
stops = []
starts = []
inhibitor_writes = []
fail_start = False
force_bad_stop = False
ready = threading.Event()
logs = []

class Login(dbus.service.Object):
    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        return dbus.UInt64(5_000_000) if name == 'InhibitDelayMaxUSec' else dbus.Boolean(False)

    @dbus.service.method('org.freedesktop.login1.Manager', in_signature='ssss', out_signature='h')
    def Inhibit(self, what, who, why, mode):
        assert what == 'sleep' and mode == 'delay'
        r, w = os.pipe()
        inhibitor_writes.append(w)
        fd = dbus.types.UnixFd(r)
        os.close(r)
        return fd

    @dbus.service.signal('org.freedesktop.login1.Manager', signature='b')
    def PrepareForSleep(self, sleeping):
        pass

class Unit(dbus.service.Object):
    def __init__(self, path):
        super().__init__(bus, path)
        self.object_path = path
        self.state, self.result = 'active', 'success'

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if name == 'ActiveState': return self.state
        if name == 'Result': return self.result
        if name == 'Job': return dbus.Struct((dbus.UInt32(0), dbus.ObjectPath('/')), signature='uo')
        raise RuntimeError(name)

class Manager(dbus.service.Object):
    @dbus.service.method('org.freedesktop.systemd1.Manager', in_signature='s', out_signature='o')
    def LoadUnit(self, name):
        return units[str(name)].object_path

    @dbus.service.method('org.freedesktop.systemd1.Manager', in_signature='ss', out_signature='o')
    def StopUnit(self, name, mode):
        assert mode == 'replace'
        stops.append(str(name))
        unit = units[str(name)]
        unit.state = 'inactive'
        if force_bad_stop: unit.result = 'timeout'
        return '/job/1'

    @dbus.service.method('org.freedesktop.systemd1.Manager', in_signature='ss', out_signature='o')
    def StartUnit(self, name, mode):
        assert mode == 'fail'
        starts.append(str(name))
        for unit in units.values():
            unit.state = 'failed' if fail_start else 'active'
            unit.result = 'exit-code' if fail_start else 'success'
        return '/job/2'

login = Login(bus, '/org/freedesktop/login1')
manager = Manager(bus, '/org/freedesktop/systemd1')
for i, name in enumerate(['aeris-openrgb.service', 'aeris-openrgb-server.service']):
    units[name] = Unit(f'/units/u{i}')

loop = GLib.MainLoop()
threading.Thread(target=loop.run, daemon=True).start()

def wait(predicate, message, timeout=6):
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() > deadline:
            raise AssertionError(message + '\n' + '\n'.join(logs))
        time.sleep(.02)

def emit(sleeping):
    GLib.idle_add(lambda: (login.PrepareForSleep(sleeping), False)[1])

def read_logs(process):
    for line in process.stderr:
        logs.append(line.strip())
        if 'watcher ready' in line: ready.set()

with tempfile.TemporaryDirectory(prefix='aeris-rgb-fixture-') as runtime:
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(Path(runtime) / 'aeris-openrgb.sock'))
    server.listen()
    def serve():
        while True:
            conn, _ = server.accept()
            with conn:
                request = json.loads(conn.recv(65536))
                assert request == {'command': 'status'}, request
                active = all(u.state == 'active' for u in units.values())
                conn.sendall(json.dumps({'ok': active, 'mode': 'work' if active else 'unknown'}).encode())
    threading.Thread(target=serve, daemon=True).start()
    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'], XDG_RUNTIME_DIR=runtime)
    process = subprocess.Popen([sys.argv[1], 'rgb', 'sleep-watch'], env=env, stderr=subprocess.PIPE, text=True)
    threading.Thread(target=read_logs, args=(process,), daemon=True).start()
    try:
        assert ready.wait(5), logs
        # Duplicate wake without a captured healthy cycle does nothing.
        emit(False)
        time.sleep(.2)
        assert not starts and not stops
        # Healthy cycle: both stops, release delay FD, one fresh start, reacquire.
        emit(True)
        wait(lambda: len(stops) == 2 and any('armed=true' in x for x in logs), 'clean pre-sleep stop')
        assert not starts
        assert (Path(runtime) / 'aeris-openrgb-sleep-in-progress').exists()
        manual = subprocess.run([sys.argv[1], 'rgb', 'start'], env=env,
                                capture_output=True, text=True, timeout=3)
        assert manual.returncode != 0 and 'paused for sleep' in manual.stdout
        assert not starts
        wait(lambda: select.select([], [inhibitor_writes[0]], [], 0)[1], 'inhibitor readiness')
        try:
            os.write(inhibitor_writes[0], b'x')
            raise AssertionError('delay inhibitor was not released')
        except BrokenPipeError:
            pass
        emit(True)  # duplicate prepare
        emit(False)
        wait(lambda: any('resume healthy' in x for x in logs), 'healthy resume')
        assert len(starts) == 1 and len(stops) == 2 and len(inhibitor_writes) == 2
        assert not (Path(runtime) / 'aeris-openrgb-start-attempt').exists()
        assert not (Path(runtime) / 'aeris-openrgb-sleep-in-progress').exists()
        emit(False)
        time.sleep(.2)
        assert len(starts) == 1
        # A failed/offline runtime before sleep is never automatically recovered.
        for u in units.values(): u.state, u.result = 'failed', 'exit-code'
        emit(True)
        wait(lambda: len(stops) == 4, 'failed runtime stopped')
        time.sleep(4.5)  # failed Result intentionally exhausts the clean-stop budget
        emit(False)
        time.sleep(.3)
        assert len(starts) == 1
        # A healthy runtime whose stop is uncertain must stay stopped on wake.
        for u in units.values(): u.state, u.result = 'active', 'success'
        force_bad_stop = True
        emit(True)
        wait(lambda: len(stops) == 6, 'uncertain stop requested')
        time.sleep(4.5)
        emit(False)
        time.sleep(.3)
        assert len(starts) == 1
        force_bad_stop = False
        # Failed fresh startup retains the marker; duplicate wake does not retry.
        for u in units.values(): u.state, u.result = 'active', 'success'
        fail_start = True
        emit(True)
        wait(lambda: len(stops) == 8, 'last stop')
        time.sleep(.2)
        emit(False)
        wait(lambda: len(starts) == 2 and any('startup failed its safety checks' in x for x in logs), 'failed start reported')
        assert (Path(runtime) / 'aeris-openrgb-start-attempt').exists()
        emit(False)
        time.sleep(.3)
        assert len(starts) == 2
        assert process.poll() is None
        print('PASS: clean stop/wake, delay FD release/reacquire, duplicate events, pre-existing failure, uncertain stop, failed-start marker and no retries')
    finally:
        process.terminate()
        process.wait(timeout=3)
        loop.quit()
        for fd in inhibitor_writes: os.close(fd)
