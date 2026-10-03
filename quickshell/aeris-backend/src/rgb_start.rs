//! Guarded startup: attended requests, or one clean sleep-cycle resume.
use crate::{
    common::{Result, err},
    rgb,
};
use dbus::{
    Path as BusPath,
    blocking::{Connection, stdintf::org_freedesktop_dbus::Properties},
};
use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    path::Path,
    process::Command,
    thread,
    time::{Duration, Instant},
};

const UNIT: &str = "aeris-openrgb.service";
const SERVER: &str = "aeris-openrgb-server.service";
const DEST: &str = "org.freedesktop.systemd1";

fn unit_path(conn: &Connection, unit: &str) -> Result<BusPath<'static>> {
    let (path,): (BusPath<'static>,) = conn
        .with_proxy(DEST, "/org/freedesktop/systemd1", Duration::from_secs(3))
        .method_call("org.freedesktop.systemd1.Manager", "LoadUnit", (unit,))
        .map_err(err)?;
    Ok(path)
}

fn state(conn: &Connection, path: &BusPath<'static>) -> Result<String> {
    conn.with_proxy(DEST, path.clone(), Duration::from_secs(3))
        .get("org.freedesktop.systemd1.Unit", "ActiveState")
        .map_err(err)
}

fn stopped(state: &str) -> bool {
    matches!(state, "inactive" | "failed")
}

fn failed_without_job(conn: &Connection, path: &BusPath<'static>) -> Result<bool> {
    let job: (u32, BusPath<'static>) = conn
        .with_proxy(DEST, path.clone(), Duration::from_secs(3))
        .get("org.freedesktop.systemd1.Unit", "Job")
        .map_err(err)?;
    // A previously failed parent may remain failed while its dependency starts.
    Ok(job.0 == 0 && state(conn, path)? == "failed")
}

fn suspend_stop(log: &str) -> bool {
    let errors: Vec<_> = log.lines().filter(|line| line.contains("ERROR")).collect();
    errors.len() == 1
        && errors[0]
            .contains("OpenRGB safety stop; no reconnect will be attempted: event loop paused for ")
        && errors[0].contains("possible suspend/resume, refusing the old hardware connection")
}

fn check_previous_failure(conn: &Connection, path: &BusPath<'static>) -> Result<()> {
    let invocation: Vec<u8> = conn
        .with_proxy(DEST, path.clone(), Duration::from_secs(3))
        .get("org.freedesktop.systemd1.Unit", "InvocationID")
        .map_err(err)?;
    if invocation.len() != 16 || invocation.iter().all(|byte| *byte == 0) {
        return Err(
            "RGB failure has no verifiable invocation; inspect its journal before starting".into(),
        );
    }
    let id: String = invocation
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let output = Command::new("journalctl")
        .args([
            "--user",
            "--no-pager",
            "-o",
            "cat",
            "-n",
            "30",
            &format!("_SYSTEMD_INVOCATION_ID={id}"),
        ])
        .output()
        .map_err(err)?;
    if !output.status.success() || !suspend_stop(&String::from_utf8_lossy(&output.stdout)) {
        return Err("RGB stopped with an unreviewed error. Inspect aeris-openrgb.service; no restart attempted".into());
    }
    Ok(())
}

fn check_usb(root: &Path) -> Result<()> {
    let matches: Vec<_> = fs::read_dir(root)
        .map_err(err)?
        .filter_map(|entry| entry.ok())
        .filter(|entry| {
            let read = |name| fs::read_to_string(entry.path().join(name)).unwrap_or_default();
            read("idVendor").trim() == "1462"
                && read("idProduct").trim() == "7c94"
                && read("serial").trim() == "A02021090806"
        })
        .collect();
    if matches.len() != 1 {
        return Err("Expected MSI lighting controller is missing or ambiguous on USB; no hardware start attempted".into());
    }
    // Inspect existing kernel enumeration, never probe HID/SMBus ourselves.
    let usb = matches[0].path().canonicalize().map_err(err)?;
    let has_hid = fs::read_dir("/sys/class/hidraw")
        .map_err(err)?
        .filter_map(|entry| entry.ok())
        .any(|entry| {
            entry
                .path()
                .join("device")
                .canonicalize()
                .is_ok_and(|device| device.starts_with(&usb))
        });
    if !has_hid {
        return Err("MSI controller has no enumerated HID interface; no start attempted".into());
    }
    Ok(())
}

pub(crate) struct PendingStart {
    conn: Connection,
    daemon: BusPath<'static>,
    server: BusPath<'static>,
    marker: std::path::PathBuf,
    deadline: Instant,
}

fn clean_inactive(conn: &Connection, path: &BusPath<'static>) -> Result<bool> {
    let result: String = conn
        .with_proxy(DEST, path.clone(), Duration::from_secs(1))
        .get("org.freedesktop.systemd1.Service", "Result")
        .map_err(err)?;
    Ok(state(conn, path)? == "inactive" && result == "success")
}

pub(crate) enum Start {
    Healthy(Value),
    Pending(PendingStart),
}

pub(crate) fn begin(automatic: bool) -> Result<Start> {
    let current = rgb::request(None);
    if current["ok"] == true {
        return Ok(Start::Healthy(current));
    } // Never restart an already healthy daemon.
    if rgb::control_path()
        .with_file_name("aeris-openrgb-sleep-in-progress")
        .exists()
    {
        return Err("Lighting is paused for sleep; wait for wake before starting".into());
    }
    let conn = Connection::new_session().map_err(err)?;
    let daemon = unit_path(&conn, UNIT)?;
    let server = unit_path(&conn, SERVER)?;
    let daemon_state = state(&conn, &daemon)?;
    let server_state = state(&conn, &server)?;
    if automatic && (!clean_inactive(&conn, &daemon)? || !clean_inactive(&conn, &server)?) {
        return Err("RGB resume requires both services to have stopped cleanly; no retry".into());
    }
    if server_state == "failed" {
        return Err(
            "The OpenRGB server failed; review its journal before another hardware start".into(),
        );
    }
    if !stopped(&daemon_state) || !stopped(&server_state) {
        return Err("RGB is running or changing state but not ready; no restart attempted".into());
    }
    if daemon_state == "failed" {
        check_previous_failure(&conn, &daemon)?;
    }
    check_usb(Path::new("/sys/bus/usb/devices"))?;

    // Atomic per-session attempt marker also suppresses duplicate taps across
    // dashboard reloads/processes. Failed/uncertain starts require manual review.
    let marker = rgb::control_path().with_file_name("aeris-openrgb-start-attempt");
    let mut file = fs::OpenOptions::new().write(true).create_new(true).open(&marker)
        .map_err(|e| if e.kind() == std::io::ErrorKind::AlreadyExists {
            "An RGB start is pending or previously failed; review its journal before another attempt".into()
        } else { err(e) })?;
    writeln!(
        file,
        "Guarded RGB startup requested; retain on failure or uncertainty"
    )
    .map_err(err)?;
    file.sync_all().map_err(err)?;

    // Use ONLY the existing unit and its pre-start audit, approved-version,
    // detector allowlist, single-owner checks and 10s discovery window.
    let (_job,): (BusPath<'static>,) = conn
        .with_proxy(DEST, "/org/freedesktop/systemd1", Duration::from_secs(3))
        .method_call(
            "org.freedesktop.systemd1.Manager",
            "StartUnit",
            (UNIT, "fail"),
        )
        .map_err(err)?;
    Ok(Start::Pending(PendingStart {
        conn,
        daemon,
        server,
        marker,
        deadline: Instant::now() + Duration::from_secs(40),
    }))
}

impl PendingStart {
    pub(crate) fn poll(&self) -> Result<Option<Value>> {
        let current = rgb::request(None);
        if current["ok"] == true {
            fs::remove_file(&self.marker).map_err(err)?;
            return Ok(Some(current));
        }
        if failed_without_job(&self.conn, &self.daemon)?
            || failed_without_job(&self.conn, &self.server)?
        {
            return Err("RGB startup failed its safety checks. Inspect aeris-openrgb.service; no automatic retry".into());
        }
        if Instant::now() >= self.deadline {
            return Err("RGB startup has not confirmed readiness. No retry sent; inspect the service before trying again".into());
        }
        Ok(None)
    }
}

fn perform() -> Result<Value> {
    let pending = match begin(false)? {
        Start::Healthy(current) => return Ok(current),
        Start::Pending(pending) => pending,
    };
    loop {
        if let Some(current) = pending.poll()? {
            return Ok(current);
        }
        thread::sleep(Duration::from_millis(250));
    }
}

pub fn start() -> Value {
    perform().unwrap_or_else(|error| json!({"ok":false,"mode":"unknown","error":error}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn startup_never_restarts_live_or_transitioning_units() {
        for value in [
            "active",
            "activating",
            "deactivating",
            "reloading",
            "unknown",
        ] {
            assert!(!stopped(value));
        }
        assert!(stopped("inactive"));
        assert!(stopped("failed"));
    }
    #[test]
    fn only_known_pause_stop_is_eligible_for_attended_start() {
        let pause = "ERROR OpenRGB safety stop; no reconnect will be attempted: event loop paused for 5.1s; possible suspend/resume, refusing the old hardware connection";
        assert!(suspend_stop(pause));
        assert!(!suspend_stop("ERROR OpenRGB safety stop; HID write failed"));
        assert!(!suspend_stop(&format!("{pause}\nERROR disconnected")));
        assert!(!suspend_stop(""));
    }
    #[test]
    fn missing_usb_fails_before_any_bus_probe_or_service_start() {
        let root = tempfile::tempdir().unwrap();
        assert!(
            check_usb(root.path())
                .unwrap_err()
                .contains("missing or ambiguous")
        );
    }
}
