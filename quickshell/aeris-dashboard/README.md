# Aeris Quickshell dashboard

1920×480 control surface for the TeNizo touchscreen on `DP-3`.

Before designing or changing a widget, read the [design contract](DESIGN.md).
It records the approved spacing, anchoring, typography, state, and motion rules;
shared layout values live in `components/Theme.qml`. See [AGENTS.md](AGENTS.md)
for the implementation and verification checklist.

All dashboard adapters now use the combined
[Rust backend](../aeris-backend/README.md). Build it with
`bash scripts/build-dashboard-backend.sh` before a manual launch; the dashboard
installer builds it automatically. Five persistent watchers share one native
process; weather/artwork and control commands invoke the same binary on demand.
The Rust backend starts with the dashboard at login. Python adapters remain only
as an explicit rollback/comparison baseline, not as default runtime dependencies.

## Vulkan and panel motion

The launcher now defaults to Vulkan; this also applies to the login service.
The existing QSB shader packs include SPIR-V, so the heatmaps and weather retain
their design. An explicit `QSG_RHI_BACKEND=opengl` overrides the default for
compatibility or comparisons. Check the **actual** running API with:

```bash
bash scripts/run-dashboard.sh ipc call dashboard renderingStatus
```

Minimize slides the whole panel down in 220ms with a restrained fade; restore
slides it back in 260ms. Widget dimensions and the selected page are unchanged.
The temporary compositing layer exists only during motion. Controls are disabled
while moving, the restore handle remains available, and hidden heatmap/weather
presentation stops while services continue. Rapid reversal resumes from the
current position. Swipe pages retain 14px side gutters each (28px between pages).

See the [matched Vulkan/OpenGL results](../../settings/dashboard-vulkan-2026-09-05.md)
for CPU/GPU tradeoffs, validation, reproduction, and the service rollback procedure.

## September 4 checkpoint

The Idle layout has media at left with unified lighting/fan groups underneath,
clock/weather at top-middle with sleep and storage below, a full-height Pomodoro
tile, and equal-width CPU/RAM and GPU/VRAM cards stacked at right. Weather, media,
telemetry, controls, and the timer now use live services.

September 5: Home now has a compact 4×2 Pomodoro tile with a remaining-time ring,
vertical session dots on its left, and a matching 4×2 clock/weather tile beside it.
It retains the countdown, ring seeking, and templates/start/pause/reset. Its compact
routine chooser stays inside the same tile. Deep Work
retains the full quote/dial/template/seek UI; both control the same Tomat session.

The six cells right of storage now hold two stacked 3×1 tiles: an explicitly
unconnected FDM downloads placeholder above, and a working network activity display
below. The Rust metrics collector reads `/proc/net/dev` once per existing one-second
tick, computes receive/send byte deltas using the actual interval, and counts only
physical interfaces (`/sys/class/net/*/device`, cached discovery every 30s). This
excludes loopback/VPN/container double-counting. New links, reset counters, missing
reads and long sampling gaps seed a fresh baseline rather than producing spikes.

`NetworkMonitor` draws two softly blended sine ribbons in a small Vulkan-compatible
shader: teal receive and mauve send, with smoothed logarithmic amplitude. This is
an impression of live activity, not a precise time-series graph. Actual byte rates
are in the tooltip. No additional process, network request, Canvas repaint loop,
or high-frequency sensor poll; motion shares the decorative clock and stops when
quiet, offscreen, or minimized. FDM integration and real queue bars are deferred.

The clock's weather uses Open-Meteo current conditions for the city in the user's
local configuration, with condition textures, a ten-minute refresh, and labelled
offline caching. Clear days gain a blue daylight field; nights show restrained
twinkling stars and Open-Meteo's live lunar phase, illumination, and bright-phase
halo. Tap the weather reading to refresh. See
[weather setup](../../settings/weather.md); the layout and clock remain independent
of network availability.

Weather uses a GPU daylight shader, cached cloud/fog textures, and scene-graph
precipitation. Hidden pages pause presentation work while live services continue.
See [rendering and performance](../../settings/dashboard-performance.md) for
measurements, shader rebuild instructions, and the reference-renderer comparison.

Tomat runs independently of the dashboard. Tap its stage label/dots to choose an
Obsidian routine: Classic, Deep Work, or Light Work. Templates supply durations,
break labels, and a random original quote per run. A running session keeps its
snapshot when notes change. See [Pomodoro setup](../../settings/pomodoro.md) for
installation, template schema, switching behavior, and tests. Reusable seed notes
are in `tomat/templates/` at the repository root; the actual vault remains the
editable source of truth. Custom work-time nudges/animations are still deferred.

The surface is organized as three horizontally swipeable modes:

- **PC Specs** — hardware showcase to the left of Idle, marked by a CPU icon in
  navigation. Its first pass shows CPU, GPU, RAM, motherboard, five physical
  drives, OS, chassis, and fans/RGB in a dated build snapshot.
  See [sources and scope](../../settings/pc-specs.md).
- **Idle** — clock, CPU/GPU heatmaps, media, storage, and lighting controls.
- **Aeris AI** — merged AI/work hub: local API status and Aeris wordmark at the
  upper left, simple live CPU/GPU/RAM/VRAM meters beside it, and the full
  Pomodoro at the right. Saved LM Studio presets and worker-template file links
  occupy the lower band. These are real files/status, not a simulated job queue.

Idle remains the startup page. Swipe right from Idle to reach PC Specs, or tap
the CPU icon. IPC indices are now Specs=0, Idle=1, Aeris AI=2.

A **Grid Preview** inspector follows Aeris AI (IPC index 3). It displays the same
18-column × 4-row placement map now used by Home, with 12px gutters and uniform
12px content insets. Toggle GRID/SPANS/INSETS at bottom-left to inspect each layer.
This static inspector starts no services. PC Specs uses the same grid primitives
with its own placement map: a 3×4 identity tile, a 3×2 memory card,
six 4×2 hardware cards, and two 3×1 fan/ARGB cards. The merged hub retains the
AI card's 720×176 bounds and full-height Pomodoro's 296px width; other cards fill
the remaining space with 12px gutters/insets. `WorkPage.qml` hosts this
combined page; the separate `AiFocusPage.qml` was removed.

The Rust `aeris-dashboard-backend ai status` command performs bounded read-only
localhost checks: llama.cpp `/health` on port 8080 and LM Studio
[`/api/v1/models`](https://lmstudio.ai/docs/developer/rest/list) on port 1234.
Only explicit LM Studio `loaded_instances` count as resident models, not the
downloaded/JIT candidates from the OpenAI-compatible model list. Offline,
authentication-required, timeout, malformed and unavailable states are distinct
from ready. It does not discover credentials, follow redirects, load models,
send inference requests, or start servers. No new permanent backend thread:
QML polls every five seconds while the hub is visible, freezes offscreen, and
reuses existing telemetry for the four meters.

Saved preset settings come from the two known `.lmstudio/config-presets` JSON
files (context and GPU offload ratio, not live settings or historical token/s).
Tapping a preset opens its JSON; tapping a worker template opens its TOML.
The buttons explicitly open LM Studio, model files, or the worker workspace.
The three worker templates are the existing smoke/edit examples in
`~/Documents/ChatGPT/aeris/jobs`, not queued/running jobs. Missing files are
omitted and missing application/workspace actions are disabled.

Drag anywhere left or right to move between modes. The CPU icon and three compact
page dots also support direct touch navigation. Tile controls keep short taps while the drag
gesture only takes over after its movement threshold is crossed. A slow drag
settles after 180 pixels, leaving room to
cancel by releasing earlier. A fast flick can settle after 36 pixels when its
release velocity exceeds 700 pixels per second.

The down-chevron beside the page dots collapses the dashboard to a small
bottom-center recovery handle. Tap its up-chevron to restore the previous mode.
While collapsed, the rest of the transparent surface is click-through.

The same state is available through IPC for keyboard shortcuts or recovery:

```bash
./scripts/run-dashboard.sh ipc call dashboard showDashboard
./scripts/run-dashboard.sh ipc call dashboard hideDashboard
./scripts/run-dashboard.sh ipc call dashboard toggleDashboard
./scripts/run-dashboard.sh ipc prop get dashboard collapsed
```

## Run

Install Quickshell 0.3+ from the upstream-documented Fedora COPR:

```bash
sudo dnf copr enable errornointernet/quickshell
sudo dnf upgrade --refresh qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtshadertools
sudo dnf install quickshell
quickshell --version
```

Validated on 2026-09-05 with `quickshell-0.3.1-2.fc44` and Qt 6.11.2.
Fedora's standard repository still offered 0.2.1 at this checkpoint. The COPR
package failed with an undefined Qt property-binding symbol on Qt 6.11.1;
updating the matching Qt module set fixed it. DNF updates dependent Qt modules
together (38 Qt packages on this machine), not just the four explicit targets.
The COPR remains enabled for normal DNF updates; there is no custom build or
separate runtime updater.

Then launch this checkout through the repository runner:

```bash
./scripts/run-dashboard.sh
```

The runner requires 0.3+ and no longer falls back to the temporary extracted
`~/.local/opt/quickshell-fedora-0.2.1` runtime. The old bundle is retained only
for rollback with the pre-upgrade configuration, not the current QML.

`BackdropWindow.qml` requests real KWin backdrop blur through Quickshell's
`BackgroundEffect` / `ext-background-effect-v1` support. The transparent surface
shows the actual desktop behind the tiles, including wallpaper changes. There
is no fixed wallpaper image, wallpaper polling, or dashboard-wide dimming fill.
KWin owns the blur strength. Its region follows the slide offset and is cleared
when minimized; the restore handle does not leave the desktop blurred.

The shell selects `DP-3` by connector name and falls back to the unique
1920×480 logical screen geometry. It does not create a surface on the primary
display.

## Aeris lighting controls

The Idle page exposes three controls spanning five live daemon states:

- **Work** — the calibrated CPU/GPU workload-responsive behavior.
- **Night / Day** — one dashboard tile toggles between low static orange Night
  lighting and uniform white Day lighting at 90% configured brightness.
- **Off** — black Direct-mode frames; it does not select a controller hardware
  mode or save anything to firmware.
- **Party** — a software-rendered spatial Rainbow wave. Music synchronization is
  a later PipeWire integration, not part of the first mode-control milestone.

For mode changes, the dashboard talks only to the running Aeris daemon through the user-owned
`$XDG_RUNTIME_DIR/aeris-openrgb.sock`. It never imports OpenRGB, opens a hardware
connection, changes controller modes, or saves device state. The selected mode
is runtime-only and returns to Work whenever the daemon restarts. The control
Night/Day and Party/Off buttons disable themselves when the daemon is unavailable and show the daemon's
reported mode rather than assuming a tap succeeded. One persistent, idle status
watcher avoids launching a polling process every second.

When offline, tapping **Aeris** makes one attended `rgb start` request to the
Rust backend. This starts the existing `aeris-openrgb.service`, never a raw OpenRGB
process, and preserves all installed pre-start safety gates and the 10-second
discovery window. The logo turns teal while pending; other controls remain
disabled until a healthy daemon reply. An online Aeris tap still selects Work.
No geometry, labels, automatic recovery, or background restart loop is added.

The start path checks stopped service states and exact MSI USB/HID enumeration.
A previously failed daemon is eligible only for the recorded suspend/pause safety
stop; hardware/unknown errors require review. Concurrent/failed/uncertain attempts
are blocked by `$XDG_RUNTIME_DIR/aeris-openrgb-start-attempt`, removed only on a
healthy reply. After failure, review the service journal before manually clearing
that marker; the widget cannot bypass it. Startup errors remain in the logo's
tooltip rather than being overwritten by the next unavailable-status poll.

Work, Night/Day, and Party/Off share one horizontal tile beneath the media player.
Each remains an independent icon-only touch target, without divider borders.
Inactive controls are neutral gray; the daemon-reported active mode tints the
group background and its icon. Work uses the user's vector Aeris mark.

The Night/Day tile enters Night when selected from another mode. Once selected,
successive taps alternate between the orange moon and a white sun. Both are
separate volatile daemon states even though they share one physical control.

Mode transitions animate over roughly 220–240 ms. Background tint,
icon color, and icon scale ease together; the moon and sun
crossfade when the shared tile toggles. A pending daemon command blocks another
tap without dimming the whole control cluster, while an actual daemon outage
still fades the controls.

Query or change the same interface from a terminal:

```bash
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb set night
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb set day
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb set work
```

## Aeris cooling controls

The three cooling controls share a unified tile beside the lighting tile and select the live
CoolerControl modes:

- **Default** — the generous everyday airflow curve.
- **Quiet / Performance** — enters Quiet from another mode, then alternates
  between Quiet and Performance on successive taps.
- **BIOS** — releases motherboard fan control back to firmware rather than
  applying a CoolerControl curve.

The selected tile follows CoolerControl's reported active mode instead of
assuming that a tap succeeded. The helper talks only to the local HTTPS API and
reuses the existing CoolerControl GUI session from its user configuration; it
does not embed or store a password or token. Controls disable themselves if the
local daemon or authenticated GUI session is unavailable.

The same modes are callable from QuickShell IPC or the terminal:

```bash
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode default
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode quiet
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode performance
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode firmware

quickshell/aeris-dashboard/bin/aeris-dashboard-backend cooling status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend cooling set default
```

Run the telemetry adapter independently with:

```bash
quickshell/aeris-dashboard/bin/aeris-dashboard-backend metrics --once
```

## Compute and memory groups

Home's four storage rows show each physical drive's temperature opposite its
label. The Rust metrics worker reads the existing UDisks2 SMART cache over system
D-Bus at most once a minute, resolving filesystem mount points to drive objects
(including the Btrfs system volume). It converts ATA/NVMe Kelvin values to Celsius
without issuing SMART refreshes, waking sleeping disks, or requiring a privileged
helper. Readings older than 30 minutes, unavailable sensors, and failed reads show
`—`. This is cached device telemetry, not second-by-second temperature polling.

The Idle right column contains two equal hardware-affinity cards: CPU with
system RAM above GPU with VRAM. Each card keeps separate aligned headers and a
21 px internal gutter, but the shared outer boundary makes the resource
relationship explicit. The processor fields deliberately use the same clean
cell-matrix language while preserving the difference between measured and
synthesized data:

- CPU topology is discovered from sysfs L3-sharing and thread-sibling data. The
  two CCDs each render eight cores, and every core is split into two lanes driven
  by real `/proc/stat` logical-CPU deltas.
- The GPU renders an exact 10×8 field for the RX 6900 XT's 80 compute units.
  Aggregate utilization controls the active-cell target; weighted neighbor
  selection grows contiguous clusters, fringe removal tapers them, and per-cell
  heat warms or cools over time. It is an activity visualization, not per-CU
  telemetry.

All four fields share the same grid height. CPU and GPU use the common
grey-teal → teal → orange → red heat scale; RAM keeps its random allocation
bloom and VRAM retains its deterministic left-to-right, top-to-bottom fill.

## Login startup

Install and immediately start the user service with:

```bash
./scripts/install-dashboard.sh
```

The service is attached to KDE's graphical session, starts automatically at
login, and restarts Quickshell after an unexpected failure. Verify the deployed
unit and its live state with:

```bash
./scripts/install-dashboard.sh --check
```

The Idle page media tile uses Quickshell's native MPRIS service. It automatically
selects a playing player, falls back to a paused player, and exposes guarded
previous, play/pause, and next controls; the scrubber was removed in the current
layout. Metadata and cover-art URLs come from the player, with a local artwork
helper for reliable loading. Rounded artwork crossfades within its clipping frame. Players
that do not advertise a capability leave the corresponding control disabled.

## Visual theme

The dashboard uses a matte Nord-inspired slate/pastel palette and bundled
Share Tech Mono typography. `components/Theme.qml` is the shared source for
colors, radii, and fonts across all three pages. Standard controls use the
bundled Feather outlines and selected Pictogrammers Material Design Icons via
`ThemeIcon.qml`; Aeris uses the user's filled-A logo mark. Feather supplies the
moon, sun, power, coffee, wind, performance bolt, CPU, and navigation symbols;
MDI supplies filled media controls, fan, party star, and the available harddisk
asset. The clock/date use the user's bundled Iosevka Nerd Font.
SVG tint/scale transitions, mode actions, heatmap telemetry,
artwork crossfades, and pending/confirmed sleep-toggle feedback are preserved.

Assets and licenses live in `assets/`; no system font or icon-theme changes are
required, and no network requests are needed to load the theme.

## Prevent sleep

The narrow bottom-middle tile is a three-position vertical switch. Tap an icon:

- **Top / monitor / amber:** fully awake, using KDE's native **prevent sleep and
  screen locking** toggle. Changes from the Power and Battery tray are shared.
- **Middle / coffee / teal:** prevent automatic system sleep while allowing normal
  display power saving and screen locking. The Rust watcher owns a sleep-only
  PowerDevil inhibitor (`InterruptSession`, not `ChangeScreenSettings`), listed
  as Aeris Dashboard in the tray's application inhibitors, not its manual toggle.
- **Bottom / moon / gray:** normal power settings. Release only our sleep-only
  request and KDE's manual request; other applications' blockers remain untouched.

The thumb moves immediately; its color follows confirmation. PowerDevil delays
new inhibitors by five seconds, so the backend waits for enforcement before
confirming and keeps protection during middle/full transitions. Failed requests
attempt to restore the preceding mode, and the next status refresh reconciles UI.

`plasma/org.aeris.sleepbridge` is an invisible Plasma applet that shares the
tray's `InhibitionControl` singleton. The dashboard helper sends requests through
Plasma's scripting API over a persistent D-Bus connection. PowerDevil inhibition
changes trigger a debounced read of the confirmed manual state (about 200ms),
instead of launching `busctl` and evaluating a script every second. A 30-second
fallback check catches missed signals; unavailable Plasma retries every two
seconds. Owner-change notifications also trigger a refresh after service restarts.
The watcher also serves `org.aeris.Dashboard.Awake.SetMode` on that same connection,
so a short-lived command never owns the sleep-only cookie. No extra daemon or
periodic poll was added. The helper uses the Rust backend's native libdbus connection; no Python or
GLib event loop is needed. The reference Python adapter remains available only
through the explicit `AERIS_DASHBOARD_BACKEND=python` rollback (two modes only).
This deliberately uses KDE's private `batterymonitor` QML module (tested on
Plasma 6.7.4); a future KDE update may require adapting the bridge.

The dashboard installer also installs/attaches this bridge, which Plasma loads
on subsequent logins. It does not replay saved ON requests at login or change
saved power settings. Dashboard restarts preserve the native fully-awake session
state. Sleep-only mode lasts while the Rust watcher is running; stopping/restarting
that backend releases its cookie automatically. It is not restored after logout
or a PowerDevil restart. No stale cookie is reused across PowerDevil owners.
The previous independent `aeris-keep-awake.service` is stopped during migration.

```bash
bash scripts/install-sleep-bridge.sh
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep set full
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep set system
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep set normal
```

`on`/`off` remain aliases for `full`/`normal`. Mode commands require the running
dashboard watcher (or an explicitly started `sleep watch`).

Custom Pomodoro activities/reminders, a full Media page, music-reactive lighting, and the
remaining Aeris runtime controls remain deferred.
