use aeris_dashboard_backend::{artwork, common, cooling, templates, tomat, weather};
use serde_json::{Value, json};
use std::fs;

fn routine() -> Value {
    json!({"type":"aeris-pomodoro","id":"classic","name":"Classic",
        "work_minutes":25,"break_minutes":5,"long_break_minutes":15})
}

#[test]
fn template_defaults_and_validation() {
    let valid = templates::validate(&routine()).unwrap();
    assert_eq!(valid["sessions"], 4);
    assert_eq!(valid["short_break_labels"], json!(["REST"]));
    for (field, value) in [
        ("sessions", json!(true)),
        ("sessions", json!(0)),
        ("sessions", json!(9)),
        ("work_minutes", json!(0)),
        ("work_minutes", json!(181)),
        ("break_minutes", json!("5")),
        ("auto_advance", json!("sometimes")),
        ("quotes", json!([])),
        ("work_label", json!("a\nb")),
        ("id", json!("../escape")),
        ("id", json!("-invalid")),
        ("command", json!("not executable")),
    ] {
        let mut data = routine();
        data[field] = value;
        assert!(
            templates::validate(&data).is_err(),
            "accepted {field}: {data}"
        );
    }
}

#[test]
fn templates_parse_only_safe_frontmatter() {
    let source = format!(
        "---\n{}\n---\n# Human notes are not commands",
        serde_yaml_ng::to_string(&routine()).unwrap()
    );
    assert!(templates::parse_note(&source).unwrap().is_some());
    assert!(
        templates::parse_note(&source.replace('\n', "\r\n"))
            .unwrap()
            .is_some()
    );
    assert_eq!(templates::parse_note("# No frontmatter").unwrap(), None);
    assert_eq!(
        templates::parse_note("---\ntype: aeris-pomodoro\n").unwrap(),
        None
    );
    assert!(
        templates::parse_note("---\n!!python/object/apply:os.system ['echo unsafe']\n---").is_err()
    );
    assert!(templates::parse_note("---\ntype: !custom aeris-pomodoro\n---").is_err());
    assert!(templates::parse_note("---\ntype: aeris-pomodoro\ntype: other\n---").is_err());
}

fn observation(now: f64) -> Value {
    json!({"current":{"temperature_2m":29.5,"weather_code":2,"is_day":1,"time":now-60.0},
        "current_units":{"temperature_2m":"°C"}})
}

#[test]
fn weather_codes_and_validation() {
    for (code, pattern) in [
        (0, "clear"),
        (1, "clear"),
        (2, "partly-cloudy"),
        (3, "cloudy"),
        (45, "fog"),
        (48, "fog"),
        (51, "rain"),
        (57, "rain"),
        (65, "rain"),
        (82, "rain"),
        (71, "snow"),
        (86, "snow"),
        (95, "storm"),
        (99, "storm"),
        (-1, "unknown"),
    ] {
        assert_eq!(weather::condition(code, true).1, pattern);
    }
    assert_eq!(weather::condition(0, false).1, "night");
    assert_eq!(
        weather::condition(2, false).2,
        "weather-night-partly-cloudy"
    );
    let now = 100000.0;
    assert_eq!(
        weather::normalize(&observation(now), now).unwrap()["temperature"],
        29.5
    );
    for (field, value) in [
        ("temperature_2m", json!(true)),
        ("temperature_2m", json!(90)),
        ("time", json!(now - 21601.0)),
        ("time", json!(now + 301.0)),
        ("is_day", json!(2)),
        ("weather_code", json!(2.5)),
    ] {
        let mut data = observation(now);
        data["current"][field] = value;
        assert!(weather::normalize(&data, now).is_err());
    }
    let mut data = observation(now);
    data["current_units"]["temperature_2m"] = json!("°F");
    assert!(weather::normalize(&data, now).is_err());
    assert!(weather::location(&json!({"name":"X","latitude":true,"longitude":0})).is_err());
}

#[test]
fn weather_cache_fresh_offline_expired_and_location_bound() {
    let temp = tempfile::tempdir().unwrap();
    let config = temp.path().join("config.json");
    let cache = temp.path().join("cache.json");
    let place = json!({"name":"Puerto Princesa","latitude":9.739,"longitude":118.735});
    common::atomic_json(&config, &place, false).unwrap();
    let now = 100000.0;
    let live = weather::collect_with(&config, &cache, now, false, |_, n| {
        weather::normalize(&observation(n), n)
    });
    assert_eq!(live["ok"], true);
    let fresh = weather::collect_with(&config, &cache, now + 100.0, false, |_, _| {
        panic!("fresh cache fetched")
    });
    assert_eq!(fresh["fetchedAt"], now);
    let offline = weather::collect_with(&config, &cache, now + 601.0, false, |_, _| {
        Err("offline".into())
    });
    assert_eq!(offline["ok"], false);
    assert_eq!(offline["available"], true);
    assert_eq!(offline["fetchedAt"], now);
    let expired = weather::collect_with(&config, &cache, now + 21601.0, false, |_, _| {
        Err("offline".into())
    });
    assert_eq!(expired["available"], false);
    common::atomic_json(
        &config,
        &json!({"name":"Elsewhere","latitude":0,"longitude":0}),
        false,
    )
    .unwrap();
    assert_eq!(
        weather::collect_with(&config, &cache, now + 100.0, false, |_, _| Err(
            "offline".into()
        ))["available"],
        false
    );
}

#[test]
fn artwork_unicode_and_video_id_boundaries() {
    assert_eq!(
        artwork::key("  STRAẞE  ", "  Artist\tName "),
        "artist name strasse"
    );
    assert_eq!(
        artwork::youtube_url(r#"{"videoId":"dQw4w9WgXcQ"}"#),
        "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
    );
    for invalid in [
        r#""videoId":"short""#,
        r#""videoId":"123456789012""#,
        r#""videoId":"12345678/00""#,
    ] {
        assert!(artwork::youtube_url(invalid).is_empty());
    }
    assert_eq!(common::quote_plus("a b&é"), "a+b%26%C3%A9");
}

#[test]
fn tomat_validates_protocol_fields() {
    let data = json!({"phase":"Work","is_paused":true,"remaining_seconds":750,
        "duration_minutes":25,"current_session":2,"sessions_until_long_break":4});
    let normalized = tomat::normalize(data.clone()).unwrap();
    assert_eq!(normalized["progress"], 0.5);
    assert_eq!(normalized["session"], 2);
    let mut invalid = data;
    invalid["phase"] = json!("Bogus");
    assert!(tomat::normalize(invalid).is_err());
    assert!(tomat::normalize(json!({})).is_err());
}

#[test]
fn cooling_modes_and_rotated_cookie() {
    for (name, uid) in cooling::MODES {
        assert_eq!(
            cooling::map_status(&json!({"current_mode_uid":uid}))["mode"],
            name
        );
    }
    assert_eq!(cooling::map_status(&json!({}))["mode"], "unknown");
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("CoolerControl.conf");
    fs::write(
        &path,
        "networkCookies=\"@ByteArray(cc=test-cookie; Path=/)\"\n",
    )
    .unwrap();
    let mut client = cooling::Client::new(path.clone());
    assert_eq!(client.cookie().unwrap(), "cc=test-cookie");
    fs::write(
        &path,
        "networkCookies=\"@ByteArray(cc=rotated-cookie; Path=/)\"\n",
    )
    .unwrap();
    assert_eq!(client.cookie().unwrap(), "cc=rotated-cookie");
    fs::write(&path, "networkCookies=invalid\n").unwrap();
    assert!(client.cookie().is_err());
}
