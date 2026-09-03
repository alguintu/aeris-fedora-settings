# Efficiency baseline and test log

Use the same workload, resolution, graphics settings, ambient conditions, and
duration when comparing profiles. Wall power requires an external meter and
must be entered manually. Idle readings are context, not a substitute for a
controlled full-load baseline.

## Initial observations

| Date | Profile/workload | CPU peak | GPU edge | GPU junction | GPU power | GPU fan | Result |
|---|---|---:|---:|---:|---:|---:|---|
| Earlier | Stock, 60 s stress-ng | 77.2°C | — | — | — | — | Passed short check |
| Earlier | Stock, 2 min vkmark | — | 52°C | 64°C | ~68 W | — | Not a full-load test |
| 2026-09-01 | Stock, point-in-time desktop reading | 48.1°C | 47°C | 55°C | 24-25 W | 0 RPM | Not controlled idle |
| 2026-09-01 | Stock, mprep combined CPU+GPU, ~1 min | 75.6°C | 68°C | 88°C | 258.8 W loaded avg / 272 W peak | 1912 RPM peak | No failure observed during capture |

Stock GPU cap was 272 W, with a driver-exposed range of 231-272 W.

## Controlled test log

| Date | Component/profile | Workload and duration | Ambient | Peak temperatures | Avg/peak power | Wall power | Score/FPS | Fan RPM/noise | Stability |
|---|---|---|---:|---|---|---:|---|---|---|
| TBD | GPU stock | Synthetic, 15 min | — | — | — | — | — | — | — |
| TBD | GPU stock | Real workload, 15+ min | — | — | — | — | — | — | — |
| TBD | GPU 231 W, stock voltage/clocks | Synthetic, 15 min | — | — | — | — | — | — | — |
| TBD | GPU 231 W, stock voltage/clocks | Real workload, 15+ min | — | — | — | — | — | — | — |
| TBD | CPU 120/80/120, CO -10 | stress-ng, 10 min | — | — | — | — | metrics | — | — |

The combined mprep run produced 62 samples at 80% or greater GPU load between
23:22:37 and 23:23:46 +08:00. Loaded averages were 74.0°C CPU Tctl, 65.4°C GPU
edge, and 83.8°C GPU junction. This short run establishes a useful stock power
and thermal reference but is not a stability qualification. The external PDU
meter ranged from 690-705 W during the test. That reading includes the PC, a
55-inch TV used as the monitor, and small network peripherals, so it is recorded
as whole-PDU AC draw rather than PC-only wall power. Use the same connected PDU
load for later profile comparisons, or meter the PC separately before treating
the value as system power.

For the GPU decision, compare performance per watt as `score / average GPU W`
and reject a profile for any reset, corruption, crash, black screen, freeze, or
unexpected performance loss. Validate CPU and GPU together only after each is
stable independently.
