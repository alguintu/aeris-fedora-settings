# Aeris Quickshell dashboard

First-pass 1920×480 control surface for the TeNizo touchscreen on `DP-3`.

The surface is organized as three horizontally swipeable modes:

- **Idle** — clock, CPU/GPU heatmaps, storage, focus, and quick launch.
- **Work** — workspace launchers, live load, and honest placeholders for project,
  Git, task, and focus integrations.
- **AI Focus** — local-model status plus live GPU, VRAM, and thermal context.

Drag anywhere left or right to move between modes. Three compact page dots also
support direct touch navigation. Short taps remain available to launch Terminal,
Firefox, Code, and Files; the drag gesture only takes over after its movement
threshold is crossed. A slow drag settles after 180 pixels, leaving room to
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

Run the telemetry adapter independently with:

```bash
python3 quickshell/aeris-dashboard/services/metrics.py --once
```

## CPU and GPU heatmaps

The equal-width CPU and GPU cards deliberately use the same clean cell-matrix
language while preserving the difference between measured and synthesized data:

- CPU topology is discovered from sysfs L3-sharing and thread-sibling data. The
  two CCDs each render eight cores, and every core is split into two lanes driven
  by real `/proc/stat` logical-CPU deltas.
- The GPU renders an exact 10×8 field for the RX 6900 XT's 80 compute units.
  Aggregate utilization controls the active-cell target; weighted neighbor
  selection grows contiguous clusters, fringe removal tapers them, and per-cell
  heat warms or cools over time. It is an activity visualization, not per-CU
  telemetry.

Both widgets use the same grey-teal → teal → orange → red heat scale.

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

Pomodoro behavior, media, Awake, and Aeris runtime controls remain deferred.
