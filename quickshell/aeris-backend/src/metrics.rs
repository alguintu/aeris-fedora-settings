//! Dashboard telemetry only. Does not change clocks, cooling or device settings.
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug)]
pub struct Paths {
    pub proc_stat: PathBuf,
    pub meminfo: PathBuf,
    pub mountinfo: PathBuf,
    pub cpu: PathBuf,
    pub drm: PathBuf,
    pub hwmon: PathBuf,
}

impl Default for Paths {
    fn default() -> Self {
        Self {
            proc_stat: "/proc/stat".into(),
            meminfo: "/proc/meminfo".into(),
            mountinfo: "/proc/self/mountinfo".into(),
            cpu: "/sys/devices/system/cpu".into(),
            drm: "/sys/class/drm".into(),
            hwmon: "/sys/class/hwmon".into(),
        }
    }
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn text(path: impl AsRef<Path>) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_owned())
}
fn number(path: &Path) -> Option<f64> {
    text(path)?.parse::<f64>().ok().filter(|n| n.is_finite())
}
fn children(path: &Path) -> Vec<PathBuf> {
    let mut paths: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|e| e.path())
        .collect();
    paths.sort();
    paths
}
fn numbered(path: &Path, prefix: &str) -> Option<u32> {
    let suffix = path.file_name()?.to_str()?.strip_prefix(prefix)?;
    if suffix.is_empty() || !suffix.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    suffix.parse().ok()
}
fn rounded(value: f64, factor: f64) -> f64 {
    (value * factor).round_ties_even() / factor
}

#[derive(Clone, Copy, Debug)]
pub struct Counter {
    pub total: u64,
    pub idle: u64,
}
#[derive(Clone, Debug)]
pub struct CpuSamples {
    pub aggregate: Counter,
    pub threads: BTreeMap<u32, Counter>,
}

impl CpuSamples {
    pub fn read(path: &Path) -> io::Result<Self> {
        Self::parse(&fs::read_to_string(path)?)
    }
    pub fn parse(input: &str) -> io::Result<Self> {
        let mut aggregate = None;
        let mut threads = BTreeMap::new();
        for line in input.lines() {
            let mut fields = line.split_whitespace();
            let Some(name) = fields.next() else {
                continue;
            };
            if name != "cpu" && numbered(Path::new(name), "cpu").is_none() {
                break;
            }
            let values: Vec<u64> = fields
                .map(str::parse)
                .collect::<Result<_, _>>()
                .map_err(|_| invalid("Invalid CPU counter"))?;
            if values.len() < 4 {
                return Err(invalid("Incomplete CPU counters"));
            }
            let total = values
                .iter()
                .try_fold(0u64, |sum, n| sum.checked_add(*n))
                .ok_or_else(|| invalid("CPU counter overflow"))?;
            let idle = values[3].saturating_add(*values.get(4).unwrap_or(&0));
            let sample = Counter { total, idle };
            if name == "cpu" {
                aggregate = Some(sample);
            } else if let Some(id) = numbered(Path::new(name), "cpu") {
                threads.insert(id, sample);
            }
        }
        Ok(Self {
            aggregate: aggregate.ok_or_else(|| invalid("Missing aggregate CPU counter"))?,
            threads,
        })
    }
}

pub fn usage(previous: Counter, current: Counter) -> f64 {
    let Some(total) = current.total.checked_sub(previous.total).filter(|n| *n > 0) else {
        return 0.0;
    };
    let Some(idle) = current.idle.checked_sub(previous.idle) else {
        return 0.0;
    };
    rounded(
        (100.0 * (total.saturating_sub(idle)) as f64 / total as f64).clamp(0.0, 100.0),
        10.0,
    )
}

pub fn cpu_list(input: &str) -> Option<Vec<u32>> {
    let mut cpus = Vec::new();
    for part in input.trim().split(',') {
        if let Some((a, b)) = part.split_once('-') {
            let (a, b): (u32, u32) = (a.parse().ok()?, b.parse().ok()?);
            if b < a || b - a > 65536 {
                return None;
            }
            cpus.extend(a..=b);
        } else {
            cpus.push(part.parse().ok()?);
        }
    }
    cpus.sort_unstable();
    cpus.dedup();
    Some(cpus)
}

fn topology(root: &Path) -> Vec<Vec<Vec<u32>>> {
    let mut groups: BTreeMap<Vec<u32>, BTreeMap<u32, Vec<u32>>> = BTreeMap::new();
    for path in children(root) {
        let Some(id) = numbered(&path, "cpu") else {
            continue;
        };
        let siblings = text(path.join("topology/thread_siblings_list"))
            .and_then(|s| cpu_list(&s))
            .unwrap_or(vec![id]);
        if siblings.first() != Some(&id) {
            continue;
        }
        let l3 = text(path.join("cache/index3/shared_cpu_list"))
            .and_then(|s| cpu_list(&s))
            .unwrap_or_else(|| siblings.clone());
        let core = text(path.join("topology/core_id"))
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(id);
        groups.entry(l3).or_default().insert(core, siblings);
    }
    groups
        .into_values()
        .map(|cores| cores.into_values().collect())
        .collect()
}

fn memory(path: &Path) -> io::Result<(u64, u64)> {
    let mut total = None;
    let mut available = None;
    for line in fs::read_to_string(path)?.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        if key != "MemTotal" && key != "MemAvailable" {
            continue;
        }
        let bytes = value
            .split_whitespace()
            .next()
            .and_then(|s| s.parse::<u64>().ok())
            .and_then(|n| n.checked_mul(1024));
        if key == "MemTotal" {
            total = bytes;
        } else {
            available = bytes;
        }
    }
    match (total, available) {
        (Some(total), Some(available)) => Ok((total.saturating_sub(available), total)),
        _ => Err(invalid("Missing RAM counters")),
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Space {
    pub total: u64,
    pub free: u64,
    pub available: u64,
}
#[derive(Clone, Debug, Serialize)]
pub struct Drive {
    pub label: &'static str,
    pub mount: &'static str,
    pub used: Option<u64>,
    pub total: Option<u64>,
}
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Disks {
    pub mounted_disk_total: Option<u64>,
    pub mounted_disk_free: Option<u64>,
    pub drives: Vec<Drive>,
}

pub fn unescape_mount(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut result = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && i + 3 < bytes.len()
            && bytes[i + 1..i + 4]
                .iter()
                .all(|b| (b'0'..=b'7').contains(b))
        {
            let octal = (bytes[i + 1] - b'0') as u16 * 64
                + (bytes[i + 2] - b'0') as u16 * 8
                + (bytes[i + 3] - b'0') as u16;
            if octal <= 255 {
                result.push(octal as u8);
                i += 4;
                continue;
            }
        }
        result.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&result).into_owned()
}

impl Disks {
    pub fn parse(input: &str, mut stat: impl FnMut(&str) -> Option<Space>) -> Self {
        let mut filesystems: BTreeMap<(String, String), Option<Space>> = BTreeMap::new();
        let mut mounts = BTreeMap::new();
        let (mut total, mut available, mut complete) = (0u64, 0u64, true);
        for line in input.lines() {
            let Some((before, after)) = line.split_once(" - ") else {
                complete = false;
                continue;
            };
            let before: Vec<_> = before.split_whitespace().collect();
            let after: Vec<_> = after.split_whitespace().collect();
            if before.len() < 5 || after.len() < 2 {
                complete = false;
                continue;
            }
            if !after[1].starts_with("/dev/") {
                continue;
            }
            let key = (after[0].to_owned(), before[2].to_owned());
            let mount = unescape_mount(before[4]);
            let space = *filesystems.entry(key).or_insert_with(|| {
                let space = stat(&mount);
                if let Some(space) = space {
                    total = total.saturating_add(space.total);
                    available = available.saturating_add(space.available);
                } else {
                    complete = false;
                }
                space
            });
            mounts.insert(mount, space);
        }
        let drives = [
            ("System", "/"),
            ("Workspace", "/mnt/workspace"),
            ("Documents", "/mnt/documents"),
            ("Storage", "/mnt/storage"),
        ]
        .into_iter()
        .map(|(label, mount)| {
            let space = mounts.get(mount).copied().flatten();
            Drive {
                label,
                mount,
                used: space.map(|s| s.total.saturating_sub(s.free)),
                total: space.map(|s| s.total),
            }
        })
        .collect();
        Self {
            mounted_disk_total: (complete && total > 0).then_some(total),
            mounted_disk_free: (complete && total > 0).then_some(available),
            drives,
        }
    }
    fn read(path: &Path) -> Self {
        Self::parse(&fs::read_to_string(path).unwrap_or_default(), |mount| {
            let stats = rustix::fs::statvfs(mount).ok()?;
            Some(Space {
                total: stats.f_blocks.checked_mul(stats.f_frsize)?,
                free: stats.f_bfree.checked_mul(stats.f_frsize)?,
                available: stats.f_bavail.checked_mul(stats.f_frsize)?,
            })
        })
    }
}

fn hwmon(root: &Path, driver: &str) -> Option<PathBuf> {
    children(root)
        .into_iter()
        .find(|p| text(p.join("name")).as_deref() == Some(driver))
}
fn temperature_path(root: Option<&Path>, label: &str) -> Option<PathBuf> {
    children(root?)
        .into_iter()
        .find(|p| {
            p.file_name()
                .and_then(|s| s.to_str())
                .is_some_and(|s| s.starts_with("temp") && s.ends_with("_label"))
                && text(p).as_deref() == Some(label)
        })
        .map(|p| {
            p.with_file_name(
                p.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .replace("_label", "_input"),
            )
        })
}

pub struct TemperaturePoll<const N: usize> {
    last_read: f64,
    busy_until: f64,
    values: [Option<f64>; N],
}
impl<const N: usize> Default for TemperaturePoll<N> {
    fn default() -> Self {
        Self {
            last_read: f64::NEG_INFINITY,
            busy_until: f64::NEG_INFINITY,
            values: [None; N],
        }
    }
}
impl<const N: usize> TemperaturePoll<N> {
    pub fn sample(
        &mut self,
        now: f64,
        busy: bool,
        mut read: impl FnMut() -> [Option<f64>; N],
    ) -> [Option<f64>; N] {
        if busy {
            self.busy_until = now + 6.0;
        }
        let interval = if now <= self.busy_until { 1.0 } else { 3.0 };
        if now - self.last_read >= interval {
            self.values = read();
            self.last_read = now;
        }
        self.values
    }
}

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub cpu_usage: f64,
    pub cpu_ccds: Vec<Vec<Vec<f64>>>,
    pub cpu_clock: Option<f64>,
    pub cpu_temp: Option<f64>,
    pub gpu_usage: Option<f64>,
    pub gpu_temp: Option<f64>,
    pub gpu_hotspot: Option<f64>,
    pub vram_used: Option<f64>,
    pub vram_total: Option<f64>,
    pub ram_used: u64,
    pub ram_total: u64,
    #[serde(flatten)]
    pub disks: Disks,
    pub timestamp: u64,
}

pub struct Collector {
    pub paths: Paths,
    topology: Vec<Vec<Vec<u32>>>,
    cpu_temp: TemperaturePoll<1>,
    gpu_temp: TemperaturePoll<2>,
    cpu_path: Option<PathBuf>,
    gpu_paths: [Option<PathBuf>; 2],
    device: Option<PathBuf>,
    clock_paths: BTreeMap<u32, PathBuf>,
    vram_total: Option<f64>,
    needs_discovery: bool,
    next_discovery: f64,
    next_disk: f64,
    disks: Disks,
}
impl Collector {
    pub fn new(paths: Paths) -> Self {
        Self {
            topology: topology(&paths.cpu),
            paths,
            cpu_temp: TemperaturePoll::default(),
            gpu_temp: TemperaturePoll::default(),
            cpu_path: None,
            gpu_paths: [None, None],
            device: None,
            clock_paths: BTreeMap::new(),
            vram_total: None,
            needs_discovery: true,
            next_discovery: f64::NEG_INFINITY,
            next_disk: f64::NEG_INFINITY,
            disks: Disks::parse("", |_| None),
        }
    }
    fn discover(&mut self, now: f64) {
        self.cpu_path = temperature_path(hwmon(&self.paths.hwmon, "k10temp").as_deref(), "Tctl");
        let gpu = hwmon(&self.paths.hwmon, "amdgpu");
        self.gpu_paths = [
            temperature_path(gpu.as_deref(), "edge"),
            temperature_path(gpu.as_deref(), "junction"),
        ];
        self.device = children(&self.paths.drm)
            .into_iter()
            .filter(|p| numbered(p, "card").is_some())
            .map(|p| p.join("device"))
            .find(|p| p.join("gpu_busy_percent").exists());
        self.vram_total = self
            .device
            .as_ref()
            .and_then(|p| number(&p.join("mem_info_vram_total")));
        self.clock_paths.clear();
        for cpu in children(&self.paths.cpu) {
            let Some(id) = numbered(&cpu, "cpu") else {
                continue;
            };
            for source in ["cpuinfo_avg_freq", "scaling_cur_freq"] {
                let path = cpu.join("cpufreq").join(source);
                if path.exists() {
                    self.clock_paths.insert(id, path);
                    break;
                }
            }
        }
        self.needs_discovery = false;
        self.next_discovery = now + 30.0;
    }
    pub fn collect(
        &mut self,
        previous: &CpuSamples,
        current: &CpuSamples,
        now: f64,
    ) -> io::Result<Snapshot> {
        if self.needs_discovery && now >= self.next_discovery {
            self.discover(now);
        }
        let cpu_usage = usage(previous.aggregate, current.aggregate);
        let threads: BTreeMap<_, _> = current
            .threads
            .iter()
            .filter_map(|(id, value)| {
                previous
                    .threads
                    .get(id)
                    .map(|prev| (*id, usage(*prev, *value)))
            })
            .collect();
        let busiest = threads
            .iter()
            .filter(|(id, _)| self.clock_paths.contains_key(id))
            .max_by(|(id_a, a), (id_b, b)| a.total_cmp(b).then_with(|| id_b.cmp(id_a)));
        // Read exactly one policy's hardware clock, selected using existing CPU counters.
        let cpu_clock = busiest
            .and_then(|(id, _)| number(&self.clock_paths[id]))
            .filter(|n| *n > 0.0)
            .map(|n| rounded(n / 1_000_000.0, 100.0));
        let gpu_usage = self
            .device
            .as_ref()
            .and_then(|p| number(&p.join("gpu_busy_percent")));
        let vram_used = self
            .device
            .as_ref()
            .and_then(|p| number(&p.join("mem_info_vram_used")));
        let cpu_temps = self.cpu_temp.sample(
            now,
            cpu_usage >= 10.0 || threads.values().any(|v| *v >= 50.0),
            || {
                [self
                    .cpu_path
                    .as_ref()
                    .and_then(|p| number(p))
                    .map(|n| n / 1000.0)]
            },
        );
        let gpu_temps = self
            .gpu_temp
            .sample(now, gpu_usage.unwrap_or(0.0) >= 10.0, || {
                self.gpu_paths
                    .each_ref()
                    .map(|p| p.as_ref().and_then(|p| number(p)).map(|n| n / 1000.0))
            });
        self.needs_discovery = [
            cpu_clock,
            gpu_usage,
            vram_used,
            self.vram_total,
            cpu_temps[0],
            gpu_temps[0],
            gpu_temps[1],
        ]
        .iter()
        .any(Option::is_none);
        if now >= self.next_disk {
            self.disks = Disks::read(&self.paths.mountinfo);
            self.next_disk = now + 60.0;
        }
        let (ram_used, ram_total) = memory(&self.paths.meminfo)?;
        let cpu_ccds = self
            .topology
            .iter()
            .map(|ccd| {
                ccd.iter()
                    .map(|core| {
                        core.iter()
                            .map(|id| *threads.get(id).unwrap_or(&0.0))
                            .collect()
                    })
                    .collect()
            })
            .collect();
        Ok(Snapshot {
            cpu_usage,
            cpu_ccds,
            cpu_clock,
            cpu_temp: cpu_temps[0],
            gpu_usage,
            gpu_temp: gpu_temps[0],
            gpu_hotspot: gpu_temps[1],
            vram_used,
            vram_total: self.vram_total,
            ram_used,
            ram_total,
            disks: self.disks.clone(),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        })
    }
}

#[cfg(test)]
#[path = "metrics_tests.rs"]
mod tests;
