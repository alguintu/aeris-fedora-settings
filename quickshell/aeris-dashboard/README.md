# Aeris Quickshell dashboard

1920×480 control surface for the TeNizo touchscreen on `DP-3`.

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

The clock's weather uses Open-Meteo current conditions for the city in the user's
local configuration, with day/night icons, condition textures, a ten-minute refresh,
and labelled offline caching. Tap the weather reading to refresh. See
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

The surface is organized as four horizontally swipeable modes:

- **PC Specs** — hardware showcase to the left of Idle, marked by a CPU icon in
  navigation. Its first pass shows CPU, GPU, RAM, motherboard, five physical
  drives, OS, chassis, and fans/RGB in a dated build snapshot.
  See [sources and scope](../../settings/pc-specs.md).
- **Idle** — clock, CPU/GPU heatmaps, media, storage, and lighting controls.
- **Work** — workspace launchers, live load, and honest placeholders for project,
  Git, task, and focus integrations.
- **AI Focus** — local-model status plus live GPU, VRAM, and thermal context.

Idle remains the startup page. Swipe right from Idle to reach PC Specs, or tap
the CPU icon. IPC indices are now Specs=0, Idle=1, Work=2, AI Focus=3.

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

Install Fedora's packaged runtime once:

```bash
sudo dnf upgrade --refresh
sudo dnf install quickshell
```

The refresh matters on the recorded Fedora 44 state: the Quickshell build in
`updates` targets Qt 6.11.2 while the desktop was still running Qt 6.11.1.

Then launch this checkout through the repository runner:

```bash
./scripts/run-dashboard.sh
```

The runner also recognizes the temporary user-local validation runtime at
`~/.local/opt/quickshell-fedora-0.2.1`.

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

The dashboard talks only to the running Aeris daemon through the user-owned
`$XDG_RUNTIME_DIR/aeris-openrgb.sock`. It never imports OpenRGB, opens a hardware
connection, changes controller modes, or saves device state. The selected mode
is runtime-only and returns to Work whenever the daemon restarts. The control
buttons disable themselves when the daemon is unavailable and show the daemon's
reported mode rather than assuming a tap succeeded. One persistent, idle status
watcher avoids launching a polling process every second.

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

The narrow coffee-cup tile in the bottom-middle row controls KDE's native **prevent sleep and
screen locking** toggle. Its amber state follows the same in-process controller
used by the Power and Battery tray applet; changes from either UI are shared.
Disabling it releases only KDE's manual request, not other applications' blockers.

`plasma/org.aeris.sleepbridge` is an invisible Plasma applet that shares the
tray's `InhibitionControl` singleton. The dashboard helper sends requests through
Plasma's scripting API over a persistent D-Bus connection. PowerDevil inhibition
changes trigger a debounced read of the confirmed manual state (about 200ms),
instead of launching `busctl` and evaluating a script every second. A 30-second
fallback check catches missed signals; unavailable Plasma retries every two
seconds. Owner-change notifications also trigger a refresh after service restarts.
The helper now uses the Rust backend's native libdbus connection; no Python or
GLib event loop is needed. The reference Python adapter remains available only
through the explicit `AERIS_DASHBOARD_BACKEND=python` rollback.
This deliberately uses KDE's private `batterymonitor` QML module (tested on
Plasma 6.7.4); a future KDE update may require adapting the bridge.

The dashboard installer also installs/attaches this bridge, which Plasma loads
on subsequent logins. It does not replay saved ON requests at login or change
saved power settings. Dashboard restarts preserve the native session state.
The previous independent `aeris-keep-awake.service` is stopped during migration.

```bash
bash scripts/install-sleep-bridge.sh
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep set on
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep set off
```

Custom Pomodoro activities/reminders, a full Media page, music-reactive lighting, and the
remaining Aeris runtime controls remain deferred.
