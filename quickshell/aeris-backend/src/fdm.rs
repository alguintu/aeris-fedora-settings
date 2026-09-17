//! Read-only FDM monitor. Its tiny in-process QML adapter retains the stock UI;
//! this Rust host owns the private transport, validation and stable UI slots.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

const APP: &str = "org.freedownloadmanager.Manager";
const PREFIX: &[u8] = b"qml: AERIS_FDM_STATE ";
const MAX_LINE: usize = 65536;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Download {
    id: String,
    title: String,
    size: Option<f64>,
    downloaded: Option<f64>,
    speed: Option<f64>,
    running: bool,
}

#[derive(Deserialize, Serialize)]
struct Snapshot {
    version: u32,
    downloads: Vec<Download>,
    #[serde(default, rename = "completedCount")]
    completed_count: Option<u32>,
}

fn parse(bytes: &[u8]) -> Option<Snapshot> {
    if bytes.len() > MAX_LINE {
        return None;
    }
    let mut snapshot: Snapshot = serde_json::from_slice(bytes).ok()?;
    if snapshot.version != 1 || snapshot.downloads.len() > 1024 {
        return None;
    }
    snapshot.downloads.retain(|d| {
        d.running
            && !d.id.is_empty()
            && d.id.len() <= 32
            && d.id.bytes().all(|c| c.is_ascii_digit())
    });
    let mut ids = std::collections::HashSet::new();
    snapshot.downloads.retain(|d| ids.insert(d.id.clone()));
    for row in &mut snapshot.downloads {
        row.title = row
            .title
            .chars()
            .filter(|c| !c.is_control())
            .take(240)
            .collect();
        for number in [&mut row.size, &mut row.downloaded, &mut row.speed] {
            *number = number.filter(|v| v.is_finite() && *v >= 0.0);
        }
    }
    Some(snapshot)
}

fn runtime_dir() -> io::Result<PathBuf> {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| io::Error::other("XDG_RUNTIME_DIR is not set"))?;
    let path = PathBuf::from(base).join("aeris-fdm");
    match fs::DirBuilder::new().mode(0o700).create(&path) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(e),
    }
    Ok(path)
}

fn save(path: &Path, snapshot: &Snapshot) -> io::Result<()> {
    let mut file = tempfile::NamedTempFile::new_in(path.parent().unwrap())?;
    serde_json::to_writer(file.as_file_mut(), snapshot)?;
    file.flush()?;
    file.persist(path).map_err(|e| e.error)?;
    Ok(())
}

#[derive(Default)]
pub struct Reader {
    slots: [Option<String>; 4],
}

impl Reader {
    pub fn status(&mut self) -> Value {
        let path = runtime_dir().map(|p| p.join("state.json"));
        self.read(path.as_deref().ok())
    }

    fn read(&mut self, path: Option<&Path>) -> Value {
        let snapshot = path.and_then(|p| {
            let metadata = fs::metadata(p).ok()?;
            if metadata.len() > MAX_LINE as u64
                || metadata.modified().ok()?.elapsed().ok()? > Duration::from_secs(5)
            {
                return None;
            }
            parse(&fs::read(p).ok()?)
        });
        let Some(snapshot) = snapshot else {
            self.slots = Default::default();
            return json!({"ok": false, "slots": [null, null, null, null]});
        };
        self.assign(snapshot)
    }

    fn assign(&mut self, snapshot: Snapshot) -> Value {
        for slot in &mut self.slots {
            if !snapshot
                .downloads
                .iter()
                .any(|d| Some(&d.id) == slot.as_ref())
            {
                *slot = None;
            }
        }
        for download in &snapshot.downloads {
            if self.slots.iter().any(|s| s.as_ref() == Some(&download.id)) {
                continue;
            }
            if let Some(slot) = self.slots.iter_mut().find(|s| s.is_none()) {
                *slot = Some(download.id.clone());
            }
        }
        let rows: Vec<Value> = self
            .slots
            .iter()
            .map(|slot| {
                let Some(d) = snapshot
                    .downloads
                    .iter()
                    .find(|d| Some(&d.id) == slot.as_ref())
                else {
                    return Value::Null;
                };
                let progress = d
                    .size
                    .filter(|s| *s > 0.0)
                    .zip(d.downloaded)
                    .map(|(s, b)| (b / s).clamp(0.0, 1.0));
                json!({"id": d.id, "title": d.title, "progress": progress,
                "indeterminate": progress.is_none(), "speed": d.speed.unwrap_or(0.0)})
            })
            .collect();
        let download_bytes_per_second: f64 =
            snapshot.downloads.iter().filter_map(|d| d.speed).sum();
        json!({"ok": true, "slots": rows, "activeCount": snapshot.downloads.len(),
            "completedCount": snapshot.completed_count,
            "downloadBytesPerSecond": download_bytes_per_second})
    }
}

// Export only explicitly opened files through the document portal. Magnet and
// web links pass through unchanged; no broad filesystem permission is needed.
fn append_open_targets(command: &mut Command, args: &[String]) {
    for arg in args {
        if arg.starts_with("file://") {
            command.args(["@@u", arg, "@@"]);
        } else if Path::new(arg).is_absolute() {
            command.args(["@@", arg, "@@"]);
        } else {
            command.arg(arg);
        }
    }
}

/// Explicit dashboard open: restore an existing window or start the monitored
/// app in its own transient unit. Never restart FDM or touch its download queue.
pub fn open() -> io::Result<bool> {
    let directory = runtime_dir()?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .mode(0o600)
        .open(directory.join("open.lock"))?;
    match rustix::fs::flock(&lock, rustix::fs::FlockOperation::NonBlockingLockExclusive) {
        Ok(()) => {}
        Err(rustix::io::Errno::WOULDBLOCK) => return Ok(true),
        Err(e) => return Err(e.into()),
    }
    if crate::fdm_window::request(true)?["found"] == true {
        return Ok(true);
    }
    let binary = std::env::current_exe()?;
    let start = |attempt| -> io::Result<()> {
        let status = Command::new("systemd-run")
            .args(["--user", "--collect", "--quiet", "--property=Type=exec"])
            .arg(format!(
                "--unit=aeris-fdm-launch-{}-{attempt}",
                std::process::id()
            ))
            .arg(&binary)
            .args(["fdm", "launch"])
            .stdin(Stdio::null())
            .status()?;
        if status.success() {
            Ok(())
        } else {
            Err(io::Error::other("Could not start the FDM launcher"))
        }
    };
    start(0)?;
    for attempt in 0..16 {
        std::thread::sleep(Duration::from_millis(500));
        if crate::fdm_window::request(true)?["found"] == true {
            return Ok(true);
        }
        // The custom-UI first launch may start hidden. Once its instance is
        // listening, a regular single-instance request maps its main window.
        if attempt == 2 || attempt == 6 {
            start(attempt + 1)?;
        }
    }
    Err(io::Error::other(
        "FDM started but its main window did not appear",
    ))
}

/// Remains alive with FDM, independently of dashboard reloads. A second launch
/// delegates ordinary activation/URLs to FDM's existing single-instance handler.
pub fn launch(args: &[String]) -> io::Result<bool> {
    let directory = runtime_dir()?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .mode(0o600)
        .open(directory.join("launcher.lock"))?;
    let mut command = Command::new("flatpak");
    command.args([
        "run",
        "--env=QT_QPA_PLATFORM=wayland",
        "--file-forwarding",
        APP,
    ]);
    match rustix::fs::flock(&lock, rustix::fs::FlockOperation::NonBlockingLockExclusive) {
        Ok(()) => {}
        Err(rustix::io::Errno::WOULDBLOCK) => {
            append_open_targets(&mut command, args);
            return Ok(command.status()?.success());
        }
        Err(e) => return Err(e.into()),
    }
    let home = std::env::var_os("HOME").ok_or_else(|| io::Error::other("HOME is not set"))?;
    let adapter = PathBuf::from(home).join(format!(".var/app/{APP}/config/aeris/Monitor.qml"));
    if !adapter.is_file() {
        return Err(io::Error::other("FDM monitor adapter is not installed"));
    }
    let state = directory.join("state.json");
    // Explicitly scoped transient state only; never touch FDM's own files.
    match fs::remove_file(&state) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    command
        .arg("--qurl")
        .arg(format!("file://{}", adapter.display()));
    append_open_targets(&mut command, args);
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()?;
    let result = (|| -> io::Result<()> {
        let mut reader = BufReader::new(child.stderr.take().unwrap());
        loop {
            // Bound allocation even if unrelated FDM diagnostics contain a huge line.
            let mut line = Vec::new();
            let count = reader
                .by_ref()
                .take(MAX_LINE as u64 + 1)
                .read_until(b'\n', &mut line)?;
            if count == 0 {
                break;
            }
            if count > MAX_LINE {
                if line.last() != Some(&b'\n') {
                    reader.skip_until(b'\n')?;
                }
                continue;
            }
            if let Some(payload) = line.strip_prefix(PREFIX) {
                if let Some(snapshot) = parse(payload) {
                    save(&state, &snapshot)?;
                }
            }
            // Do not persist or forward FDM diagnostics: they may contain URLs.
        }
        Ok(())
    })();
    // On transport failure leave FDM running; monitoring must never stop downloads.
    if result.is_err() {
        return result.map(|_| false);
    }
    let success = child.wait()?.success();
    let _ = fs::remove_file(state);
    Ok(success)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample(ids: &[&str]) -> Snapshot {
        Snapshot {
            version: 1,
            completed_count: None,
            downloads: ids
                .iter()
                .map(|id| Download {
                    id: id.to_string(),
                    title: "file".into(),
                    size: Some(100.0),
                    downloaded: Some(40.0),
                    speed: Some(1024.0),
                    running: true,
                })
                .collect(),
        }
    }
    #[test]
    fn completed_count_is_current_history_not_active_slots() {
        let mut reader = Reader::default();
        for count in [Some(3), Some(1), Some(0), None] {
            let mut data = sample(&[]);
            data.completed_count = count;
            let value = reader.assign(data);
            assert_eq!(value["completedCount"], json!(count));
            assert_eq!(value["activeCount"], 0);
            assert_eq!(value["slots"], json!([null, null, null, null]));
        }
        let snapshot = parse(br#"{"version":1,"downloads":[],"completedCount":7}"#).unwrap();
        assert_eq!(snapshot.completed_count, Some(7));
        assert_eq!(
            parse(br#"{"version":1,"downloads":[]}"#)
                .unwrap()
                .completed_count,
            None
        );
        assert!(parse(br#"{"version":1,"downloads":[],"completedCount":-1}"#).is_none());
    }

    #[test]
    fn file_targets_use_portal_but_links_remain_unchanged() {
        let mut command = Command::new("flatpak");
        let targets = [
            "file:///tmp/a%20b.torrent",
            "magnet:?xt=urn:btih:test",
            "https://example.org/file",
            "/tmp/a b.torrent",
        ];
        append_open_targets(&mut command, &targets.map(str::to_owned));
        let args: Vec<_> = command.get_args().map(|s| s.to_str().unwrap()).collect();
        assert_eq!(
            args,
            [
                "@@u", targets[0], "@@", targets[1], targets[2], "@@", targets[3], "@@"
            ]
        );
        let mut empty = Command::new("flatpak");
        append_open_targets(&mut empty, &[]);
        assert_eq!(empty.get_args().count(), 0);
    }

    #[test]
    fn stable_four_slots_and_replacement() {
        let mut reader = Reader::default();
        let initial = reader.assign(sample(&["1", "2", "3", "4", "5"]));
        assert_eq!(initial["downloadBytesPerSecond"], 5120.0);
        let value = reader.assign(sample(&["5", "4", "2", "3"]));
        assert_eq!(value["slots"][0]["id"], "5");
        assert_eq!(value["slots"][1]["id"], "2");
        assert_eq!(value["slots"][2]["progress"], 0.4);
        assert_eq!(value["slots"].as_array().unwrap().len(), 4);
        assert_eq!(value["downloadBytesPerSecond"], 4096.0);
        assert_eq!(reader.assign(sample(&[]))["downloadBytesPerSecond"], 0.0);
    }
    #[test]
    fn unknown_total_is_not_fake_progress() {
        let mut data = sample(&["1"]);
        data.downloads[0].size = None;
        let value = Reader::default().assign(data);
        assert!(value["slots"][0]["progress"].is_null());
        assert_eq!(value["slots"][0]["indeterminate"], true);
    }
    #[test]
    fn private_snapshot_and_missing_corrupt_stale_states() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state.json");
        let mut reader = Reader::default();
        assert_eq!(reader.read(Some(&path))["ok"], false);
        save(&path, &sample(&["1"])).unwrap();
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(reader.read(Some(&path))["ok"], true);
        let past = std::time::SystemTime::now() - Duration::from_secs(6);
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(past))
            .unwrap();
        assert_eq!(
            reader.read(Some(&path))["slots"],
            json!([null, null, null, null])
        );
        fs::write(&path, "not json").unwrap();
        assert_eq!(reader.read(Some(&path))["ok"], false);
    }
    #[test]
    fn validates_and_sanitizes_only_allowlisted_fields() {
        assert!(parse(br#"{"version":2,"downloads":[]}"#).is_none());
        let raw = br#"{"version":1,"downloads":[{"id":"1","title":"a\nb","size":-1,"downloaded":10,"speed":null,"running":true,"url":"secret"}]}"#;
        let parsed = parse(raw).unwrap();
        assert_eq!(parsed.downloads[0].title, "ab");
        assert_eq!(parsed.downloads[0].size, None);
        assert!(!serde_json::to_string(&parsed).unwrap().contains("secret"));
    }
}
