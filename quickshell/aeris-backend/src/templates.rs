//! Data-only Obsidian templates and the existing atomic selection/snapshot format.
use crate::common::{self, Result, err};
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    env,
    fs::{self, File, OpenOptions},
    io::Read,
    os::unix::fs::{MetadataExt, OpenOptionsExt},
    path::{Path, PathBuf},
    sync::OnceLock,
};
const FIELDS: [&str; 12] = [
    "type",
    "id",
    "name",
    "work_minutes",
    "break_minutes",
    "long_break_minutes",
    "sessions",
    "auto_advance",
    "work_label",
    "short_break_labels",
    "long_break_label",
    "quotes",
];
fn text(value: &Value, field: &str, limit: usize) -> Result<String> {
    value
        .as_str()
        .filter(|s| {
            !s.trim().is_empty()
                && s.chars().count() <= limit
                && !s.chars().any(|c| (c as u32) < 32)
        })
        .map(|s| s.trim().to_owned())
        .ok_or_else(|| format!("{field}: expected text of 1–{limit} characters"))
}
pub fn validate(data: &Value) -> Result<Value> {
    let obj = data.as_object().ok_or("type must be aeris-pomodoro")?;
    if data["type"] != "aeris-pomodoro" {
        return Err("type must be aeris-pomodoro".into());
    }
    if obj.keys().any(|key| !FIELDS.contains(&key.as_str())) {
        return Err("Unknown template fields".into());
    }
    let id = text(&data["id"], "id", 48)?;
    if !id
        .bytes()
        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        || id.starts_with('-')
    {
        return Err("id must be a lowercase slug".into());
    }
    let mut result = json!({"id":id,"name":text(&data["name"],"name",32)?});
    for field in ["work_minutes", "break_minutes", "long_break_minutes"] {
        if !data[field]
            .as_f64()
            .is_some_and(|v| v.is_finite() && (1.0..=180.0).contains(&v))
        {
            return Err(format!("{field}: expected 1–180 minutes"));
        }
        result[field] = data[field].clone();
    }
    let sessions = obj.get("sessions").cloned().unwrap_or(json!(4));
    if !sessions.as_i64().is_some_and(|v| (1..=8).contains(&v)) {
        return Err("sessions: expected 1–8".into());
    }
    result["sessions"] = sessions;
    let advance = obj
        .get("auto_advance")
        .and_then(Value::as_str)
        .unwrap_or("none");
    if !["none", "all", "to-break", "to-work"].contains(&advance)
        || obj.get("auto_advance").is_some_and(|v| !v.is_string())
    {
        return Err("Invalid auto_advance".into());
    }
    result["auto_advance"] = json!(advance);
    for (field, default) in [("work_label", "WORK"), ("long_break_label", "LONG BREAK")] {
        result[field] = json!(text(obj.get(field).unwrap_or(&json!(default)), field, 16)?);
    }
    for (field, default, count, len) in [
        ("short_break_labels", "REST", 8, 16),
        ("quotes", "Nothing lasts. Make it count.", 32, 72),
    ] {
        let fallback = json!([default]);
        let values = obj
            .get(field)
            .unwrap_or(&fallback)
            .as_array()
            .filter(|a| !a.is_empty() && a.len() <= count)
            .ok_or_else(|| format!("Invalid {field}"))?;
        result[field] = Value::Array(
            values
                .iter()
                .map(|v| text(v, field, len).map(Value::String))
                .collect::<Result<_>>()?,
        );
    }
    Ok(result)
}
pub fn template_dir() -> Result<PathBuf> {
    if let Some(path) = env::var_os("AERIS_TOMAT_TEMPLATE_DIR") {
        return Ok(path.into());
    }
    for config in [
        common::home().join(".var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"),
        common::home().join(".config/obsidian/obsidian.json"),
    ] {
        if !config.exists() {
            continue;
        }
        let data = common::read_json(&config, 1024 * 1024)?;
        let candidate = data["vaults"]
            .as_object()
            .into_iter()
            .flat_map(|o| o.values())
            .filter(|v| {
                v["path"]
                    .as_str()
                    .is_some_and(|p| Path::new(p).join(".obsidian").is_dir())
            })
            .max_by(|a, b| {
                a["open"]
                    .as_bool()
                    .unwrap_or(false)
                    .cmp(&b["open"].as_bool().unwrap_or(false))
                    .then_with(|| {
                        a["ts"]
                            .as_f64()
                            .unwrap_or(0.0)
                            .total_cmp(&b["ts"].as_f64().unwrap_or(0.0))
                    })
            });
        if let Some(v) = candidate {
            return Ok(Path::new(v["path"].as_str().unwrap()).join("Aeris/Pomodoro Templates"));
        }
    }
    Err("No configured Obsidian vault found".into())
}
fn has_tag(value: &serde_yaml_ng::Value) -> bool {
    use serde_yaml_ng::Value as Y;
    match value {
        Y::Tagged(_) => true,
        Y::Sequence(items) => items.iter().any(has_tag),
        Y::Mapping(m) => m.iter().any(|(k, v)| has_tag(k) || has_tag(v)),
        _ => false,
    }
}
pub fn parse_note(content: &str) -> Result<Option<Value>> {
    let mut lines = content.lines();
    if lines.next().map(str::trim_end) != Some("---") {
        return Ok(None);
    }
    let mut yaml = String::new();
    let mut ended = false;
    for line in lines {
        if line.trim_end() == "---" {
            ended = true;
            break;
        }
        yaml.push_str(line);
        yaml.push('\n');
    }
    if !ended {
        return Ok(None);
    }
    let value: serde_yaml_ng::Value = serde_yaml_ng::from_str(&yaml).map_err(err)?;
    if has_tag(&value) {
        return Err("Custom YAML tags are not permitted".into());
    }
    validate(&serde_json::to_value(value).map_err(err)?).map(Some)
}
type Signature = Vec<(PathBuf, u64, u64, i64, i64, i64, i64, u32)>;
#[derive(Default)]
pub struct Catalog {
    cache: Option<Value>,
    checked: f64,
    signature: Option<Signature>,
}
impl Catalog {
    pub fn get(&mut self, force: bool) -> Value {
        let now = common::monotonic();
        if !force
            && now - self.checked < 3.0
            && let Some(value) = &self.cache
        {
            return value.clone();
        }
        self.checked = now;
        let mut routines = Vec::new();
        let mut errors = Vec::new();
        let mut seen = HashSet::new();
        let mut signature = None;
        let mut retry = false;
        let read = (|| -> Result<()> {
            let directory = template_dir()?;
            let mut paths: Vec<_> = fs::read_dir(&directory)
                .map_err(err)?
                .filter_map(std::result::Result::ok)
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|e| e == "md"))
                .collect();
            paths.sort();
            paths.truncate(64);
            let mut infos = Vec::new();
            let mut sig = Vec::new();
            for path in paths {
                let info = fs::symlink_metadata(&path).map_err(err)?;
                sig.push((
                    path.clone(),
                    info.ino(),
                    info.len(),
                    info.mtime(),
                    info.mtime_nsec(),
                    info.ctime(),
                    info.ctime_nsec(),
                    info.mode(),
                ));
                infos.push((path, info));
            }
            // Include the directory identity even for an empty catalog.
            sig.push((directory, 0, 0, 0, 0, 0, 0, 0));
            signature = Some(sig);
            if !force && self.signature == signature && self.cache.is_some() {
                return Ok(());
            }
            for (path, info) in infos {
                if info.file_type().is_symlink() {
                    continue;
                }
                let note = (|| -> Result<Option<Value>> {
                    if info.len() > 65536 {
                        return Err("Template exceeds 64 KB".into());
                    }
                    let content = fs::read_to_string(&path).map_err(|e| {
                        retry = true;
                        err(e)
                    })?;
                    parse_note(&content)
                })();
                match note {
                    Ok(Some(routine)) => {
                        let id = routine["id"].as_str().unwrap().to_owned();
                        if !seen.insert(id.clone()) {
                            routines.retain(|r: &Value| r["id"] != id);
                            errors.push(format!(
                                "{}: Duplicate routine id: {id}",
                                path.file_name().unwrap().to_string_lossy()
                            ));
                        } else {
                            routines.push(routine);
                        }
                    }
                    Ok(None) => {}
                    Err(error) => errors.push(format!(
                        "{}: {error}",
                        path.file_name().unwrap_or_default().to_string_lossy()
                    )),
                }
            }
            Ok(())
        })();
        if let Err(error) = read {
            retry = true;
            errors.push(error);
        }
        if !retry
            && !force
            && signature == self.signature
            && let Some(value) = &self.cache
        {
            return value.clone();
        }
        self.signature = if retry { None } else { signature };
        let value = json!({"templates":routines,"templateErrors":errors});
        self.cache = Some(value.clone());
        value
    }
}
pub fn state_path() -> PathBuf {
    env::var_os("AERIS_TOMAT_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| common::xdg("XDG_STATE_HOME", ".local/state").join("aeris-pomodoro"))
        .join("selection.json")
}
pub fn load() -> Result<Value> {
    let path = state_path();
    if !path.exists() {
        return Ok(json!({}));
    }
    let data = common::read_json(&path, 1024 * 1024)?;
    if !data.is_object() {
        return Err("Invalid saved routine selection".into());
    }
    Ok(data)
}
pub fn save(data: &Value) -> Result<()> {
    common::atomic_json(&state_path(), data, true)
}
pub fn lock() -> Result<File> {
    let path = state_path().with_extension("lock");
    fs::create_dir_all(path.parent().unwrap()).map_err(err)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(path)
        .map_err(err)?;
    rustix::fs::flock(&file, rustix::fs::FlockOperation::LockExclusive).map_err(err)?;
    Ok(file)
}
pub fn boot_id() -> String {
    static BOOT: OnceLock<String> = OnceLock::new();
    BOOT.get_or_init(|| {
        fs::read_to_string("/proc/sys/kernel/random/boot_id")
            .unwrap_or_default()
            .trim()
            .to_owned()
    })
    .clone()
}
fn find<'a>(id: &str, entries: &'a [Value]) -> Result<&'a Value> {
    entries.iter().find(|v| v["id"] == id).ok_or_else(|| {
        "Selected routine is missing or invalid; choose another in the picker".into()
    })
}
fn selected<'a>(model: &Value, entries: &'a [Value]) -> Result<Option<&'a Value>> {
    if let Some(id) = model["selected"].as_str().filter(|s| !s.is_empty()) {
        return find(id, entries).map(Some);
    }
    Ok(entries
        .iter()
        .find(|v| v["id"] == "classic")
        .or(entries.first()))
}
fn start(
    routine: &Value,
    model: &mut Value,
    request: &mut impl FnMut(&str, Value) -> Result<Value>,
) -> Result<()> {
    request(
        "start",
        json!({"work":routine["work_minutes"],"break":routine["break_minutes"],"long_break":routine["long_break_minutes"],"sessions":routine["sessions"],"auto_advance":routine["auto_advance"]}),
    )?;
    let quotes = routine["quotes"].as_array().ok_or("Missing quotes")?;
    let mut random = [0u8; 8];
    let _ = File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut random));
    model["selected"] = routine["id"].clone();
    model["active"] = routine.clone();
    model["boot"] = json!(boot_id());
    model["startedAt"] = json!(common::monotonic());
    model["quote"] = quotes[(u64::from_ne_bytes(random) % (quotes.len() as u64)) as usize].clone();
    save(model)
}
pub fn action(
    name: &str,
    raw: &Value,
    catalog: &mut Catalog,
    mut request: impl FnMut(&str, Value) -> Result<Value>,
    identifier: Option<&str>,
    mode: Option<&str>,
) -> Result<()> {
    if ["pause", "resume", "skip"].contains(&name) || (name == "toggle" && raw["phase"] != "Idle") {
        request(name, json!({}))?;
        return Ok(());
    }
    let _lock = lock()?;
    let mut model = match load() {
        Ok(v) => v,
        Err(error) => {
            // Explicit selection/reset may recover corrupt JSON, not an I/O
            // failure: never replace state we lacked permission to read.
            if ["select", "reset"].contains(&name) && fs::read_to_string(state_path()).is_ok() {
                json!({})
            } else {
                return Err(error);
            }
        }
    };
    let data = catalog.get(true);
    let entries = data["templates"].as_array().ok_or("Invalid catalog")?;
    match name {
        "select" => {
            if !matches!(mode, Some("next" | "now")) {
                return Err("Choose next or now".into());
            }
            let routine = find(identifier.unwrap_or(""), entries)?;
            if mode == Some("now") && raw["phase"] != "Idle" {
                start(routine, &mut model, &mut request)?;
            } else {
                model["selected"] = routine["id"].clone();
                save(&model)?;
            }
        }
        "toggle" => {
            let routine = selected(&model, entries)?
                .ok_or("No valid Obsidian routines. Open the template picker.")?;
            start(routine, &mut model, &mut request)?;
        }
        "reset" => {
            request("stop", json!({}))?;
            model.as_object_mut().unwrap().remove("active");
            model.as_object_mut().unwrap().remove("quote");
            save(&model)?;
        }
        _ => return Err("Unsupported timer action".into()),
    }
    Ok(())
}
pub fn enrich(mut state: Value, catalog: &mut Catalog, observed: f64) -> Value {
    let data = catalog.get(false);
    let mut errors = data["templateErrors"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let model = (|| -> Result<Value> {
        let mut model = load()?;
        if model.get("active").is_some() && (state["phase"] == "Idle" || model["boot"] != boot_id())
        {
            let _lock = lock()?;
            model = load()?;
            if model["boot"] != boot_id() || model["startedAt"].as_f64().unwrap_or(0.0) < observed {
                model.as_object_mut().unwrap().remove("active");
                model.as_object_mut().unwrap().remove("quote");
                save(&model)?;
            }
        }
        if let Some(active) = model.get("active") {
            let mut check = active.clone();
            if !check.is_object() {
                return Err("Invalid active routine".into());
            }
            check["type"] = json!("aeris-pomodoro");
            // Use the validated/default-filled value too: a manually damaged
            // snapshot must not make later label/quote access panic the worker.
            model["active"] = validate(&check)?;
        }
        Ok(model)
    })();
    let model = model.unwrap_or_else(|error| {
        errors.push(json!(format!("Saved selection: {error}")));
        json!({})
    });
    let entries = data["templates"].as_array().cloned().unwrap_or_default();
    let choice = selected(&model, &entries).unwrap_or_else(|error| {
        errors.push(json!(error));
        None
    });
    let active = if state["phase"] != "Idle" {
        model.get("active")
    } else {
        None
    };
    let routine = active.or_else(|| {
        if state["phase"] == "Idle" {
            choice
        } else {
            None
        }
    });
    state["templates"] = data["templates"].clone();
    state["templateErrors"] = json!(errors);
    for (key, entry, field) in [
        ("selectedId", choice, "id"),
        ("selectedName", choice, "name"),
        ("activeId", active, "id"),
        ("activeName", active, "name"),
    ] {
        state[key] = entry.map(|v| v[field].clone()).unwrap_or(json!(""));
    }
    state["quote"] = model
        .get("quote")
        .cloned()
        .unwrap_or(json!("Nothing lasts. Make it count."));
    if let Some(routine) = routine {
        if state["phase"] == "Idle" {
            let seconds =
                (routine["work_minutes"].as_f64().unwrap() * 60.0).round_ties_even() as i64;
            state["remaining"] = json!(seconds);
            state["duration"] = json!(seconds);
            state["sessions"] = routine["sessions"].clone();
            state["session"] = json!(1);
            state["progress"] = json!(0);
            state["quote"] = routine["quotes"][0].clone();
        }
        let labels = routine["short_break_labels"].as_array().unwrap();
        let index = (state["session"].as_i64().unwrap_or(1) - 2).max(0) as usize % labels.len();
        state["stageLabel"] = match state["phase"].as_str() {
            Some("Break") => labels[index].clone(),
            Some("LongBreak") => routine["long_break_label"].clone(),
            _ => routine["work_label"].clone(),
        };
    }
    state
}
