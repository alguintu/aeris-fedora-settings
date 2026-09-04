use crate::common::{self, Result, err};
use serde_json::{Value, json};
use std::{env, path::PathBuf, time::Duration};
const MAX_AGE: f64 = 21600.0;
pub fn paths() -> (PathBuf, PathBuf) {
    (
        env::var_os("AERIS_WEATHER_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                common::xdg("XDG_CONFIG_HOME", ".config").join("aeris-dashboard/weather.json")
            }),
        env::var_os("AERIS_WEATHER_CACHE")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                common::xdg("XDG_CACHE_HOME", ".cache").join("aeris-dashboard/weather.json")
            }),
    )
}
pub fn location(data: &Value) -> Result<Value> {
    for (field, limit) in [("latitude", 90.0), ("longitude", 180.0)] {
        if !data[field]
            .as_f64()
            .is_some_and(|n| n.is_finite() && n.abs() <= limit)
        {
            return Err("Invalid weather coordinates".into());
        }
    }
    let name = data["name"]
        .as_str()
        .filter(|s| (1..=80).contains(&s.chars().count()))
        .ok_or("Invalid weather location name")?;
    Ok(json!({"name":name,"latitude":data["latitude"],"longitude":data["longitude"]}))
}
pub fn condition(code: i64, day: bool) -> (&'static str, &'static str, &'static str) {
    match code {
        0 | 1 => (
            if code == 0 {
                "Clear sky"
            } else {
                "Mainly clear"
            },
            if day { "clear" } else { "night" },
            if day {
                "white-balance-sunny"
            } else {
                "moon-waning-crescent"
            },
        ),
        2 => (
            "Partly cloudy",
            "partly-cloudy",
            if day {
                "weather-partly-cloudy"
            } else {
                "weather-night-partly-cloudy"
            },
        ),
        3 => ("Overcast", "cloudy", "weather-cloudy"),
        45 | 48 => ("Fog", "fog", "weather-fog"),
        51 | 53 | 55 | 56 | 57 => (
            if code >= 56 {
                "Freezing drizzle"
            } else {
                "Drizzle"
            },
            "rain",
            "weather-rainy",
        ),
        61 | 63 | 65 | 66 | 67 | 80 | 81 | 82 => (
            if code == 66 || code == 67 {
                "Freezing rain"
            } else if code >= 80 {
                "Showers"
            } else {
                "Rain"
            },
            "rain",
            "weather-rainy",
        ),
        71 | 73 | 75 | 77 | 85 | 86 => (
            if code >= 85 { "Snow showers" } else { "Snow" },
            "snow",
            "weather-snowy",
        ),
        95 | 96 | 99 => (
            if code == 95 {
                "Thunderstorm"
            } else {
                "Thunder + hail"
            },
            "storm",
            "weather-lightning-rainy",
        ),
        _ => ("Unknown conditions", "unknown", "weather-cloudy"),
    }
}
pub fn normalize(data: &Value, now: f64) -> Result<Value> {
    let current = &data["current"];
    let temp = current["temperature_2m"]
        .as_f64()
        .filter(|n| n.is_finite() && (-100.0..=70.0).contains(n))
        .ok_or("Invalid weather temperature")?;
    let code = current["weather_code"]
        .as_i64()
        .ok_or("Invalid weather condition")?;
    let day = current["is_day"]
        .as_i64()
        .filter(|n| *n == 0 || *n == 1)
        .ok_or("Invalid weather day flag")?;
    let measured = current["time"]
        .as_f64()
        .filter(|n| n.is_finite() && (-300.0..MAX_AGE).contains(&(now - n)))
        .ok_or("Expired weather timestamp")?;
    if data["current_units"]["temperature_2m"] != "°C" {
        return Err("Unexpected temperature unit".into());
    }
    let (label, pattern, icon) = condition(code, day == 1);
    Ok(
        json!({"temperature":temp,"code":code,"isDay":day==1,"description":label,"condition":pattern,"icon":icon,"observedAt":measured,"fetchedAt":now}),
    )
}
pub fn cached(data: &Value, place: &Value, now: f64) -> Option<Value> {
    if data["location"] != *place {
        return None;
    }
    let old = &data["weather"];
    let mut value = normalize(&json!({"current":{"temperature_2m":old["temperature"],"weather_code":old["code"],
        "is_day":if old["isDay"].as_bool()? {1} else {0},"time":old["observedAt"]},"current_units":{"temperature_2m":"°C"}}),now).ok()?;
    let fetched = old["fetchedAt"].as_f64()?;
    if !(0.0..MAX_AGE).contains(&(now - fetched)) {
        return None;
    }
    value["fetchedAt"] = old["fetchedAt"].clone();
    Some(value)
}
pub fn collect_with(
    config: &std::path::Path,
    cache: &std::path::Path,
    now: f64,
    force: bool,
    fetch: impl FnOnce(&Value, f64) -> Result<Value>,
) -> Value {
    let Ok(place) = common::read_json(config, 65536).and_then(|v| location(&v)) else {
        return json!({"ok":false,"available":false,"description":"Set location","error":"Configure ~/.config/aeris-dashboard/weather.json"});
    };
    let old = common::read_json(cache, 131072)
        .ok()
        .and_then(|v| cached(&v, &place, now));
    if !force
        && let Some(mut value) = old.clone()
        && now - value["fetchedAt"].as_f64().unwrap_or(0.0) < 600.0
    {
        value["ok"] = json!(true);
        value["available"] = json!(true);
        value["location"] = place["name"].clone();
        return value;
    }
    match fetch(&place, now) {
        Ok(mut value) => {
            let _ = common::atomic_json(cache, &json!({"location":place,"weather":value}), false);
            value["ok"] = json!(true);
            value["available"] = json!(true);
            value["location"] = place["name"].clone();
            value
        }
        Err(_) => {
            let available = old.is_some();
            let mut value = old.unwrap_or_else(|| json!({"description":"Unavailable"}));
            value["ok"] = json!(false);
            value["available"] = json!(available);
            value["location"] = place["name"].clone();
            value["error"] = json!("Weather update unavailable");
            value
        }
    }
}
pub fn collect(force: bool) -> Value {
    let (config, cache) = paths();
    collect_with(&config, &cache, common::now(), force, |place, now| {
        let url = format!(
            "https://api.open-meteo.com/v1/forecast?latitude={}&longitude={}&current=temperature_2m%2Cweather_code%2Cis_day&temperature_unit=celsius&timeformat=unixtime&timezone=auto&forecast_days=1",
            place["latitude"], place["longitude"]
        );
        let bytes = common::get(&url, Duration::from_secs(12), 131072, "Aeris-Weather/1.0")?;
        normalize(&serde_json::from_slice(&bytes).map_err(err)?, now)
    })
}
