use crate::common::{self, Result, err};
use dbus::{
    arg::PropMap,
    blocking::{
        Connection,
        stdintf::org_freedesktop_dbus::{Properties, RequestNameReply},
    },
    channel::{MatchingReceiver, Sender},
    message::MatchRule,
};
use serde_json::{Value, json};
use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};
const FIND: &str = r#"
var ds = desktops();
var bridge = null;
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        if (ws[j].type === 'org.aeris.sleepbridge') bridge = ws[j];
    }
}
if (!bridge) throw new Error('Aeris sleep bridge is not attached to the desktop');
bridge.currentConfigGroup = ['General'];
"#;
const CONTROL: &str = "org.aeris.Dashboard.Awake";
const CONTROL_PATH: &str = "/org/aeris/Dashboard/Awake";
const POWER: &str = "org.kde.Solid.PowerManagement";
const POLICY: &str = "org.kde.Solid.PowerManagement.PolicyAgent";
const POLICY_PATH: &str = "/org/kde/Solid/PowerManagement/PolicyAgent";
const APP: &str = "Aeris Dashboard";
const REASON: &str = "Keep the computer awake; allow display power saving";
const MANUAL_REASON: &str = "The battery applet has enabled suppressing sleep and screen locking";
type Inhibition = (String, String, String, String, u32);

fn read_system_active(conn: &Connection) -> Result<bool> {
    let inhibitions: Vec<Inhibition> = conn
        .with_proxy(POWER, POLICY_PATH, Duration::from_secs(3))
        .get(POLICY, "ActiveInhibitions")
        .map_err(err)?;
    Ok(system_active(&inhibitions))
}

fn read_full_active(conn: &Connection) -> Result<bool> {
    let inhibitions: Vec<Inhibition> = conn
        .with_proxy(POWER, POLICY_PATH, Duration::from_secs(3))
        .get(POLICY, "ActiveInhibitions")
        .map_err(err)?;
    Ok(["sleep", "idle"].iter().all(|kind| {
        inhibitions.iter().any(|(what, who, why, _, flags)| {
            what.split(':').any(|part| part == *kind)
                && who == "org.kde.plasmashell"
                && why == MANUAL_REASON
                && flags & 1 != 0
        })
    }))
}

fn mode_name(action: &str) -> Result<&str> {
    match action {
        "on" | "full" => Ok("full"),
        "off" | "normal" => Ok("normal"),
        "system" => Ok("system"),
        _ => Err("Invalid sleep mode".into()),
    }
}

fn system_active(inhibitions: &[Inhibition]) -> bool {
    inhibitions.iter().any(|(what, who, why, _, flags)| {
        what.split(':').any(|part| part == "sleep") && who == APP && why == REASON && flags & 1 != 0
    })
}

fn confirmed_mode(manual: bool, system: bool) -> &'static str {
    if manual {
        "full"
    } else if system {
        "system"
    } else {
        "normal"
    }
}
fn script(conn: &Connection, source: &str) -> Result<String> {
    let proxy = conn.with_proxy(
        "org.kde.plasmashell",
        "/PlasmaShell",
        Duration::from_secs(8),
    );
    let (result,): (String,) = proxy
        .method_call("org.kde.PlasmaShell", "evaluateScript", (source,))
        .map_err(err)?;
    Ok(result)
}
pub fn status(conn: &Connection) -> Result<Value> {
    let value: Value = serde_json::from_str(&script(
        conn,
        &format!("{FIND}\nprint(JSON.stringify({{active: bridge.readConfig('active', false)}}));"),
    )?)
    .map_err(err)?;
    let active = value["active"]
        .as_bool()
        .ok_or("Invalid Plasma bridge state")?;
    let mode = confirmed_mode(active, read_system_active(conn)?);
    Ok(json!({"ok":true,"active":mode != "normal","mode":mode,"error":""}))
}
fn failure(error: String) -> Value {
    json!({"ok":false,"active":false,"error":error})
}
pub fn execute(action: &str) -> Value {
    perform(action).unwrap_or_else(failure)
}

fn perform(action: &str) -> Result<Value> {
    let conn = Connection::new_session().map_err(err)?;
    match action {
        "status" => status(&conn),
        "on" | "off" | "normal" | "system" | "full" => {
            // A short-lived command cannot own a durable PowerDevil cookie.
            // The already-running watcher owns it, without another process/poll.
            let (reply,): (String,) = conn
                .with_proxy(CONTROL, CONTROL_PATH, Duration::from_secs(30))
                .method_call(CONTROL, "SetMode", (mode_name(action)?,))
                .map_err(err)?;
            serde_json::from_str(&reply).map_err(err)
        }
        "attach-bridge" => {
            script(
                &conn,
                r#"var ds=desktops(); var found=false;
for(var i=0;i<ds.length;i++){var ws=ds[i].widgets();for(var j=0;j<ws.length;j++){if(ws[j].type==='org.aeris.sleepbridge')found=true;}}
if(!found){if(!ds.length)throw new Error('No Plasma desktop available');ds[0].addWidget('org.aeris.sleepbridge');}"#,
            )?;
            Ok(json!({"ok":true,"error":""}))
        }
        _ => Err("Invalid sleep action".into()),
    }
}

#[derive(Default)]
struct SystemInhibitor {
    // Cookies can be reused after PowerDevil restarts. Never release a cookie
    // against a different owner, where it might now belong to another app.
    cookie: Option<(String, u32)>,
}

impl SystemInhibitor {
    fn set(&mut self, conn: &Connection, enabled: bool) -> Result<()> {
        let (owner,): (String,) = conn
            .with_proxy(
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                Duration::from_secs(3),
            )
            .method_call("org.freedesktop.DBus", "GetNameOwner", (POWER,))
            .map_err(err)?;
        if self
            .cookie
            .as_ref()
            .is_some_and(|(previous, _)| previous != &owner)
        {
            self.cookie = None;
        }
        let proxy = conn.with_proxy(owner.as_str(), POLICY_PATH, Duration::from_secs(3));
        if enabled && self.cookie.is_none() {
            // PowerDevil InterruptSession = 1; deliberately NOT ChangeScreenSettings = 4.
            let (cookie,): (u32,) = proxy
                .method_call(POLICY, "AddInhibition", (1u32, APP, REASON))
                .map_err(err)?;
            self.cookie = Some((owner, cookie));
        } else if !enabled && let Some((_, cookie)) = self.cookie.as_ref() {
            let (): () = proxy
                .method_call(POLICY, "ReleaseInhibition", (*cookie,))
                .map_err(err)?;
            self.cookie = None;
        }
        Ok(())
    }

    fn select(&mut self, conn: &Connection, mode: &str) -> Result<Value> {
        let mode = mode_name(mode)?;
        let previous = status(conn)?;
        let result = self.select_inner(conn, mode);
        if result.is_err() {
            // A failed transition must not strand a newly acquired inhibitor.
            // Restore only our prior mode; unrelated blockers are never touched.
            let _ = self.select_inner(conn, previous["mode"].as_str().unwrap_or("normal"));
        }
        result
    }

    fn select_inner(&mut self, conn: &Connection, mode: &str) -> Result<Value> {
        let mode = mode_name(mode)?;
        let enabled = mode == "full";
        // Acquire sleep-only before releasing full, so transitions never leave
        // the system briefly unprotected. Going full does the reverse.
        if mode == "system" {
            self.set(conn, true)?;
            // PowerDevil deliberately delays new application inhibitors by 5s.
            // Wait for actual enforcement before releasing the full-mode block.
            let deadline = Instant::now() + Duration::from_secs(7);
            while !read_system_active(conn)? {
                if Instant::now() >= deadline {
                    return Err("KDE did not enable sleep-only inhibition".into());
                }
                thread::sleep(Duration::from_millis(250));
            }
        }
        let serial = format!("aeris-rust-{}-{}", std::process::id(), common::now() * 1e9);
        script(
            conn,
            &format!(
                "{FIND}\nbridge.writeConfig('requested', {enabled});\nbridge.writeConfig('requestSerial', {});",
                json!(serial)
            ),
        )?;
        for _ in 0..30 {
            let value = status(conn)?;
            if (value["mode"] == "full") == enabled {
                if enabled {
                    // Native manual cookies also have an enforcement delay.
                    // Keep the middle-mode cookie until BOTH native policies apply.
                    let deadline = Instant::now() + Duration::from_secs(7);
                    while !read_full_active(conn)? {
                        if Instant::now() >= deadline {
                            return Err("KDE did not enable full sleep/display inhibition".into());
                        }
                        thread::sleep(Duration::from_millis(250));
                    }
                }
                if mode != "system" {
                    self.set(conn, false)?;
                }
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
        for _ in 0..30 {
            let value = status(conn)?;
            if value["mode"] == mode {
                return Ok(value);
            }
            thread::sleep(Duration::from_millis(100));
        }
        Err(
            "KDE did not confirm the requested sleep mode (it may have blocked the inhibition)"
                .into(),
        )
    }
}

fn serve(conn: &Connection, changed: Arc<AtomicBool>) -> Result<()> {
    if conn
        .request_name(CONTROL, false, false, true)
        .map_err(err)?
        != RequestNameReply::PrimaryOwner
    {
        return Ok(()); // A diagnostic `sleep watch` observes, never takes ownership.
    }
    let mut inhibitor = SystemInhibitor::default();
    let mut rule = MatchRule::new_method_call();
    rule.path = Some(CONTROL_PATH.into());
    rule.interface = Some(CONTROL.into());
    rule.member = Some("SetMode".into());
    conn.start_receive(
        rule,
        Box::new(move |msg, conn| {
            let value = msg
                .read1::<String>()
                .map_err(err)
                .and_then(|mode| inhibitor.select(conn, &mode))
                .unwrap_or_else(failure);
            let _ = conn.send(msg.method_return().append1(value.to_string()));
            changed.store(true, Ordering::Relaxed);
            true
        }),
    );
    Ok(())
}
fn subscribe(conn: &Connection, changed: Arc<AtomicBool>) -> Result<()> {
    let rule = MatchRule::new_signal("org.freedesktop.DBus.Properties", "PropertiesChanged")
        .with_sender("org.kde.Solid.PowerManagement")
        .with_path("/org/kde/Solid/PowerManagement/PolicyAgent");
    let flag = changed.clone();
    conn.add_match(
        rule,
        move |(iface, _, _): (String, PropMap, Vec<String>), _, _| {
            if iface == "org.kde.Solid.PowerManagement.PolicyAgent" {
                flag.store(true, Ordering::Relaxed);
            }
            true
        },
    )
    .map_err(err)?;
    let rule = MatchRule::new_signal(
        "org.kde.Solid.PowerManagement.PolicyAgent",
        "InhibitionsChanged",
    )
    .with_sender("org.kde.Solid.PowerManagement")
    .with_path("/org/kde/Solid/PowerManagement/PolicyAgent");
    let flag = changed.clone();
    // Older PowerDevil releases use different payload signatures here. The
    // notification is only a hint to re-read confirmed Plasma state.
    conn.add_match_no_cb(&rule.match_str()).map_err(err)?;
    conn.start_receive(
        rule,
        Box::new(move |_, _| {
            flag.store(true, Ordering::Relaxed);
            true
        }),
    );
    // Filter owners on the bus so unrelated application connections don't wake us.
    for name in ["org.kde.plasmashell", "org.kde.Solid.PowerManagement"] {
        conn.add_match_no_cb(&format!("type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='{name}'")).map_err(err)?;
    }
    conn.start_receive(
        MatchRule::new_signal("org.freedesktop.DBus", "NameOwnerChanged"),
        Box::new(move |msg, _| {
            if let Ok((name, _, _)) = msg.read3::<String, String, String>()
                && ["org.kde.plasmashell", "org.kde.Solid.PowerManagement"].contains(&name.as_str())
            {
                changed.store(true, Ordering::Relaxed);
            }
            true
        }),
    );
    Ok(())
}
pub fn watch(mut publish: impl FnMut(Value) -> bool) {
    loop {
        let run = (|| -> Result<bool> {
            let conn = Connection::new_session().map_err(err)?;
            let changed = Arc::new(AtomicBool::new(false));
            subscribe(&conn, changed.clone())?;
            serve(&conn, changed.clone())?;
            let mut due = Instant::now();
            let mut pending: Option<Instant> = None;
            loop {
                let now = Instant::now();
                if now >= due || pending.is_some_and(|time| now >= time) {
                    let value = status(&conn).unwrap_or_else(failure);
                    let healthy = value["ok"] == true;
                    if !publish(value) {
                        return Ok(false);
                    }
                    due = Instant::now() + Duration::from_secs(if healthy { 30 } else { 2 });
                    pending = None;
                }
                let next = pending.map_or(due, |p| p.min(due));
                conn.process(next.saturating_duration_since(Instant::now()))
                    .map_err(err)?;
                if changed.swap(false, Ordering::Relaxed) && pending.is_none() {
                    pending = Some(Instant::now() + Duration::from_millis(200));
                }
            }
        })();
        match run {
            Ok(false) => return,
            Err(error) => {
                if !publish(failure(error)) {
                    return;
                }
            }
            _ => {}
        }
        thread::sleep(Duration::from_secs(2));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn modes_and_legacy_aliases() {
        for (input, expected) in [
            ("on", "full"),
            ("off", "normal"),
            ("system", "system"),
            ("full", "full"),
            ("normal", "normal"),
        ] {
            assert_eq!(mode_name(input).unwrap(), expected);
        }
        assert!(mode_name("unknown").is_err());
        assert_eq!(confirmed_mode(false, false), "normal");
        assert_eq!(confirmed_mode(false, true), "system");
        assert_eq!(confirmed_mode(true, false), "full");
        assert_eq!(confirmed_mode(true, true), "full");
    }

    #[test]
    fn only_our_confirmed_sleep_inhibitor_is_middle_mode() {
        let entry = |what: &str, who: &str, why: &str, flags| {
            (what.into(), who.into(), why.into(), "block".into(), flags)
        };
        assert!(!system_active(&[entry("sleep", "Other app", REASON, 3)]));
        assert!(!system_active(&[entry(
            "sleep",
            APP,
            "Different request",
            3
        )]));
        assert!(!system_active(&[entry("sleep", APP, REASON, 2)]));
        assert!(!system_active(&[entry("idle", APP, REASON, 3)]));
        assert!(system_active(&[entry("sleep", APP, REASON, 3)]));
    }
}
