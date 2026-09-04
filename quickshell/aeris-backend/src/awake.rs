use crate::common::{self, Result, err};
use dbus::{arg::PropMap, blocking::Connection, channel::MatchingReceiver, message::MatchRule};
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
    Ok(json!({"ok":true,"active":active,"error":""}))
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
        "on" | "off" => {
            let enabled = action == "on";
            let current = status(&conn)?;
            if current["active"] == enabled {
                return Ok(current);
            }
            let serial = format!("aeris-rust-{}-{}", std::process::id(), common::now() * 1e9);
            script(
                &conn,
                &format!(
                    "{FIND}\nbridge.writeConfig('requested', {enabled});\nbridge.writeConfig('requestSerial', {});",
                    json!(serial)
                ),
            )?;
            for _ in 0..30 {
                let value = status(&conn)?;
                if value["active"] == enabled {
                    return Ok(value);
                }
                thread::sleep(Duration::from_millis(100));
            }
            Err("KDE's manual sleep toggle did not reach the requested state".into())
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
