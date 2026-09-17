//! Private HTTP adapter for the existing dashboard, or a dedicated LAN wake relay.
//! Bind only to loopback; use an authenticated HTTPS VPN proxy (Tailscale Serve).
use aeris_dashboard_backend::{
    awake, cooling,
    metrics::{Collector, CpuSamples, Paths},
    rgb, templates, tomat, workout,
};
use serde_json::{Value, json};
use std::io::Read;
use std::{
    env, fs, io,
    net::{Ipv4Addr, UdpSocket},
    os::unix::fs::PermissionsExt,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn failed(message: impl ToString) -> Value {
    json!({"ok":false,"error":message.to_string()})
}
type Cache = Arc<Mutex<Value>>;
fn publish(cache: &Cache, key: &str, data: Value) {
    cache.lock().unwrap()[key] = json!({"updated_at":now(),"payload":data});
}
fn start_collectors(cache: &Cache) {
    let tomat_cache = cache.clone();
    thread::spawn(move || {
        let mut catalog = templates::Catalog::default();
        loop {
            publish(
                &tomat_cache,
                "tomat",
                tomat::execute("status", None, None, &mut catalog),
            );
            thread::sleep(Duration::from_secs(1));
        }
    });
    let metrics_cache = cache.clone();
    thread::spawn(move || {
        let mut collector = Collector::new(Paths::default());
        let mut previous = CpuSamples::read(&collector.paths.proc_stat).ok();
        let started = Instant::now();
        loop {
            thread::sleep(Duration::from_secs(2));
            let result = CpuSamples::read(&collector.paths.proc_stat).and_then(|current| {
                let result = collector.collect(
                    previous.as_ref().unwrap_or(&current),
                    &current,
                    started.elapsed().as_secs_f64(),
                );
                previous = Some(current);
                result
            });
            let value = match result {
                Ok(data) => json!({"ok":true,"data":data}),
                Err(e) => failed(e),
            };
            publish(&metrics_cache, "metrics", value);
        }
    });
    for key in ["rgb", "cooling", "awake"] {
        let cache = cache.clone();
        thread::spawn(move || {
            let mut cooling = cooling::Client::default();
            loop {
                let value = match key {
                    "rgb" => rgb::request(None),
                    "cooling" => cooling.execute(None),
                    _ => awake::execute("status"),
                };
                publish(&cache, key, value);
                thread::sleep(Duration::from_secs(2));
            }
        });
    }
}

fn magic_packet(mac: &str) -> Result<[u8; 102], &'static str> {
    let octets = mac
        .split(':')
        .map(|s| {
            if s.len() == 2 {
                u8::from_str_radix(s, 16).ok()
            } else {
                None
            }
        })
        .collect::<Option<Vec<_>>>()
        .ok_or("Invalid MAC address")?;
    if octets.len() != 6 || octets[0] & 1 != 0 || octets.iter().all(|v| *v == 0) {
        return Err("Expected a unicast MAC address");
    }
    let mut packet = [0xff; 102];
    for chunk in packet[6..].chunks_mut(6) {
        chunk.copy_from_slice(&octets);
    }
    Ok(packet)
}
fn authorized(header: Option<&str>, token: &str) -> bool {
    header
        .and_then(|h| h.strip_prefix("Bearer "))
        .is_some_and(|given| {
            given.len() == token.len() && bool::from(given.as_bytes().ct_eq(token.as_bytes()))
        })
}
fn power_off() -> Value {
    let result = (|| -> Result<(), Box<dyn std::error::Error>> {
        let connection = dbus::blocking::Connection::new_system()?;
        let proxy = connection.with_proxy(
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            Duration::from_secs(5),
        );
        let (allowed,): (String,) =
            proxy.method_call("org.freedesktop.login1.Manager", "CanPowerOff", ())?;
        if allowed != "yes" {
            return Err("Shutdown requires local authorization".into());
        }
        let (): () = proxy.method_call("org.freedesktop.login1.Manager", "PowerOff", (false,))?;
        Ok(())
    })();
    match result {
        Ok(()) => json!({"ok":true,"message":"Shutdown requested"}),
        Err(e) => failed(e),
    }
}

struct App {
    token: String,
    cache: Cache,
    wake: Option<([u8; 102], Ipv4Addr)>,
    actions: Mutex<()>,
    last_wake: Mutex<Option<Instant>>,
    allow_poweroff: bool,
}
fn header<'a>(request: &'a Request, name: &str) -> Option<&'a str> {
    request
        .headers()
        .iter()
        .find(|h| h.field.to_string().eq_ignore_ascii_case(name))
        .map(|h| h.value.as_str())
}
fn route(app: &App, request: &Request) -> (u16, Value) {
    if !authorized(header(request, "Authorization"), &app.token) {
        return (401, failed("Pairing token rejected"));
    }
    // Browser origins are not clients. Tokens are never accepted in URLs/cookies.
    if header(request, "Origin").is_some() {
        return (403, failed("Browser requests are not supported"));
    }
    if request.method() == &Method::Get && request.url() == "/v1/status" {
        return (
            200,
            json!({"ok":true,"role":if app.wake.is_some() {"relay"} else {"aeris"},"server_time":now(),"shutdown_enabled":app.allow_poweroff,"services":app.cache.lock().unwrap().clone()}),
        );
    }
    if request.method() != &Method::Post {
        return (404, failed("Unknown endpoint"));
    }
    if request.body_length().unwrap_or(0) > 0 || header(request, "Transfer-Encoding").is_some() {
        return (400, failed("This endpoint accepts no request body"));
    }
    let Ok(_action) = app.actions.try_lock() else {
        return (409, failed("Another control action is running"));
    };
    if let Some((packet, broadcast)) = &app.wake {
        if request.url() != "/v1/wake" {
            return (404, failed("Relay supports wake only"));
        }
        let mut last = app.last_wake.lock().unwrap();
        if last.is_some_and(|t| t.elapsed() < Duration::from_secs(10)) {
            return (
                429,
                failed("Wait ten seconds before sending another wake request"),
            );
        }
        let result = (|| -> io::Result<()> {
            let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
            socket.set_broadcast(true)?;
            socket.send_to(packet, (*broadcast, 9))?;
            Ok(())
        })();
        return match result {
            Ok(()) => {
                *last = Some(Instant::now());
                (
                    202,
                    json!({"ok":true,"message":"Wake packet sent; waiting for Aeris to become reachable"}),
                )
            }
            Err(e) => (502, failed(e)),
        };
    }
    if request.url() == "/v1/poweroff" {
        if !app.allow_poweroff {
            return (403, failed("Shutdown is not enabled on this server"));
        }
        if header(request, "X-Aeris-Confirm") != Some("poweroff") {
            return (400, failed("Shutdown confirmation required"));
        }
        let value = power_off();
        return (if value["ok"] == true { 202 } else { 502 }, value);
    }
    let parts: Vec<_> = request.url().split('/').collect();
    let value = match parts.as_slice() {
        ["", "v1", "rgb", mode] if rgb::MODES.contains(mode) => rgb::request(Some(mode)),
        ["", "v1", "cooling", mode] if cooling::MODES.iter().any(|(m, _)| m == mode) => {
            cooling::Client::default().execute(Some(mode))
        }
        ["", "v1", "awake", mode] if ["normal", "system", "full"].contains(mode) => {
            awake::execute(mode)
        }
        _ => return (404, failed("Unknown control or mode")),
    };
    publish(&app.cache, parts[2], value.clone());
    (if value["ok"] == true { 200 } else { 502 }, value)
}
fn reply(request: Request, code: u16, value: Value) {
    let response = Response::from_string(value.to_string())
        .with_status_code(StatusCode(code))
        .with_header(Header::from_bytes("Content-Type", "application/json").unwrap())
        .with_header(Header::from_bytes("Cache-Control", "no-store").unwrap())
        .with_header(Header::from_bytes("X-Content-Type-Options", "nosniff").unwrap());
    let _ = request.respond(response);
}

fn route_with_body(app: &App, request: &mut Request) -> (u16, Value) {
    if !["/v1/tomat", "/v1/workout/set"].contains(&request.url()) {
        return route(app, request);
    }
    if !authorized(header(request, "Authorization"), &app.token) {
        return (401, failed("Pairing token rejected"));
    }
    if header(request, "Origin").is_some() {
        return (403, failed("Browser requests are not supported"));
    }
    if app.wake.is_some() || request.method() != &Method::Post {
        return (404, failed("Unknown endpoint"));
    }
    if header(request, "Transfer-Encoding").is_some()
        || header(request, "Content-Type") != Some("application/json")
        || !request
            .body_length()
            .is_some_and(|n| (1..=4096).contains(&n))
    {
        return (400, failed("Expected a JSON body of at most 4096 bytes"));
    }
    let Ok(_guard) = app.actions.try_lock() else {
        return (409, failed("Another control action is running"));
    };
    let mut bytes = Vec::new();
    if std::io::Read::read_to_end(&mut request.as_reader().take(4097), &mut bytes).is_err()
        || bytes.len() > 4096
    {
        return (400, failed("Invalid request body"));
    }
    let Ok(body) = serde_json::from_slice(&bytes) else {
        return (400, failed("Invalid JSON"));
    };
    let result = if request.url() == "/v1/tomat" {
        tomat::remote(body, &mut templates::Catalog::default()).map(|timer| {
            publish(&app.cache, "tomat", timer.clone());
            json!({"ok":true,"timer":timer})
        })
    } else {
        workout::record(body).map(|day| {
            publish(
                &app.cache,
                "tomat",
                tomat::execute("status", None, None, &mut templates::Catalog::default()),
            );
            json!({"ok":true,"workout":day})
        })
    };
    match result {
        Ok(value) => (200, value),
        Err(error) => (409, failed(error)),
    }
}
fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let token_path = env::var("AERIS_COMPANION_TOKEN_FILE")?;
    if fs::metadata(&token_path)?.permissions().mode() & 0o077 != 0 {
        return Err("Token file must be private (chmod 600)".into());
    }
    let token = fs::read_to_string(token_path)?.trim().to_owned();
    if token.len() < 64 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("Token must contain at least 64 hexadecimal characters".into());
    }
    let role = env::var("AERIS_COMPANION_ROLE").unwrap_or_else(|_| "aeris".into());
    let wake = match role.as_str() {
        "aeris" => None,
        "relay" => Some((
            magic_packet(&env::var("AERIS_WAKE_MAC")?)?,
            env::var("AERIS_WAKE_BROADCAST")?.parse::<Ipv4Addr>()?,
        )),
        _ => return Err("Role must be aeris or relay".into()),
    };
    let port = env::var("AERIS_COMPANION_PORT")
        .unwrap_or_else(|_| "4280".into())
        .parse::<u16>()?;
    let server = Arc::new(Server::http((Ipv4Addr::LOCALHOST, port))?);
    let cache = Arc::new(Mutex::new(json!({})));
    if wake.is_none() {
        start_collectors(&cache);
    }
    let app = Arc::new(App {
        token,
        cache,
        wake,
        actions: Mutex::new(()),
        last_wake: Mutex::new(None),
        allow_poweroff: role == "aeris" && env::var("AERIS_ALLOW_POWEROFF").as_deref() == Ok("1"),
    });
    eprintln!("Aeris companion {role} listening on 127.0.0.1:{port}");
    let mut workers = Vec::new();
    for _ in 0..4 {
        let server = server.clone();
        let app = app.clone();
        workers.push(thread::spawn(move || {
            for mut request in server.incoming_requests() {
                let (code, value) = route_with_body(&app, &mut request);
                reply(request, code, value);
            }
        }));
    }
    for worker in workers {
        let _ = worker.join();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn app(relay: bool) -> App {
        App {
            token: "a".repeat(64),
            cache: Arc::new(Mutex::new(json!({}))),
            wake: relay.then(|| {
                (
                    magic_packet("2c:f0:5d:57:a2:c2").unwrap(),
                    Ipv4Addr::LOCALHOST,
                )
            }),
            actions: Mutex::new(()),
            last_wake: Mutex::new(None),
            allow_poweroff: false,
        }
    }
    fn request(method: Method, path: &str) -> tiny_http::TestRequest {
        tiny_http::TestRequest::new()
            .with_method(method)
            .with_path(path)
            .with_header(
                Header::from_bytes("Authorization", format!("Bearer {}", "a".repeat(64))).unwrap(),
            )
    }
    #[test]
    fn unauthenticated_requests_never_reach_controls() {
        for path in ["/v1/status", "/v1/poweroff", "/v1/rgb/off", "/v1/wake"] {
            let request = tiny_http::TestRequest::new()
                .with_method(Method::Post)
                .with_path(path)
                .into();
            assert_eq!(route(&app(false), &request).0, 401);
        }
    }
    #[test]
    fn fixed_routes_reject_unexpected_actions_and_bodies() {
        let app = app(false);
        for path in [
            "/v1/wake",
            "/v1/cooling/0",
            "/v1/awake/on",
            "/v1/rgb/custom",
            "/v1/exec/reboot",
        ] {
            assert_eq!(route(&app, &request(Method::Post, path).into()).0, 404);
        }
        assert_eq!(
            route(&app, &request(Method::Get, "/v1/rgb/off").into()).0,
            404
        );
        assert_eq!(
            route(
                &app,
                &request(Method::Post, "/v1/rgb/off").with_body("{}").into()
            )
            .0,
            400
        );
        assert_eq!(
            route(
                &app,
                &request(Method::Get, "/v1/status")
                    .with_header(Header::from_bytes("Origin", "https://example.com").unwrap())
                    .into()
            )
            .0,
            403
        );
    }
    #[test]
    fn relay_cannot_control_the_pc_and_shutdown_is_explicit() {
        let relay = app(true);
        assert_eq!(
            route(&relay, &request(Method::Post, "/v1/poweroff").into()).0,
            404
        );
        assert_eq!(
            route(&relay, &request(Method::Post, "/v1/rgb/off").into()).0,
            404
        );
        let mut local = app(false);
        assert_eq!(
            route(&local, &request(Method::Post, "/v1/poweroff").into()).0,
            403
        );
        local.allow_poweroff = true;
        assert_eq!(
            route(&local, &request(Method::Post, "/v1/poweroff").into()).0,
            400
        );
    }
    #[test]
    fn status_exposes_freshness_and_role_without_credentials() {
        let app = app(false);
        publish(&app.cache, "rgb", json!({"ok":true,"mode":"work"}));
        let (code, value) = route(&app, &request(Method::Get, "/v1/status").into());
        assert_eq!(code, 200);
        assert_eq!(value["role"], "aeris");
        assert_eq!(value["services"]["rgb"]["payload"]["mode"], "work");
        assert!(value["services"]["rgb"]["updated_at"].as_u64().unwrap() > 0);
        assert!(!value.to_string().contains(&app.token));
    }
    #[test]
    fn busy_actions_are_rejected_without_retries() {
        let app = app(false);
        let _guard = app.actions.lock().unwrap();
        assert_eq!(
            route(&app, &request(Method::Post, "/v1/rgb/off").into()).0,
            409
        );
    }
    #[test]
    fn packet_targets_only_configured_mac() {
        let packet = magic_packet("2c:f0:5d:57:a2:c2").unwrap();
        assert_eq!(&packet[..6], &[255; 6]);
        for mac in packet[6..].chunks(6) {
            assert_eq!(mac, &[0x2c, 0xf0, 0x5d, 0x57, 0xa2, 0xc2]);
        }
        for invalid in [
            "",
            "a:b:c:d:e:f",
            "ff:ff:ff:ff:ff:ff",
            "00:00:00:00:00:00",
            "2c:f0:5d:57:a2",
        ] {
            assert!(magic_packet(invalid).is_err());
        }
    }
    #[test]
    fn authentication_rejects_missing_or_altered_credentials() {
        let token = "a".repeat(64);
        assert!(authorized(Some(&format!("Bearer {token}")), &token));
        for given in [None, Some(""), Some("Bearer a"), Some("Basic aaa")] {
            assert!(!authorized(given, &token));
        }
        assert!(!authorized(
            Some(&format!("Bearer {}b", "a".repeat(63))),
            &token
        ));
    }
}
