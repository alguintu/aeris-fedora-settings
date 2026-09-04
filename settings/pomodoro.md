# Pomodoro backend

Tomat 2.13.0 is installed for Drei at `~/.local/bin/tomat`, from the official
x86_64 GNU/Linux release. `scripts/install-tomat.sh` pins the version and verifies
the archive SHA-256 before installing. No GTK or GNOME packages are needed;
the executable uses the system's existing ALSA, libc, libm and libgcc libraries.

## Install and verify

```bash
bash scripts/install-tomat.sh
bash scripts/install-tomat.sh --check
```

The installer preserves an existing user configuration and refuses to replace
a different existing binary or service unit. The config template is
`tomat/config.toml`; the unit is `systemd/user/tomat.service`.

The user service starts at login, independently of Quickshell. It does not
start a focus session by itself. Defaults: 25-minute work, 5-minute break,
15-minute long break after four sessions, manual confirmation between phases.

## Integration boundary

The reusable `components/PomodoroTile.qml` reads one shared `TomatService` QML
singleton. `services/tomatctl.py` queries the pinned 2.13 JSON socket protocol
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
new vault, never overwrite customized routines. Python requires PyYAML
(`python3-pyyaml` on Fedora); the installer checks this dependency.

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

Important: upstream stores timer state in the runtime directory, which normally
clears at reboot/logout. Service autostart is durable; preserving an active
session across a full reboot is not promised by this setup. We should explicitly
choose suspend/idle behavior when adding work-context nudges.

Source: <https://github.com/jolars/tomat/releases/tag/v2.13.0>
License: MIT; installed alongside the binary in `~/.local/share/tomat/LICENSE`.
