#!/usr/bin/env python3
"""Read-only, interval-based dashboard CPU, DRM engine and memory measurements."""
import argparse
import json
import os
import pathlib
import re
import subprocess
import time


def number(text, key):
    match = re.search(r"^" + re.escape(key) + r"[: ]+\s*(\d+)", text, re.M)
    return int(match[1]) if match else 0


def compositor_snapshot(pid):
    if not pid:
        return None
    try:
        stat = pathlib.Path(f"/proc/{pid}/stat").read_text()
        fields = stat[stat.rfind(")") + 2:].split()
        clients = {}
        for fd in pathlib.Path(f"/proc/{pid}/fdinfo").glob("*"):
            try:
                text = fd.read_text()
            except (FileNotFoundError, PermissionError):
                continue
            if "drm-client-id:" not in text:
                continue
            device = re.search(r"drm-pdev:\s*(\S+)", text)
            key = (device[1] if device else "") + ":" + str(number(text, "drm-client-id"))
            clients[key] = dict((m[1], int(m[2])) for m in
                re.finditer(r"^drm-engine-(\S+):\s*(\d+) ns", text, re.M))
        return {"start": fields[19], "ticks": int(fields[11]) + int(fields[12]), "clients": clients}
    except (FileNotFoundError, PermissionError):
        return None


def snapshot(group, compositor_pid=None):
    clients = {}
    threads = {}
    for pid in (group / "cgroup.procs").read_text().split():
        try:
            args = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0")
            script = next((pathlib.Path(a).name for a in args if a.endswith(".py")), "")
            for task in pathlib.Path(f"/proc/{pid}/task").iterdir():
                stat = (task / "stat").read_text()
                end = stat.rfind(")")
                fields = stat[end + 2:].split()
                key = f"{pid}/{task.name}/{fields[19]}"
                threads[key] = {"name": script or stat[stat.find("(") + 1:end],
                                "ticks": int(fields[11]) + int(fields[12])}
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
        for fd in pathlib.Path(f"/proc/{pid}/fdinfo").glob("*"):
            try:
                text = fd.read_text()
            except (FileNotFoundError, PermissionError):
                continue
            if "drm-client-id:" not in text:
                continue
            device = re.search(r"drm-pdev:\s*(\S+)", text)
            key = (device[1] if device else "") + ":" + str(number(text, "drm-client-id"))
            clients[key] = {"engines": dict((m[1], int(m[2])) for m in
                re.finditer(r"^drm-engine-(\S+):\s*(\d+) ns", text, re.M)),
                "vram": number(text, "drm-resident-vram") * 1024}
    power, busy = [], []
    for device in pathlib.Path("/sys/class/drm").glob("card[0-9]*/device"):
        if not re.fullmatch(r"card\d+", device.parent.name):
            continue
        try:
            busy.append(float((device / "gpu_busy_percent").read_text()))
        except OSError:
            pass
        for path in device.glob("hwmon/hwmon*/power1_average"):
            try:
                power.append(float(path.read_text()) / 1e6)
            except OSError:
                pass
    return {"at": time.monotonic(), "threads": threads, "compositor": compositor_snapshot(compositor_pid),
            "cpu": number((group / "cpu.stat").read_text(), "usage_usec"),
            "memory": int((group / "memory.current").read_text()), "clients": clients,
            "gpuBoardWatts": power, "gpuDeviceBusyPercent": busy}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=20, choices=range(1, 61), metavar="1..60")
    parser.add_argument("--label", default="current")
    args = parser.parse_args()
    cg = subprocess.check_output(["systemctl", "--user", "show", "aeris-dashboard.service",
                                  "-p", "ControlGroup", "--value"], text=True).strip()
    if not cg or cg == "/":
        raise SystemExit("Dashboard service is not running")
    group = pathlib.Path("/sys/fs/cgroup") / cg.lstrip("/")
    compositor_pid = subprocess.run(["pgrep", "-xo", "kwin_wayland"], capture_output=True, text=True).stdout.strip()
    first = snapshot(group, compositor_pid)
    samples = []
    for _ in range(args.seconds):
        time.sleep(1)
        samples.append(snapshot(group, compositor_pid))
    last = samples[-1]
    if any(b["cpu"] < a["cpu"] for a, b in zip([first] + samples[:-1], samples)):
        raise SystemExit("Invalid sample: dashboard service restarted; repeat after it settles.")
    seconds = last["at"] - first["at"]
    engines = {}
    for client, value in last["clients"].items():
        for engine, ns in value["engines"].items():
            before = first["clients"].get(client, {}).get("engines", {}).get(engine, ns)
            engines[engine] = engines.get(engine, 0) + max(0, ns - before) / (seconds * 1e9) * 100
    mean = lambda values: round(sum(values) / len(values), 3) if values else None
    thread_cpu = {}
    for key, thread in last["threads"].items():
        if key not in first["threads"]:
            continue
        used = (thread["ticks"] - first["threads"][key]["ticks"]) / os.sysconf("SC_CLK_TCK") / seconds * 100
        thread_cpu[thread["name"]] = thread_cpu.get(thread["name"], 0) + used
    compositor_cpu, compositor_engines = None, {}
    a, b = first["compositor"], last["compositor"]
    if a and b and a["start"] == b["start"]:
        compositor_cpu = (b["ticks"] - a["ticks"]) / os.sysconf("SC_CLK_TCK") / seconds * 100
        for client, engines_now in b["clients"].items():
            for engine, ns in engines_now.items():
                old = a["clients"].get(client, {}).get(engine, ns)
                compositor_engines[engine] = compositor_engines.get(engine, 0) + max(0, ns - old) / seconds / 1e9 * 100
    print(json.dumps({"label": args.label, "seconds": round(seconds, 2),
        "cpuPercentOneLogicalCPU": round((last["cpu"] - first["cpu"]) / (seconds * 1e6) * 100, 3),
        "gpuEngineBusyPercent": {k: round(v, 4) for k, v in engines.items()},
        "threadCpuPercent": {k: round(v, 3) for k, v in sorted(thread_cpu.items(), key=lambda p: -p[1]) if v > 0},
        "wholeCompositorCpuPercent": round(compositor_cpu, 3) if compositor_cpu is not None else None,
        "wholeCompositorGpuEngineBusyPercent": {k: round(v, 4) for k, v in compositor_engines.items()} or None,
        "serviceMemoryMiB": round(last["memory"] / 1048576, 1),
        "residentVramMiB": round(sum(v["vram"] for v in last["clients"].values()) / 1048576, 1),
        "wholeGpuBoardWattsMean": mean([v for s in samples for v in s["gpuBoardWatts"]]),
        "wholeGpuBusyPercentMean": mean([v for s in samples for v in s["gpuDeviceBusyPercent"]])}))


if __name__ == "__main__":
    main()
