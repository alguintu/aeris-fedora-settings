# Dashboard rendering and performance

For the component-by-component and thread attribution measurements, see
[September 4 ablation](dashboard-ablation-2026-09-04.md).

## Vulkan default and slide reveal — September 5

The launcher now selects Vulkan, with an explicit OpenGL override supported.
Matched clear/rain/storm samples show approximately **17% / 8% / 20% less dashboard
CPU** at 60fps. Graphics-engine busy time increases from about **1.0% to 1.2–1.3%**;
service RAM decreases by approximately 16MiB. This is not a wall-power result.
The driver work partly moves into Qt's render thread, so the disappearance of
OpenGL worker threads must not be counted as eliminating all of their work.

Minimize/restore now slides the panel without reflowing widgets. Its temporary
layer is disabled at rest, and hidden decorative clocks stop. Full methods,
all samples, compositor caveats, and rollback are in
[Vulkan comparison](dashboard-vulkan-2026-09-05.md).

## Completed Python/Rust comparison — September 5

[Full method, repeated results, command timings, and raw data](dashboard-rust-comparison-2026-09-05.md).

The migration saves about **50 MiB of RAM**: helper PSS falls from 55.85 to
5.42 MiB (90%); animated-case service RAM falls from 160.6 to 110.0 MiB (31%).
An isolated cgroup check measures helper CPU at **0.217% → 0.150% of one logical
CPU**, a 31% relative reduction but only 0.067 percentage points in absolute
terms. New-process Tomat status falls from 50.2 to 2.1 ms; awake status from
45.1 to 3.6 ms. Cached weather/artwork calls drop from about 52 to 1.5–1.6 ms.

The animated-page CPU means are 10.34% versus 10.17%, with overlapping run ranges;
there is **no reliable animated-page CPU or GPU improvement** established here.
Qt/driver rendering remains the main cost. This measures the already-optimized
Python baseline against the full native migration, not the original early code.

## Full Rust adapter migration — September 4

All eight dashboard adapter modules are now ported. The default service runs
Quickshell plus **one Rust watcher process** for telemetry, RGB, cooling, native
awake status, and Tomat/templates. Weather/artwork and user commands invoke the
same release binary on demand. No dashboard Python helper remains running.
The original adapters are retained behind `AERIS_DASHBOARD_BACKEND=python` so the
next performance comparison can use the same QML and presentation settings.

Live read-only status parity matched all fields for cooling, awake, Tomat, and
cached weather. Fresh remote weather and artwork requests also succeeded.
The existing paused STRETCH session and quote survived deployment and a forced
backend-only termination; all five watchers recovered automatically. Screenshots
at 1920×480 confirm the unchanged layout, and the decorative clock remains 60fps.

Validation includes 25 Rust tests, 50 Python/integration tests, 18 JavaScript
tests, and a private D-Bus signal fixture. Rust Clippy passes with warnings denied.
Coverage includes persistent cooling HTTPS/auth recovery and no ambiguous POST
replay, isolated real-Tomat command cycles, template snapshots/boot/stale-Idle
races, YAML rejection, weather expiry/offline behavior, artwork keys/IDs, and
offscreen QML event routing, late-created tiles, pending feedback, and disconnects.
Real fan/light/awake modes were not changed to test controls.

At this migration checkpoint no full-port comparison had yet been made. The
completed comparison is linked above; the historical numbers below describe
previous implementations, not the completed port.
See [build/interfaces/recovery](../quickshell/aeris-backend/README.md).

## Historical Rust migration — telemetry and RGB first slice

At this checkpoint the dashboard ran one Rust backend for metrics and RGB polling,
with independent workers so socket failures did not stall telemetry. The other three
persistent adapters remained Python. The Rust binary also handled RGB commands;
the original Python implementations remain available through an explicit
rollback option. See [build/interfaces/recovery](../quickshell/aeris-backend/README.md).

Live proportional-set-size measurements (PSS accounts proportionally for shared
resident pages, not duplicated per-process RSS):

| Helper footprint | Before | After |
| --- | ---: | ---: |
| Metrics + RGB adapters | ~17.8 MiB (two Python processes) | 0.82 MiB (one Rust process) |
| All persistent dashboard adapters | 55.5 MiB | 38.65 MiB |

This first slice saves approximately **17 MiB / 30% of helper memory** without
porting the UI or changing presentation. The installed release executable is
776 KiB on this build. A separate 30-second live sample measured the complete
service at 130.3 MiB in cgroup accounting (versus 148.0 MiB in the earlier Python
sample); cgroup memory and PSS are different measures, so do not subtract them
from one another.

The same post-migration sample measured 8.479% of one logical CPU for the whole
dashboard, and 0.066% for the Rust metrics worker; other backend threads were
below the sample's per-thread CPU tick resolution. Graphics-engine busy time
was 1.149%. These live animation/load samples are not a controlled CPU or power
comparison. **The demonstrated gain here is memory, not a whole-page CPU win.**

Validation: all telemetry JSON keys, 2×8×2 CPU topology, RAM/VRAM and drive
capacities match the Python output; live RGB status matches exactly. Rust tests
cover cadence, clock selection, missing-sensor recovery, disk cache/deduplication,
socket framing/errors/deadlines, safe command validation, and metrics continuing
while RGB is unavailable. QML was inspected at the actual 1920×480 size and the
60fps setting verified. Test suites: 15 Rust + 48 Python + 18 JavaScript tests;
Clippy passes with warnings denied. Real fan/light/awake modes were not changed
during tests; the existing paused Tomat session remains independent.
Terminating only the live backend also verified Quickshell's two-second restart
path: a new process resumed healthy telemetry and RGB status automatically.

## Shared-clock trial (later September 4)

**Current setting: 60fps restored at the user's request.** The ~30Hz trial did
not establish a whole-page saving worth reduced smoothness. Shared color-update
scheduling remains; the measurements below describe the historical trial.

CPU/GPU/RAM/VRAM presentation was trialled with `DecorativeClock` at approximately
30 updates/second (32ms Qt timer; measured about 31 ticks/second). Color-frame
uploads are coalesced onto that tick as well. GPU/memory simulation remains at
100ms, CPU telemetry remains unchanged, and interpolation durations remain
220ms/340ms. The clock stops when no grid has pending colors or an active
transition. Pause/resume and retarget continuity are preserved. Input, swipe,
button, and media animations are not capped by this clock.

Weather was also tested on the shared clock, but that did not deliver a clear
whole-page CPU improvement. It was restored to its original 33ms timer and
elapsed-time stepping, preserving its previous motion. An experimental native
rounded-layer mask did not resolve the extra window presentations and was
removed; the original weather clipping remains intact.

Matched recorded telemetry, 20-second measurement after warm-up:

| Presentation | CPU % of one logical CPU | Graphics-engine busy % |
| --- | ---: | ---: |
| Before, weather frozen | 7.21 | 0.783 |
| Shared ~30Hz heatmaps, weather frozen | 5.69 | 0.625 |
| Shared ~60Hz heatmaps, weather frozen | 7.84 | 0.956 |
| Shared ~30Hz heatmaps and animated weather | 8.91 | 0.997 |
| Shared ~60Hz heatmaps and animated weather | 9.22 | 1.164 |
| Retained trial: ~30Hz heatmaps, original weather timing | 8.50 | 1.149 |

The isolated heatmap case saves about 21% CPU and 20% graphics-engine time.
The full animated page does **not** establish an overall saving against the
earlier roughly 8.3% full-page sample. An instrumented window still presented
about 60 frames/second while the decorative clock ticked about 31 times/second.
Clock cadence is not a whole-window frame cap. The remaining render/layer
scheduling needs further investigation; do not claim a wall-power saving.

The ~30Hz heatmap setting remains available for diagnostics, not as the default
or an assertion that it is indistinguishable from full refresh. Compare without reloading:

```bash
bash scripts/run-dashboard.sh ipc call dashboard decorationRate 60
bash scripts/run-dashboard.sh ipc call dashboard decorationRate 30
bash scripts/run-dashboard.sh ipc call dashboard decorationClock
```

These switches affect only the heatmap presentation clock. Startup defaults
to 60fps. The lifecycle test verifies synchronized grid transitions,
pause/resume, and that the shared clock has no clients once all grids pause.

## September 4, 2026 optimization

### Service overhead follow-up

Kept Python: measurements still put most dashboard CPU time in Qt/QML scene
updates, rendering, and graphics-driver threads rather than the adapters.

- CoolerControl status remains 1Hz, but shares one loopback HTTPS connection and
  SSL context. The session cookie is reread only when its file metadata changes
  or authentication fails. Broken keep-alive connections retry GET once;
  **POST mode changes are never automatically replayed** after ambiguous errors.
  The server's connection-close response and authentication rotation are handled.
- Awake status now uses the existing dbus-python/GLib runtime and a persistent
  session-bus connection. Inhibition/owner-change signals trigger a coalesced
  200ms refresh of the existing native Plasma bridge, preserving tray semantics.
  Healthy fallback polling is 30 seconds (formerly 1); failures retry in two
  seconds. Commands still obtain confirmed state immediately. No per-poll
  `busctl` process, no new independent inhibitor, no fan/power policy changes.
  The [dbus-python bus API](https://dbus.freedesktop.org/doc/dbus-python/dbus.bus.html)
  supplies direct calls, signal subscriptions, and disconnect handling.
- Tomat still samples at 2Hz. Template metadata is checked every three seconds,
  but unchanged notes are no longer reread/YAML-parsed; additions, deletions and
  edits invalidate the cache. Transient read errors retry instead of becoming
  permanently cached. The immutable boot ID is read once per helper lifetime.
  Timer state and template selection writes/locking semantics are unchanged.
- RGB's cheap 1Hz local-socket query was left alone. No visual/frame-rate changes.

Two 30-second live Idle-page samples, before/after service restart:

| CPU, % of one logical CPU | Before | After |
| --- | ---: | ---: |
| Entire dashboard service | 8.206 | 8.055 |
| Persistent Python helpers, combined | ~0.40 | ~0.13 |
| Tomat helper | 0.133 | 0.033 |
| Cooling helper | 0.133 | below 0.033 resolution |
| Awake helper | 0.033 | below 0.033 resolution |

Helper attribution uses coarse `/proc` ticks for surviving processes and does
not count the old short-lived `busctl` children; total service accounting does.
These are short, live-telemetry samples, not a controlled whole-dashboard
benchmark: renderer/driver time varied. The total-page difference is small and
does not establish a wall-power saving. Service memory increased from 143.1 to
148.0 MiB in these samples, including loading the GLib/D-Bus event machinery.
A separate 20-request, read-only microbenchmark measured cooling status CPU
cost **1.085ms → 0.127ms/call**; a live socket check verified identical local
port/descriptor across successive requests.

Validation: connection reuse, GET reconnection, no duplicate POST, cookie
refresh, server-close handling, coalesced notifications, fallback/recovery,
template invalidation and transient failure tests. A private D-Bus session with
mock Plasma/PowerDevil drove the actual watcher through OFF → ON → OFF by
signals; it never changed the user's actual inhibitor or fan/RGB modes.
Live service startup/dependency checks passed, with the existing awake state
preserved. Full suite: 48 Python and 18 JavaScript tests.

### Sensor-polling audit (before the adaptive collector change)

`services/metrics.py` takes a snapshot, emits JSON, then sleeps for one second;
the effective interval is one second plus collection time. One `/proc/stat`
read supplies all 32 logical CPU counters, with utilization derived from the
previous snapshot and rounded to 0.1%. CPU topology is discovered once at
startup. GPU usage is a global driver percentage, not per-compute-unit data.
GPU/memory simulation ticks at 100ms and color presentation now at ~60Hz;
neither cadence causes extra sensor reads.

Every metrics snapshot also reads CPU Tctl, GPU edge/hotspot, all 32 logical
CPU frequency files (averaged), RAM/VRAM totals and usage, mounted filesystem
capacity/free space, physical disk capacity, and four drive usage records.
GPU device and hwmon names/temperature labels are rediscovered each snapshot.
The collector keeps running while the dashboard is hidden.

A ten-snapshot instrumented local microbenchmark measured about 3.61ms CPU
and 3.64ms elapsed per snapshot: 61 text reads and 11 `statvfs` calls. Of those
text reads, 32 were CPU frequencies, 15 sensor names/labels, and three actual
temperature inputs. This is consistent with the earlier roughly 0.3–0.4% of
one CPU thread for the running metrics helper; it is not a wall-power measure.

The averaged `cpuClock`, `physicalDiskTotal`, and legacy `rootUsed/rootTotal`
fields had no QML presentation consumer at the time of this audit. Frequency collection alone
took roughly 1.06ms per sample. Filesystem capacity is queried redundantly:
root three times; workspace/documents/storage twice each, plus boot filesystems.

Potential follow-up identified by this audit: retain 1Hz CPU/GPU load,
use 1–2 seconds for RAM/VRAM and about two seconds for temperatures, refresh
filesystem space at 10–30 seconds, cache device/sensor discovery with recovery
on missing paths, and remove unused collection fields. Fan/RGB/awake status
watchers poll separately at roughly 1Hz; Tomat status at 2Hz. These are status
queries, not the underlying fan-control sensor loop.

### Adaptive telemetry collector (implemented September 4)

- CPU utilization, 32 thread counters, RAM usage, GPU utilization and VRAM usage
  remain at one snapshot per second. The CPU counters still come from a single
  `/proc/stat` read, not 32 separate reads. Rendering remains at 60fps.
- CPU header now reads `R9 5950X 4.5GHz` (example, live value). One frequency
  file is read per snapshot, selected from the busiest logical CPU according to
  the already sampled counters. This is **not an all-core average**. On this
  machine `amd-pstate-epp` has one logical CPU per policy; `cpuinfo_avg_freq`
  provides short-window hardware feedback for that policy. If that attribute
  is absent, discovery selects `scaling_cur_freq`, which may reflect a requested
  P-state instead of an exact hardware measurement. See the kernel's
  [CPUFreq policy attribute documentation](https://docs.kernel.org/admin-guide/pm/cpufreq.html).
  A hover hint explains the representative clock; failed/zero reads show `--GHz`.
- Temperatures: independently every three seconds for idle CPU/GPU, or every
  second when CPU aggregate reaches 10%, any CPU thread reaches 50%, or GPU
  reaches 10%, respectively. Fast polling persists for six seconds after load
  drops, then returns to three seconds. This is dashboard telemetry only, not
  the underlying cooling controller or its safety loop.
- Filesystem capacity/free space and all four drive bars share a snapshot on
  startup and every 60 seconds. Each unique local filesystem gets one `statvfs`;
  btrfs subvolumes are deduplicated. Unmounted drives remain unknown, and mount
  changes appear on the next refresh. `used` excludes reserved free blocks;
  aggregate `free` is user-available space, as before.
- GPU/hwmon/frequency paths and VRAM capacity are discovered once. Missing reads
  trigger rediscovery at most once every 30 seconds, allowing device-path
  recovery. CPU topology remains startup-only. Removed unused physical disk and
  duplicate root capacity reads/fields; GPU hotspot remains because AI uses it.

Matched local 120-call collector microbenchmark, old HEAD implementation versus
the new warm collector: **2.554ms → 0.188ms CPU per collection**. File-content
reads averaged **60 → 5.08**; frequency reads **32 → 1**; healthy sensor
name/label discovery reads **15 → 0**. This excludes the common `/proc/stat`
read, startup discovery, JSON output and sleep; the new schedule was advanced
one logical second per call and included two minute-boundary disk refreshes.
It is a collector-cost comparison, not a claim of a 93% whole-dashboard or
wall-power reduction. The rendering workload is unchanged. A separate 20-second
sample of the restarted live metrics helper measured about **0.10% of one
logical CPU** (coarse `/proc` CPU-tick accounting, not a matched power test).

Verified the live single-line CPU header at 1920×480, successful service restart,
60fps setting, and 37 Python plus 18 JavaScript tests. Collector tests cover
adaptive cadence/cooldown, busy-single-thread escalation, frequency source and
single-read selection, missing sensor recovery, disk refresh/deduplication,
unmounted drives, and removal of unused fields.

Measured on Aeris: Ryzen 9 5950X (16 cores/32 threads), RX 6900 XT, 1920×480
dashboard on DP-3. The weather tile is 480×206. No layout, typography, weather
motion speeds, lighting/fan behavior, or timer semantics were changed.

| Presentation | Before: CPU % of one logical CPU | After: CPU % of one logical CPU |
| --- | ---: | ---: |
| PC specs page, weather hidden | 8.9 | 1.7 |
| Idle with clear-weather rays | 42.8 | 9.1–10.4 |
| Idle with live overcast weather | 15.6 | 8.1–8.5 |

After samples for storm and fog were about 12.7% and 8.8%, respectively.
Collapsed, the optimized dashboard measured about 1.2% of one logical CPU and
0.015% graphics-engine busy time; the independent services remained running.
Samples are 15 seconds (the earlier specs baseline was 30 seconds), include the
dashboard service and its children, and are indicative rather than controlled
benchmarks. Current telemetry, media state, clock changes, and other desktop
activity can vary. 100% here is one logical CPU's scheduled time, not the entire
32-thread machine. Separate OpenRGB, CoolerControl, Tomat, and KWin services are
not included in the service-group CPU measurement.

The dashboard's graphics-engine busy time was about 1.22% with CPU-rendered rays
and 1.06–1.09% with accelerated rays; the optimized specs page was about 0.06%.
This is per-client DRM execution time, not shader-unit occupancy or a fraction
of peak GPU compute capacity. Deduplicate repeated DRM file descriptors by
device/client ID. Compositor work is not attributed to this client.

Observed whole-GPU board-power averages were roughly 32–33 W across these runs,
with no clear increase from acceleration. These readings include other GPU work,
are not wall power, and do not establish an energy saving. Wall-meter A/B testing
with steady unrelated workloads is still required to measure system power.

## What changed

- Six daylight beams and two haze fields are evaluated in one small GPU pass.
  Beam motion is calculated once per scene tick and passed as uniforms; the
  shader does not perform per-pixel trigonometry. Continuous Gaussian opacity
  replaces 144 repeatedly rasterized translucent polygons.
- Cloud banks and fog volumes retain the original procedural shapes, painted
  into textures once. Only their position/opacity changes thereafter.
- Rain and snow are small scene-graph primitives. Lightning geometry and glows
  are cached per strike, then faded by the scene graph instead of repainted.
- GPU/memory heatmap simulation and Pomodoro dial repainting pause off-page or
  collapsed. Metrics bindings retain their last value while hidden and receive
  the latest sample when shown. Adjacent pages remain active during swipes;
  none is removed from the Row, preserving swipe positions and cancellation.
- Settled memory grids stop their simulation timer and wake on new utilization.
  Pressure colors are calculated once per grid, and unused RAM/VRAM delegates
  are no longer instantiated. Cell sizes and visible heat/color transitions
  remain unchanged.
- The clock updates by minute rather than second. Media no longer polls playback
  position for a scrubber that is not present. MPRIS metadata/transport signals,
  weather polling, telemetry collection, and independent control daemons continue.

## Build and test

The compiled `daylight.frag.qsb` and `heatmap.frag.qsb` packs are shipped in
`quickshell/aeris-dashboard/shaders` alongside their readable GLSL sources.
No compiler is needed at dashboard startup.
Rebuild after editing the shader (Fedora package: `qt6-qtshadertools`):

```bash
bash scripts/build-dashboard-shaders.sh
python3 -m unittest discover -s tests -p 'test_*.py'
node --test tests/test_weather_scene.cjs tests/test_heatmap_frames.cjs
python3 scripts/profile-dashboard.py --seconds 20 --label current
```

Set `QSB` to an alternate Qt 6 shader-baker executable if necessary. The pack
contains SPIR-V, desktop/GLES GLSL, HLSL, and Metal variants. Daylight falls back
to the reference Canvas if the shader reports an error or Qt uses its software
renderer. Other weather continues using its cached textures/geometry.
After rebuilding a shader already loaded by the dashboard, restart only
`aeris-dashboard.service`: QML hot reload can retain the old shader pack,
including obsolete uniform/sampler bindings.

## Batched heatmaps

CPU, GPU, RAM, and VRAM now use one shader surface per visible grid instead of
hundreds of rectangle/shape delegates and individual color animations. A tiny
three-row texture holds each cell's starting color, target color, and remaining
transition time. One clock per grid drives GPU interpolation. Identical 8-bit
target colors do not upload another texture or restart transitions; retargeting
starts at the currently displayed color, preserving smooth cooldowns.
GPU/RAM simulation cells use plain internal arrays instead of observable model
roles; only the resulting color frame reaches the renderer. A settled GPU grid
does not repeatedly regenerate its unchanged color frame.

The CPU still has 16 cores/32 side-by-side threads, with only the four outer
package corners chamfered. Memory cells remain squares. GPU clustering,
hysteresis, low-load rotation, heat/cool rates, and 98% saturation threshold are
unchanged. Software rendering or shader failure uses a Canvas fallback.

GPU presentation can be exercised without launching a competing GPU workload:

```bash
bash scripts/run-dashboard.sh ipc call dashboard simulateGpu 99
# Restore real GPU telemetry on the next metrics sample:
bash scripts/run-dashboard.sh ipc call dashboard simulateGpu -1
```

This session-only diagnostic overrides only dashboard GPU-utilization input;
it does not stress the physical GPU, modify fan/RGB controls, or fake temperatures.
Use both sustained 99% and repeated 99/45/90/15% cycles (five seconds each): a
settled fully lit grid is cheaper than many cells changing concurrently. Keep
the dashboard visible on Idle and freeze weather for matched heatmap tests.
Discard samples spanning a page switch or service restart. The profiler rejects
CPU counter resets automatically.

Matched heavy-presentation check (weather frozen, Idle visible):

| Synthetic GPU input | Before CPU | After CPU | Before/after graphics-engine busy |
| --- | ---: | ---: | ---: |
| 99 → 45 → 90 → 15%, every 5 seconds, 40-second sample | 9.24% | 7.73% | 1.00% / 1.00% |

CPU is percent of **one logical CPU**, including dashboard child services.
This run reduced CPU time by about 16%, without a measurable graphics-engine
increase. These are short, unseeded presentation tests, not an energy benchmark:
CPU telemetry, random cell placement, and desktop activity still vary.
The settled 99% samples were cheaper (roughly 3.6–4.3% CPU) because fully heated
cells stop changing. Do not use that alone as the heavy-animation benchmark.
Actual display captures verified full GPU saturation, changing clusters, CPU
thread colors/chamfers, and square memory cells after the shader restart.
With real low-load GPU telemetry and frozen weather, CPU was essentially
unchanged: 7.99% before versus 8.12% after (20-second samples). This pass improves
the busy heatmap case; it does not establish an across-the-board idle reduction.

The QML lifecycle test runs an isolated, offscreen presentation config; it does
not instantiate the real dashboard shell, hardware watchers, or timer daemon.
It checks hidden pause, resume, settled-memory wake-up, and fixed-time rendering.

## Visual comparison and profiling

The old Canvas path remains accessible for regression checks. The diagnostics
are session-only, default to accelerated/animated, and do not modify weather data.

```bash
bash scripts/run-dashboard.sh ipc call dashboard setMode 1
bash scripts/run-dashboard.sh ipc call weather preview clear
bash scripts/run-dashboard.sh ipc call weather freeze 5.09642195
bash scripts/run-dashboard.sh ipc call weather renderer canvas
# Capture the tile, then compare the exact same animation time:
bash scripts/run-dashboard.sh ipc call weather renderer accelerated
# Always restore animation and live weather when finished:
bash scripts/run-dashboard.sh ipc call weather freeze -1
bash scripts/run-dashboard.sh ipc call weather preview ''
```

Preview conditions remain temporary (30 seconds). Fixed-time mode is explicitly
cleared with `freeze -1` or by restarting/reloading the shell; do not leave it
enabled after a comparison. The 5.09642195 timestamp captures the first lightning
peak. Matched screenshots of clear, night, partly cloudy, fog, rain, snow, and
storm were inspected on the actual dashboard during this optimization.

Read-only `profile-dashboard.py` samples the service cgroup and per-client DRM
counters. It also reports resident VRAM, service memory, and whole-GPU board
power/busy values where the driver exposes them. It does not switch pages,
change clocks, stop services, or alter device settings.
