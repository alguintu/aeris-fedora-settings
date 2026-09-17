//! Bounded, ephemeral KWin request for FDM only. No persistent window watcher.
use dbus::{blocking::Connection, channel::MatchingReceiver, message::MatchRule};
use serde_json::Value;
use std::{
    io::{self, Write},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

pub fn request(restore: bool) -> io::Result<Value> {
    let error = |e: dbus::Error| io::Error::other(e.to_string());
    let connection = Connection::new_session().map_err(error)?;
    let (kwin_owner,): (String,) = connection
        .with_proxy(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            Duration::from_secs(1),
        )
        .method_call("org.freedesktop.DBus", "GetNameOwner", ("org.kde.KWin",))
        .map_err(error)?;
    let result = Arc::new(Mutex::new(None));
    let captured = result.clone();
    connection.start_receive(
        MatchRule::new_method_call()
            .with_sender(kwin_owner)
            .with_path("/FdmWindow")
            .with_interface("org.aeris.FdmWindow")
            .with_member("report"),
        Box::new(move |message, connection| {
            if let Ok(payload) = message.read1::<String>() {
                *captured.lock().unwrap() = serde_json::from_str::<Value>(&payload).ok();
            }
            let _ = connection.channel().send(message.method_return());
            true
        }),
    );
    let source = include_str!("fdm_window.js")
        .replace(
            "__DESTINATION__",
            &serde_json::to_string(&connection.unique_name().to_string()).unwrap(),
        )
        .replace("__RESTORE__", if restore { "true" } else { "false" });
    let mut file = tempfile::Builder::new()
        .prefix("aeris-fdm-window-")
        .suffix(".js")
        .tempfile()?;
    file.write_all(source.as_bytes())?;
    file.flush()?;
    let proxy = connection.with_proxy("org.kde.KWin", "/Scripting", Duration::from_secs(1));
    let name = format!("aeris-fdm-window-{}", std::process::id());
    let (id,): (i32,) = proxy
        .method_call(
            "org.kde.kwin.Scripting",
            "loadScript",
            (file.path().to_string_lossy().to_string(), name.clone()),
        )
        .map_err(error)?;
    if id < 0 {
        return Err(io::Error::other("KWin refused FDM activation script"));
    }
    let action = (|| {
        let script = connection.with_proxy(
            "org.kde.KWin",
            format!("/Scripting/Script{id}"),
            Duration::from_secs(1),
        );
        let _: () = script
            .method_call("org.kde.kwin.Script", "run", ())
            .map_err(error)?;
        let deadline = Instant::now() + Duration::from_secs(1);
        while Instant::now() < deadline {
            connection
                .process(Duration::from_millis(50))
                .map_err(error)?;
            if let Some(value) = result.lock().unwrap().take() {
                return Ok(value);
            }
        }
        Err(io::Error::other(
            "KWin did not confirm the FDM window request",
        ))
    })();
    // Unload on success and error; no callback or script remains installed.
    let _: Result<(bool,), _> =
        proxy.method_call("org.kde.kwin.Scripting", "unloadScript", (name,));
    action
}
