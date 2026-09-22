//! Read UDisks' existing SMART cache, never refresh SMART or wake a disk.
use crate::metrics::Drive;
use dbus::arg::PropMap;
use dbus::blocking::{Connection, stdintf::org_freedesktop_dbus::ObjectManager};
use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

type Objects = HashMap<dbus::Path<'static>, HashMap<String, PropMap>>;
type Readings = HashMap<String, Reading>;
const FILESYSTEM: &str = "org.freedesktop.UDisks2.Filesystem";
const BLOCK: &str = "org.freedesktop.UDisks2.Block";
const ATA: &str = "org.freedesktop.UDisks2.Drive.Ata";
const NVME: &str = "org.freedesktop.UDisks2.NVMe.Controller";

#[derive(Clone, Copy)]
struct Reading {
    celsius: f64,
    updated: u64,
}

fn reading(properties: &PropMap) -> Option<Reading> {
    let value = &properties.get("SmartTemperature")?.0;
    let kelvin = value
        .as_f64()
        .or_else(|| value.as_u64().map(|v| v as f64))?;
    let updated = properties.get("SmartUpdated")?.0.as_u64()?;
    let celsius = kelvin - 273.15;
    (updated != 0 && celsius.is_finite() && (-40.0..=150.0).contains(&celsius))
        .then_some(Reading { celsius, updated })
}

fn parse(objects: &Objects) -> Readings {
    let mut result = HashMap::new();
    for interfaces in objects.values() {
        let Some(mounts) = interfaces
            .get(FILESYSTEM)
            .and_then(|p| p.get("MountPoints"))
            .and_then(|v| v.0.as_iter())
        else {
            continue;
        };
        let Some(drive_path) = interfaces
            .get(BLOCK)
            .and_then(|p| p.get("Drive"))
            .and_then(|v| v.0.as_str())
        else {
            continue;
        };
        let Some(drive) = objects
            .iter()
            .find_map(|(path, v)| (&**path == drive_path).then_some(v))
        else {
            continue;
        };
        let Some(value) = drive.get(NVME).or_else(|| drive.get(ATA)).and_then(reading) else {
            continue;
        };
        // Resolve via mount points: Btrfs root's virtual device number does not
        // identify its physical disk, and kernel disk names can change on boot.
        for mount in mounts {
            let Some(bytes) = mount.as_iter() else {
                continue;
            };
            let bytes: Option<Vec<u8>> = bytes
                .map(|v| v.as_u64().and_then(|v| u8::try_from(v).ok()))
                .collect();
            let Some(mut bytes) = bytes else { continue };
            while bytes.last() == Some(&0) {
                bytes.pop();
            }
            if let Ok(path) = String::from_utf8(bytes) {
                result.insert(path, value);
            }
        }
    }
    result
}

fn fetch() -> Option<Readings> {
    let connection = Connection::new_system().ok()?;
    let proxy = connection.with_proxy(
        "org.freedesktop.UDisks2",
        "/org/freedesktop/UDisks2",
        Duration::from_millis(200),
    );
    let objects: Objects = proxy.get_managed_objects().ok()?;
    Some(parse(&objects))
}

#[derive(Default)]
pub struct Reader {
    readings: Readings,
    next_refresh: Option<f64>,
}

impl Reader {
    pub fn update(&mut self, drives: &mut [Drive], elapsed: f64) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        self.update_with(drives, elapsed, now, fetch);
    }

    fn update_with(
        &mut self,
        drives: &mut [Drive],
        elapsed: f64,
        now: u64,
        fetch: impl FnOnce() -> Option<Readings>,
    ) {
        if self.next_refresh.is_none_or(|deadline| elapsed >= deadline) {
            self.readings = fetch().unwrap_or_default();
            self.next_refresh = Some(elapsed + 60.0);
        }
        for drive in drives {
            drive.temperature = self
                .readings
                .get(drive.mount)
                .filter(|r| {
                    // UDisks can retain sleeping HDD readings for several minutes.
                    // Expire them rather than forcing device activity for the UI.
                    r.updated <= now && now - r.updated <= 30 * 60
                })
                .map(|r| r.celsius);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dbus::arg::{RefArg, Variant};

    fn properties(values: Vec<(&str, Box<dyn RefArg>)>) -> PropMap {
        values
            .into_iter()
            .map(|(key, value)| (key.into(), Variant(value)))
            .collect()
    }

    #[test]
    fn resolves_mounts_to_ata_and_nvme_with_kelvin_conversion() {
        let mut objects = Objects::new();
        for (index, interface, temp, mounts) in [
            (
                0,
                ATA,
                Box::new(308_f64) as Box<dyn RefArg>,
                vec![b"/mnt/storage\0".to_vec()],
            ),
            (
                1,
                NVME,
                Box::new(319_u16) as Box<dyn RefArg>,
                vec![b"/\0".to_vec(), b"/home\0".to_vec()],
            ),
        ] {
            let path = dbus::Path::new(format!("/drives/d{index}")).unwrap();
            objects.insert(
                path.clone(),
                HashMap::from([(
                    interface.into(),
                    properties(vec![
                        ("SmartTemperature", temp),
                        ("SmartUpdated", Box::new(100_u64)),
                    ]),
                )]),
            );
            objects.insert(
                dbus::Path::new(format!("/blocks/b{index}")).unwrap(),
                HashMap::from([
                    (BLOCK.into(), properties(vec![("Drive", Box::new(path))])),
                    (
                        FILESYSTEM.into(),
                        properties(vec![("MountPoints", Box::new(mounts))]),
                    ),
                ]),
            );
        }
        let result = parse(&objects);
        assert_eq!(result.len(), 3);
        assert_eq!(result["/"].celsius.round(), 46.0);
        assert_eq!(result["/home"].celsius.round(), 46.0);
        assert_eq!(result["/mnt/storage"].celsius.round(), 35.0);
    }

    #[test]
    fn unknown_and_invalid_smart_values_are_not_zero_celsius() {
        for (kelvin, updated) in [(0.0, 100), (310.0, 0), (f64::NAN, 100), (900.0, 100)] {
            assert!(
                reading(&properties(vec![
                    ("SmartTemperature", Box::new(kelvin)),
                    ("SmartUpdated", Box::new(updated as u64))
                ]))
                .is_none()
            );
        }
        assert!(parse(&Objects::new()).is_empty());
    }

    #[test]
    fn caches_for_a_minute_expires_old_data_and_clears_on_failure() {
        let mut reader = Reader::default();
        let mut drives = [Drive {
            label: "System",
            mount: "/",
            used: None,
            total: None,
            temperature: None,
        }];
        let cached = || {
            Some(HashMap::from([(
                "/".into(),
                Reading {
                    celsius: 35.0,
                    updated: 100,
                },
            )]))
        };
        reader.update_with(&mut drives, 0.0, 100, cached);
        assert_eq!(drives[0].temperature, Some(35.0));
        reader.update_with(&mut drives, 59.0, 159, || panic!("must use cache"));
        reader.update_with(&mut drives, 60.0, 160, || None);
        assert_eq!(drives[0].temperature, None);
        reader.update_with(&mut drives, 120.0, 1901, cached);
        assert_eq!(drives[0].temperature, None);
        reader.update_with(&mut drives, 180.0, 99, cached);
        assert_eq!(drives[0].temperature, None);
    }
}
