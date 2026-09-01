# Hardware monitoring

## Installed tools

- `lm_sensors`: exposes CPU, GPU, NVMe, and other hardware sensors
- `stress-ng`: short CPU stability and thermal checks
- `vkmark`: lightweight Vulkan benchmark and GPU thermal check

Current hardware sensor mapping:

- CPU: AMD Ryzen 9 5950X, `cpu/all/averageTemperature`
- GPU: AMD Radeon RX 6900 XT, `gpu/gpu1/temperature`
- Storage: Samsung 990 PRO 1 TB and Lexar NM620 512 GB

## Plasma System Monitor

The Overview page keeps its existing CPU and GPU donut charts and adds a second
center value to each:

- CPU usage / average CPU temperature
- GPU usage / GPU edge temperature

The temperature value uses orange (`233,120,61`) to distinguish it from the
blue usage value. The restore script locates the CPU and GPU faces by title, so
it does not copy unrelated application state or hard-code Plasma face IDs.

Close Plasma System Monitor before applying the profile:

```bash
./scripts/apply-monitoring.sh
```

Verify without changing anything:

```bash
./scripts/apply-monitoring.sh --check
```

The script installs the three packages, backs up `overview.page` under
`~/.local/state/fedora-settings/backups/`, and patches the existing page. Open
System Monitor once before running it on a fresh installation so the default
Overview page exists.

The GPU sensor path is hardware-specific. If KDE enumerates the Radeon under a
different index after a hardware change, update `gpu_sensor` in the script.

## Reference thermal results

These are observations from this machine, not restore-time acceptance tests:

- Light background activity: CPU `Tctl` held around 53-54°C while `rsync`, Chrome,
  Plasma, and other processes were active. The system load average was about 3.16,
  so this was not true idle even though aggregate CPU usage appeared to be about
  5%. On the 32-thread Ryzen 9 5950X, 5% aggregate utilization can still represent
  roughly one or two busy, boosting cores and produce short localized temperature
  spikes.
- CPU: 60-second `stress-ng --cpu 0 --cpu-method all --verify` peaked at 77.2°C
- CPU lighting validation: a separate 30-second `stress-ng --cpu 16` run peaked
  at 71.6°C and visibly exercised the OpenRGB workload and temperature transitions
- GPU: two-minute 2560×1440 `vkmark` peaked at 52°C edge, 64°C junction, and
  56°C VRAM; this test drew only about 68 W and is not a maximum-power test

AMD specifies 90°C as the Ryzen 9 5950X maximum operating temperature (`Tjmax`):
<https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-5000-series/amd-ryzen-9-5950x.html>.
On this machine, temperatures in the low-to-mid 50s during light background work
are expected. Investigate sustained temperatures above roughly 55-60°C only after
confirming the system is genuinely idle, or normal heavy workloads approaching
85-90°C.
