#!/usr/bin/python3
"""Emit lightweight Aeris dashboard telemetry as newline-delimited JSON."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import time
from pathlib import Path
from typing import Any


HWMON_ROOT = Path("/sys/class/hwmon")
DRM_ROOT = Path("/sys/class/drm")
CPU_ROOT = Path("/sys/devices/system/cpu")
BLOCK_ROOT = Path("/sys/block")


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


def physical_disk_capacity() -> int | None:
    """Count whole physical disks once, excluding partitions and virtual devices."""
    total = 0
    found = False
    for disk in BLOCK_ROOT.glob("*"):
        if not (disk / "device").exists() or "virtual" in disk.resolve().parts:
            continue
        sectors = read_number(disk / "size")
        if sectors is not None and sectors > 0:
            # Linux sysfs reports size in 512-byte sectors, even for 4K disks.
            total += int(sectors) * 512
            found = True
    return total if found else None


def mounted_disk_space() -> tuple[int | None, int | None]:
    """Usable capacity and user-available space on unique mounted local filesystems."""
    total = available = 0
    seen = set()
    try:
        for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
            before, after = line.split(" - ", 1)
            fs_type, source, *_ = after.split()
            if not source.startswith("/dev/"):
                continue
            mount_fields = before.split()
            # Btrfs subvolumes can have different statvfs IDs while sharing
            # the same filesystem capacity. Mountinfo's device ID is shared.
            key = (fs_type, mount_fields[2])
            if key in seen:
                continue
            mountpoint = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), mount_fields[4])
            stats = os.statvfs(mountpoint)
            seen.add(key)
            total += stats.f_blocks * stats.f_frsize
            available += stats.f_bavail * stats.f_frsize
    except (OSError, ValueError):
        return None, None
    return (total, available) if total > 0 else (None, None)


def drive_usage() -> list[dict[str, Any]]:
    drives = []
    for label, mount in (("System", "/"), ("Workspace", "/mnt/workspace"),
                         ("Documents", "/mnt/documents"), ("Storage", "/mnt/storage")):
        entry = {"label": label, "mount": mount, "used": None, "total": None}
        try:
            # Do not report the root filesystem if a data drive is unmounted.
            if os.path.ismount(mount):
                usage = shutil.disk_usage(mount)
                entry.update(used=usage.used, total=usage.total)
        except OSError:
            pass
        drives.append(entry)
    return drives


def hwmon_dir(driver_name: str) -> Path | None:
    for candidate in sorted(HWMON_ROOT.glob("hwmon*")):
        if read_text(candidate / "name") == driver_name:
            return candidate
    return None


def labeled_temperature(driver_name: str, wanted_label: str) -> float | None:
    directory = hwmon_dir(driver_name)
    if directory is None:
        return None
    for label_path in directory.glob("temp*_label"):
        if read_text(label_path) == wanted_label:
            return read_number(label_path.with_name(label_path.name.replace("_label", "_input")), 1000)
    return None


def gpu_device() -> Path | None:
    for card in sorted(DRM_ROOT.glob("card[0-9]*")):
        device = card / "device"
        if (device / "gpu_busy_percent").exists():
            return device
    return None


def cpu_clock_ghz() -> float | None:
    clocks = [read_number(path, 1_000_000) for path in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq")]
    valid = [clock for clock in clocks if clock is not None]
    return round(sum(valid) / len(valid), 2) if valid else None


def collect(
    previous_cpu: dict[int | str, tuple[int, int]],
    current_cpu: dict[int | str, tuple[int, int]],
) -> dict[str, Any]:
    ram_used, ram_total = memory_bytes()
    root_disk = shutil.disk_usage("/")
    mounted_total, mounted_free = mounted_disk_space()
    device = gpu_device()

    return {
        "cpuUsage": cpu_usage(previous_cpu["cpu"], current_cpu["cpu"]),
        "cpuCcds": cpu_ccd_usage(previous_cpu, current_cpu),
        "cpuTemp": labeled_temperature("k10temp", "Tctl"),
        "cpuClock": cpu_clock_ghz(),
        "gpuUsage": read_number(device / "gpu_busy_percent") if device else None,
        "gpuTemp": labeled_temperature("amdgpu", "edge"),
        "gpuHotspot": labeled_temperature("amdgpu", "junction"),
        "vramUsed": int(read_number(device / "mem_info_vram_used") or 0) if device else None,
        "vramTotal": int(read_number(device / "mem_info_vram_total") or 0) if device else None,
        "ramUsed": ram_used,
        "ramTotal": ram_total,
        "rootUsed": root_disk.used,
        "rootTotal": root_disk.total,
        "physicalDiskTotal": physical_disk_capacity(),
        "mountedDiskTotal": mounted_total,
        "mountedDiskFree": mounted_free,
        "drives": drive_usage(),
        "timestamp": int(time.time()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    previous_cpu = cpu_samples()
    time.sleep(0.25)

    while True:
        current_cpu = cpu_samples()
        print(json.dumps(collect(previous_cpu, current_cpu), separators=(",", ":")), flush=True)
        previous_cpu = current_cpu
        if args.once:
            return
        time.sleep(1.0)


if __name__ == "__main__":
    main()
