//! A logind delay inhibitor lets us close hardware connections before sleep.
//! Only a healthy runtime that we cleanly stopped earns ONE fresh start on wake.
use crate::{
    common::{Result, err},
    rgb, rgb_start,
};
use dbus::{
    Path as BusPath,
    arg::OwnedFd,
    blocking::{
        Connection,
        stdintf::org_freedesktop_dbus::{Properties, RequestNameReply},
    },
    message::MatchRule,
};
use std::{
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

const LOGIN: &str = "org.freedesktop.login1";
const LOGIN_PATH: &str = "/org/freedesktop/login1";
const MANAGER: &str = "org.freedesktop.login1.Manager";
const SYSTEMD: &str = "org.freedesktop.systemd1";
const UNITS: [&str; 2] = ["aeris-openrgb.service", "aeris-openrgb-server.service"];
const CALL_TIMEOUT: Duration = Duration::from_millis(300);

#[derive(Default)]
struct Cycle {
    sleeping: bool,
    armed: bool,
}
impl Cycle {
    fn prepare(&mut self) -> bool {
        if self.sleeping {
            return false;
        }
        self.sleeping = true;
        self.armed = false;
        true
    }
    fn stopped(&mut self, was_healthy: bool, clean: bool) {
        self.armed = self.sleeping && was_healthy && clean;
    }
    fn resume(&mut self) -> bool {
        let start = self.sleeping && self.armed;
        self.sleeping = false;
        self.armed = false; // Consume before any fallible startup; never retry.
        start
    }
}

struct Unit {
    path: BusPath<'static>,
}
impl Unit {
    fn load(conn: &Connection, name: &str) -> Result<Self> {
        let (path,) = conn
            .with_proxy(SYSTEMD, "/org/freedesktop/systemd1", CALL_TIMEOUT)
            .method_call("org.freedesktop.systemd1.Manager", "LoadUnit", (name,))
            .map_err(err)?;
        Ok(Self { path })
    }
    fn state(&self, conn: &Connection) -> Result<String> {
        conn.with_proxy(SYSTEMD, self.path.clone(), CALL_TIMEOUT)
            .get("org.freedesktop.systemd1.Unit", "ActiveState")
            .map_err(err)
    }
    fn clean(&self, conn: &Connection) -> Result<bool> {
        let result: String = conn
            .with_proxy(SYSTEMD, self.path.clone(), CALL_TIMEOUT)
            .get("org.freedesktop.systemd1.Service", "Result")
            .map_err(err)?;
        Ok(self.state(conn)? == "inactive" && result == "success")
    }
}

fn stop_for_sleep(conn: &Connection, units: &[Unit; 2]) -> Result<bool> {
    // Reserve one second of logind's verified >=5s delay for signal delivery.
    let deadline = Instant::now() + Duration::from_secs(4);
    let healthy = units[0].state(conn)? == "active"
        && units[1].state(conn)? == "active"
        && rgb::request(None)["ok"] == true;
    // Stop even an unhealthy/starting stack, but it cannot earn a resume start.
    for name in UNITS {
        let (_job,): (BusPath<'static>,) = conn
            .with_proxy(SYSTEMD, "/org/freedesktop/systemd1", CALL_TIMEOUT)
            .method_call(
                "org.freedesktop.systemd1.Manager",
                "StopUnit",
                (name, "replace"),
            )
            .map_err(err)?;
    }
    loop {
        if units[0].clean(conn)? && units[1].clean(conn)? {
            return Ok(healthy && Instant::now() < deadline);
        }
        if Instant::now() >= deadline {
            return Err("RGB did not stop cleanly before sleep; automatic resume disarmed".into());
        }
        thread::sleep(Duration::from_millis(25));
    }
}

fn inhibit(conn: &Connection) -> Result<OwnedFd> {
    let (fd,): (OwnedFd,) = conn
        .with_proxy(LOGIN, LOGIN_PATH, Duration::from_secs(1))
        .method_call(
            MANAGER,
            "Inhibit",
            (
                "sleep",
                "Aeris RGB",
                "Close RGB hardware connections before sleep",
                "delay",
            ),
        )
        .map_err(err)?;
    Ok(fd)
}

pub fn watch() -> Result<()> {
    let system = Connection::new_system().map_err(err)?;
    let session = Connection::new_session().map_err(err)?;
    if session
        .request_name("org.aeris.RgbSleep", false, false, true)
        .map_err(err)?
        != RequestNameReply::PrimaryOwner
    {
        return Err("Another RGB sleep watcher already owns this session".into());
    }
    let units = [
        Unit::load(&session, UNITS[0])?,
        Unit::load(&session, UNITS[1])?,
    ];
    let (send, events) = mpsc::channel();
    system
        .add_match(
            MatchRule::new_signal(MANAGER, "PrepareForSleep")
                .with_sender(LOGIN)
                .with_path(LOGIN_PATH),
            move |(sleeping,): (bool,), _, _| {
                let _ = send.send(sleeping);
                true
            },
        )
        .map_err(err)?;
    // Losing logind invalidates the inhibitor. Exit; don't silently keep watching
    // without a delay lock, and don't manufacture a resume on a bus reconnect.
    let (lost_send, lost) = mpsc::channel();
    system
        .add_match(
            MatchRule::new_signal("org.freedesktop.DBus", "NameOwnerChanged")
                .with_sender("org.freedesktop.DBus")
                .with_path("/org/freedesktop/DBus"),
            move |(name, old, _): (String, String, String), _, _| {
                if name == LOGIN && !old.is_empty() {
                    let _ = lost_send.send(());
                }
                true
            },
        )
        .map_err(err)?;
    let proxy = system.with_proxy(LOGIN, LOGIN_PATH, Duration::from_secs(1));
    let max_delay: u64 = proxy.get(MANAGER, "InhibitDelayMaxUSec").map_err(err)?;
    if max_delay < 5_000_000 {
        return Err("RGB sleep watcher requires at least 5 seconds of logind delay budget".into());
    }
    let mut inhibitor = Some(inhibit(&system)?);
    let preparing: bool = proxy.get(MANAGER, "PreparingForSleep").map_err(err)?;
    if preparing {
        return Err(
            "Sleep is already preparing; RGB watcher will not adopt an unknown cycle".into(),
        );
    }
    let sleep_marker = rgb::control_path().with_file_name("aeris-openrgb-sleep-in-progress");
    if sleep_marker.exists() {
        return Err("A previous RGB sleep cycle was interrupted; review services and sleep marker before restarting watcher".into());
    }
    let mut cycle = Cycle::default();
    let mut pending: Option<rgb_start::PendingStart> = None;
    eprintln!("RGB sleep watcher ready; delay inhibitor held, no hardware start requested");
    loop {
        system.process(Duration::from_millis(100)).map_err(err)?;
        if lost.try_recv().is_ok() {
            return Err("logind owner changed; RGB resume disarmed".into());
        }
        for sleeping in events.try_iter() {
            if sleeping {
                if !cycle.prepare() {
                    continue;
                }
                // Dropping an incomplete start preserves its attempt marker.
                // StopUnit cancels its job; another auto-start is not authorized.
                let was_starting = pending.take().is_some();
                // Suppress logo/manual starts until the wake notification. A
                // watcher crash leaves evidence and keeps startup fail-closed.
                std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&sleep_marker)
                    .map_err(err)?;
                match stop_for_sleep(&session, &units) {
                    Ok(eligible) => cycle.stopped(!was_starting, eligible),
                    Err(error) => eprintln!("{error}"),
                }
                eprintln!(
                    "RGB sleep preparation complete; resume armed={}",
                    cycle.armed
                );
                drop(inhibitor.take());
            } else {
                if inhibitor.is_none() {
                    inhibitor = Some(inhibit(&system)?);
                }
                if cycle.sleeping {
                    std::fs::remove_file(&sleep_marker).map_err(err)?;
                }
                if cycle.resume() {
                    eprintln!("RGB wake: requesting one guarded fresh start");
                    match rgb_start::begin(true) {
                        Ok(rgb_start::Start::Pending(start)) => pending = Some(start),
                        Ok(rgb_start::Start::Healthy(_)) => (),
                        Err(error) => eprintln!("RGB resume stopped: {error}"),
                    }
                }
            }
        }
        if let Some(start) = &pending {
            match start.poll() {
                Ok(Some(_)) => {
                    eprintln!("RGB resume healthy in Work mode");
                    pending = None;
                }
                Ok(None) => (),
                Err(error) => {
                    eprintln!("RGB resume stopped: {error}");
                    pending = None;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn one_clean_cycle_authorizes_exactly_one_start() {
        let mut cycle = Cycle::default();
        assert!(!cycle.resume()); // watcher startup / unsolicited wake
        assert!(cycle.prepare());
        cycle.stopped(true, true);
        assert!(!cycle.prepare()); // duplicate prepare must not stop twice
        assert!(cycle.resume());
        assert!(!cycle.resume()); // includes startup failure: no retry
    }
    #[test]
    fn offline_failed_or_uncertain_stop_cannot_restart() {
        for (healthy, clean) in [(false, true), (true, false), (false, false)] {
            let mut cycle = Cycle::default();
            cycle.prepare();
            cycle.stopped(healthy, clean);
            assert!(!cycle.resume());
        }
        let mut cycle = Cycle::default();
        cycle.prepare(); // stop error before any completion
        assert!(!cycle.resume());
    }
    #[test]
    fn next_cycle_does_not_inherit_permission() {
        let mut cycle = Cycle::default();
        cycle.prepare();
        cycle.stopped(true, true);
        assert!(cycle.resume());
        cycle.prepare();
        cycle.stopped(false, true);
        assert!(!cycle.resume());
    }
}
