use crate::{
    common::{self, Result, err},
    templates,
};
use serde_json::{Value, json};
use std::{env, path::PathBuf, time::Duration};
pub fn socket() -> PathBuf {
    env::var_os("TOMAT_RUNTIME_DIR")
        .or_else(|| env::var_os("XDG_RUNTIME_DIR"))
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(format!("/run/user/{}", rustix::process::getuid().as_raw()))
        })
        .join("tomat.sock")
}
pub fn request(command: &str, args: Value) -> Result<Value> {
    let value = crate::rgb::exchange(
        &socket(),
        &json!({"command":command,"args":args}),
        Duration::from_secs(2),
        true,
    )
    .map_err(err)?;
    if value["success"] != true {
        return Err(value["message"]
            .as_str()
            .unwrap_or("Tomat request failed")
            .into());
    }
    Ok(value["data"].clone())
}
pub fn normalize(data: Value) -> Result<Value> {
    let phase = data["phase"]
        .as_str()
        .filter(|s| ["Idle", "Work", "Break", "LongBreak"].contains(s))
        .ok_or("Unsupported timer phase")?;
    let remaining = data["remaining_seconds"]
        .as_i64()
        .ok_or("Missing timer remaining time")?
        .max(0);
    let minutes = data["duration_minutes"]
        .as_f64()
        .filter(|n| n.is_finite())
        .ok_or("Missing timer duration")?;
    let duration = (minutes * 60.0).round_ties_even().max(1.0) as i64;
    Ok(
        json!({"ok":true,"phase":phase,"paused":data["is_paused"].as_bool().ok_or("Missing pause state")?,
        "remaining":remaining,"duration":duration,"session":data["current_session"].as_i64().ok_or("Missing session")?.max(1),
        "sessions":data["sessions_until_long_break"].as_i64().ok_or("Missing sessions")?.max(1),
        "progress":if phase=="Idle"{0.0}else{(1.0-remaining as f64/duration as f64).clamp(0.0,1.0)},
        "canSeek":data["can_seek"] == true && data["revision"].is_u64(),
        "revision":data["revision"].as_u64().map(|revision| revision.to_string())}),
    )
}
pub fn status() -> Result<Value> {
    normalize(request("status", json!({}))?)
}

fn seek_args(elapsed: &str, revision: &str) -> Result<Value> {
    let elapsed = elapsed
        .parse::<u64>()
        .map_err(|_| "Elapsed seconds must be a non-negative integer")?;
    let revision = revision
        .parse::<u64>()
        .map_err(|_| "Missing or invalid timer revision")?;
    Ok(json!({"elapsed_seconds": elapsed, "expected_revision": revision}))
}

pub fn seek(elapsed: &str, revision: &str, catalog: &mut templates::Catalog) -> Value {
    (|| -> Result<Value> {
        request("seek", seek_args(elapsed, revision)?)?;
        Ok(templates::enrich(status()?, catalog, common::monotonic()))
    })()
    .unwrap_or_else(|error| json!({"ok": false, "error": error}))
}

pub fn execute(
    action: &str,
    id: Option<&str>,
    mode: Option<&str>,
    catalog: &mut templates::Catalog,
) -> Value {
    (|| -> Result<Value> {
        if ![
            "status", "watch", "toggle", "pause", "resume", "reset", "skip", "select",
        ]
        .contains(&action)
        {
            return Err("Unsupported timer action".into());
        }
        if action != "status" && action != "watch" {
            templates::action(action, &status()?, catalog, request, id, mode)?;
        }
        let observed = common::monotonic();
        Ok(templates::enrich(status()?, catalog, observed))
    })()
    .unwrap_or_else(|error| json!({"ok":false,"error":error}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn seek_requires_unsigned_seconds_and_exact_revision() {
        assert_eq!(
            seek_args("600", "18446744073709551615").unwrap(),
            json!({"elapsed_seconds":600,"expected_revision":u64::MAX})
        );
        for input in ["-1", "1.5", "NaN", "", "18446744073709551616"] {
            assert!(seek_args(input, "2").is_err());
            assert!(seek_args("2", input).is_err());
        }
    }
    #[test]
    fn older_daemons_do_not_offer_scrubbing() {
        let mut data = json!({"phase":"Work","remaining_seconds":900,"duration_minutes":25,
            "is_paused":false,"current_session":1,"sessions_until_long_break":4});
        assert_eq!(normalize(data.clone()).unwrap()["canSeek"], false);
        data["can_seek"] = true.into();
        data["revision"] = u64::MAX.into();
        let state = normalize(data).unwrap();
        assert_eq!(state["canSeek"], true);
        assert_eq!(state["revision"], u64::MAX.to_string());
    }
}
