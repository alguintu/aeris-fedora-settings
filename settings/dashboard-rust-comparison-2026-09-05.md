# Dashboard Python → Rust comparison

Measured September 4–5, 2026, Asia/Manila, on Aeris (Ryzen 9 5950X / RX 6900 XT).

## Result

The completed migration saves approximately **50 MiB of memory**, reduces the
backend helpers' scheduled CPU time by **31%**, and substantially reduces
new-process status/cached-lookup latency. It does **not** establish a meaningful
animated-page CPU or GPU improvement. Rendering still dominates that workload.

This compares the retained, already-optimized Python adapters against the shipped
Rust implementation, including its consolidation into one watcher process. It is
not a comparison against the original unoptimized dashboard or an isolated
programming-language microbenchmark.

## Steady-state results

All CPU percentages refer to **one logical CPU**: 100% is one fully occupied
logical CPU, not the entire 32-thread machine.

| Measurement | Python | Rust | Interpretation |
| --- | ---: | ---: | --- |
| Persistent helper processes | 5 | 1 | Consolidated native watcher |
| Helper PSS, animated-case mean | 55.85 MiB | 5.42 MiB | **90.3% lower**, 50.43 MiB saved |
| Whole dashboard cgroup RAM, animated-case mean | 160.60 MiB | 110.03 MiB | **31.5% lower**, 50.57 MiB saved |
| Isolated helpers CPU, precise cgroup accounting | 0.217% | 0.150% | **30.8% lower**, but only **0.067 percentage points** absolute |
| Animated page CPU | 10.336% | 10.166% | Mean 1.6% lower; ranges overlap, not a reliable whole-page win |
| Animated page graphics-engine busy time | 0.888% | 0.910% | No GPU saving established |
| Frozen page CPU | 0.386% | 0.355% | Mean 8.1% lower; variability prevents a strong total-page claim |

PSS apportions shared resident pages among processes; it was sampled every five
seconds. Cgroup RAM is kernel service accounting sampled at each window's end.
These are different accounting methods: do not add them or subtract one from the
other. The helper and whole-service comparisons independently show a roughly
50 MiB reduction. Graphics-engine time is per-dashboard DRM execution time,
not shader occupancy or whole-device utilization.

### Every whole-page sample

Each row is a 40-second measurement after 15 seconds of warm-up. No samples were
discarded. Media presentation was hidden equally; playback continued normally.

| Block | Backend | Animated CPU | Animated graphics busy | Frozen CPU |
| --- | --- | ---: | ---: | ---: |
| 1 | Python | 10.083% | 0.9212% | 0.379% |
| 2 | Rust | 10.159% | 0.9264% | 0.327% |
| 3 | Rust | 9.670% | 0.9176% | 0.332% |
| 4 | Python | 10.260% | 0.8603% | 0.393% |
| 5 | Python | 10.664% | 0.8830% | 0.387% |
| 6 | Rust | 10.668% | 0.8848% | 0.406% |

Animated CPU ranges were 10.083–10.664% (Python) and 9.670–10.668% (Rust).
The final frozen Rust run had more Qt/render-thread work and 0.0092% graphics
busy time, versus 0–0.0014% in the other frozen runs. Its cause was not isolated;
it remains included, rather than being removed to improve the Rust result.

Mean scene-graph render-thread CPU was approximately 3.35% in both animated
cases; the graphics-driver worker threads together were approximately 3.58%
in both. A backend rewrite does not remove this rendering work.

### Isolated backend CPU check

To avoid attributing Qt activity to the helper language, both stacks were then
run simultaneously in separate temporary user-service cgroups. After ten
seconds of warm-up, three consecutive 20-second windows used microsecond CPU
accounting. Each stack had the same supervising Rust executable; stdout was
discarded equally. The normal dashboard remained on Rust outside those groups.

| Window | Python helpers | Rust helpers |
| --- | ---: | ---: |
| 1 | 0.2156% | 0.1491% |
| 2 | 0.2198% | 0.1615% |
| 3 | 0.2160% | 0.1399% |
| Mean | **0.2172%** | **0.1502%** |

This is about 2.17 ms versus 1.50 ms of scheduled CPU time per second. It confirms
a real backend saving, but also shows why that saving is small beside the
animated page. Per-process CPU counters in the whole-page raw data are coarser
(100 Hz ticks); use this isolated cgroup result for the backend percentage.

## Read-only command latency

Twenty measured new-process calls per implementation, after two warm-up pairs,
with Python/Rust order alternating. OS/filesystem caches were warm. Values are
medians and include process launch, parsing, and the reply.

| Command | Python | Rust | Speedup |
| --- | ---: | ---: | ---: |
| Cooling status, local HTTPS | 95.14 ms | 50.97 ms | 1.9× |
| Awake status, Plasma D-Bus | 45.14 ms | 3.62 ms | 12.5× |
| Tomat status + template catalog | 50.20 ms | 2.06 ms | 24.3× |
| Weather, cached reading | 52.32 ms | 1.62 ms | 32.3× |
| Artwork, cached lookup | 52.22 ms | 1.55 ms | 33.8× |

These are read-only adapter calls, not actual hardware mode-change completion
times. The cached lookup results do not mean internet downloads became 32×
faster. Media MPRIS controls remain in Quickshell and are not represented by
these adapter timings.

## Controls and limitations

- Same QML/shaders, release backend, 1920×480 output, and 60fps decorative setting.
- Same ten-sample recorded CPU/memory/disk trace for every page case. GPU widget
  input cycles 99 → 45 → 90 → 15% every five seconds, after a 99% warm-up.
  This exercises busy heatmap presentation; **no physical GPU stress was run**.
- Fixed rain preview in the animated case. The frozen case pauses heatmaps,
  weather, telemetry presentation and Pomodoro presentation. Watchers continue.
- Each backend starts afresh three times, in Python/Rust/Rust/Python/Python/Rust
  order. Compilation and command-latency tests ran outside page measurements.
- The real timer stayed paused on STRETCH. Fan/RGB modes, awake state, media
  playback, and the external control daemons were not changed.
- The replay and preview tools add equal diagnostic work in both page cases;
  these numbers describe the controlled workload, not every normal desktop state.
- CPU frequency, random heatmap positions, background desktop activity, and
  occasional UI updates add noise. Only three independent page runs per backend
  were taken. Do not interpret the small whole-page difference as a proven win.
- Whole-GPU board-power samples include unrelated applications. There is **no
  supported wall-power saving claim** from this experiment.

## Artifacts and reproduction

- [Page samples](benchmarks/2026-09-04-rust-comparison/results.jsonl)
- [Telemetry trace](benchmarks/2026-09-04-rust-comparison/telemetry.json)
- [Method and original page state](benchmarks/2026-09-04-rust-comparison/method.json)
- [Command samples, medians and p95](benchmarks/2026-09-04-rust-comparison/commands.json)
- [Isolated helper CPU samples](benchmarks/2026-09-04-rust-comparison/helpers.json)
- [Rust comparison harness](../quickshell/aeris-backend/src/bin/aeris-dashboard-benchmark.rs)

The harness uses the existing read-only Python profiler, unchanged. All new
benchmark orchestration, PSS collection, command timing, and isolated helper
supervision are Rust, in keeping with the project rule.

The normal/error cleanup restores the native dashboard and the original captured
page/visibility. The temporary runtime override was removed, transient helper
units stopped/collected, and normal Rust service health, 60fps, live telemetry,
and the unchanged paused timer were verified after this run.
