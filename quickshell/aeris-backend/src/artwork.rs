use crate::common;
use serde_json::{Value, json};
use std::time::Duration;
use unicode_casefold::UnicodeCaseFold;
pub fn key(title: &str, artist: &str) -> String {
    format!("{artist} {title}")
        .case_fold()
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
pub fn youtube_url(page: &str) -> String {
    for rest in page.split("\"videoId\":\"").skip(1) {
        if let Some(id) = rest.get(..11)
            && rest.as_bytes().get(11) == Some(&b'"')
            && id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        {
            return format!("https://i.ytimg.com/vi/{id}/hqdefault.jpg");
        }
    }
    String::new()
}
pub fn resolve(title: &str, artist: &str) -> Value {
    let key = key(title, artist);
    if key.is_empty() {
        return json!({"url":""});
    }
    let path = common::xdg("XDG_CACHE_HOME", ".cache").join("aeris-dashboard/media-art.json");
    let mut cache = common::read_json(&path, 8 * 1024 * 1024)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
    let now = common::now();
    if let Some(url) = cache[&key]["url"].as_str().filter(|s| !s.is_empty())
        && cache[&key]["updated"]
            .as_f64()
            .is_some_and(|n| (0.0..30.0 * 86400.0).contains(&(now - n)))
    {
        return json!({"url":url});
    }
    let query = [artist.trim(), title.trim()]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let url = format!(
        "https://www.youtube.com/results?search_query={}",
        common::quote_plus(&query)
    );
    let art = common::get(&url, Duration::from_secs(8), 8 * 1024 * 1024, "Mozilla/5.0")
        .map(|bytes| youtube_url(&String::from_utf8_lossy(&bytes)))
        .unwrap_or_default();
    if !art.is_empty() {
        cache[&key] = json!({"url":art,"updated":now.floor()});
        let _ = common::atomic_json(&path, &cache, false);
    }
    json!({"url":art})
}
