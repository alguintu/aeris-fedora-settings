#!/usr/bin/env python3
import colorsys
import glob
import json
import logging
import math
import os
import signal
import socket
import stat
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


def rainbow_frame(count, now, period_seconds, spatial_cycles, brightness, phase_offset=0.0):
    frame = []
    for index in range(count):
        position = index / max(1, count)
        hue = (position * spatial_cycles - now / period_seconds + phase_offset) % 1.0
        red, green, blue = colorsys.hsv_to_rgb(hue, 1.0, brightness)
        frame.append((round(red * 255), round(green * 255), round(blue * 255)))
    return frame


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


class RuntimeModeController:
    MODES = ("work", "night", "day", "off", "party")

    def __init__(self, path, default_mode):
        if default_mode not in self.MODES:
            raise RuntimeError(f"invalid default lighting mode: {default_mode!r}")
        self.path = Path(path)
        self.mode = default_mode
        self.thermal_override = False
        self.listener = None
        self._open()

    def _open(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.exists() or self.path.is_socket():
            mode = self.path.lstat().st_mode
            if not stat.S_ISSOCK(mode):
                raise RuntimeError(f"refusing non-socket control path: {self.path}")
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                probe.settimeout(0.2)
                probe.connect(str(self.path))
            except OSError:
                self.path.unlink()
            else:
                raise RuntimeError(f"another Aeris lighting controller owns {self.path}")
            finally:
                probe.close()

        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(self.path))
        os.chmod(self.path, 0o600)
        self.listener.listen(4)
        self.listener.setblocking(False)

    def status(self):
        return {
            "ok": True,
            "mode": self.mode,
            "modes": list(self.MODES),
            "thermalOverride": self.thermal_override,
        }

    def _handle(self, request):
        command = request.get("command")
        if command == "status":
            return self.status(), False
        if command != "set":
            return {"ok": False, "error": "unknown command"}, False
        mode = request.get("mode")
        if mode not in self.MODES:
            return {"ok": False, "error": f"invalid mode: {mode!r}"}, False
        changed = mode != self.mode
        self.mode = mode
        return self.status(), changed

    def poll(self):
        changed = False
        while True:
            try:
                connection, _ = self.listener.accept()
            except BlockingIOError:
                break
            with connection:
                connection.settimeout(0.2)
                try:
                    payload = connection.recv(4096)
                    request = json.loads(payload.decode("utf-8"))
                    response, request_changed = self._handle(request)
                    changed = changed or request_changed
                except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                    response = {"ok": False, "error": str(exc)}
                try:
                    connection.sendall((json.dumps(response) + "\n").encode("utf-8"))
                except OSError:
                    pass
        return changed

    def close(self):
        if self.listener is not None:
            self.listener.close()
            self.listener = None
        try:
            if self.path.is_socket():
                self.path.unlink()
        except OSError:
            pass


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
        self.last_cpu_frame = None
        self.last_gpu_frame = None

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

    def invalidate_cache(self):
        self.last_motherboard_frame = None
        self.last_cpu_color = None
        self.last_gpu_color = None
        self.last_cpu_frame = None
        self.last_gpu_frame = None

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

    def apply_motherboard_zones(self, workload, fans):
        if len(workload) != len(self.workload_zone.leds):
            raise RuntimeError("workload-zone frame length changed")
        if len(fans) != len(self.fan_zone.leds):
            raise RuntimeError("fan-zone frame length changed")
        load_rgb = [RGBColor(*color) for color in workload]
        fan_rgb = [RGBColor(*mask_jrainbow2_color(color)) for color in fans]
        frame = []
        for zone in self.motherboard.zones:
            if zone.name == self.workload_zone.name:
                zone_frame = load_rgb
            elif zone.name == self.fan_zone.name:
                zone_frame = fan_rgb
            else:
                zone_frame = [RGBColor(0, 0, 0)] * len(zone.leds)
            frame.extend(zone_frame)
        frame_key = tuple((color.red, color.green, color.blue) for color in frame)
        if frame_key == self.last_motherboard_frame:
            return
        self.motherboard.set_colors(frame, fast=True)
        self.last_motherboard_frame = frame_key

    def apply_motherboard(self, workload, fans):
        self.apply_motherboard_zones(
            [workload] * len(self.workload_zone.leds),
            [fans] * len(self.fan_zone.leds),
        )

    def apply_cpu(self, cpu):
        if cpu == self.last_cpu_color:
            return
        cpu_rgb = RGBColor(*cpu)
        for device in self.cpu_devices:
            device.set_color(cpu_rgb, fast=True)
        self.last_cpu_color = cpu
        self.last_cpu_frame = None

    def apply_gpu(self, gpu):
        if gpu == self.last_gpu_color:
            return
        gpu_rgb = RGBColor(*gpu)
        for device in self.gpu_devices:
            device.set_color(gpu_rgb, fast=True)
        self.last_gpu_color = gpu
        self.last_gpu_frame = None

    @staticmethod
    def _device_frame_key(frames):
        return tuple(tuple(frame) for frame in frames)

    def apply_cpu_frames(self, frames):
        frame_key = self._device_frame_key(frames)
        if frame_key == self.last_cpu_frame:
            return
        for device, frame in zip(self.cpu_devices, frames):
            device.set_colors([RGBColor(*color) for color in frame], fast=True)
        self.last_cpu_frame = frame_key
        self.last_cpu_color = None

    def apply_gpu_frames(self, frames):
        frame_key = self._device_frame_key(frames)
        if frame_key == self.last_gpu_frame:
            return
        for device, frame in zip(self.gpu_devices, frames):
            device.set_colors([RGBColor(*color) for color in frame], fast=True)
        self.last_gpu_frame = frame_key
        self.last_gpu_color = None

    def apply_party_motherboard(self, now, cfg):
        workload = rainbow_frame(
            len(self.workload_zone.leds), now, cfg["period_seconds"],
            cfg["spatial_cycles"], cfg["brightness"],
        )
        fans = rainbow_frame(
            len(self.fan_zone.leds), now, cfg["period_seconds"],
            cfg["spatial_cycles"], cfg["brightness"], cfg["fan_phase_offset"],
        )
        self.apply_motherboard_zones(workload, fans)

    def apply_party_accents(self, now, cfg):
        cpu_frames = []
        for index, device in enumerate(self.cpu_devices):
            cpu_frames.append(rainbow_frame(
                len(device.leds), now, cfg["period_seconds"],
                cfg["accent_spatial_cycles"], cfg["brightness"],
                index * cfg["dimm_phase_offset"],
            ))
        gpu_frames = []
        for device in self.gpu_devices:
            gpu_frames.append(rainbow_frame(
                len(device.leds), now, cfg["period_seconds"],
                cfg["accent_spatial_cycles"], cfg["brightness"],
                cfg["gpu_phase_offset"],
            ))
        self.apply_cpu_frames(cpu_frames)
        self.apply_gpu_frames(gpu_frames)

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
    black = (0, 0, 0)
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
    mode_cfg = cfg["runtime_modes"]
    party_cfg = mode_cfg["party"]
    telemetry = Telemetry(float(cfg["workload"]["gpu_power_watts_max"]))
    override_cfg = cfg["temperature_override"]
    thermal_override = ThermalOverride(
        float(override_cfg["cpu_enter_c"]),
        float(override_cfg["cpu_exit_c"]),
        float(override_cfg["gpu_enter_c"]),
        float(override_cfg["gpu_exit_c"]),
        float(override_cfg["dwell_seconds"]),
    )
    night_brightness = mode_cfg["night_brightness"]
    night_colors = (
        scale_color(chain_palette[1], float(night_brightness["workload_chain"])),
        scale_color(fan_palette[1], float(night_brightness["fans"])),
        scale_color(ram_palette[1], float(night_brightness["ram"])),
        scale_color(gpu_palette[1], float(night_brightness["gpu"])),
    )
    day_cfg = mode_cfg["day"]
    day_color = scale_color(
        parse_color(day_cfg["color"]),
        float(day_cfg["brightness"]),
    )
    day_colors = (day_color, day_color, day_color, day_color)
    work_colors = [chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0]]
    smooth_cpu_temp = None
    smooth_gpu_temp = None
    smooth_cpu = 0.0
    smooth_gpu = 0.0
    smooth_load = 0.0
    stop_requested = False
    last_loop_at = None
    next_telemetry_at = 0.0
    next_accent_render_at = 0.0
    max_loop_gap = float(cfg["safety"]["max_loop_gap_seconds"])
    render_interval = min(
        float(pulse_cfg["motherboard_render_interval_seconds"]),
        float(party_cfg["motherboard_render_interval_seconds"]),
    )
    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    control_path = runtime_dir / mode_cfg["socket_name"]
    controller = None

    def request_stop(_signum, _frame):
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    try:
        lighting = Lighting(cfg)
        controller = RuntimeModeController(control_path, mode_cfg["default"])
        LOG.info("Runtime lighting control ready at %s (mode=%s)", control_path, controller.mode)
        lighting.apply(*work_colors)

        while not stop_requested:
            loop_at = time.monotonic()
            if last_loop_at is not None and loop_at - last_loop_at > max_loop_gap:
                raise RuntimeError(
                    f"event loop paused for {loop_at - last_loop_at:.1f}s; "
                    "possible suspend/resume, refusing the old hardware connection"
                )
            last_loop_at = loop_at

            if controller.poll():
                lighting.invalidate_cache()
                next_accent_render_at = 0.0
                LOG.info("Runtime lighting mode changed to %s", controller.mode)

            if loop_at >= next_telemetry_at:
                cpu_temp, gpu_temp, workload, cpu_workload, gpu_workload = telemetry.sample()
                next_telemetry_at = loop_at + poll
                if cpu_temp is not None:
                    smooth_cpu_temp = (
                        cpu_temp if smooth_cpu_temp is None
                        else smooth_cpu_temp * (1 - alpha) + cpu_temp * alpha
                    )
                if gpu_temp is not None:
                    smooth_gpu_temp = (
                        gpu_temp if smooth_gpu_temp is None
                        else smooth_gpu_temp * (1 - alpha) + gpu_temp * alpha
                    )

                override_was_active = thermal_override.active
                temperature_override = thermal_override.update(smooth_cpu_temp, smooth_gpu_temp)
                controller.thermal_override = temperature_override
                if temperature_override and not override_was_active:
                    LOG.warning(
                        "Temperature override entered: CPU=%s GPU=%s",
                        smooth_cpu_temp, smooth_gpu_temp,
                    )
                elif override_was_active and not temperature_override:
                    LOG.info(
                        "Temperature override cleared: CPU=%s GPU=%s",
                        smooth_cpu_temp, smooth_gpu_temp,
                    )

                if workload is None or gpu_workload is None:
                    smooth_cpu = 0.0
                    smooth_gpu = 0.0
                    smooth_load = 0.0
                    work_colors = [chain_palette[0], fan_palette[0], ram_idle, gpu_palette[0]]
                else:
                    smooth_cpu = cpu_envelope.update(cpu_workload, loop_at)
                    smooth_gpu = gpu_envelope.update(gpu_workload, loop_at)
                    smooth_load = max(smooth_cpu, smooth_gpu)
                    wcfg = cfg["workload"]
                    bcfg = cfg["fan_brightness"]
                    load_color = gradient(
                        smooth_load, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                        *chain_palette,
                    )
                    fan_color = fan_workload_color(
                        smooth_load, wcfg["idle"], wcfg["orange"], bcfg["off_workload"],
                        fan_palette, bcfg,
                    )
                    cpu_color = gradient(
                        smooth_cpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                        ram_idle, ram_palette[1], ram_palette[2],
                    )
                    gpu_color = gradient(
                        smooth_gpu, wcfg["idle"], wcfg["orange"], wcfg["maximum"],
                        *gpu_palette,
                    )
                    gpu_color = scale_color(
                        gpu_color,
                        subordinate_brightness(
                            smooth_cpu, smooth_gpu, wcfg["idle"], wcfg["orange"],
                        ),
                    )
                    work_colors = [load_color, fan_color, cpu_color, gpu_color]

            if thermal_override.active:
                lighting.apply(chain_palette[2], fan_palette[2], ram_palette[2], gpu_palette[2])
            elif controller.mode == "work":
                if smooth_load > pulse_cfg["start_workload"]:
                    lighting.apply_motherboard(
                        high_load_pulse_color(work_colors[0], smooth_load, loop_at, pulse_cfg),
                        work_colors[1],
                    )
                    if loop_at >= next_accent_render_at:
                        lighting.apply_cpu(
                            high_load_pulse_color(work_colors[2], smooth_cpu, loop_at, pulse_cfg)
                        )
                        lighting.apply_gpu(
                            high_load_pulse_color(work_colors[3], smooth_gpu, loop_at, pulse_cfg)
                        )
                        next_accent_render_at = (
                            loop_at + float(pulse_cfg["accent_render_interval_seconds"])
                        )
                else:
                    lighting.apply(*work_colors)
            elif controller.mode == "night":
                lighting.apply(*night_colors)
            elif controller.mode == "day":
                lighting.apply(*day_colors)
            elif controller.mode == "off":
                lighting.apply(black, black, black, black)
            elif controller.mode == "party":
                lighting.apply_party_motherboard(loop_at, party_cfg)
                if loop_at >= next_accent_render_at:
                    lighting.apply_party_accents(loop_at, party_cfg)
                    next_accent_render_at = (
                        loop_at + float(party_cfg["accent_render_interval_seconds"])
                    )
            else:
                raise RuntimeError(f"unexpected runtime mode: {controller.mode!r}")

            elapsed = time.monotonic() - loop_at
            time.sleep(max(0.0, render_interval - elapsed))
    except Exception as exc:
        LOG.error("OpenRGB safety stop; no reconnect will be attempted: %s", exc)
        return 1
    finally:
        if controller is not None:
            controller.close()

    LOG.info("Stopping without changing controller modes or persistent state")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
