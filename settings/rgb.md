# Aeris OpenRGB lighting

> **Approved automatic runtime:** the exact upstream rc3.1 RPM is installed,
> version-locked, and recorded in the runtime approval file. The fail-closed
> Direct-mode server and daemon passed controlled canary and workload tests on
> 2026-09-03. `aeris-openrgb.service` is enabled for user-session startup and
> pulls in its audited SDK-server dependency. Normal operation must continue to follow the
> [OpenRGB hardware-safety policy](rgb-safety.md).

## Components

- OpenRGB package plus its installed `60-openrgb.rules` udev policy. The exact
  upstream rc3.1 RPM bundles the rule in the main package; Fedora's older rc2
  build split it into `openrgb-udev-rules`.
- Installed package: `openrgb-0.9.2026^1.0rc3.1-0.fc43.x86_64`, official
  upstream release tag commit `5e81e26fcc65d3dacfb76b0a30ec0142ec7bb131`.
  The package is version-locked because RPM ordering otherwise treats Fedora's
  unsafe `1.0~rc2` package as an upgrade over upstream's unusual version string.
- Python 3 virtual environment: `~/.local/share/aeris-openrgb/venv`
- Controller: MSI MAG B550M MORTAR WIFI, recovered serial `A02021090806`
- SDK endpoint: `127.0.0.1:6742`
- Poll interval: 1 second
- Temperature smoothing alpha: 0.20
- CPU and GPU workload envelopes: 0.30 attack, 2-second peak hold, 0.40 release

The pinned Python dependencies are listed in `openrgb/requirements.txt`. The
virtual environment and generated caches are deliberately excluded from Git.

## Runtime modes and dashboard control

The daemon exposes a user-only Unix socket at
`$XDG_RUNTIME_DIR/aeris-openrgb.sock`. The Quickshell dashboard and the
`rgbctl.py` helper use this narrow JSON command interface; neither connects to
OpenRGB directly. Mode state is volatile and defaults to Work after every daemon
start.

| Mode | Behavior |
|---|---|
| Work | Existing calibrated load-responsive curve, smoothing, pulse, and thermal override |
| Night | Static per-device orange anchors at low configured brightness |
| Day | Uniform white Direct frames at 90% configured brightness |
| Off | Black Direct frames, without selecting a hardware Off mode |
| Party | Software spatial Rainbow rendered entirely through Direct frames |

All five daemon states retain the single OpenRGB SDK connection and the already-audited
Direct mode. Switching modes performs no profile load, controller effect change,
autonomous-mode selection, or persistent save. Party is capped at the existing
high-load cadence: motherboard frames no faster than 150 ms and ENE/GPU accents
no faster than 300 ms. The temperature-warning override remains authoritative
in every mode, including Off.

Night and Day share one dashboard tile. Selecting it from another mode enters
Night; tapping the already-selected tile alternates Night and Day. Day sends
`#FFFFFF` scaled to 0.90 (`230,230,230`) to every mapped zone and device. The
dashboard changes the selected tile from an orange moon to a white sun only
after the daemon reports the new state.

Party currently uses an eight-second software Rainbow cycle. PipeWire capture is
available on the machine, so music synchronization is technically feasible, but
it is deferred until capture-node selection, privacy behavior, beat/envelope
processing, and failure fallback are designed and tested.

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

The old rc2 `openrgb/sizes.ors` file recorded both JRAINBOW zones at 75 LEDs.
It is retained only as historical evidence and must not be deployed or loaded by
another OpenRGB version. Recreate and verify the 75/75 sizes under the exact
approved build.

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
for two seconds, and sustained recovery uses a 0.40 release factor. This
suppresses short utilization dips while allowing the lighting to return to idle
within a few seconds. The combined workload chain and fans use the maximum of
the two filtered signals; RAM uses filtered CPU load and the GPU uses filtered
GPU load.

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

Additional attended rc3.1 tests confirmed that this is still the correct
workaround. Direct pure blue leaves some LEDs dark even though the controller's
autonomous Rainbow mode renders blue and purple correctly; autonomous blue
Chase is also too dim. The temporary Chase and Rainbow tests used volatile
`save=False` mode changes only, and all four DIMMs were returned to Off before
the Direct-mode daemon was restarted. No ENE persistent save was attempted.

An idle GPU yields visually to CPU activity: its teal fades out as CPU load
rises, remains off until filtered CPU load falls below 40%, then returns on a
squared curve to full teal at the 20% idle anchor. Meaningful GPU activity
restores its own independently workload-driven lighting.

Above 75% filtered workload, affected lighting begins a synchronized brightness
pulse without changing its current interpolated hue. The backplane follows
combined CPU/GPU load, RAM follows CPU load only, and the GPU follows GPU load
only. Pulse depth increases with the corresponding signal and reaches the
approved 100%-to-5% brightness range at 95% workload. The shared cycle is 4.6
seconds. Motherboard frames render at 150 ms intervals; active RAM/GPU pulse
frames render at 300 ms to limit ENE SMBus traffic. The thermal-warning override
remains solid full red rather than pulsing.

On graceful logout, reboot, shutdown, suspend, or failure, the daemon must exit
without sending any final color, mode, profile-save, or persistent-state
command. A single manually authorized firmware-idle handoff was completed on
2026-09-03 after controller recovery, then deliberately retuned to 90% of the
approved teal commands: JRAINBOW1 is saved as static `#00B4B4`, JRAINBOW2 as
static `#007C4C`, and the ASUS GPU as static `#00B4B4`. The RAM was not detected
or written, preserving its existing red Chase Fade. Each final save used a
separate, single-detector OpenRGB 1.0rc3.1 process at commit `5e81e26f`; the MSI
save completed and USB enumeration was verified before the GPU process began.
The temporary writer was not installed. No daemon, shutdown hook, or repository
script may perform persistent writes.

After the full hardware identity is validated, the controller, four DIMMs, and
GPU are switched to **Direct** mode only if they are not already in it. The
process keeps one SDK connection for its lifetime. Any discovery mismatch,
disconnect, or update failure exits immediately; it never reconnects or retries.
Unchanged frames are not resent.

OpenRGB rc3.1 initially rendered `JRAINBOW2` with a completely different color
mapping from identical frames on `JRAINBOW1`. The daemon now clears the lower
two control-flag bits of every `JRAINBOW2` color channel (`channel & 0xFC`),
matching upstream MR !3306. A same-frame Rainbow test then rendered both headers
identically, and the corrected workload daemon reproduced the previously
approved smooth colors and transitions.

The SDK server has no restart policy and is blocked by an exact-package approval
gate before discovery. At every start it also re-audits the installed daemon,
refuses a second OpenRGB process, and requires the detector configuration to be
exactly the three approved Aeris detector families. Once approved and explicitly
enabled, it waits for udev to settle and delays discovery for 10 seconds. The
client requires exactly six allowlisted devices, the recovered motherboard name
and serial, and the exact 1/75/75 zone map before its first write. After its one
allowed `set_mode("Direct", save=False)` transition site, it verifies that each
device actually reports Direct mode before sending any color frame.

## Install or synchronize

From the repository root, deployment is deliberately non-activating:

```bash
./scripts/install-openrgb.sh
```

The installer:

1. Requires an already installed OpenRGB package and installed udev rules; it never
   upgrades hardware-control software implicitly.
2. Stops and disables both Aeris RGB services.
3. Backs up existing Aeris files.
4. Builds the pinned Python virtual environment.
5. Deploys the daemon, configuration, runtime command auditor, safety gate,
   detector-policy tool, and user units.
6. Quarantines every OpenRGB detector. It does not copy the legacy `sizes.ors`,
   enable a service, start OpenRGB, or access hardware.

Before installation, the script rejects daemon source containing known
persistent or shutdown-firmware write paths (`save_mode`, `save_profile`,
`save=True`, `set_custom_mode`, or `apply_firmware_idle`).

Check an existing installation without modifying or restarting it:

```bash
./scripts/install-openrgb.sh --check
```

## Service management

```bash
systemctl --user status aeris-openrgb.service aeris-openrgb-server.service
systemctl --user stop aeris-openrgb.service aeris-openrgb-server.service
journalctl --user -u aeris-openrgb.service -u aeris-openrgb-server.service
~/.local/share/aeris-openrgb/check-openrgb-safety.sh
~/.local/share/aeris-openrgb/configure-openrgb-detectors.py --check
~/.local/share/aeris-openrgb/configure-openrgb-detectors.py --require-aeris
journalctl --user -u aeris-openrgb.service -u aeris-openrgb-server.service -f
```

`aeris-openrgb.service` is enabled and defaults to Work at user-session startup.
Its SDK-server unit is deliberately not enabled independently: the parent pulls
it in through `Requires=` and orders itself after the server. The server remains
in its startup state for 10 seconds after launch so device discovery completes
before the daemon validates the exact inventory. Neither unit retries a failure;
any startup anomaly remains fail-closed.

## Validation history

A 30-second `stress-ng --cpu 16` run passed. CPU temperature peaked at 71.6 °C,
and the lighting visibly transitioned under load. This stress test is documented
rather than rerun automatically.

The complete curve was subsequently observed under separate one-minute CPU and
GPU stress runs and normal GPU work. Attack, peak hold, faster sustained release,
inactive-device dimming, high-load synchronized pulsing, and the fan-off maximum
all behaved as approved. The JRAINBOW2 rc3.1 color-mask correction was then
verified with the actual daemon, which again matched the approved visual result.

During the accepted manual run on 2026-09-03, the Python daemon used about
0–1% CPU and 20 MiB resident memory. The separate OpenRGB SDK server used about
4–5% CPU and 24 MiB resident memory. These are brief settled observations, not
capacity guarantees.

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
GPU, and backplane is more dramatic. Separate CPU/GPU stress and real GPU-load
validation also passed visually.

Do not change these values blindly. Tune them while observing the physical system
under controlled CPU and GPU loads, then record the calibrated values here and in
`openrgb/config.yaml`.
