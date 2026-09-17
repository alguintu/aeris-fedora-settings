//! One /proc/net/dev read per existing metrics tick. Physical links only, so
//! loopback, VPNs and container bridges do not count the same traffic twice.
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs, io,
    path::Path,
};

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub ok: bool,
    pub ready: bool,
    pub rx_bytes_per_second: f64,
    pub tx_bytes_per_second: f64,
    pub interfaces: Vec<String>,
}
type Counters = BTreeMap<String, (u64, u64)>;

fn parse(input: &str) -> io::Result<Counters> {
    let mut counters = BTreeMap::new();
    for line in input.lines().skip(2) {
        let Some((name, fields)) = line.split_once(':') else {
            continue;
        };
        let fields: Vec<_> = fields.split_whitespace().collect();
        if fields.len() < 16 {
            return Err(io::Error::other("Incomplete network counters"));
        }
        let number = |index: usize| fields[index].parse::<u64>().map_err(io::Error::other);
        counters.insert(name.trim().into(), (number(0)?, number(8)?));
    }
    Ok(counters)
}

#[derive(Default)]
pub struct Collector {
    previous: Option<(f64, Counters)>,
    physical: BTreeSet<String>,
    next_discovery: f64,
}
impl Collector {
    pub fn sample(&mut self, proc_dev: &Path, sys_net: &Path, now: f64) -> Snapshot {
        let counters = fs::read_to_string(proc_dev).and_then(|value| parse(&value));
        let Ok(mut counters) = counters else {
            self.previous = None;
            return Snapshot::default();
        };
        if self.previous.is_none() || now >= self.next_discovery {
            self.physical = counters
                .keys()
                .filter(|name| name.as_str() != "lo" && sys_net.join(name).join("device").exists())
                .cloned()
                .collect();
            self.next_discovery = now + 30.0;
        }
        counters.retain(|name, _| self.physical.contains(name));
        let mut snapshot = Snapshot {
            ok: true,
            interfaces: counters.keys().cloned().collect(),
            ..Snapshot::default()
        };
        if let Some((before, previous)) = &self.previous {
            let elapsed = now - before;
            // A stall/resume or clock discontinuity seeds a new baseline, never
            // renders a giant spike or divides by a nominal one-second interval.
            if elapsed > 0.0 && elapsed <= 5.0 {
                snapshot.ready = true;
                for (name, (rx, tx)) in &counters {
                    if let Some((old_rx, old_tx)) = previous.get(name)
                        && let (Some(rx), Some(tx)) =
                            (rx.checked_sub(*old_rx), tx.checked_sub(*old_tx))
                    {
                        snapshot.rx_bytes_per_second += rx as f64 / elapsed;
                        snapshot.tx_bytes_per_second += tx as f64 / elapsed;
                    }
                }
            }
        }
        self.previous = Some((now, counters));
        snapshot
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn row(name: &str, rx: u64, tx: u64) -> String {
        format!("{name}: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0\n")
    }
    #[test]
    fn physical_rates_baselines_reset_and_read_failure() {
        let dir = tempfile::tempdir().unwrap();
        let net = dir.path().join("net");
        fs::create_dir_all(net.join("eth0/device")).unwrap();
        let proc_dev = dir.path().join("dev");
        let write = |rx, tx| {
            fs::write(
                &proc_dev,
                format!(
                    "header\nheader\n{}{}{}",
                    row("eth0", rx, tx),
                    row("lo", rx * 9, tx * 9),
                    row("tun0", rx * 2, tx * 2)
                ),
            )
            .unwrap()
        };
        let mut collector = Collector::default();
        write(1000, 2000);
        assert!(!collector.sample(&proc_dev, &net, 0.0).ready);
        write(5000, 4000);
        let current = collector.sample(&proc_dev, &net, 2.0);
        assert!(current.ok && current.ready);
        assert_eq!(current.interfaces, vec!["eth0"]);
        assert_eq!(
            (current.rx_bytes_per_second, current.tx_bytes_per_second),
            (2000.0, 1000.0)
        );
        write(1, 1);
        assert_eq!(
            collector.sample(&proc_dev, &net, 3.0).rx_bytes_per_second,
            0.0
        );
        write(10000, 10000);
        assert!(!collector.sample(&proc_dev, &net, 100.0).ready);
        fs::write(&proc_dev, "header\nheader\neth0: invalid\n").unwrap();
        assert!(!collector.sample(&proc_dev, &net, 101.0).ok);
        write(20000, 20000);
        assert!(!collector.sample(&proc_dev, &net, 102.0).ready);
    }
    #[test]
    fn new_interface_starts_with_no_counter_spike() {
        let dir = tempfile::tempdir().unwrap();
        let net = dir.path().join("net");
        fs::create_dir_all(&net).unwrap();
        let proc_dev = dir.path().join("dev");
        let mut collector = Collector::default();
        fs::write(&proc_dev, "header\nheader\n").unwrap();
        collector.sample(&proc_dev, &net, 0.0);
        fs::create_dir_all(net.join("eth1/device")).unwrap();
        fs::write(
            &proc_dev,
            format!("header\nheader\n{}", row("eth1", 9000000, 5000000)),
        )
        .unwrap();
        let first = collector.sample(&proc_dev, &net, 30.0);
        assert_eq!(first.interfaces, vec!["eth1"]);
        assert_eq!(first.rx_bytes_per_second, 0.0);
        fs::write(&proc_dev, "header\nheader\n").unwrap();
        assert!(
            collector
                .sample(&proc_dev, &net, 31.0)
                .interfaces
                .is_empty()
        );
    }
}
