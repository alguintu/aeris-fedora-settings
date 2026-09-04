use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};

struct Fixture {
    root: PathBuf,
    paths: Paths,
}
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let root = loop {
            let path = std::env::temp_dir().join(format!(
                "aeris-metrics-test-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(e) => panic!("{e}"),
            }
        };
        let paths = Paths {
            proc_stat: root.join("stat"),
            meminfo: root.join("meminfo"),
            mountinfo: root.join("mountinfo"),
            cpu: root.join("cpu"),
            hwmon: root.join("hwmon"),
            drm: root.join("drm"),
        };
        let fixture = Self { root, paths };
        fixture.write(
            "meminfo",
            "MemTotal: 67108864 kB\nMemAvailable: 50331648 kB\n",
        );
        fixture.write("mountinfo", "1 0 0:1 / / rw - btrfs /dev/test rw\n");
        fixture.write("hwmon/hwmon0/name", "k10temp");
        fixture.write("hwmon/hwmon0/temp1_label", "Tctl");
        fixture.write("hwmon/hwmon0/temp1_input", "44000");
        fixture.write("hwmon/hwmon1/name", "amdgpu");
        fixture.write("hwmon/hwmon1/temp1_label", "edge");
        fixture.write("hwmon/hwmon1/temp1_input", "45000");
        fixture.write("hwmon/hwmon1/temp2_label", "junction");
        fixture.write("hwmon/hwmon1/temp2_input", "55000");
        for (file, value) in [
            ("gpu_busy_percent", "1"),
            ("mem_info_vram_used", "1073741824"),
            ("mem_info_vram_total", "17179869184"),
        ] {
            fixture.write(&format!("drm/card0/device/{file}"), value);
        }
        for id in 0..32 {
            let core = id % 16;
            fixture.write(
                &format!("cpu/cpu{id}/topology/thread_siblings_list"),
                &format!("{core},{}", core + 16),
            );
            fixture.write(&format!("cpu/cpu{id}/topology/core_id"), &core.to_string());
            fixture.write(
                &format!("cpu/cpu{id}/cache/index3/shared_cpu_list"),
                if core < 8 { "0-7,16-23" } else { "8-15,24-31" },
            );
            fixture.write(
                &format!("cpu/cpu{id}/cpufreq/cpuinfo_avg_freq"),
                if id == 31 { "4500000" } else { "3400000" },
            );
            fixture.write(&format!("cpu/cpu{id}/cpufreq/scaling_cur_freq"), "4900000");
        }
        fixture
    }
    fn write(&self, relative: &str, value: &str) {
        let path = self.root.join(relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, value).unwrap();
    }
    fn samples(busy: bool) -> (CpuSamples, CpuSamples) {
        let previous = CpuSamples {
            aggregate: Counter {
                total: 1000,
                idle: 900,
            },
            threads: (0..32)
                .map(|id| {
                    (
                        id,
                        Counter {
                            total: 100,
                            idle: 90,
                        },
                    )
                })
                .collect(),
        };
        let current = CpuSamples {
            aggregate: Counter {
                total: 1100,
                idle: 998,
            },
            threads: (0..32)
                .map(|id| {
                    (
                        id,
                        Counter {
                            total: 200,
                            idle: if id == 31 && busy { 100 } else { 188 },
                        },
                    )
                })
                .collect(),
        };
        (previous, current)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.root).unwrap();
    }
}

#[test]
fn parses_shared_counter_read_and_defends_against_reset() {
    let samples = CpuSamples::parse("cpu 10 0 10 80 5\ncpu0 10 0 10 80 5\nintr 123\n").unwrap();
    assert_eq!(samples.aggregate.total, 105);
    assert_eq!(samples.aggregate.idle, 85);
    assert_eq!(samples.threads.len(), 1);
    assert_eq!(
        usage(
            Counter { total: 0, idle: 0 },
            Counter {
                total: 100,
                idle: 80
            }
        ),
        20.0
    );
    assert_eq!(
        usage(
            Counter {
                total: 100,
                idle: 90
            },
            Counter {
                total: 50,
                idle: 40
            }
        ),
        0.0
    );
    assert!(CpuSamples::parse("cpu oops").is_err());
    assert!(CpuSamples::parse("cpu0 1 2 3 4").is_err());
}

#[test]
fn cpu_list_ranges_and_invalid_data() {
    assert_eq!(cpu_list("0-2,16-18"), Some(vec![0, 1, 2, 16, 17, 18]));
    assert_eq!(cpu_list("2-1"), None);
    assert_eq!(cpu_list(""), None);
    assert_eq!(cpu_list("0-4294967295"), None);
}

#[test]
fn temperature_idle_busy_hold_and_failed_read() {
    let mut poll = TemperaturePoll::<1>::default();
    let mut reads = 0;
    for now in 0..4 {
        poll.sample(now as f64, false, || {
            reads += 1;
            [Some(42.0)]
        });
    }
    assert_eq!(reads, 2);
    poll.sample(4.0, true, || {
        reads += 1;
        [Some(43.0)]
    });
    for now in 5..13 {
        poll.sample(now as f64, false, || {
            reads += 1;
            [Some(43.0)]
        });
    }
    assert_eq!(reads, 9);
    assert_eq!(poll.sample(13.0, false, || [None]), [None]);
}

#[test]
fn disk_deduplication_unmounted_drives_and_escaped_names() {
    let input = "1 0 0:1 / / rw - btrfs /dev/a rw\n2 0 0:1 /home /home rw - btrfs /dev/a rw\n3 0 0:2 / /mnt/workspace rw - ext4 /dev/b rw\n4 0 0:3 / /mnt/other\\040disk rw - ext4 /dev/c rw\n5 0 0:4 / /proc rw - proc proc rw\n";
    let mut paths = Vec::new();
    let disks = Disks::parse(input, |path| {
        paths.push(path.to_owned());
        Some(Space {
            total: 100,
            free: 40,
            available: 35,
        })
    });
    assert_eq!(paths, ["/", "/mnt/workspace", "/mnt/other disk"]);
    assert_eq!(disks.mounted_disk_total, Some(300));
    assert_eq!(disks.mounted_disk_free, Some(105));
    assert_eq!(disks.drives[0].used, Some(60));
    assert_eq!(disks.drives[2].used, None);
    let failed = Disks::parse(input, |_| None);
    assert_eq!(failed.mounted_disk_total, None);
    assert_eq!(failed.drives[0].total, None);
}

#[test]
fn full_layout_contract_busiest_core_clock_and_static_discovery() {
    let fixture = Fixture::new();
    let mut collector = Collector::new(fixture.paths.clone());
    let (previous, current) = Fixture::samples(true);
    let sample = collector.collect(&previous, &current, 0.0).unwrap();
    assert_eq!(sample.cpu_clock, Some(4.5)); // selected core, not 32-core mean or requested 4.9
    assert_eq!(sample.cpu_ccds.len(), 2);
    assert!(
        sample
            .cpu_ccds
            .iter()
            .all(|ccd| ccd.len() == 8 && ccd.iter().all(|core| core.len() == 2))
    );
    assert_eq!(sample.cpu_ccds[1][7], [2.0, 90.0]);
    assert_eq!(sample.ram_used, 16 * 1024 * 1024 * 1024);
    assert_eq!(sample.vram_total, Some(16.0 * 1024.0 * 1024.0 * 1024.0));
    // Labels/static VRAM total are not reread during healthy collection.
    fixture.write("hwmon/hwmon0/temp1_label", "wrong");
    fixture.write("drm/card0/device/mem_info_vram_total", "1");
    let next = collector.collect(&previous, &current, 1.0).unwrap();
    assert_eq!(next.cpu_temp, Some(44.0));
    assert_eq!(next.vram_total, sample.vram_total);
    let json = serde_json::to_value(next).unwrap();
    assert!(json.get("cpuCcds").is_some());
    assert!(json.get("gpuHotspot").is_some());
    for unused in ["rootUsed", "rootTotal", "physicalDiskTotal"] {
        assert!(json.get(unused).is_none());
    }
}

#[test]
fn busy_thread_escalates_only_cpu_and_gpu_load_escalates_both_gpu_sensors() {
    let fixture = Fixture::new();
    let mut collector = Collector::new(fixture.paths.clone());
    let (previous, idle) = Fixture::samples(false);
    collector.collect(&previous, &idle, 0.0).unwrap();
    fixture.write("hwmon/hwmon0/temp1_input", "51000");
    fixture.write("hwmon/hwmon1/temp1_input", "52000");
    fixture.write("hwmon/hwmon1/temp2_input", "63000");
    let (_, busy) = Fixture::samples(true);
    let sample = collector.collect(&previous, &busy, 1.0).unwrap();
    assert_eq!(sample.cpu_temp, Some(51.0));
    assert_eq!(sample.gpu_temp, Some(45.0));
    fixture.write("drm/card0/device/gpu_busy_percent", "99");
    let sample = collector.collect(&previous, &idle, 2.0).unwrap();
    assert_eq!(sample.gpu_temp, Some(52.0));
    assert_eq!(sample.gpu_hotspot, Some(63.0));
}

#[test]
fn disk_cache_expires_at_sixty_seconds() {
    let fixture = Fixture::new();
    let mut collector = Collector::new(fixture.paths.clone());
    let (previous, current) = Fixture::samples(false);
    assert!(
        collector
            .collect(&previous, &current, 0.0)
            .unwrap()
            .disks
            .mounted_disk_total
            .is_some()
    );
    fixture.write("mountinfo", "");
    assert!(
        collector
            .collect(&previous, &current, 59.0)
            .unwrap()
            .disks
            .mounted_disk_total
            .is_some()
    );
    assert!(
        collector
            .collect(&previous, &current, 60.0)
            .unwrap()
            .disks
            .mounted_disk_total
            .is_none()
    );
}

#[test]
fn missing_frequency_re_discovers_fallback_at_thirty_seconds() {
    let fixture = Fixture::new();
    let mut collector = Collector::new(fixture.paths.clone());
    let (previous, current) = Fixture::samples(true);
    collector.collect(&previous, &current, 0.0).unwrap();
    fs::remove_file(fixture.root.join("cpu/cpu31/cpufreq/cpuinfo_avg_freq")).unwrap();
    assert_eq!(
        collector
            .collect(&previous, &current, 1.0)
            .unwrap()
            .cpu_clock,
        None
    );
    assert_eq!(
        collector
            .collect(&previous, &current, 29.0)
            .unwrap()
            .cpu_clock,
        None
    );
    assert_eq!(
        collector
            .collect(&previous, &current, 30.0)
            .unwrap()
            .cpu_clock,
        Some(4.9)
    );
}

#[test]
fn invalid_sensor_is_unknown_not_zero_and_bad_memory_is_error() {
    let fixture = Fixture::new();
    fixture.write("drm/card0/device/gpu_busy_percent", "NaN");
    let mut collector = Collector::new(fixture.paths.clone());
    let (previous, current) = Fixture::samples(false);
    assert_eq!(
        collector
            .collect(&previous, &current, 0.0)
            .unwrap()
            .gpu_usage,
        None
    );
    fixture.write("meminfo", "MemTotal: oops kB");
    assert!(collector.collect(&previous, &current, 1.0).is_err());
}
