#!/usr/bin/env python3
import glob
import logging
import time
from pathlib import Path

import psutil
import yaml
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor


CONFIG = Path.home() / ".config/aeris-openrgb/config.yaml"
LOG = logging.getLogger("aeris-openrgb")


def read_number(path, scale=1.0):
    try:
        return float(Path(path).read_text().strip()) / scale
    except (OSError, ValueError):
        return None


def find_hwmon(name):
    for entry in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if (Path(entry) / "name").read_text().strip() == name:
                return Path(entry)
        except OSError:
            pass
    return None


def find_gpu_hwmon():
    for entry in glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*"):
        try:
            if (Path(entry) / "name").read_text().strip() == "amdgpu":
                return Path(entry)
        except OSError:
            pass
    return None


def find_gpu_busy():
    for path in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
        if Path(path).exists():
            return Path(path)
    return None


def parse_color(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def interpolate(a, b, amount):
    amount = max(0.0, min(1.0, amount))
    return tuple(round(x + (y - x) * amount) for x, y in zip(a, b))


def gradient(value, low, middle, high, teal, orange, red):
    if value <= low:
        return teal
    if value < middle:
        return interpolate(teal, orange, (value - low) / (middle - low))
    if value < high:
        return interpolate(orange, red, (value - middle) / (high - middle))
    return red


def scale_color(color, brightness):
    brightness = max(0.0, min(1.0, brightness))
    return tuple(round(channel * brightness) for channel in color)


def fan_brightness(value, low, middle, high, idle, orange, maximum):
    if value <= low:
        return idle
    if value < middle:
        amount = (value - low) / (middle - low)
        return idle + (orange - idle) * amount
    if value < high:
        amount = (value - middle) / (high - middle)
        return orange + (maximum - orange) * amount
    return maximum


class Telemetry:
    def __init__(self, gpu_power_max):
        self.cpu = find_hwmon("k10temp")
        self.gpu = find_gpu_hwmon()
        self.gpu_busy = find_gpu_busy()
        self.gpu_power_max = gpu_power_max
        psutil.cpu_percent(interval=None)

    def sample(self):
        cpu_temp = read_number(self.cpu / "temp1_input", 1000) if self.cpu else None
        gpu_temps = []
        if self.gpu:
            for path in self.gpu.glob("temp*_input"):
                value = read_number(path, 1000)
                if value is not None and 0 < value < 130:
                    gpu_temps.append(value)
        temperatures = [v for v in [cpu_temp, *gpu_temps] if v is not None]
        temperature = max(temperatures) if temperatures else None

        cpu_load = psutil.cpu_percent(interval=None) / 100.0
        gpu_load = None
        gpu_power = None
        if self.gpu:
            gpu_load_raw = read_number(self.gpu_busy) if self.gpu_busy else None
            gpu_load = gpu_load_raw / 100.0 if gpu_load_raw is not None else None
            gpu_power_watts = read_number(self.gpu / "power1_average", 1_000_000)
            if gpu_power_watts is not None:
                gpu_power = gpu_power_watts / self.gpu_power_max
        gpu_loads = [v for v in [gpu_load, gpu_power] if v is not None]
        gpu_workload = max(gpu_loads) if gpu_loads else None
        loads = [v for v in [cpu_load, gpu_workload] if v is not None]
        workload = max(loads) if loads else None
        return temperature, workload, cpu_load, gpu_workload


class Lighting:
    def __init__(self, cfg):
        ocfg = cfg["openrgb"]
        self.client = OpenRGBClient(ocfg["host"], ocfg["port"], name="Aeris telemetry")
        self.motherboard = next(
            device for device in self.client.devices
            if ocfg["motherboard_contains"].lower() in device.name.lower()
        )
        self.workload_zone = next(z for z in self.motherboard.zones if z.name == ocfg["workload_zone"])
        self.temperature_zone = next(z for z in self.motherboard.zones if z.name == ocfg["temperature_zone"])
        cpu_wanted = [name.lower() for name in ocfg["cpu_devices"]]
        gpu_wanted = [name.lower() for name in ocfg["gpu_devices"]]
        self.cpu_devices = [
            device for device in self.client.devices
            if any(name in device.name.lower() for name in cpu_wanted)
        ]
        self.gpu_devices = [
            device for device in self.client.devices
            if any(name in device.name.lower() for name in gpu_wanted)
        ]
        if len(self.cpu_devices) < 4 or len(self.gpu_devices) < 1:
            raise RuntimeError(
                "incomplete OpenRGB discovery: expected 4 ENE DRAM and 1 GPU, "
                f"found {len(self.cpu_devices)} DRAM and {len(self.gpu_devices)} GPU"
            )
        self.accents = self.cpu_devices + self.gpu_devices
        self.motherboard.set_mode("Direct")
        for device in self.accents:
            device.set_mode("Direct")
            time.sleep(0.1)
        LOG.info(
            "Mapped workload=%s, temperature=%s, CPU devices=%s, GPU devices=%s",
            self.workload_zone.name,
            self.temperature_zone.name,
            ", ".join(d.name for d in self.cpu_devices),
            ", ".join(d.name for d in self.gpu_devices),
        )

    def apply(self, workload, temperature, cpu, gpu):
        load_rgb = RGBColor(*workload)
        temp_rgb = RGBColor(*temperature)
        cpu_rgb = RGBColor(*cpu)
        gpu_rgb = RGBColor(*gpu)
        frame = []
        for zone in self.motherboard.zones:
            color = load_rgb if zone.name == self.workload_zone.name else temp_rgb
            frame.extend([color] * len(zone.leds))
        self.motherboard.set_colors(frame, fast=True)
        for device in self.cpu_devices:
            device.set_color(cpu_rgb, fast=True)
        for device in self.gpu_devices:
            device.set_color(gpu_rgb, fast=True)


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    cfg = yaml.safe_load(CONFIG.read_text())
    teal = parse_color(cfg["palette"]["teal"])
    orange = parse_color(cfg["palette"]["orange"])
    red = parse_color(cfg["palette"]["red"])
    device_palettes = cfg.get("device_palettes", {})

    def hardware_palette(name):
        overrides = device_palettes.get(name, {})
        return (
            parse_color(overrides.get("teal", cfg["palette"]["teal"])),
            parse_color(overrides.get("orange", cfg["palette"]["orange"])),
            parse_color(overrides.get("red", cfg["palette"]["red"])),
        )

    fan_palette = hardware_palette("fans")
    chain_palette = hardware_palette("workload_chain")
    ram_palette = hardware_palette("ram")
    gpu_palette = hardware_palette("gpu")
    ram_idle = parse_color(device_palettes.get("ram", {}).get("idle", "000000"))
    alpha = float(cfg["smoothing_alpha"])
    poll = float(cfg["poll_seconds"])
    telemetry = Telemetry(float(cfg["workload"]["gpu_power_watts_max"]))
    smooth_temp = None
    smooth_load = None
    smooth_cpu = None
    smooth_gpu = None
    lighting = None
    retry_at = 0.0

    while True:
        try:
            if lighting is None:
                if time.monotonic() < retry_at:
                    time.sleep(poll)
                    continue
                lighting = Lighting(cfg)
                lighting.apply(chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0])

            temperature, workload, cpu_workload, gpu_workload = telemetry.sample()
            if temperature is None or workload is None or gpu_workload is None:
                lighting.apply(chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0])
                time.sleep(poll)
                continue

            smooth_temp = temperature if smooth_temp is None else smooth_temp * (1 - alpha) + temperature * alpha
            smooth_load = workload if smooth_load is None else smooth_load * (1 - alpha) + workload * alpha
            smooth_cpu = cpu_workload if smooth_cpu is None else smooth_cpu * (1 - alpha) + cpu_workload * alpha
            smooth_gpu = gpu_workload if smooth_gpu is None else smooth_gpu * (1 - alpha) + gpu_workload * alpha
            tcfg = cfg["temperature"]
            wcfg = cfg["workload"]
            temp_color = gradient(smooth_temp, tcfg["cool_c"], tcfg["orange_c"], tcfg["hot_c"], *fan_palette)
            load_color = gradient(smooth_load, wcfg["idle"], wcfg["orange"], wcfg["maximum"], *chain_palette)
            cpu_color = gradient(
                smooth_cpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                ram_idle, ram_palette[1], ram_palette[2],
            )
            gpu_color = gradient(smooth_gpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"], *gpu_palette)
            bcfg = cfg["fan_brightness"]
            brightness = fan_brightness(
                smooth_load, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                bcfg["idle"], bcfg["orange"], bcfg["maximum"],
            )
            temp_color = scale_color(temp_color, brightness)
            lighting.apply(load_color, temp_color, cpu_color, gpu_color)
        except Exception as exc:
            LOG.warning("OpenRGB update failed; reconnecting: %s", exc)
            lighting = None
            retry_at = time.monotonic() + 5.0
        time.sleep(poll)


if __name__ == "__main__":
    main()
