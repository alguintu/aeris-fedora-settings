# Aeris dashboard backend

One release binary replaces **all eight Python dashboard adapter modules**:
metrics, RGB, cooling, awake, Tomat, Obsidian templates, weather, and artwork.
The dashboard runs one `watch` process with five independent workers and a
bounded output queue. Weather and artwork remain short-lived, on-demand commands.
There is no Python interpreter or GLib/GTK dependency in the default adapter
path. Rust code forbids unsafe blocks; Linux syscalls use safe `rustix` APIs.
Qt/QML still owns the UI and graphics; existing hardware/control daemons remain
independent and unchanged.

## Build, test and deploy

From the repository root, with Rust/Cargo, a C toolchain, pkg-config, and OpenSSL
development headers installed (Fedora: `rust cargo gcc pkgconf-pkg-config
openssl-devel`). The pinned D-Bus crate builds its bundled libdbus; no dbus-devel
or Python D-Bus/YAML packages are required for the native build/runtime.

```bash
cargo test --manifest-path quickshell/aeris-backend/Cargo.toml --locked
cargo clippy --manifest-path quickshell/aeris-backend/Cargo.toml --all-targets --locked -- -D warnings
python3 -m unittest discover -s tests -p 'test_*.py'
dbus-run-session -- python3 tests/fixtures/sleep-bus-check.py "$PWD/quickshell/aeris-backend/target/debug/aeris-dashboard-backend"
bash scripts/build-dashboard-backend.sh
systemctl --user restart aeris-dashboard.service
bash scripts/install-dashboard.sh --check
```

Cargo.lock pins dependency resolution. Add `--offline` to the build script when
the locked crates are cached. The script atomically installs the release binary
into `quickshell/aeris-dashboard/bin/`; build outputs are ignored by Git.
The normal dashboard installer builds it before enabling/restarting the service.
Login runs the installed binary directly, **never Cargo**. After Rust source
changes, rebuild and restart; QML hot reload does not rebuild Rust.
Python remains a **test/reference** dependency: the isolated-daemon, private-bus,
and reference-adapter tests use PyYAML, dbus-python, and GLib on the test host.

## Interfaces

```bash
quickshell/aeris-dashboard/bin/aeris-dashboard-backend metrics --once
quickshell/aeris-dashboard/bin/aeris-dashboard-backend metrics
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb watch
quickshell/aeris-dashboard/bin/aeris-dashboard-backend rgb set work
quickshell/aeris-dashboard/bin/aeris-dashboard-backend cooling status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend sleep status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend tomat status
quickshell/aeris-dashboard/bin/aeris-dashboard-backend weather
quickshell/aeris-dashboard/bin/aeris-dashboard-backend artwork --title 'The Night We Met' --artist 'Lord Huron'
quickshell/aeris-dashboard/bin/aeris-dashboard-backend watch
bash scripts/run-dashboard.sh ipc call dashboard backendStatus
```

Subcommands preserve the previous newline-delimited JSON payloads. Combined
`watch` emits `metrics`, `rgb`, `cooling`, `awake`, and `tomat` envelopes:

```json
{"service":"metrics","payload":{"ok":true,"data":{"cpuUsage":3.2}}}
{"service":"rgb","payload":{"ok":true,"mode":"work"}}
```

The abbreviated metrics example omits the other unchanged fields. Failed
metrics collection emits `ok:false,error:...` and retries; the UI retains its
last values but marks telemetry unhealthy. Missing individual sensors stay
`null`. RGB replies are bounded to 64 KiB and a 750ms I/O deadline. A missing or
unresponsive RGB daemon does not block metrics. Each mode change is sent once,
never automatically replayed after an ambiguous timeout. All existing daemon
modes and native ownership remain intact; this adapter never talks to OpenRGB
hardware directly.

Telemetry keeps the established 1Hz load/memory snapshots, busiest-core single
clock read, independent 1–3 second CPU/GPU temperature cadence with a six-second
cooldown hold, 60-second disk snapshots, 30-second missing-sensor rediscovery,
and startup CPU topology. The Qt/QML layout and rendering are unchanged.

### Other adapter behavior

- **Cooling:** persistent loopback HTTPS connection, cached cookie with file
  change detection, 1.5-second request deadlines, bounded replies. Status reads
  can recover once from a stale connection/authentication cookie. Mode POSTs are
  never replayed after an uncertain result. Certificate verification is disabled
  only for the fixed `127.0.0.1:11987` endpoint; proxies and redirects are disabled
  there so the local cookie cannot be forwarded to another host.
- **Awake:** native libdbus connection to the unchanged Plasma bridge. Filtered
  PowerDevil/owner-change signals prompt a 200ms debounced status read, with a
  30-second fallback (two seconds while unavailable). No polling subprocesses,
  no independent inhibitor, and no saved ON request replay at startup.
- **Tomat/templates:** two-second Unix socket deadline and 64 KiB response cap.
  Same selected/active snapshot JSON, exclusive state-file locking, atomic
  writes, Linux monotonic timestamps, boot guard, and stale-Idle race protection.
  Notes stay read-only, data-only YAML; custom tags, unknown fields, duplicate
  IDs, and invalid values are rejected. Catalog metadata is checked every three
  seconds, unchanged YAML is not reparsed. Active routines survive note edits.
- **Weather:** verified remote HTTPS, 12-second deadline, 128 KiB reply cap,
  unchanged location config, ten-minute cache, and six-hour expiry/offline rules.
- **Artwork:** verified remote HTTPS, eight-second deadline, 8 MiB page/cache
  caps, Unicode case-folded keys, and the existing 30-day artwork cache. Qt still
  loads/crossfades the images; Rust resolves missing browser metadata artwork.

Each watcher has independent blocking I/O on its own worker, so one unavailable
service cannot stall the rest. The shell owns/restarts the single stream after
two seconds. `BackendService.qml` routes events and command invocations and
caches infrequent state for late-created tiles; disconnects invalidate consumers.
Command subprocesses remain short-lived and preserve confirmation/pending UI.

## Rollback / comparison baseline

The Python adapters are retained as reference implementations. To temporarily
run them, stop the managed dashboard, then launch with the process-local override:

```bash
systemctl --user stop aeris-dashboard.service
AERIS_DASHBOARD_BACKEND=python bash scripts/run-dashboard.sh
```

After stopping that foreground process, `systemctl --user start
aeris-dashboard.service` returns to Rust. Do not run the managed service and
foreground fallback together. The fallback is explicit, not a silent substitute
that would hide missing release builds. Both paths retain the same QML control
and profiling behavior.

The override selects **all** original Python adapters, including one-shot
commands. They are deliberately retained for a matched baseline and recovery;
they are not running under the default native setup. The actual Tomat daemon,
CoolerControl daemon, Aeris OpenRGB daemon, QML UI, and shaders are outside this
adapter migration. Python profiling/test utilities also remain developer tools.

Historical first-slice measurements and full-port verification are in
[dashboard performance](../../settings/dashboard-performance.md).

## Benchmarking the native and reference paths

The Rust benchmark harness uses the retained read-only profiler without adding
new Python helpers. Start from a healthy default Rust dashboard. The page
comparison temporarily restarts that service with each implementation and hides
media presentation, but never changes playback, hardware modes, or the timer.
Use a new output directory/file each time; existing outputs are not overwritten.

```bash
cargo build --manifest-path quickshell/aeris-backend/Cargo.toml --release --locked --bin aeris-dashboard-benchmark
quickshell/aeris-backend/target/release/aeris-dashboard-benchmark "$PWD" \
  settings/benchmarks/2026-09-04-rust-comparison/telemetry.json /tmp/aeris-python-rust-new
quickshell/aeris-backend/target/release/aeris-dashboard-benchmark --commands "$PWD" /tmp/aeris-python-rust-new/commands.json
quickshell/aeris-backend/target/release/aeris-dashboard-benchmark --helpers "$PWD" /tmp/aeris-python-rust-new/helpers.json
```

The page pass takes about eleven minutes: three 40-second samples per backend
and case, plus warm-up. Page/visibility changes abort it and preserve the user's
new selection. Normal/error cleanup removes only its own temporary runtime
override and restores Rust. If the harness is forcibly killed, check
`/run/user/1000/systemd/user/aeris-dashboard.service.d/90-aeris-benchmark.conf`;
remove only that experiment-owned override, reload user units, and restart the
dashboard. The isolated helper units have a 120-second lifetime limit as an
additional cleanup safeguard. They contain only read-only watcher processes.

Command timings use fresh processes with warm OS caches; weather/artwork cases
measure cache hits, not network fetches. Full measurements and caveats are in
[the September 5 comparison](../../settings/dashboard-rust-comparison-2026-09-05.md).
