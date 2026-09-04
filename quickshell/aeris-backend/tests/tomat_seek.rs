use serde_json::Value;
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

struct Daemon(Child);
impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn seek_uses_fork_and_preserves_active_obsidian_routine() {
    let Some(tomat) = std::env::var_os("AERIS_TEST_TOMAT") else {
        eprintln!("Set AERIS_TEST_TOMAT to the fork binary to run this isolated integration test");
        return;
    };
    let temp = tempfile::tempdir().unwrap();
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut daemon = Command::new(tomat);
    daemon
        .args(["daemon", "run"])
        .env("TOMAT_RUNTIME_DIR", temp.path())
        .env("TOMAT_TESTING", "1")
        .env(
            "TOMAT_CONFIG",
            repo.join("tests/fixtures/tomat-silent.toml"),
        )
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let _daemon = Daemon(daemon.spawn().unwrap());
    let request = |args: &[&str]| -> Output {
        Command::new(env!("CARGO_BIN_EXE_aeris-dashboard-backend"))
            .arg("tomat")
            .args(args)
            .env("TOMAT_RUNTIME_DIR", temp.path())
            .env("AERIS_TOMAT_TEMPLATE_DIR", repo.join("tomat/templates"))
            .env("AERIS_TOMAT_STATE_DIR", temp.path().join("selection"))
            .output()
            .unwrap()
    };
    let value = |args: &[&str]| -> Value {
        let output = request(args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stdout)
        );
        serde_json::from_slice(&output.stdout).unwrap()
    };
    let deadline = Instant::now() + Duration::from_secs(3);
    while !request(&["status"]).status.success() {
        assert!(Instant::now() < deadline, "isolated daemon did not start");
        std::thread::sleep(Duration::from_millis(20));
    }
    value(&["select", "classic", "now"]);
    // An idle selection does not start a session until the play action.
    value(&["toggle"]);
    let before = value(&["pause"]);
    assert_eq!(before["canSeek"], true);
    assert_eq!(before["activeId"], "classic");
    let after = value(&["seek", "600", before["revision"].as_str().unwrap()]);
    assert_eq!(after["remaining"], 900);
    assert_eq!(after["paused"], true);
    assert_eq!(after["progress"], 0.4);
    for key in [
        "duration",
        "session",
        "sessions",
        "activeId",
        "activeName",
        "stageLabel",
        "quote",
    ] {
        assert_eq!(after[key], before[key], "seek altered {key}");
    }
    let stale = request(&["seek", "100", before["revision"].as_str().unwrap()]);
    assert!(!stale.status.success());
    assert_eq!(value(&["status"])["remaining"], 900);
    value(&["resume"]);
    assert!(value(&["status"])["remaining"].as_u64().unwrap() >= 898);
}
