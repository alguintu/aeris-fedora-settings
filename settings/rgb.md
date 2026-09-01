# Aeris OpenRGB lighting

## Components

- Fedora packages: `openrgb` and `openrgb-udev-rules`
- Python 3 virtual environment: `~/.local/share/aeris-openrgb/venv`
- Controller: MSI MAG B550M MORTAR WIFI, serial `A02020051203`
- SDK endpoint: `127.0.0.1:6742`
- Poll interval: 1 second
- Exponential smoothing alpha: 0.20

The pinned Python dependencies are listed in `openrgb/requirements.txt`. The
virtual environment and generated caches are deliberately excluded from Git.

## Logical mapping

| Device or zone | Signal |
|---|---|
| Motherboard `JRAINBOW1`, 75 LEDs | Maximum of CPU and GPU workload; pump, PSU, backplate, and accent chain |
| Motherboard `JRAINBOW2`, 75 LEDs | Hottest CPU `k10temp` or Radeon edge/junction/memory temperature; all fans |
| Four ENE DRAM devices (64 GB total) | CPU utilization |
| ASUS TUF Radeon RX 6900 XT Gaming OC | Maximum of GPU utilization and board power normalized to 272 W |

`JRGB1` is unused logically. OpenRGB Direct mode requires complete motherboard
frames, so the controller still receives a harmless filler color for its single
JRGB1 LED followed by 75 JRAINBOW1 and 75 JRAINBOW2 colors: 151 total.

The hardware-specific `openrgb/sizes.ors` profile activates both JRAINBOW zones
at 75 LEDs. Without it, OpenRGB initially reports zero LEDs for those zones.
Do not use this binary profile on different RGB hardware.

## Palette

| Anchor | Color | Temperature | Workload |
|---|---|---:|---:|
| Calm | Teal `#00C8C8` | ≤45 °C | ≤20% |
| Elevated | Orange `#FF8A00` | 65 °C | 60% |
| High | Red `#FF2A1A` | ≥85 °C | 100% |

Colors interpolate between anchors. CPU package power is not exposed on this
machine, so CPU lighting uses utilization. GPU lighting uses both utilization
and `power1_average`.

Fan hue continues to represent the hottest CPU/GPU temperature, while fan
brightness moves inversely with the combined CPU/GPU workload. The fans are at
100% brightness at or below 20% workload, dim smoothly to 35% brightness at
full workload, and brighten again as work returns to idle. This brightness
effect applies only to `JRAINBOW2`; the workload chain, DIMMs, and GPU retain
their normal brightness.

The controller, both DIMMs, and GPU are switched to **Direct** mode on every SDK
connection. Otherwise their hardware rainbow effects remain active. The process
starts calm teal, keeps one persistent SDK connection, reconnects after server or
controller resets, and falls back to teal when telemetry is unavailable.

At login, the SDK server waits for udev to settle and then delays hardware
discovery for 10 seconds. This prevents it from scanning before the AMD I2C/SMBus
devices are ready. The client rejects an incomplete discovery unless all four ENE
DRAM modules and the Radeon GPU are present, rather than silently leaving those
devices in their firmware rainbow mode.

## Install or synchronize

From the repository root:

```bash
./scripts/install-openrgb.sh
```

The installer:

1. Installs Fedora's OpenRGB package and udev rules.
2. Backs up existing Aeris files.
3. Builds the pinned Python virtual environment.
4. Deploys the application, YAML configuration, OpenRGB size profile, and user units.
5. Enables and restarts the main Aeris service; its required SDK server starts automatically.

Check an existing installation without modifying or restarting it:

```bash
./scripts/install-openrgb.sh --check
```

## Service management

```bash
systemctl --user status aeris-openrgb.service aeris-openrgb-server.service
systemctl --user restart aeris-openrgb.service
systemctl --user stop aeris-openrgb.service aeris-openrgb-server.service
systemctl --user enable --now aeris-openrgb.service
journalctl --user -u aeris-openrgb.service -u aeris-openrgb-server.service -f
```

Only `aeris-openrgb.service` is enabled. It declares `Requires=` and `After=` on
the SDK server, so systemd starts the server automatically.

## Validation history

A 30-second `stress-ng --cpu 16` run passed. CPU temperature peaked at 71.6 °C,
and the lighting visibly transitioned under load. This stress test is documented
rather than rerun automatically.

## Day-one tuning notes

The functional behavior is accepted for day one: CPU-specific DIMM lighting,
GPU-specific GPU lighting, the combined workload chain, temperature-driven fans,
and inverse fan brightness all reacted during separate one-minute CPU and GPU
tests without service errors.

Future visual tuning should address:

- The 35% full-workload fan brightness floor is still too bright for the intended
  dimming effect; test a substantially lower floor.
- Make workload and temperature transitions more dramatic while retaining smooth
  changes and avoiding flicker.
- Calibrate colors per hardware group. The motherboard backplate/PSU chain, fans,
  ENE DRAM, and ASUS GPU render identical RGB values differently because their
  LEDs, diffusers, and controllers come from different vendors.
- Build per-device corrected teal, orange, and red anchors instead of assuming one
  shared RGB triplet will visually match every component.

Do not change these values blindly. Tune them while observing the physical system
under controlled CPU and GPU loads, then record the calibrated values here and in
`openrgb/config.yaml`.
