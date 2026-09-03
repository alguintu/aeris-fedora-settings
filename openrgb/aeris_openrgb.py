#!/usr/bin/env python3
import glob
import logging
import math
import signal
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


def mask_jrainbow2_color(color):
    """Clear JRAINBOW2's two control-flag bits from each color channel."""
    return tuple(channel & 0xFC for channel in color)


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


def high_load_pulse_color(color, workload, now, cfg):
    start = cfg["start_workload"]
    full = cfg["full_depth_workload"]
    strength = max(0.0, min(1.0, (workload - start) / (full - start)))
    wave = (1.0 - math.cos(2.0 * math.pi * now / cfg["period_seconds"])) / 2.0
    brightness = 1.0 - strength * (1.0 - cfg["minimum_brightness"]) * wave
    return scale_color(color, brightness)


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
        if len(self.client.devices) != int(ocfg["expected_device_count"]):
            raise RuntimeError(
                "unexpected OpenRGB inventory: expected "
                f"{ocfg['expected_device_count']} devices, found {len(self.client.devices)}"
            )

        motherboards = [
            device for device in self.client.devices
            if device.name == ocfg["motherboard_name"]
        ]
        if len(motherboards) != 1:
            raise RuntimeError(
                f"expected exactly one {ocfg['motherboard_name']!r}, found {len(motherboards)}"
            )
        self.motherboard = motherboards[0]
        motherboard_serial = self.motherboard.metadata.serial
        if motherboard_serial != ocfg["motherboard_serial"]:
            raise RuntimeError(
                "motherboard serial mismatch: expected "
                f"{ocfg['motherboard_serial']!r}, found {motherboard_serial!r}"
            )

        zones = {zone.name: zone for zone in self.motherboard.zones}
        expected_zones = ocfg["expected_zones"]
        if set(zones) != set(expected_zones):
            raise RuntimeError(
                f"motherboard zone mismatch: expected {sorted(expected_zones)}, found {sorted(zones)}"
            )
        for name, expected_leds in expected_zones.items():
            if len(zones[name].leds) != int(expected_leds):
                raise RuntimeError(
                    f"zone {name!r} LED mismatch: expected {expected_leds}, "
                    f"found {len(zones[name].leds)}"
                )
        self.workload_zone = zones[ocfg["workload_zone"]]
        self.fan_zone = zones[ocfg["fan_zone"]]

        cpu_wanted = set(ocfg["cpu_devices"])
        gpu_wanted = set(ocfg["gpu_devices"])
        self.cpu_devices = [
            device for device in self.client.devices
            if device.name in cpu_wanted
        ]
        self.gpu_devices = [
            device for device in self.client.devices
            if device.name in gpu_wanted
        ]
        cpu_count_ok = len(self.cpu_devices) == int(ocfg["expected_cpu_devices"])
        gpu_count_ok = len(self.gpu_devices) == int(ocfg["expected_gpu_devices"])
        if not cpu_count_ok or not gpu_count_ok:
            raise RuntimeError(
                "incomplete OpenRGB discovery: expected 4 ENE DRAM and 1 GPU, "
                f"found {len(self.cpu_devices)} DRAM and {len(self.gpu_devices)} GPU"
            )
        self.accents = self.cpu_devices + self.gpu_devices
        self.last_motherboard_frame = None
        self.last_cpu_color = None
        self.last_gpu_color = None

        self._ensure_direct(self.motherboard)
        for device in self.accents:
            self._ensure_direct(device)
            time.sleep(0.1)
        LOG.info(
            "Mapped workload=%s, fans=%s, CPU devices=%s, GPU devices=%s",
            self.workload_zone.name,
            self.fan_zone.name,
            ", ".join(d.name for d in self.cpu_devices),
            ", ".join(d.name for d in self.gpu_devices),
        )

    @staticmethod
    def _ensure_direct(device):
        active_mode = device.modes[device.active_mode]
        if active_mode.name.lower() != "direct":
            device.set_mode("Direct", save=False)
            active_mode = device.modes[device.active_mode]
        if active_mode.name.lower() != "direct":
            raise RuntimeError(
                f"device {device.name!r} did not enter Direct mode; refusing color writes"
            )

    def apply_motherboard(self, workload, fans):
        load_rgb = RGBColor(*workload)
        fan_rgb = RGBColor(*mask_jrainbow2_color(fans))
        frame = []
        for zone in self.motherboard.zones:
            if zone.name == self.workload_zone.name:
                color = load_rgb
            elif zone.name == self.fan_zone.name:
                color = fan_rgb
            else:
                color = RGBColor(0, 0, 0)
            frame.extend([color] * len(zone.leds))
        frame_key = tuple((color.red, color.green, color.blue) for color in frame)
        if frame_key == self.last_motherboard_frame:
            return
        self.motherboard.set_colors(frame, fast=True)
        self.last_motherboard_frame = frame_key

    def apply_cpu(self, cpu):
        if cpu == self.last_cpu_color:
            return
        cpu_rgb = RGBColor(*cpu)
        for device in self.cpu_devices:
            device.set_color(cpu_rgb, fast=True)
        self.last_cpu_color = cpu

    def apply_gpu(self, gpu):
        if gpu == self.last_gpu_color:
            return
        gpu_rgb = RGBColor(*gpu)
        for device in self.gpu_devices:
            device.set_color(gpu_rgb, fast=True)
        self.last_gpu_color = gpu

    def apply_accents(self, cpu, gpu):
        self.apply_cpu(cpu)
        self.apply_gpu(gpu)

    def apply(self, workload, fans, cpu, gpu):
        self.apply_motherboard(workload, fans)
        self.apply_accents(cpu, gpu)

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
    pulse_cfg = cfg["high_load_pulse"]
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
    stop_requested = False
    last_loop_at = None
    max_loop_gap = float(cfg["safety"]["max_loop_gap_seconds"])

    def request_stop(_signum, _frame):
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    try:
        lighting = Lighting(cfg)
        lighting.apply(chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0])

        while not stop_requested:
            loop_at = time.monotonic()
            if last_loop_at is not None and loop_at - last_loop_at > max_loop_gap:
                raise RuntimeError(
                    f"event loop paused for {loop_at - last_loop_at:.1f}s; "
                    "possible suspend/resume, refusing the old hardware connection"
                )
            last_loop_at = loop_at
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
                time.sleep(poll)
            else:
                now = time.monotonic()
                pulsed_load_color = high_load_pulse_color(load_color, smooth_load, now, pulse_cfg)
                pulsed_cpu_color = high_load_pulse_color(cpu_color, smooth_cpu, now, pulse_cfg)
                pulsed_gpu_color = high_load_pulse_color(gpu_color, smooth_gpu, now, pulse_cfg)
                lighting.apply(pulsed_load_color, fan_color, pulsed_cpu_color, pulsed_gpu_color)
                if smooth_load <= pulse_cfg["start_workload"]:
                    time.sleep(poll)
                else:
                    render_until = time.monotonic() + poll
                    next_accent_render = now + pulse_cfg["accent_render_interval_seconds"]
                    while not stop_requested:
                        remaining = render_until - time.monotonic()
                        if remaining <= 0:
                            break
                        time.sleep(min(pulse_cfg["motherboard_render_interval_seconds"], remaining))
                        now = time.monotonic()
                        pulsed_load_color = high_load_pulse_color(
                            load_color, smooth_load, now, pulse_cfg,
                        )
                        lighting.apply_motherboard(pulsed_load_color, fan_color)
                        if now >= next_accent_render:
                            if smooth_cpu > pulse_cfg["start_workload"]:
                                lighting.apply_cpu(high_load_pulse_color(cpu_color, smooth_cpu, now, pulse_cfg))
                            if smooth_gpu > pulse_cfg["start_workload"]:
                                lighting.apply_gpu(high_load_pulse_color(gpu_color, smooth_gpu, now, pulse_cfg))
                            next_accent_render = now + pulse_cfg["accent_render_interval_seconds"]
    except Exception as exc:
        LOG.error("OpenRGB safety stop; no reconnect will be attempted: %s", exc)
        return 1

    LOG.info("Stopping without changing controller modes or persistent state")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
