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


def fan_workload_color(value, low, middle, high, palette, brightness):
    black = (0, 0, 0)
    teal = scale_color(palette[0], brightness["idle"])
    orange = scale_color(palette[1], brightness["orange"])
    red = scale_color(palette[2], brightness["maximum"])
    if value <= low:
        return teal
    if value < middle:
        amount = (value - low) / (middle - low)
        if amount <= 0.5:
            return interpolate(teal, black, amount * 2)
        return interpolate(black, orange, (amount - 0.5) * 2)
    if value < high:
        return interpolate(orange, red, (value - middle) / (high - middle))
    return red


def subordinate_brightness(primary, own, low, middle):
    own_progress = max(0.0, min(1.0, (own - low) / (middle - low)))
    return_start = low + (middle - low) * 0.5
    return_progress = max(0.0, min(1.0, (return_start - primary) / (return_start - low)))
    idle_visibility = return_progress ** 2
    return idle_visibility + (1.0 - idle_visibility) * own_progress


class LoadEnvelope:
    def __init__(self, attack_alpha, release_alpha, hold_seconds):
        self.attack_alpha = attack_alpha
        self.release_alpha = release_alpha
        self.hold_seconds = hold_seconds
        self.value = None
        self.hold_until = 0.0

    def update(self, sample, now=None):
        now = time.monotonic() if now is None else now
        if self.value is None:
            self.value = sample
        elif sample >= self.value:
            self.value += (sample - self.value) * self.attack_alpha
            self.hold_until = now + self.hold_seconds
        elif now >= self.hold_until:
            self.value += (sample - self.value) * self.release_alpha
        return self.value


class ThermalOverride:
    def __init__(self, cpu_enter, cpu_exit, gpu_enter, gpu_exit, dwell_seconds):
        self.cpu_enter = cpu_enter
        self.cpu_exit = cpu_exit
        self.gpu_enter = gpu_enter
        self.gpu_exit = gpu_exit
        self.dwell_seconds = dwell_seconds
        self.pending_since = None
        self.active = False

    def update(self, cpu_temp, gpu_temp, now=None):
        now = time.monotonic() if now is None else now
        if self.active:
            cpu_clear = cpu_temp is None or cpu_temp < self.cpu_exit
            gpu_clear = gpu_temp is None or gpu_temp < self.gpu_exit
            if cpu_clear and gpu_clear:
                self.active = False
            return self.active

        triggered = (
            (cpu_temp is not None and cpu_temp >= self.cpu_enter)
            or (gpu_temp is not None and gpu_temp >= self.gpu_enter)
        )
        if not triggered:
            self.pending_since = None
        elif self.pending_since is None:
            self.pending_since = now
        elif now - self.pending_since >= self.dwell_seconds:
            self.active = True
            self.pending_since = None
        return self.active


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
        gpu_temp = max(gpu_temps) if gpu_temps else None

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
        return cpu_temp, gpu_temp, workload, cpu_load, gpu_workload


class Lighting:
    def __init__(self, cfg):
        ocfg = cfg["openrgb"]
        self.client = OpenRGBClient(ocfg["host"], ocfg["port"], name="Aeris telemetry")
        self.motherboard = next(
            device for device in self.client.devices
            if ocfg["motherboard_contains"].lower() in device.name.lower()
        )
        self.workload_zone = next(z for z in self.motherboard.zones if z.name == ocfg["workload_zone"])
        self.fan_zone = next(z for z in self.motherboard.zones if z.name == ocfg["fan_zone"])
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
            "Mapped workload=%s, fans=%s, CPU devices=%s, GPU devices=%s",
            self.workload_zone.name,
            self.fan_zone.name,
            ", ".join(d.name for d in self.cpu_devices),
            ", ".join(d.name for d in self.gpu_devices),
        )

    def apply(self, workload, fans, cpu, gpu):
        load_rgb = RGBColor(*workload)
        fan_rgb = RGBColor(*fans)
        cpu_rgb = RGBColor(*cpu)
        gpu_rgb = RGBColor(*gpu)
        frame = []
        for zone in self.motherboard.zones:
            if zone.name == self.workload_zone.name:
                color = load_rgb
            elif zone.name == self.fan_zone.name:
                color = fan_rgb
            else:
                color = RGBColor(0, 0, 0)
            frame.extend([color] * len(zone.leds))
        self.motherboard.set_colors(frame, fast=True)
        for device in self.cpu_devices:
            device.set_color(cpu_rgb, fast=True)
        for device in self.gpu_devices:
            device.set_color(gpu_rgb, fast=True)


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    cfg = yaml.safe_load(CONFIG.read_text())
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
    workload_smoothing = cfg["workload_smoothing"]
    cpu_envelope = LoadEnvelope(
        float(workload_smoothing["attack_alpha"]),
        float(workload_smoothing["release_alpha"]),
        float(workload_smoothing["hold_seconds"]),
    )
    gpu_envelope = LoadEnvelope(
        float(workload_smoothing["attack_alpha"]),
        float(workload_smoothing["release_alpha"]),
        float(workload_smoothing["hold_seconds"]),
    )
    poll = float(cfg["poll_seconds"])
    telemetry = Telemetry(float(cfg["workload"]["gpu_power_watts_max"]))
    override_cfg = cfg["temperature_override"]
    thermal_override = ThermalOverride(
        float(override_cfg["cpu_enter_c"]),
        float(override_cfg["cpu_exit_c"]),
        float(override_cfg["gpu_enter_c"]),
        float(override_cfg["gpu_exit_c"]),
        float(override_cfg["dwell_seconds"]),
    )
    smooth_cpu_temp = None
    smooth_gpu_temp = None
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

            cpu_temp, gpu_temp, workload, cpu_workload, gpu_workload = telemetry.sample()
            if workload is None or gpu_workload is None:
                lighting.apply(chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0])
                time.sleep(poll)
                continue

            if cpu_temp is not None:
                smooth_cpu_temp = cpu_temp if smooth_cpu_temp is None else smooth_cpu_temp * (1 - alpha) + cpu_temp * alpha
            if gpu_temp is not None:
                smooth_gpu_temp = gpu_temp if smooth_gpu_temp is None else smooth_gpu_temp * (1 - alpha) + gpu_temp * alpha
            smooth_cpu = cpu_envelope.update(cpu_workload)
            smooth_gpu = gpu_envelope.update(gpu_workload)
            smooth_load = max(smooth_cpu, smooth_gpu)
            wcfg = cfg["workload"]
            override_was_active = thermal_override.active
            temperature_override = thermal_override.update(smooth_cpu_temp, smooth_gpu_temp)
            if temperature_override and not override_was_active:
                LOG.warning("Temperature override entered: CPU=%s GPU=%s", smooth_cpu_temp, smooth_gpu_temp)
            elif override_was_active and not temperature_override:
                LOG.info("Temperature override cleared: CPU=%s GPU=%s", smooth_cpu_temp, smooth_gpu_temp)

            load_color = gradient(smooth_load, wcfg["idle"], wcfg["orange"], wcfg["maximum"], *chain_palette)
            bcfg = cfg["fan_brightness"]
            fan_color = fan_workload_color(
                smooth_load, wcfg["idle"], wcfg["orange"], bcfg["off_workload"],
                fan_palette, bcfg,
            )
            cpu_color = gradient(
                smooth_cpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                ram_idle, ram_palette[1], ram_palette[2],
            )
            gpu_color = gradient(smooth_gpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"], *gpu_palette)
            gpu_color = scale_color(
                gpu_color,
                subordinate_brightness(smooth_cpu, smooth_gpu, wcfg["idle"], wcfg["orange"]),
            )
            if temperature_override:
                lighting.apply(chain_palette[2], fan_palette[2], ram_palette[2], gpu_palette[2])
            else:
                lighting.apply(load_color, fan_color, cpu_color, gpu_color)
        except Exception as exc:
            LOG.warning("OpenRGB update failed; reconnecting: %s", exc)
            lighting = None
            retry_at = time.monotonic() + 5.0
        time.sleep(poll)


if __name__ == "__main__":
    main()
