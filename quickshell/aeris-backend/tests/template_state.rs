use aeris_dashboard_backend::{common, templates};
use serde_json::{Value, json};
use std::{env, fs, process::Command};

fn state(phase: &str) -> Value {
    json!({"ok":true,"phase":phase,"session":1,"duration":1500,"remaining":1400,"sessions":4,"progress":0.067})
}

#[test]
fn selection_snapshot_and_recovery_contract() {
    // Subprocess environment isolation avoids unsafe global environment mutation
    // and makes it impossible to address the user's actual state directory.
    if env::var_os("AERIS_NATIVE_TEMPLATE_TEST_CHILD").is_none() {
        let temp = tempfile::tempdir().unwrap();
        let notes = temp.path().join("notes");
        fs::create_dir(&notes).unwrap();
        for entry in fs::read_dir(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../tomat/templates"
        ))
        .unwrap()
        {
            let entry = entry.unwrap();
            fs::copy(entry.path(), notes.join(entry.file_name())).unwrap();
        }
        let output = Command::new(env::current_exe().unwrap())
            .args([
                "--exact",
                "selection_snapshot_and_recovery_contract",
                "--nocapture",
            ])
            .env("AERIS_NATIVE_TEMPLATE_TEST_CHILD", "1")
            .env("AERIS_TOMAT_TEMPLATE_DIR", &notes)
            .env("AERIS_TOMAT_STATE_DIR", temp.path().join("state"))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        return;
    }
    let mut catalog = templates::Catalog::default();
    let initial = catalog.get(true);
    assert_eq!(initial["templates"].as_array().unwrap().len(), 3);
    assert_eq!(initial["templateErrors"], json!([]));
    let observed = common::monotonic();
    templates::action(
        "toggle",
        &state("Idle"),
        &mut catalog,
        |_, _| Ok(json!({})),
        None,
        None,
    )
    .unwrap();
    let snapshot = templates::load().unwrap();
    assert_eq!(snapshot["active"]["id"], "classic");
    let mut incomplete = snapshot.clone();
    incomplete["active"]
        .as_object_mut()
        .unwrap()
        .remove("short_break_labels");
    incomplete["active"]
        .as_object_mut()
        .unwrap()
        .remove("quotes");
    templates::save(&incomplete).unwrap();
    assert_eq!(
        templates::enrich(state("Break"), &mut catalog, common::monotonic())["stageLabel"],
        "REST"
    );
    templates::save(&snapshot).unwrap();
    templates::enrich(state("Idle"), &mut catalog, observed);
    assert!(
        templates::load().unwrap().get("active").is_some(),
        "stale idle destroyed new snapshot"
    );
    let notes = templates::template_dir().unwrap();
    let classic = notes.join("Classic.md");
    let source = fs::read_to_string(&classic).unwrap();
    fs::write(
        &classic,
        source.replace("work_label: WORK", "work_label: EDITED"),
    )
    .unwrap();
    catalog.get(true);
    assert_eq!(
        templates::enrich(state("Work"), &mut catalog, common::monotonic())["stageLabel"],
        "WORK"
    );
    fs::remove_file(&classic).unwrap();
    catalog.get(true);
    let current = templates::enrich(state("Work"), &mut catalog, common::monotonic());
    assert_eq!(current["activeId"], "classic");
    assert_eq!(current["quote"], snapshot["quote"]);
    assert!(!current["templateErrors"].as_array().unwrap().is_empty());
    templates::action(
        "select",
        &state("Work"),
        &mut catalog,
        |_, _| panic!("queued selection sent command"),
        Some("deep-work"),
        Some("next"),
    )
    .unwrap();
    let before = templates::load().unwrap();
    assert!(
        templates::action(
            "select",
            &state("Work"),
            &mut catalog,
            |_, _| Err("offline".into()),
            Some("light-work"),
            Some("now")
        )
        .is_err()
    );
    assert_eq!(
        templates::load().unwrap(),
        before,
        "failed start altered selection"
    );
    let mut other_boot = before;
    other_boot["boot"] = json!("another-boot");
    templates::save(&other_boot).unwrap();
    assert_eq!(
        templates::enrich(state("Work"), &mut catalog, common::monotonic())["activeId"],
        ""
    );
    fs::write(templates::state_path(), "not JSON").unwrap();
    assert_eq!(
        templates::enrich(state("Work"), &mut catalog, common::monotonic())["ok"],
        true
    );
    templates::action(
        "toggle",
        &state("Work"),
        &mut catalog,
        |name, _| {
            assert_eq!(name, "toggle");
            Ok(json!({}))
        },
        None,
        None,
    )
    .unwrap();
    templates::action(
        "select",
        &state("Work"),
        &mut catalog,
        |_, _| panic!("sent command"),
        Some("deep-work"),
        Some("next"),
    )
    .unwrap();
    assert_eq!(templates::load().unwrap()["selected"], "deep-work");
    fs::write(&classic, &source).unwrap();
    fs::write(notes.join("Copy.md"), &source).unwrap();
    fs::write(notes.join("Copy2.md"), &source).unwrap();
    let duplicates = catalog.get(true);
    assert!(
        duplicates["templates"]
            .as_array()
            .unwrap()
            .iter()
            .all(|v| v["id"] != "classic")
    );
    assert_eq!(duplicates["templateErrors"].as_array().unwrap().len(), 2);
}
