use serde_json::Value;
use std::{
    env, fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
pub type Result<T> = std::result::Result<T, String>;
pub fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/nonexistent"))
}
pub fn xdg(key: &str, fallback: &str) -> PathBuf {
    env::var_os(key)
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
pub fn monotonic() -> f64 {
    let t = rustix::time::clock_gettime(rustix::time::ClockId::Monotonic);
    t.tv_sec as f64 + t.tv_nsec as f64 / 1e9
}
pub fn read_json(path: &Path, limit: u64) -> Result<Value> {
    let file = fs::File::open(path).map_err(err)?;
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes).map_err(err)?;
    if bytes.len() as u64 > limit {
        return Err("JSON file exceeds size limit".into());
    }
    serde_json::from_slice(&bytes).map_err(err)
}
pub fn atomic_json(path: &Path, data: &Value, sync: bool) -> Result<()> {
    let parent = path.parent().ok_or("Missing parent directory")?;
    fs::create_dir_all(parent).map_err(err)?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(err)?;
    serde_json::to_writer(&mut file, data).map_err(err)?;
    file.flush().map_err(err)?;
    if sync {
        file.as_file().sync_all().map_err(err)?;
    }
    file.persist(path).map_err(err)?;
    Ok(())
}
pub fn agent(timeout: Duration, loopback: bool) -> ureq::Agent {
    let tls = ureq::tls::TlsConfig::builder()
        .provider(ureq::tls::TlsProvider::NativeTls)
        .disable_verification(loopback)
        .build();
    let mut config = ureq::Agent::config_builder()
        .tls_config(tls)
        .timeout_global(Some(timeout))
        .http_status_as_error(false)
        .max_redirects(if loopback { 0 } else { 3 });
    // Never send the local authentication cookie through a configured proxy.
    if loopback {
        config = config.proxy(None);
    }
    config.build().into()
}
pub fn get(url: &str, timeout: Duration, limit: u64, user_agent: &str) -> Result<Vec<u8>> {
    let mut response = agent(timeout, false)
        .get(url)
        .header("User-Agent", user_agent)
        .call()
        .map_err(err)?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    response
        .body_mut()
        .with_config()
        .limit(limit)
        .read_to_vec()
        .map_err(err)
}
pub fn quote_plus(text: &str) -> String {
    let mut encoded = String::new();
    for b in text.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(b as char)
            }
            b' ' => encoded.push('+'),
            _ => encoded.push_str(&format!("%{b:02X}")),
        }
    }
    encoded
}
