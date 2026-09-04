# Dashboard cost attribution — September 4, 2026

## Method

Measured Aeris's running dashboard service and its children on the Idle page.
CPU percentages mean scheduled time of **one logical CPU**, not the whole
5950X. The graphics number is per-client DRM graphics-engine execution time,
not GPU shader occupancy. Hardware control daemons, the actual media player,
and Tomat's daemon were never stopped or modified.

Each condition received the same ten-sample recorded CPU/memory/disk trace,
with synthetic GPU utilization cycling 99 → 45 → 90 → 15% every five seconds.
Before each measurement, the GPU widget warmed at 99% for 13 seconds; after
applying the diagnostic switches, there were two seconds to settle. Samples
lasted 20 seconds. GPU computation was **not** stressed on the physical device.
CPU telemetry was a recorded light desktop workload, not an all-core stress test.

These are ablation deltas, not additive component ownership. A widget can keep
the shared renderer/driver busy even when every other widget is static.
The graphics context still draws static content while another item animates.
Short runs, random heatmap placement, CPU frequency, and unrelated desktop work
introduce noise; savings smaller than the baseline spread are inconclusive.

## Broad pass

Live weather was nighttime partly cloudy in Puerto Princesa. All rows except
the first have weather animation paused in place. Media/Pomodoro tests hide
their presentation, not the MPRIS connections or daemon watchers. Tomat was
already paused on STRETCH; this does not measure an actively counting timer.

| Condition | Dashboard CPU % | Dashboard graphics-engine busy % |
| --- | ---: | ---: |
| Heavy changing GPU input, weather animated | 8.32 | 1.002 |
| Weather paused, all heatmaps running | 7.16 | 0.888 |
| CPU heatmap also paused | 6.55 | 0.740 |
| GPU heatmap also paused | 3.43 | 0.410 |
| Memory heatmaps also paused | 7.56 | 0.817 |
| All heatmaps also paused; telemetry/text still update | 1.24 | 0.013 |
| Media presentation hidden; heatmaps running | 7.36 | 0.800 |
| Pomodoro presentation hidden; heatmaps running | 7.24 | 0.771 |
| Weather/heatmaps and telemetry presentation all frozen | 1.14 | 0.000 |
| Dashboard collapsed, same frozen presentation | 1.08 | 0.001 |
| Repeat: weather paused, all heatmaps running | 7.59 | 0.774 |

The frozen-weather baseline spanned 7.16–7.59%. The small differences for memory,
media, and the paused Pomodoro are not evidence of a meaningful CPU saving.
The GPU heatmap is the strongest individual trigger; stopping all heatmaps
removes about six percentage points of scheduled CPU time. Merely freezing
the remaining telemetry/text changes then saves only about 0.1 points.

In the fully animated 8.32% sample, persistent-thread CPU was approximately:

| Work | CPU % |
| --- | ---: |
| Qt scene-graph render thread | 2.04 |
| CPU-side graphics-driver threads (`gl0`, `gdrv0`, `cs0`) | 3.04 |
| Main Qt UI / JavaScript thread | 1.89 |
| Wayland event thread | 0.30 |
| Metrics, Tomat, cooling, RGB and sleep watcher helpers together | 0.85 |

Thread counters are coarser than the cgroup total and omit short-lived threads
that do not exist at both endpoints. They will not sum perfectly. Helpers are
mostly a roughly 1% floor, not the source of the continuous-rendering cost.

## GPU simulation versus presentation

A second pass used a newly recorded trace, identical across its own cases:

| Weather paused; GPU diagnostic | Dashboard CPU % | Dashboard graphics busy % | Whole KWin CPU % |
| --- | ---: | ---: | ---: |
| Normal heatmap simulation and smooth transitions | 6.98 | 0.789 | 4.68 |
| Simulation and color uploads run; no interpolated blending | 5.01 | 0.514 | 3.54 |
| Simulation and color calculation run; display updates paused | 3.71 | 0.338 | 3.59 |
| Entire GPU heatmap paused | 3.42 | 0.341 | 3.49 |

CPU and memory heatmaps remained active in all four rows. Disabling only GPU
blending presented its normal 100ms color updates immediately; this was a
diagnostic, not a shipped quality change. In the no-display-update case, the
simulation still selected cells, applied hysteresis, changed heat, and calculated
colors, but did not hand a new color frame to the renderer.

For this workload, the GPU simulation/color math itself accounts for only about
0.3 percentage points over the fully paused GPU widget. Presenting the color
frames adds about 1.3 points, and the interpolated transitions another 2 points.
These approximate deltas include the shared render/driver work triggered by
those updates; they are not instruction-level profiles of individual functions.

KWin numbers cover the **entire compositor**, including unrelated windows.
Their decrease is consistent with reduced presentation work, but must not all
be attributed to the dashboard. KWin DRM counters were inaccessible due to
`/proc/<pid>/fdinfo` permissions; missing values mean unavailable, not zero.
Whole-GPU board power varied with unrelated activity and does not support a
wall-power saving claim. A page change during the next warm-up stopped the
runner; no partial measurement from that interrupted case was recorded.

## What to optimize next

1. Test a shared, synchronized presentation clock for decorative heatmap and
   weather motion, potentially around 30Hz, while leaving touch/swipe response
   at display refresh. Preserve simulation rates and transition durations.
2. Reduce color-frame preparation/upload and QML-to-renderer handoff overhead.
   The clustering algorithm is not the primary remaining cost.
3. Re-measure quality and CPU/GPU/compositor cost before adopting any cadence
   change. This investigation does **not** implement a lower frame rate.

Memory polling, static layouts, and the tested media/paused-Pomodoro presentation
are lower priority. Their observed CPU differences were smaller than test noise.

## Reproduce / restore

```bash
python3 scripts/ablate-dashboard.py --seconds 20 \
  --output /tmp/aeris-ablation-new.jsonl
```

The runner saves its captured trace next to its output as `.telemetry.json`.
Reuse that file with `--telemetry` for another pass. Outputs are opened
exclusively to avoid overwriting another experiment. The runner checks page
and visibility throughout, restores the original page/visibility and live data
in `finally`, and handles SIGTERM. If the user changes the page/visibility, it
aborts the sample and preserves that choice while restoring live telemetry.
An in-shell 60-second watchdog also clears
replay/pause switches if IPC updates stop. No renderer quality setting changes.

Manual emergency reset of presentation diagnostics:

```bash
bash scripts/run-dashboard.sh ipc call dashboard profile '' false
bash scripts/run-dashboard.sh ipc call dashboard simulateGpu -1
bash scripts/run-dashboard.sh ipc call dashboard showDashboard
```

`profile` controls session-only presentation switches; normal startup leaves
them empty. `profileFrame` supplies diagnostic telemetry only while replaying.
The weather service itself remains live; its presentation pause is cleared by
the same reset. Weather's separate `freeze`/`preview` tools are not used here.

The focused GPU pass is selected with:

```bash
python3 scripts/ablate-dashboard.py --seconds 20 \
  --cases no-weather,no-gpu-blend,no-gpu-paint,no-gpu \
  --output /tmp/aeris-gpu-ablation-new.jsonl
```
