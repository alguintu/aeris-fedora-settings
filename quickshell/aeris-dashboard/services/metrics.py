#!/usr/bin/python3
"""Emit lightweight Aeris dashboard telemetry as newline-delimited JSON."""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from pathlib import Path
from typing import Any


HWMON_ROOT = Path("/sys/class/hwmon")
DRM_ROOT = Path("/sys/class/drm")
CPU_ROOT = Path("/sys/devices/system/cpu")
MOUNTINFO = Path("/proc/self/mountinfo")
DRIVES = (("System", "/"), ("Workspace", "/mnt/workspace"),
          ("Documents", "/mnt/documents"), ("Storage", "/mnt/storage"))


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, ValueError):
        return None


def read_number(path: Path, divisor: float = 1.0) -> float | None:
    value = read_text(path)
    if value is None:
        return None
    try:
        return float(value) / divisor
    except ValueError:
        return None


def cpu_samples() -> dict[int | str, tuple[int, int]]:
    samples: dict[int | str, tuple[int, int]] = {}
    for line in Path("/proc/stat").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        name = fields[0]
        if name == "cpu":
            key: int | str = "cpu"
        elif name.startswith("cpu") and name[3:].isdigit():
            key = int(name[3:])
        else:
            break

        values = [int(field) for field in fields[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        samples[key] = (sum(values), idle)
    return samples


def cpu_usage(previous: tuple[int, int], current: tuple[int, int]) -> float:
    total_delta = current[0] - previous[0]
    idle_delta = current[1] - previous[1]
    if total_delta <= 0:
        return 0.0
    return round(100.0 * (total_delta - idle_delta) / total_delta, 1)


def parse_cpu_list(value: str | None) -> tuple[int, ...]:
    if not value:
        return ()
    cpus: list[int] = []
    for part in value.split(","):
        if "-" in part:
            start, end = (int(item) for item in part.split("-", 1))
            cpus.extend(range(start, end + 1))
        else:
            cpus.append(int(part))
    return tuple(sorted(cpus))


def cpu_topology() -> list[list[tuple[int, ...]]]:
    """Group physical cores by shared L3 cache, which maps the two Ryzen CCDs."""
    groups: dict[tuple[int, ...], dict[int, tuple[int, ...]]] = {}
    for cpu_path in sorted(CPU_ROOT.glob("cpu[0-9]*"), key=lambda path: int(path.name[3:])):
        cpu_id = int(cpu_path.name[3:])
        siblings = parse_cpu_list(read_text(cpu_path / "topology/thread_siblings_list")) or (cpu_id,)
        if cpu_id != siblings[0]:
            continue

        l3_group = parse_cpu_list(read_text(cpu_path / "cache/index3/shared_cpu_list")) or siblings
        core_id = int(read_text(cpu_path / "topology/core_id") or cpu_id)
        groups.setdefault(l3_group, {})[core_id] = siblings

    return [
        [cores[core_id] for core_id in sorted(cores)]
        for _, cores in sorted(groups.items(), key=lambda item: min(item[0]))
    ]


CPU_TOPOLOGY = cpu_topology()


def cpu_ccd_usage(
    previous: dict[int | str, tuple[int, int]],
    current: dict[int | str, tuple[int, int]],
) -> list[list[list[float]]]:
    result: list[list[list[float]]] = []
    for ccd in CPU_TOPOLOGY:
        cores: list[list[float]] = []
        for siblings in ccd:
            threads = [
                cpu_usage(previous[cpu_id], current[cpu_id])
                if cpu_id in previous and cpu_id in current else 0.0
                for cpu_id in siblings
            ]
            cores.append(threads)
        result.append(cores)
    return result


def memory_bytes() -> tuple[int, int]:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
        key, raw_value = line.split(":", 1)
        values[key] = int(raw_value.split()[0]) * 1024
    total = values["MemTotal"]
    return total - values["MemAvailable"], total


def disk_snapshot() -> dict[str, Any]:
    """Share one statvfs per local filesystem between totals and drive bars."""
    total = available = 0
    filesystems = {}
    mounts = {}
    complete = True
    try:
        for line in MOUNTINFO.read_text(encoding="utf-8").splitlines():
            before, after = line.split(" - ", 1)
            fs_type, source, *_ = after.split()
            if not source.startswith("/dev/"):
                continue
            mount_fields = before.split()
            # Btrfs subvolumes can have different statvfs IDs while sharing
            # the same filesystem capacity. Mountinfo's device ID is shared.
            key = (fs_type, mount_fields[2])
            mountpoint = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), mount_fields[4])
            if key not in filesystems:
                try:
                    stats = os.statvfs(mountpoint)
                    filesystems[key] = stats
                    total += stats.f_blocks * stats.f_frsize
                    available += stats.f_bavail * stats.f_frsize
                except OSError:
                    filesystems[key] = None
                    complete = False
            mounts[mountpoint] = filesystems[key]
    except (OSError, ValueError):
        complete = False
    drives = []
    for label, mount in DRIVES:
        entry = {"label": label, "mount": mount, "used": None, "total": None}
        # Only actual mountpoints: an unmounted data drive must not show root usage.
        stats = mounts.get(mount)
        if stats is not None:
            entry.update(used=(stats.f_blocks - stats.f_bfree) * stats.f_frsize,
                         total=stats.f_blocks * stats.f_frsize)
        drives.append(entry)
    return {"mountedDiskTotal": total if complete and total > 0 else None,
            "mountedDiskFree": available if complete and total > 0 else None,
            "drives": drives}


def hwmon_dir(driver_name: str) -> Path | None:
    for candidate in sorted(HWMON_ROOT.glob("hwmon*")):
        if read_text(candidate / "name") == driver_name:
            return candidate
    return None


def temperature_path(directory: Path | None, wanted_label: str) -> Path | None:
    if directory is None:
        return None
    for label_path in directory.glob("temp*_label"):
        if read_text(label_path) == wanted_label:
            return label_path.with_name(label_path.name.replace("_label", "_input"))
    return None


def gpu_device() -> Path | None:
    for card in sorted(DRM_ROOT.glob("card[0-9]*")):
        device = card / "device"
        if (device / "gpu_busy_percent").exists():
            return device
    return None


class TemperaturePoll:
    """Independent CPU/GPU cadence, retaining fast reads through early cooldown."""

    def __init__(self) -> None:
        self.last_read = self.busy_until = float("-inf")
        self.values: dict[str, float | None] = {}

    def sample(self, now: float, busy: bool, paths: dict[str, Path | None]) -> dict:
        if busy:
            self.busy_until = now + 6.0
        interval = 1.0 if now <= self.busy_until else 3.0
        if now - self.last_read >= interval:
            self.values = {key: read_number(path, 1000) if path else None
                           for key, path in paths.items()}
            self.last_read = now
        return self.values


class MetricsCollector:
    def __init__(self) -> None:
        self.cpu_temperatures = TemperaturePoll()
        self.gpu_temperatures = TemperaturePoll()
        self.next_discovery = self.next_disk = float("-inf")
        self.needs_discovery = True
        self.disks: dict[str, Any] = {}
        self.clock_paths: dict[int, Path] = {}

    def discover(self, now: float) -> None:
        cpu_hwmon, gpu_hwmon = hwmon_dir("k10temp"), hwmon_dir("amdgpu")
        self.cpu_paths = {"cpuTemp": temperature_path(cpu_hwmon, "Tctl")}
        self.gpu_paths = {"gpuTemp": temperature_path(gpu_hwmon, "edge"),
                          "gpuHotspot": temperature_path(gpu_hwmon, "junction")}
        self.device = gpu_device()
        self.vram_total = read_number(self.device / "mem_info_vram_total") if self.device else None
        self.clock_paths = {}
        for cpu in CPU_ROOT.glob("cpu[0-9]*"):
            for name in ("cpuinfo_avg_freq", "scaling_cur_freq"):
                path = cpu / "cpufreq" / name
                if path.exists():
                    self.clock_paths[int(cpu.name[3:])] = path
                    break
        self.needs_discovery = False
        self.next_discovery = now + 30.0

    def collect(self, previous_cpu: dict, current_cpu: dict, now: float | None = None) -> dict[str, Any]:
        now = time.monotonic() if now is None else now
        if self.needs_discovery and now >= self.next_discovery:
            self.discover(now)
        usage = cpu_usage(previous_cpu["cpu"], current_cpu["cpu"])
        threads = {cpu: cpu_usage(previous_cpu[cpu], sample)
                   for cpu, sample in current_cpu.items() if isinstance(cpu, int) and cpu in previous_cpu}
        # One policy read, not a package-wide average. Selection reuses /proc/stat.
        candidates = threads.keys() & self.clock_paths.keys()
        busiest = max(candidates, key=lambda cpu: (threads[cpu], -cpu)) if candidates else None
        clock = read_number(self.clock_paths[busiest], 1_000_000) if busiest is not None else None
        if clock is not None and clock <= 0:
            clock = None
        gpu_usage = read_number(self.device / "gpu_busy_percent") if self.device else None
        vram_used = read_number(self.device / "mem_info_vram_used") if self.device else None
        cpu_temps = self.cpu_temperatures.sample(now, usage >= 10 or max(threads.values(), default=0) >= 50,
                                                self.cpu_paths)
        gpu_temps = self.gpu_temperatures.sample(now, (gpu_usage or 0) >= 10, self.gpu_paths)
        # Missing/unplugged sensors recover without rescanning labels every second.
        self.needs_discovery = any(value is None for value in
                                   [clock, gpu_usage, vram_used, self.vram_total,
                                    *cpu_temps.values(), *gpu_temps.values()])
        if now >= self.next_disk:
            self.disks = disk_snapshot()
            self.next_disk = now + 60.0
        ram_used, ram_total = memory_bytes()
        return {"cpuUsage": usage, "cpuCcds": cpu_ccd_usage(previous_cpu, current_cpu),
                "cpuClock": round(clock, 2) if clock is not None else None,
                "gpuUsage": gpu_usage, "vramUsed": vram_used, "vramTotal": self.vram_total,
                "ramUsed": ram_used, "ramTotal": ram_total,
                **cpu_temps, **gpu_temps, **self.disks, "timestamp": int(time.time())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    collector = MetricsCollector()

    previous_cpu = cpu_samples()
    time.sleep(0.25)

    while True:
        current_cpu = cpu_samples()
        print(json.dumps(collector.collect(previous_cpu, current_cpu), separators=(",", ":")), flush=True)
        previous_cpu = current_cpu
        if args.once:
            return
        time.sleep(1.0)


if __name__ == "__main__":
    main()
