#!/usr/bin/python3
"""Emit lightweight Aeris dashboard telemetry as newline-delimited JSON."""

from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path


HWMON_ROOT = Path("/sys/class/hwmon")
DRM_ROOT = Path("/sys/class/drm")


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


def cpu_sample() -> tuple[int, int]:
    fields = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0].split()[1:]
    values = [int(field) for field in fields]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle


def cpu_usage(previous: tuple[int, int], current: tuple[int, int]) -> float:
    total_delta = current[0] - previous[0]
    idle_delta = current[1] - previous[1]
    if total_delta <= 0:
        return 0.0
    return round(100.0 * (total_delta - idle_delta) / total_delta, 1)


def memory_bytes() -> tuple[int, int]:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
        key, raw_value = line.split(":", 1)
        values[key] = int(raw_value.split()[0]) * 1024
    total = values["MemTotal"]
    return total - values["MemAvailable"], total


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


def collect(previous_cpu: tuple[int, int], current_cpu: tuple[int, int]) -> dict[str, float | int | None]:
    ram_used, ram_total = memory_bytes()
    root_disk = shutil.disk_usage("/")
    device = gpu_device()

    return {
        "cpuUsage": cpu_usage(previous_cpu, current_cpu),
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
        "timestamp": int(time.time()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    previous_cpu = cpu_sample()
    time.sleep(0.25)

    while True:
        current_cpu = cpu_sample()
        print(json.dumps(collect(previous_cpu, current_cpu), separators=(",", ":")), flush=True)
        previous_cpu = current_cpu
        if args.once:
            return
        time.sleep(1.0)


if __name__ == "__main__":
    main()
