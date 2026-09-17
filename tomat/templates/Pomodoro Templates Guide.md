# Pomodoro Templates Guide

These notes are the source of truth for the Aeris dashboard's timer routines:
[[Classic]], [[Deep Work]], and [[Light Work]].

Tap the stage label/dots at the top of the Pomodoro tile to open the picker.
Choose a routine, then **Use template** while idle. Press Play to start.
During a session, **Next session** selects the routine for the next fresh run
(after resetting to idle); **Restart now** replaces the running timer immediately.
Changing the selection does not alter the current work/break cycle.

The routine and one randomly selected quote are snapshotted when a run starts.
Editing a note affects the next run, never the running countdown or labels.
Notes refresh in the picker within a few seconds. Invalid notes are excluded
and their errors appear in the picker; duplicate IDs are rejected.

## Editing a routine

Duplicate a routine note in this folder, then change its unique `id` and `name`.
Only Markdown files directly inside this folder are read. YAML frontmatter is
the configuration; the Markdown body is yours to use for context.

- `type`: always `aeris-pomodoro`.
- `id`: unique lowercase slug, up to 48 characters.
- `name`: display name, up to 32 characters.
- `work_minutes`, `break_minutes`, `long_break_minutes`: 1–180; fractions allowed.
- `sessions`: 1–8 work periods per cycle.
- `auto_advance`: `none` (confirm each transition), `all`, `to-break`, or `to-work`.
- `work_label` and `long_break_label`: up to 16 characters.
- `short_break_labels`: 1–8 labels, each up to 16 characters; rotate in order.
- `quotes`: 1–32 original lines, each up to 72 characters. The tile credits AERIS.

Unknown fields are rejected to catch typos. No scripts or commands are executed.
STRETCH, WALK, STAND, and WORKOUT are activity labels on Tomat's existing breaks,
not additional timers or exercise prescriptions. Starter timings are editable.

## What is and is not connected

The existing Tomat alarm and desktop notifications remain enabled globally.
Tomat 2.13 ignores per-run sound overrides, so these notes do not expose sound
settings. Custom animations and reminders during work are not implemented yet.
Notifications use Tomat's standard phase names; custom labels appear in the tile.

Selection and the active snapshot live outside the vault in
`~/.local/state/aeris-pomodoro/selection.json`. The dashboard only reads notes.
Selection survives login/reboot; Tomat's live countdown uses its runtime state
and is not promised to survive a full reboot. Start routines through the widget;
direct CLI starts use Tomat's own configuration, not these templates.

Related: [[Quickshell Dashboard Rollout Log]], [[aeris-quickshell-touch-dashboard-handoff]].

## Workout blocks (phone companion 0.1.5)

A routine may include an optional `workout` object. The Upper body and Lower
body starter notes are in `tomat/workout-templates/` in the source repository
and installed alongside these notes in the active vault. They transcribe the
September working draft and remain marked `draft`. Choose a routine manually;
weekday labels are guidance, not automatic scheduling. Existing routines work
without workout data.

Workout metadata: `id` (stable lowercase slug), `name`, `status` (`draft` or
`ready`), `source` (note reference), `notes`, and `blocks`. Each block has a unique
`id`, `exercise`, `after_round` (1 through this routine's session count), `sets`
(1–8), `reps_min`, `reps_max` (1–200), `per_side`, optional `load_kg`,
`rest_seconds` (15–600), and `notes`. Unknown fields are rejected, including
commands/scripts. Note references are informational; nothing is executed.

`after_round` describes the intended break. The phone keeps the first unfinished
exercise handy and allows the daily sheet to log or reschedule work explicitly.
No phase transition automatically completes a set. The prescribed reps are
targets; the editor requires actual reps and, for per-side work, both sides.
Load and reps left are optional. Skip and clear are explicit logged actions.

The active routine is still snapshotted at timer start. Independently, the first
view of a workout each local calendar day freezes that day's prescription by
workout ID. Later template edits apply on a new day; switching templates or
restarting the timer does not overwrite the existing daily log. Reusing a
workout ID intentionally refers to the same daily prescription. Do not reuse
an ID for an unrelated workout. Logs are private JSON files under
`~/.local/state/aeris-pomodoro/workouts/`, separate from `selection.json`.
Old days remain on disk; the phone currently displays the selected plan's
current day rather than a history browser. No missed sets carry into tomorrow.

The phone requires a connection to Aeris for this iteration. Tomat owns the
countdown; Aeris owns the set log. App closure, timer reset and API restart
preserve saved sets. Pending unsent form edits are not a completed set.
