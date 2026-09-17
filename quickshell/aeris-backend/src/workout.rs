//! Data-only prescriptions and independently durable daily set logs.
//! A countdown transition never calls `record`; completion is always explicit.
use crate::common::{self, Result, err};
use chrono::Local;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, HashSet},
    fs::{self, File, OpenOptions},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Plan {
    pub id: String,
    pub name: String,
    pub status: String,
    pub source: String,
    pub notes: String,
    pub blocks: Vec<Block>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Block {
    pub id: String,
    pub exercise: String,
    pub after_round: u8,
    pub sets: u8,
    pub reps_min: u16,
    pub reps_max: u16,
    #[serde(default)]
    pub per_side: bool,
    #[serde(default)]
    pub load_kg: Option<f64>,
    pub rest_seconds: u16,
    pub notes: String,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SetResult {
    pub status: String,
    pub reps: Option<u16>,
    pub right_reps: Option<u16>,
    pub load_kg: Option<f64>,
    pub rir: Option<u8>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Record {
    pub request_id: String,
    pub day_id: String,
    pub expected_revision: u64,
    pub block_id: String,
    pub set: u8,
    pub result: SetResult,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Day {
    id: String,
    date: String,
    revision: u64,
    plan: Plan,
    logs: BTreeMap<String, SetResult>,
    requests: BTreeMap<String, Record>,
}
fn slug(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 48
        && s.as_bytes()[0].is_ascii_alphanumeric()
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}
fn text(s: &str, max: usize) -> bool {
    !s.trim().is_empty() && s.chars().count() <= max && !s.chars().any(char::is_control)
}
impl Plan {
    fn check(&self) -> Result<()> {
        if !slug(&self.id)
            || !text(&self.name, 64)
            || !["draft", "ready"].contains(&self.status.as_str())
            || !text(&self.source, 200)
            || !text(&self.notes, 1000)
            || self.blocks.is_empty()
            || self.blocks.len() > 12
        {
            return Err("Invalid workout plan metadata".into());
        }
        let mut ids = HashSet::new();
        for b in &self.blocks {
            if !slug(&b.id)
                || !ids.insert(&b.id)
                || !text(&b.exercise, 80)
                || !(1..=8).contains(&b.after_round)
                || !(1..=8).contains(&b.sets)
                || b.reps_min == 0
                || b.reps_min > b.reps_max
                || b.reps_max > 200
                || !(15..=600).contains(&b.rest_seconds)
                || !text(&b.notes, 600)
                || b.load_kg
                    .is_some_and(|v| !v.is_finite() || !(0.0..=500.0).contains(&v))
            {
                return Err("Invalid workout block".into());
            }
        }
        Ok(())
    }
}
pub fn validate(value: &Value) -> Result<Value> {
    let plan: Plan = serde_json::from_value(value.clone()).map_err(err)?;
    plan.check()?;
    serde_json::to_value(plan).map_err(err)
}
fn directory() -> PathBuf {
    crate::templates::state_path()
        .parent()
        .unwrap()
        .join("workouts")
}
fn lock(dir: &Path) -> Result<File> {
    fs::create_dir_all(dir).map_err(err)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(dir.join("workout.lock"))
        .map_err(err)?;
    rustix::fs::flock(&file, rustix::fs::FlockOperation::LockExclusive).map_err(err)?;
    Ok(file)
}
fn valid_day_id(id: &str) -> bool {
    let Some((date, plan)) = id.split_once("__") else {
        return false;
    };
    date.len() == 10 && chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d").is_ok() && slug(plan)
}
fn read(dir: &Path, id: &str) -> Result<Day> {
    if !valid_day_id(id) {
        return Err("Invalid workout day".into());
    }
    let day: Day = serde_json::from_value(common::read_json(
        &dir.join(format!("{id}.json")),
        2 * 1024 * 1024,
    )?)
    .map_err(err)?;
    day.plan.check()?;
    if day.id != id || day.id != format!("{}__{}", day.date, day.plan.id) {
        return Err("Invalid saved workout identity".into());
    }
    Ok(day)
}
fn view(day: &Day) -> Value {
    let slots: Vec<_> = day
        .plan
        .blocks
        .iter()
        .flat_map(|b| (1..=b.sets).map(move |s| (b, format!("{}:{s}", b.id))))
        .collect();
    let done = slots
        .iter()
        .filter(|(_, key)| day.logs.get(key).is_some_and(|s| s.status == "done"))
        .count();
    let next = slots.iter().find(|(_, key)| {
        !day.logs
            .get(key)
            .is_some_and(|s| s.status == "done" || s.status == "skipped")
    });
    json!({"id":day.id,"date":day.date,"revision":day.revision,"plan":day.plan,"logs":day.logs,
        "completed":done,"total":slots.len(),"next_exercise":next.map(|(b,_)| &b.exercise)})
}
fn open_day(dir: &Path, date: &str, plan: Plan) -> Result<Value> {
    plan.check()?;
    let id = format!("{date}__{}", plan.id);
    if !valid_day_id(&id) {
        return Err("Invalid workout date".into());
    }
    let _lock = lock(dir)?;
    let path = dir.join(format!("{id}.json"));
    if path.exists() {
        return read(dir, &id).map(|d| view(&d));
    }
    let day = Day {
        id,
        date: date.into(),
        revision: 0,
        plan,
        logs: BTreeMap::new(),
        requests: BTreeMap::new(),
    };
    common::atomic_json(&path, &serde_json::to_value(&day).map_err(err)?, true)?;
    Ok(view(&day))
}
pub fn today(plan: &Value) -> Result<Value> {
    // The workstation's local calendar owns day boundaries for every client.
    open_day(
        &directory(),
        &Local::now().format("%Y-%m-%d").to_string(),
        serde_json::from_value(plan.clone()).map_err(err)?,
    )
}
fn record_in(dir: &Path, input: Record) -> Result<Value> {
    if !text(&input.request_id, 64)
        || !input
            .request_id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    {
        return Err("Invalid request ID".into());
    }
    let _lock = lock(dir)?;
    let mut day = read(dir, &input.day_id)?;
    if let Some(previous) = day.requests.get(&input.request_id) {
        if previous != &input {
            return Err("Request ID was already used for a different set".into());
        }
        return Ok(view(&day));
    }
    if input.expected_revision != day.revision {
        return Err("Workout changed. Review the latest sets before saving again.".into());
    }
    let block = day
        .plan
        .blocks
        .iter()
        .find(|b| b.id == input.block_id)
        .ok_or("Unknown exercise")?;
    let r = &input.result;
    if input.set == 0
        || input.set > block.sets
        || !["done", "skipped", "pending"].contains(&r.status.as_str())
        || r.reps.is_some_and(|v| v == 0 || v > 500)
        || r.right_reps.is_some_and(|v| v == 0 || v > 500)
        || r.load_kg
            .is_some_and(|v| !v.is_finite() || !(0.0..=500.0).contains(&v))
        || r.rir.is_some_and(|v| v > 10)
        || (r.status == "done" && (r.reps.is_none() || block.per_side != r.right_reps.is_some()))
        || (r.status != "done"
            && (r.reps.is_some()
                || r.right_reps.is_some()
                || r.load_kg.is_some()
                || r.rir.is_some()))
    {
        return Err("Invalid set result".into());
    }
    if day.requests.len() >= 1000 {
        return Err("Daily edit limit reached; saved sets are intact".into());
    }
    day.logs.insert(
        format!("{}:{}", input.block_id, input.set),
        input.result.clone(),
    );
    day.requests.insert(input.request_id.clone(), input);
    day.revision = day
        .revision
        .checked_add(1)
        .ok_or("Workout revision limit reached")?;
    common::atomic_json(
        &dir.join(format!("{}.json", day.id)),
        &serde_json::to_value(&day).map_err(err)?,
        true,
    )?;
    Ok(view(&day))
}
pub fn record(value: Value) -> Result<Value> {
    record_in(&directory(), serde_json::from_value(value).map_err(err)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn plan() -> Plan {
        serde_json::from_value(json!({"id":"upper","name":"Upper","status":"draft","source":"Workout/source","notes":"Existing draft","blocks":[{"id":"row","exercise":"Supported row","after_round":2,"sets":2,"reps_min":8,"reps_max":12,"per_side":true,"rest_seconds":90,"notes":"Per side"}]})).unwrap()
    }
    fn input(day: &Value) -> Record {
        Record {
            request_id: "test-1".into(),
            day_id: day["id"].as_str().unwrap().into(),
            expected_revision: 0,
            block_id: "row".into(),
            set: 1,
            result: SetResult {
                status: "done".into(),
                reps: Some(10),
                right_reps: Some(9),
                load_kg: Some(6.0),
                rir: Some(3),
            },
        }
    }
    #[test]
    fn snapshots_survive_reopening_template_edits_and_new_days() {
        let dir = tempfile::tempdir().unwrap();
        let a = open_day(dir.path(), "2026-09-14", plan()).unwrap();
        let logged = record_in(dir.path(), input(&a)).unwrap();
        let mut edited = plan();
        edited.blocks[0].sets = 3;
        assert_eq!(open_day(dir.path(), "2026-09-14", edited).unwrap(), logged);
        let next = open_day(dir.path(), "2026-09-15", plan()).unwrap();
        assert_eq!(next["logs"], json!({}));
        assert_eq!(
            read(dir.path(), a["id"].as_str().unwrap())
                .unwrap()
                .revision,
            1
        );
    }
    #[test]
    fn duplicate_ack_is_idempotent_and_stale_edits_do_not_overwrite() {
        let dir = tempfile::tempdir().unwrap();
        let day = open_day(dir.path(), "2026-09-14", plan()).unwrap();
        let request = input(&day);
        let saved = record_in(dir.path(), request.clone()).unwrap();
        assert_eq!(saved, record_in(dir.path(), request.clone()).unwrap());
        let mut conflict = request.clone();
        conflict.request_id = "new".into();
        assert!(record_in(dir.path(), conflict).is_err());
        let mut reused = request;
        reused.result.reps = Some(12);
        assert!(record_in(dir.path(), reused).is_err());
        assert_eq!(
            read(dir.path(), day["id"].as_str().unwrap())
                .unwrap()
                .revision,
            1
        );
    }
    #[test]
    fn completion_requires_valid_explicit_actuals_and_both_sides() {
        let dir = tempfile::tempdir().unwrap();
        let day = open_day(dir.path(), "2026-09-14", plan()).unwrap();
        let mut request = input(&day);
        request.result.right_reps = None;
        assert!(record_in(dir.path(), request.clone()).is_err());
        request.result.status = "skipped".into();
        assert!(record_in(dir.path(), request.clone()).is_err());
        request.result = SetResult {
            status: "skipped".into(),
            reps: None,
            right_reps: None,
            load_kg: None,
            rir: None,
        };
        assert_eq!(
            record_in(dir.path(), request).unwrap()["logs"]["row:1"]["status"],
            "skipped"
        );
    }
    #[test]
    fn rejects_paths_corrupt_logs_and_unknown_schema_fields() {
        let dir = tempfile::tempdir().unwrap();
        assert!(read(dir.path(), "../../selection").is_err());
        let day = open_day(dir.path(), "2026-09-14", plan()).unwrap();
        let path = dir
            .path()
            .join(format!("{}.json", day["id"].as_str().unwrap()));
        fs::write(&path, "broken").unwrap();
        assert!(open_day(dir.path(), "2026-09-14", plan()).is_err());
        assert_eq!(fs::read_to_string(path).unwrap(), "broken");
        let mut data = serde_json::to_value(plan()).unwrap();
        data["exec"] = json!("bad");
        assert!(validate(&data).is_err());
        let mut data = serde_json::to_value(plan()).unwrap();
        data["blocks"][0]["sets"] = json!(0);
        assert!(validate(&data).is_err());
    }
}
