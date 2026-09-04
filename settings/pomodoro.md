# Pomodoro backend

Our [Tomat fork](https://github.com/alguintu/tomat/tree/dev/timer-seek),
reporting upstream version `2.13.0`, is installed for Drei at `~/.local/bin/tomat`.
`tomat/source.env` pins commit `8591531bc42ef489c6ca84666a85dab86f60a207`,
based on upstream v2.13.0. `scripts/build-tomat.sh` fetches that exact source
and compiles it with Cargo's lockfile, release optimization and audio enabled.
Updates are deliberate; no upstream monitor, auto-update or PR is configured.
The feature branch contains one generic seek commit, with no project-specific
branding or version bump. Build provenance belongs here, not in Tomat's source.
The version string alone does not distinguish this build from the official one;
the pinned revision and live `can_seek` capability do.
No GTK or GNOME packages are needed;
the executable uses the system's existing ALSA, libc, libm and libgcc libraries.

## Install and verify

```bash
bash scripts/install-tomat.sh
bash scripts/install-tomat.sh --check
```

The installer preserves user configuration, upgrades the known official 2.13.0
or Aeris build, and refuses an unrelated binary or modified service unit. It
backs up the previous executable and saved state, replaces the binary atomically,
restarts Tomat only when the binary changes, and checks live seek capability.
If the fork health check fails, the previous binary is restored when available.
Backups live under `~/.local/share/tomat/backups/`; installed source provenance
is `~/.local/share/tomat/aeris-source.env`. The config template is
`tomat/config.toml`; the unit is `systemd/user/tomat.service`.

The user service starts at login, independently of Quickshell. It does not
start a focus session by itself. Defaults: 25-minute work, 5-minute break,
15-minute long break after four sessions, manual confirmation between phases.

Build prerequisites: Rust/Cargo, a C linker, Git, pkg-config and ALSA development
files (`alsa-lib-devel` and `pkgconf-pkg-config` on Fedora). This machine uses a
user-local sysroot in `~/.cache/aeris-tomat-build/sysroot`, extracted from the
Fedora `alsa-lib-devel-1.2.16.1-1.fc44.x86_64` RPM, linked to the installed matching
`libasound.so.2.0.0`. No privileged package install was required. The build helper
accepts system pkg-config or this local sysroot; runtime still uses system ALSA.

## Adjust elapsed time

Start a timer, then drag the visible dial arc forward or backward. The countdown
previews immediately; release sends one seek request. A tap or tiny movement does
nothing. Mouse/touch cancellation discards the preview, and page swiping is
disabled while the dial owns the gesture. The current stage must already be
started, but it can be paused. Stage/session changes during a drag reject the
stale request rather than adjusting the new stage.

Seeking changes elapsed time, not stage duration or the selected Obsidian routine.
The actual daemon deadline, CLI and widget agree; no additional timer runs in
QML. The dial cannot directly finish/skip a stage and is clamped to one second
remaining. CLI example: `tomat seek 600` credits ten elapsed minutes.
Convenience actions such as "three more minutes" belong in the frontend: they
calculate an earlier elapsed position and use the same seek primitive. No extra
relative-adjustment command or extension policy was added to Tomat.

The fork's raw socket status adds `can_seek` and `revision`. Seek accepts
`elapsed_seconds` and optional `expected_revision`; the dashboard always supplies
the guard. No transition hook, sound or notification fires just for seeking.

## Integration boundary

The reusable `components/PomodoroTile.qml` reads one shared `TomatService` QML
singleton. The Rust backend's Tomat worker queries the pinned 2.13 JSON socket protocol
every half-second, without spawning Tomat clients or running a second timer.
The socket is `$XDG_RUNTIME_DIR/tomat.sock`. Offline state disables the controls
and reconnects automatically; failed commands do not pretend to succeed.

Controls: reset returns the session to idle, Play starts/resumes, Pause freezes
it, and Skip advances a phase. The live dial represents elapsed progress over
its visible half. Dots represent work-session position in the cycle; labels
distinguish WORK, SHORT BREAK, and LONG BREAK. Countdown, progress and controls
all follow the daemon, including changes made from the CLI.

The dashboard exposes the same control path for checks through its `pomodoro`
IPC target (`status`, `toggle`, `reset`, `skip`).
Work/short-break/long-break transitions and hook events can drive future Aeris
activity suggestions. Workout/stretch/water reminders are not implemented yet.
Obsidian routines now supply timing, activity labels and a random original quote
per run. Work-time nudges and custom animations remain deferred.

## Obsidian routines

Tap the dots/stage label to open the in-tile routine picker. Classic (25/5/15),
Deep Work (45/5/15), and Light Work (20/5/10) are editable starters, all four rounds
with manual phase transitions. Labels such as STRETCH/WALK/WORKOUT describe the
existing breaks; they do not insert additional phases. Notifications retain
Tomat's standard phase names.

The active Obsidian vault is resolved from its local configuration. Its
`Aeris/Pomodoro Templates/*.md` files are read-only inputs to the dashboard.
See `Pomodoro Templates Guide.md` there for schema and editing instructions.
Portable seed copies are in `tomat/templates/`; copy only missing notes into a
new vault, never overwrite customized routines. The Rust backend parses the
data-only YAML without a Python runtime. PyYAML is needed only for the reference
adapter and its tests, not for the native dashboard/installer.

While idle, **Use template** selects the next run; Play starts it. During a run,
**Next session** changes only the selection for the next fresh start after Reset.
It does not switch at the next work/break transition. **Restart now** explicitly
replaces the current timer. The selected routine, labels, and one randomly chosen
quote are snapshotted on start. Note edits apply to future runs. Validation errors
are shown in the picker, including missing selections and duplicate IDs.

Selection/snapshot are atomically persisted in
`~/.local/state/aeris-pomodoro/selection.json`. Snapshots are scoped to the current
boot and cleared on Reset/observed Idle. Start template runs through the widget;
direct CLI starts use upstream settings and are not a template-switch interface.
The dashboard continues to display/control a pre-existing non-template timer.

Tomat 2.13's socket start handler ignores per-session sound overrides. Global
sound/notification settings are retained; there are no misleading per-template
sound controls. YAML uses safe loading and strict declarative fields; no commands
are executed from notes. Quotes are original Aeris lines, not attributed to
historical philosophers.

For isolated tests, `AERIS_TOMAT_TEMPLATE_DIR` and `AERIS_TOMAT_STATE_DIR` redirect
notes and selection storage. IPC `pomodoro.showTemplates(bool)` opens/closes the
picker, and `pomodoro.chooseTemplate(id, next|now)` uses the same selection path.

## Verification (2026-09-04)

An isolated, silent daemon passed start, pause (countdown stays frozen), resume,
short/long-break sequencing, natural timer expiry, stop, and paused-state restore
after daemon restart. The actual systemd service also restarted cleanly and was
left idle. No real suspend or reboot was performed.

Widget wiring: start/pause/resume/reset were verified through the dashboard's
shared control path, and a paused session retained its time through QML reload.
Regression tests cover raw-state mapping, offline/malformed responses, reset
semantics, and an isolated daemon's short/long breaks and natural expiry:

```bash
python3 -m unittest discover -s tests -p test_tomatctl.py
python3 -m unittest discover -s tests -p test_pomodoro_templates.py
```

Template integration also passed isolated silent-daemon checks for exact start
durations, non-disruptive queued selection, explicit restart, custom short-break
labels, and next-run selection after Reset. Unit tests cover note edits/deletion,
unsafe YAML, duplicate IDs, corrupt state, stale Idle responses and failed starts.
The user's live timer was not reset or skipped during template implementation.

### Fork and scrub verification (2026-09-05)

- Fork: 93 unit tests and 52 integration tests passed, including five new seek
  scenarios. `cargo check`, format check, Clippy with warnings denied and the
  release build passed. mdbook is absent, so HTML documentation generation is
  skipped; CLI reference/man pages still generate.
- Tests ran with the silent default fixture, avoiding the user's custom display
  format. An existing three-second wall-clock assertion crossed a second boundary
  on one run; the complete rerun passed without changing that upstream test.
- New native adapter tests verify strict argument/revision parsing, compatibility
  with the old daemon, and a real isolated fork plus Obsidian routine snapshot.
- Offscreen QML tests verify arc geometry, preview/cancel/single commit, stale
  revision capture, and synthesized mouse/touch input with paging exclusion.
- Installed from the exact published commit through the new build/install path.
  The live service retained Deep Work's paused STRETCH break at 5:00 during the
  switch; the dashboard reconnected with seek capability. Test gestures did not
  address the user's live timer. Backup: `install.ZgJAIeEv` under the backup path.

Run the new tests:

```bash
AERIS_TEST_TOMAT="$HOME/.local/bin/tomat" cargo test --locked --manifest-path quickshell/aeris-backend/Cargo.toml
python3 -c 'import sys; sys.path.insert(0,"tests"); from test_dashboard_presentation import PresentationTests; PresentationTests().run_qml("TimerSeek.qml", "TIMER_SEEK_TEST")'
```

Important: upstream stores timer state in the runtime directory, which normally
clears at reboot/logout. Service autostart is durable; preserving an active
session across a full reboot is not promised by this setup. We should explicitly
choose suspend/idle behavior when adding work-context nudges.

Source: <https://github.com/jolars/tomat/releases/tag/v2.13.0>
License: MIT; installed alongside the binary in `~/.local/share/tomat/LICENSE`.
