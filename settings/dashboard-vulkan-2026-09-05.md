# Vulkan and slide-reveal checkpoint

Measured September 5, 2026, on Aeris: Ryzen 9 5950X, RX 6900 XT, Fedora KDE
Wayland, bundled Qt 6.11.2, Mesa 26.1.8. Vulkan device selection was verified as
**AMD Radeon RX 6900 XT (RADV NAVI21)**, not the enumerated llvmpipe device.

## Result

Vulkan is now the launcher's default, including login startup. The already-shipped
QSB shader packages contain SPIR-V and run unchanged. No detail, transparency,
resolution, or heatmap frame-rate reduction was made for this comparison.

All CPU numbers are percentages of **one logical CPU**, not the whole machine.
Each value below averages two 30-second samples per API and weather condition.

| Weather | OpenGL dashboard CPU | Vulkan dashboard CPU | Reduction |
| --- | ---: | ---: | ---: |
| Clear / god rays | 7.558% | 6.302% | 16.6% |
| Rain | 9.743% | 8.953% | 8.1% |
| Storm / lightning | 11.149% | 8.873% | 20.4% |

The observed Vulkan CPU range was below the OpenGL range in each condition,
but this is a small local experiment, not a general Vulkan speedup guarantee.

| Weather | OpenGL graphics busy | Vulkan graphics busy | OpenGL service RAM | Vulkan service RAM |
| --- | ---: | ---: | ---: | ---: |
| Clear | 1.045% | 1.198% | 105.75 MiB | 89.60 MiB |
| Rain | 0.977% | 1.203% | 109.20 MiB | 92.55 MiB |
| Storm | 0.983% | 1.281% | 111.50 MiB | 95.45 MiB |

Graphics busy is per-client DRM engine execution time, not shader occupancy or
whole-device utilization. Vulkan saves dashboard CPU and approximately 16MiB of
cgroup RAM here, but spends somewhat more GPU execution time. Resident client
VRAM also fell from roughly 122–126MiB to 103MiB. These memory accounting methods
are distinct; do not add their savings together.

### What happened to the 3.58% driver cost?

It did not simply disappear. In the matched rain samples, OpenGL's three worker
threads averaged **3.439%**, alongside **3.206%** in `QSGRenderThread`. Vulkan has
no corresponding `gl0` / `gdrv0` / `cs0` workers, but `QSGRenderThread` rises to
**5.733%**, including work now executed through Vulkan on that thread.
The combined rendering-thread/driver cost declines from about 6.645% to 5.733%.
Total dashboard CPU is the deciding comparison, not thread names.

### Frame pacing and whole-desktop caveats

All twelve samples averaged approximately **60fps**. Across **21,756 measured
frame-swap intervals**, p95 was 17–18ms, p99 was 17–18ms, the maximum was 20ms,
and none exceeded 25ms. This measures delivery of `QQuickWindow::frameSwapped`
signals using a millisecond clock, not physical scanout or input latency. The
probe is connected only when explicitly measuring and has a 60-second timeout.

Whole-KWin CPU was higher in the Vulkan clear/rain samples; for rain its mean
was 5.432% with OpenGL and 6.380% with Vulkan. That process includes every other
window and the user's ongoing desktop activity, so this test does not isolate
the dashboard's compositor contribution. The dashboard CPU saving is **not** a
claim that aggregate desktop CPU improves in every condition. Whole-GPU board
power also includes unrelated activity. **No wall-power saving is established.**

## All samples and controls

| Block | API | Clear CPU | Rain CPU | Storm CPU |
| --- | --- | ---: | ---: | ---: |
| 1 | OpenGL | 7.784% | 10.031% | 11.367% |
| 2 | Vulkan | 6.317% | 9.287% | 9.353% |
| 3 | Vulkan | 6.287% | 8.619% | 8.392% |
| 4 | OpenGL | 7.332% | 9.454% | 10.930% |

- Same Rust backend, page layout, 1920×480 output, and 60fps heatmap setting.
- Same recorded CPU/memory/disk telemetry. GPU widget input cycles
  99 → 45 → 90 → 15% every five seconds, after an eight-second 99% warm-up.
  This exercises busy heatmap presentation; **no physical GPU stress was run**.
- Weather previews run normally; the same three conditions run in every block.
  Random heatmap placement, weather phase, CPU frequency and desktop activity
  remain sources of variation. No samples were discarded.
- Media presentation is hidden equally, without interrupting actual playback.
  Timer, awake state, lighting/fan modes, and external daemons are untouched.
- API selection is checked via live `GraphicsInfo.api`, not inferred from an
  environment variable. Compilation and visual smoke tests occur outside samples.
- A user page/visibility change aborts the sample and is preserved. Normal/error
  cleanup removes only the runner-owned runtime drop-in and restores the original
  page/visibility with the configured renderer. A forced kill still requires
  manual removal of that specific drop-in; do not delete unrelated overrides.

Raw [samples](benchmarks/2026-09-05-vulkan-comparison/results.jsonl),
[method](benchmarks/2026-09-05-vulkan-comparison/method.json), and
[trace](benchmarks/2026-09-05-vulkan-comparison/telemetry.json) are retained.

## Slide behavior and validation

`SlideReveal.qml` moves the whole fixed-size panel below the screen in 220ms,
with a restrained fade, and restores it in 260ms. It does not reflow widgets.
Repeated toggles reverse from the current position. A temporary layer groups
the fade correctly and is released when motion ends. Controls remain disabled
during motion; the window keeps its full input region until fully hidden, then
leaves only the restore handle interactive. Decorative presentation pauses during
motion/while hidden, but live services keep running.

Offscreen QML tests cover reversal, visibility, layout dimensions, layer release,
control gating, paging gutters and backend routing. Native OpenGL and Vulkan
fixtures exercise both heatmap layouts, color uploads, daylight, storm, fog,
rounded clipping, blur and slide/restore. The live dashboard renders correctly on
Vulkan. The live hidden check showed zero decorative-clock clients and unchanged
tick counts over three seconds; restoration resumed healthy services and motion.

Validation: 27 Rust tests, 52 existing Python/QML tests, 18 JavaScript tests,
Clippy with warnings denied, shell syntax and `git diff --check` passed.

## Reproduce or roll back

```bash
cargo build --release --locked --offline --manifest-path quickshell/aeris-backend/Cargo.toml --bin aeris-dashboard-benchmark
quickshell/aeris-backend/target/release/aeris-dashboard-benchmark --renderers "$PWD" settings/benchmarks/2026-09-05-vulkan-comparison/telemetry.json /tmp/aeris-new-renderer-comparison
bash scripts/run-dashboard.sh ipc call dashboard renderingStatus
```

The output directory must not already exist. The Rust runner reuses the retained
read-only profiler; no new Python runtime code was introduced.

For a persistent OpenGL fallback, use `systemctl --user edit aeris-dashboard.service`
to add a user override containing:

```ini
[Service]
Environment=QSG_RHI_BACKEND=opengl
```

Then reload user units and restart `aeris-dashboard.service`. Remove only that
setting to return to the Vulkan default. Setting an environment variable on an
IPC command alone cannot change the already-running renderer.

Qt references: [RHI/backend selection](https://doc.qt.io/qt-6.8/qtquick-visualcanvas-scenegraph-renderer.html),
[portable QSB shaders](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html),
[temporary layer costs](https://doc.qt.io/qt-6/qml-qtquick-item.html#memory-and-performance).
