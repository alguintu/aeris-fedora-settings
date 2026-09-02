# Aeris Quickshell dashboard

First-pass 1920×480 control surface for the TeNizo touchscreen on `DP-3`.

The surface is organized as three horizontally swipeable modes:

- **Idle** — clock, system overview, thermals, storage, and quick launch.
- **Work** — workspace launchers, live load, and honest placeholders for project,
  Git, task, and focus integrations.
- **AI Focus** — local-model status plus live GPU, VRAM, and thermal context.

Drag anywhere left or right to move between modes. A persistent mode strip also
supports direct touch navigation. Short taps remain available to launch Terminal,
Firefox, Code, and Files; the drag gesture only takes over after its movement
threshold is crossed.

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

Autostart, Pomodoro behavior, media, Awake, and Aeris runtime controls remain
deferred. The four launch targets have passed a first physical touch test; mode
swiping is the next on-device validation gate.
