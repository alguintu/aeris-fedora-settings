//! Adapter for the existing OpenRGB daemon. Never opens the hardware directly.
use rustix::event::{PollFd, PollFlags, Timespec, poll};
use rustix::net::{
    AddressFamily, SocketAddrUnix, SocketFlags, SocketType, connect, socket_with, sockopt,
};
use serde_json::{Value, json};
use std::env;
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub const MODES: [&str; 5] = ["work", "night", "day", "off", "party"];
const TIMEOUT: Duration = Duration::from_millis(750);
const MAX_RESPONSE: usize = 65536;

pub fn control_path() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(format!("/run/user/{}", rustix::process::getuid().as_raw()))
        })
        .join("aeris-openrgb.sock")
}
fn remaining(deadline: Instant) -> io::Result<Duration> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|d| !d.is_zero())
        .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "Lighting daemon timed out"))
}
fn connect_deadline(path: &Path, deadline: Instant) -> io::Result<UnixStream> {
    let fd = socket_with(
        AddressFamily::UNIX,
        SocketType::STREAM,
        SocketFlags::NONBLOCK | SocketFlags::CLOEXEC,
        None,
    )?;
    let address = SocketAddrUnix::new(path)?;
    if let Err(error) = connect(&fd, &address) {
        // AF_UNIX may return AGAIN for a full listener queue: fail safely rather
        // than blocking indefinitely or treating it as a completed connection.
        if error != rustix::io::Errno::INPROGRESS {
            return Err(error.into());
        }
        loop {
            let duration = remaining(deadline)?;
            let timeout = Timespec {
                tv_sec: duration.as_secs() as i64,
                tv_nsec: duration.subsec_nanos() as i64,
            };
            match poll(&mut [PollFd::new(&fd, PollFlags::OUT)], Some(&timeout)) {
                Ok(0) => {
                    return Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "Lighting connection timed out",
                    ));
                }
                Ok(_) => {
                    sockopt::socket_error(&fd)??;
                    break;
                }
                Err(rustix::io::Errno::INTR) => continue,
                Err(error) => return Err(error.into()),
            }
        }
    }
    let stream = UnixStream::from(fd);
    stream.set_nonblocking(false)?;
    Ok(stream)
}

pub fn request_at(path: &Path, payload: &Value) -> io::Result<Value> {
    let value = exchange(path, payload, TIMEOUT, false)?;
    if !value.is_object() || !value.get("ok").is_some_and(Value::is_boolean) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Invalid lighting status",
        ));
    }
    Ok(value)
}

pub fn exchange(
    path: &Path,
    payload: &Value,
    timeout: Duration,
    newline: bool,
) -> io::Result<Value> {
    let deadline = Instant::now() + timeout;
    let mut stream = connect_deadline(path, deadline)?;
    stream.set_write_timeout(Some(remaining(deadline)?))?;
    let mut request = serde_json::to_vec(payload)?;
    if newline {
        request.push(b'\n');
    }
    stream.write_all(&request)?;
    let mut response = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        stream.set_read_timeout(Some(remaining(deadline)?))?;
        let size = stream.read(&mut chunk)?;
        if size == 0 {
            break;
        }
        response.extend_from_slice(&chunk[..size]);
        if response.len() > MAX_RESPONSE {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Socket response exceeds 64 KiB",
            ));
        }
        if response.contains(&b'\n') {
            break;
        }
    }
    let value: Value = serde_json::from_slice(&response)?;
    Ok(value)
}

pub fn request(mode: Option<&str>) -> Value {
    if let Some(mode) = mode
        && !MODES.contains(&mode)
    {
        return json!({"ok": false, "mode": "unknown", "error": "Invalid lighting mode"});
    }
    let payload = mode.map_or_else(
        || json!({"command": "status"}),
        |mode| json!({"command": "set", "mode": mode}),
    );
    // No automatic set retry: a timeout could mean the daemon already applied it.
    request_at(&control_path(), &payload)
        .unwrap_or_else(|error| json!({"ok": false, "mode": "unknown", "error": error.to_string()}))
}
