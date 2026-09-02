# Aeris OpenRGB lighting

## Components

- Fedora packages: `openrgb` and `openrgb-udev-rules`
- Python 3 virtual environment: `~/.local/share/aeris-openrgb/venv`
- Controller: MSI MAG B550M MORTAR WIFI, serial `A02020051203`
- SDK endpoint: `127.0.0.1:6742`
- Poll interval: 1 second
- Temperature smoothing alpha: 0.20
- CPU and GPU workload envelopes: 0.30 attack, 4-second peak hold, 0.08 release

The pinned Python dependencies are listed in `openrgb/requirements.txt`. The
virtual environment and generated caches are deliberately excluded from Git.

## Logical mapping

| Device or zone | Signal |
|---|---|
| Motherboard `JRAINBOW1`, 75 LEDs | Maximum of CPU and GPU workload; pump, PSU, backplate, and accent chain |
| Motherboard `JRAINBOW2`, 75 LEDs | Maximum of CPU and GPU workload with inverse brightness; all fans |
| Four ENE DRAM devices (64 GB total) | CPU utilization |
| ASUS TUF Radeon RX 6900 XT Gaming OC | Maximum of GPU utilization and board power normalized to 272 W |

`JRGB1` is unused logically. OpenRGB Direct mode requires complete motherboard
frames, so the controller still receives a harmless filler color for its single
JRGB1 LED followed by 75 JRAINBOW1 and 75 JRAINBOW2 colors: 151 total.

The hardware-specific `openrgb/sizes.ors` profile activates both JRAINBOW zones
at 75 LEDs. Without it, OpenRGB initially reports zero LEDs for those zones.
Do not use this binary profile on different RGB hardware.

## Palette

| Anchor | Color | Workload |
|---|---|---:|
| Calm | Teal `#00C8C8` | ≤20% |
| Elevated | Orange `#FF8A00` | 60% |
| High | Red `#FF0000` | 100% |

The shared palette is a fallback. Hardware-specific palette overrides compensate
for differences between LED vendors and diffusers. Calibrated teal anchors are:

| Hardware group | Teal command | Orange command |
|---|---|---|
| Fans (`JRAINBOW2`) | `#008A54` | `#C03000` (visually confirmed) |
| Backplane/PSU/ambient (`JRAINBOW1`) | `#00C8C8` | `#FF6000` (visually confirmed) |
| ASUS GPU | `#00C8C8` | `#FF6000` (visually confirmed) |
| ENE DRAM | `#0060B0` (provisional; direct teal is unreliable) | `#FF8000` (visually confirmed) |

Pure red `#FF0000` is visually confirmed across all four hardware groups. The
previous `#FF2A1A` anchor did not read as red and must not be restored.

Colors interpolate between anchors. CPU package power is not exposed on this
machine, so CPU lighting uses utilization. GPU lighting uses both utilization
and `power1_average`.

CPU and GPU workloads each pass through the same asymmetric envelope before
driving lighting. Rising load uses a 0.30 attack factor, momentary drops are held
for four seconds, and sustained recovery uses a slower 0.08 release factor. This
suppresses utilization jitter without replacing the graduated ramps. The
combined workload chain and fans use the maximum of the two filtered signals;
RAM uses filtered CPU load and the GPU uses filtered GPU load.

Fan hue follows the same combined CPU/GPU workload wave as the workload chain,
while fan brightness moves inversely with that workload. The approved curve is
100% brightness at or below 20% workload, 40% at the 60% orange anchor, and
fully off by 85% workload. Between teal and orange, the fans crossfade through
black so their diffuser does not expose the washed-out RGB midpoint. The path
reverses smoothly as work returns to idle.

Temperature is an override, not a normal color input. A smoothed CPU Tctl of
82°C or GPU hottest reported temperature (normally junction/hotspot) of 95°C,
sustained for five seconds, forces every hardware group to full `#FF0000`,
including the normally dark high-load fans. Normal workload lighting resumes
only after CPU is below 75°C and GPU is below 85°C.

The RAM is deliberately black at or below the 20% CPU idle anchor. Above that
point it fades from black to its calibrated `#FF8000` at 60% CPU usage, then to
the shared `#FF0000` at maximum CPU usage.

An idle GPU yields visually to CPU activity: its teal fades out as CPU load
rises, remains off until filtered CPU load falls below 40%, then returns on a
squared curve to full teal at the 20% idle anchor. Meaningful GPU activity
restores its own independently workload-driven lighting.

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
GPU-specific GPU lighting, the combined workload-driven fan hue, inverse fan
brightness, and combined workload chain reacted during CPU and GPU tests without
service errors.

Future visual tuning should address:

- Make workload and temperature transitions more dramatic while retaining smooth
  changes and avoiding flicker.
- Calibrate colors per hardware group. The motherboard backplate/PSU chain, fans,
  ENE DRAM, and ASUS GPU render identical RGB values differently because their
  LEDs, diffusers, and controllers come from different vendors.
- Build per-device corrected teal, orange, and red anchors instead of assuming one
  shared RGB triplet will visually match every component.
- The PNY `16GF2X08QFHH36-135-K-RGB` DIMMs render Direct-mode teal, blue, and
  white unreliably even though their hardware Rainbow mode produces convincing
  blue and purple. RAM is off through the 20% CPU idle anchor, then transitions
  through its visually confirmed `#FF8000` orange to shared `#FF0000` red.

The complete synthetic preview—idle to orange to maximum and back—was visually
approved. At maximum load, switching the fan LEDs fully off was preferred over
the tested 15% and 5% red levels because the contrast against the full-red RAM,
GPU, and backplane is more dramatic. Actual CPU/GPU load validation remains.

Do not change these values blindly. Tune them while observing the physical system
under controlled CPU and GPU loads, then record the calibrated values here and in
`openrgb/config.yaml`.
