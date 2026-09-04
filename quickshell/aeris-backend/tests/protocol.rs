use aeris_dashboard_backend::rgb;
use serde_json::{Value, json};
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, Instant};

struct Runtime(PathBuf);
impl Runtime {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        loop {
            let path = std::env::temp_dir().join(format!(
                "aeris-rgb-test-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            match fs::create_dir(&path) {
                Ok(()) => return Self(path),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => panic!("{e}"),
            }
        }
    }
    fn socket(&self) -> PathBuf {
        self.0.join("aeris-openrgb.sock")
    }
}
impl Drop for Runtime {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
const BIN: &str = env!("CARGO_BIN_EXE_aeris-dashboard-backend");

#[test]
fn split_reply_and_mode_command_match_existing_protocol() {
    let runtime = Runtime::new();
    let listener = UnixListener::bind(runtime.socket()).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut buffer = [0; 4096];
        let size = stream.read(&mut buffer).unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&buffer[..size]).unwrap(),
            json!({"command":"set", "mode":"night"})
        );
        stream.write_all(b"{\"ok\":true,").unwrap();
        thread::sleep(Duration::from_millis(10));
        stream
            .write_all(b"\"mode\":\"night\",\"thermalOverride\":false}\n")
            .unwrap();
    });
    let output = Command::new(BIN)
        .args(["rgb", "set", "night"])
        .env("XDG_RUNTIME_DIR", &runtime.0)
        .output()
        .unwrap();
    assert!(output.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["mode"],
        "night"
    );
    worker.join().unwrap();
}

#[test]
fn invalid_mode_is_rejected_before_contacting_socket() {
    let runtime = Runtime::new();
    let listener = UnixListener::bind(runtime.socket()).unwrap();
    listener.set_nonblocking(true).unwrap();
    let output = Command::new(BIN)
        .args(["rgb", "set", "invalid"])
        .env("XDG_RUNTIME_DIR", &runtime.0)
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["ok"],
        false
    );
    assert!(listener.accept().is_err());
}

#[test]
fn missing_daemon_fails_cleanly_then_recovers() {
    let runtime = Runtime::new();
    assert!(rgb::request_at(&runtime.socket(), &json!({"command":"status"})).is_err());
    let listener = UnixListener::bind(runtime.socket()).unwrap();
    let worker = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut buf = [0; 1024];
        assert!(stream.read(&mut buf).unwrap() > 0);
        stream
            .write_all(b"{\"ok\":true,\"mode\":\"work\"}\n")
            .unwrap();
    });
    assert_eq!(
        rgb::request_at(&runtime.socket(), &json!({"command":"status"})).unwrap()["mode"],
        "work"
    );
    worker.join().unwrap();
}

#[test]
fn malformed_and_oversized_responses_are_rejected() {
    for payload in [b"[]\n".to_vec(), b"not json\n".to_vec(), vec![b'x'; 65537]] {
        let runtime = Runtime::new();
        let listener = UnixListener::bind(runtime.socket()).unwrap();
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0; 1024];
            assert!(stream.read(&mut buf).unwrap() > 0);
            let _ = stream.write_all(&payload);
        });
        assert!(rgb::request_at(&runtime.socket(), &json!({"command":"status"})).is_err());
        worker.join().unwrap();
    }
}

#[test]
fn unresponsive_daemon_has_bounded_deadline() {
    let runtime = Runtime::new();
    let listener = UnixListener::bind(runtime.socket()).unwrap();
    let worker = thread::spawn(move || {
        let (_stream, _) = listener.accept().unwrap();
        thread::sleep(Duration::from_millis(1000));
    });
    let begin = Instant::now();
    assert!(rgb::request_at(&runtime.socket(), &json!({"command":"status"})).is_err());
    assert!(begin.elapsed() < Duration::from_millis(1500));
    worker.join().unwrap();
}

#[test]
fn combined_stream_keeps_metrics_alive_with_rgb_unavailable() {
    let runtime = Runtime::new();
    let mut child = Command::new(BIN)
        .arg("watch")
        .env("XDG_RUNTIME_DIR", &runtime.0)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let pipe = child.stdout.take().unwrap();
    let (sender, receiver) = std::sync::mpsc::channel();
    let reader = thread::spawn(move || {
        for line in BufReader::new(pipe).lines().map_while(Result::ok) {
            if sender
                .send(serde_json::from_str::<Value>(&line).unwrap())
                .is_err()
            {
                break;
            }
        }
    });
    let mut metrics = 0;
    let mut rgb_error = false;
    let deadline = Instant::now() + Duration::from_secs(4);
    while metrics < 2 || !rgb_error {
        let Some(wait) = deadline.checked_duration_since(Instant::now()) else {
            break;
        };
        let Ok(event) = receiver.recv_timeout(wait) else {
            break;
        };
        if event["service"] == "metrics" && event["payload"]["ok"] == true {
            metrics += 1;
        }
        if event["service"] == "rgb" && event["payload"]["ok"] == false {
            rgb_error = true;
        }
    }
    child.kill().unwrap();
    child.wait().unwrap();
    reader.join().unwrap();
    assert!(metrics >= 2 && rgb_error);
}
