//! Read-only AI hub snapshot. Never load a model or execute a worker job.
use crate::common::{agent, home, read_json};
use serde_json::{Value, json};
use std::{path::Path, time::Duration};

fn endpoint(port: u16, path: &str) -> Result<Value, String> {
    let mut response = agent(Duration::from_millis(700), true)
        .get(format!("http://127.0.0.1:{port}{path}"))
        .call()
        .map_err(|error| match error {
            ureq::Error::Timeout(_) => "TIMED OUT".to_string(),
            _ => "API OFF".to_string(),
        })?;
    let status = response.status().as_u16();
    if status == 401 || status == 403 {
        return Err("AUTH REQUIRED".into());
    }
    if status == 503 {
        return Err("UNAVAILABLE".into());
    }
    if status != 200 {
        return Err(format!("HTTP {status}"));
    }
    let bytes = response
        .body_mut()
        .with_config()
        .limit(262_144)
        .read_to_vec()
        .map_err(|_| "INVALID RESPONSE".to_string())?;
    serde_json::from_slice(&bytes).map_err(|_| "INVALID RESPONSE".to_string())
}

fn lm_models(value: &Value) -> Result<Vec<String>, String> {
    let models = value["models"].as_array().ok_or("INVALID RESPONSE")?;
    let mut loaded = Vec::new();
    for model in models {
        // OpenAI /v1/models may include unloaded JIT candidates. Native v1
        // identifies resident instances; absent fields are unknown, not idle.
        let instances = model["loaded_instances"]
            .as_array()
            .ok_or("INVALID RESPONSE")?;
        if !instances.is_empty() {
            loaded.push(
                model["display_name"]
                    .as_str()
                    .or(model["key"].as_str())
                    .ok_or("INVALID RESPONSE")?
                    .to_owned(),
            );
        }
    }
    Ok(loaded)
}

fn api_status(name: &str, port: u16, lm: bool) -> Value {
    let result = if lm {
        endpoint(port, "/api/v1/models").and_then(|v| lm_models(&v))
    } else {
        endpoint(port, "/health").and_then(|v| {
            if v["status"] == "ok" {
                Ok(Vec::new())
            } else {
                Err("UNAVAILABLE".into())
            }
        })
    };
    match result {
        Ok(models) => json!({"name": name, "port": port, "online": true,
            "state": if lm && models.is_empty() { "NO MODEL" } else { "READY" },
            "detail": if lm && !models.is_empty() { models.join(" · ") }
                else if lm { "API online · no loaded instances".into() }
                else { "Local inference API ready".into() }}),
        Err(state) => json!({"name": name, "port": port, "online": false,
            "state": state, "detail": format!("127.0.0.1:{port}")}),
    }
}

fn preset(path: &Path) -> Option<Value> {
    let data = read_json(path, 65_536).ok()?;
    let fields = data["load"]["fields"].as_array()?;
    let field = |key: &str| fields.iter().find(|f| f["key"] == key).map(|f| &f["value"]);
    Some(json!({"name": data["name"].as_str()?, "path": path,
        "context": field("llm.load.contextLength").and_then(Value::as_u64),
        "offload": field("llm.load.llama.acceleration.offloadRatio")
            .and_then(Value::as_f64).filter(|n| (0.0..=1.0).contains(n))}))
}

fn catalog(base: &Path) -> Value {
    let presets: Vec<Value> = [
        "Aeris Qwen3.8 Fast Text 16GB",
        "Aeris Qwen3.8 Q4 Hybrid 64GB",
    ]
    .iter()
    .filter_map(|name| {
        preset(
            &base
                .join(".lmstudio/config-presets")
                .join(format!("{name}.preset.json")),
        )
    })
    .collect();
    let workspace = base.join("Documents/ChatGPT/aeris");
    let jobs: Vec<Value> = [
        ("read-only-smoke", "Read-only smoke"),
        ("disposable-edit", "Disposable edit"),
        ("live-write-smoke", "Write smoke"),
    ]
    .iter()
    .filter_map(|(file, label)| {
        let path = workspace.join("jobs").join(format!("{file}.toml"));
        path.is_file().then(|| json!({"name": label, "path": path}))
    })
    .collect();
    let models = base.join(".lmstudio/models");
    json!({"presets": presets, "jobs": jobs,
        "workspace": workspace.is_dir().then_some(workspace),
        "modelsPath": models.is_dir().then_some(models),
        "studioInstalled": base.join(".local/share/applications/lm-studio.desktop").is_file()})
}

pub fn status() -> Value {
    let mut snapshot = catalog(&home());
    snapshot["apis"] = json!([
        api_status("llama.cpp", 8080, false),
        api_status("LM Studio", 1234, true)
    ]);
    snapshot
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};

    fn reply(status: &str, body: &str) -> (u16, std::thread::JoinHandle<String>) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        let thread = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut request = Vec::new();
            let mut buffer = [0; 1024];
            while !request.windows(4).any(|w| w == b"\r\n\r\n") {
                let n = stream.read(&mut buffer).unwrap();
                assert!(n > 0);
                request.extend_from_slice(&buffer[..n]);
            }
            stream.write_all(response.as_bytes()).unwrap();
            String::from_utf8(request).unwrap()
        });
        (port, thread)
    }

    #[test]
    fn probes_are_read_only_and_failure_states_are_explicit() {
        for (status, body, expected) in [
            ("401 Unauthorized", "{}", "AUTH REQUIRED"),
            ("503 Unavailable", "{}", "UNAVAILABLE"),
            ("302 Found", "{}", "HTTP 302"),
            ("200 OK", "not JSON", "INVALID RESPONSE"),
        ] {
            let (port, server) = reply(status, body);
            assert_eq!(endpoint(port, "/api/v1/models").unwrap_err(), expected);
            let request = server.join().unwrap();
            assert!(request.starts_with("GET /api/v1/models HTTP/1.1\r\n"));
            assert!(!request.to_lowercase().contains("authorization:"));
        }
        let (port, server) = reply("200 OK", r#"{"status":"ok"}"#);
        assert_eq!(endpoint(port, "/health").unwrap()["status"], "ok");
        server.join().unwrap();
    }
    #[test]
    fn distinguishes_downloaded_from_loaded() {
        let v = json!({"models": [
            {"key":"downloaded", "loaded_instances":[]},
            {"key":"resident", "loaded_instances":[{"id":"one"}]}]});
        assert_eq!(lm_models(&v).unwrap(), ["resident"]);
        assert!(lm_models(&json!({"models":[{"key":"unknown"}]})).is_err());
        assert!(lm_models(&json!({"data":[]})).is_err());
    }
    #[test]
    fn absent_catalog_is_empty_not_a_mock() {
        let dir = tempfile::tempdir().unwrap();
        let data = catalog(dir.path());
        assert_eq!(data["presets"], json!([]));
        assert_eq!(data["jobs"], json!([]));
        assert!(data["workspace"].is_null());
        assert_eq!(data["studioInstalled"], false);
    }
    #[test]
    fn preset_reads_saved_settings_not_benchmark_claims() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.json");
        std::fs::write(
            &path,
            json!({"name":"Test", "load":{"fields":[
                {"key":"llm.load.contextLength","value":8192},
                {"key":"llm.load.llama.acceleration.offloadRatio","value":0.75}
            ]}})
            .to_string(),
        )
        .unwrap();
        let data = preset(&path).unwrap();
        assert_eq!(data["context"], 8192);
        assert_eq!(data["offload"], 0.75);
        assert!(data.get("tokensPerSecond").is_none());
    }
}
