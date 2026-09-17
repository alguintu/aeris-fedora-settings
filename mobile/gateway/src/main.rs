//! CasaOS-only bridge: private HTTPS -> loopback gateway -> restricted SSH tunnel.
//! Separate loopback listener/token for wake keeps the existing Android APK compatible.
use serde_json::{Value, json};
use std::io::Read;
use std::{
    fs,
    net::{Ipv4Addr, UdpSocket},
    os::unix::fs::PermissionsExt,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;
use tiny_http::{Header, Method, Request, Response, Server};

struct App {
    control_token: String,
    wake_token: String,
    upstream_token: String,
    agent: ureq::Agent,
    upstream: String,
    packet: [u8; 102],
    broadcast: Ipv4Addr,
    actions: Mutex<()>,
    last_wake: Mutex<Option<Instant>>,
}
fn error(message: &str) -> Value {
    json!({"ok":false,"error":message})
}
fn header<'a>(r: &'a Request, key: &str) -> Option<&'a str> {
    r.headers()
        .iter()
        .find(|h| h.field.to_string().eq_ignore_ascii_case(key))
        .map(|h| h.value.as_str())
}
fn authorized(value: Option<&str>, token: &str) -> bool {
    value
        .and_then(|s| s.strip_prefix("Bearer "))
        .is_some_and(|s| s.len() == token.len() && bool::from(s.as_bytes().ct_eq(token.as_bytes())))
}
fn allowed(path: &str) -> bool {
    matches!(
        path,
        "/v1/poweroff"
            | "/v1/rgb/work"
            | "/v1/rgb/night"
            | "/v1/rgb/day"
            | "/v1/rgb/off"
            | "/v1/rgb/party"
            | "/v1/cooling/default"
            | "/v1/cooling/quiet"
            | "/v1/cooling/performance"
            | "/v1/cooling/firmware"
            | "/v1/awake/normal"
            | "/v1/awake/system"
            | "/v1/awake/full"
    )
}
fn packet(mac: &str) -> Result<[u8; 102], &'static str> {
    let octets: Vec<u8> = mac
        .split(':')
        .map(|s| {
            if s.len() == 2 {
                u8::from_str_radix(s, 16).ok()
            } else {
                None
            }
        })
        .collect::<Option<_>>()
        .ok_or("Invalid wake MAC")?;
    if octets.len() != 6 || octets[0] & 1 != 0 || octets.iter().all(|n| *n == 0) {
        return Err("Invalid wake MAC");
    }
    let mut result = [255; 102];
    for chunk in result[6..].chunks_mut(6) {
        chunk.copy_from_slice(&octets);
    }
    Ok(result)
}
fn proxy(app: &App, r: &Request) -> (u16, Value) {
    proxy_with_body(app, r, None)
}
fn proxy_with_body(app: &App, r: &Request, body: Option<&[u8]>) -> (u16, Value) {
    let url = format!("{}{}", app.upstream, r.url());
    let auth = format!("Bearer {}", app.upstream_token);
    // Fresh connection for each command, no redirects/proxy environment, no action retries.
    let result = if r.method() == &Method::Get {
        app.agent
            .get(&url)
            .header("Authorization", &auth)
            .header("Connection", "close")
            .config()
            .timeout_global(Some(Duration::from_secs(4)))
            .build()
            .call()
    } else {
        let mut request = app
            .agent
            .post(&url)
            .header("Authorization", &auth)
            .header("Connection", "close");
        if r.url() == "/v1/poweroff" {
            request = request.header("X-Aeris-Confirm", "poweroff");
        }
        if let Some(body) = body {
            request
                .header("Content-Type", "application/json")
                .send(body)
        } else {
            request.send_empty()
        }
    };
    let Ok(mut response) = result else {
        return (
            503,
            error("Aeris is unreachable. Check its connection before retrying an action."),
        );
    };
    let code = response.status().as_u16();
    if !(200..300).contains(&code) && !(400..600).contains(&code) {
        return (502, error("Unexpected response from Aeris"));
    }
    let value = response
        .body_mut()
        .with_config()
        .limit(262144)
        .read_to_vec()
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok());
    match value {
        Some(v) if v.get("ok").is_some_and(Value::is_boolean) => (code, v),
        _ => (502, error("Invalid response from Aeris")),
    }
}
fn route(app: &App, r: &Request, wake: bool) -> (u16, Value) {
    let token = if wake {
        &app.wake_token
    } else {
        &app.control_token
    };
    if !authorized(header(r, "Authorization"), token) {
        return (401, error("Pairing token rejected"));
    }
    if header(r, "Origin").is_some() {
        return (403, error("Browser requests are not supported"));
    }
    if r.body_length().unwrap_or(0) > 0 || header(r, "Transfer-Encoding").is_some() {
        return (400, error("This endpoint accepts no request body"));
    }
    if r.method() == &Method::Get && r.url() == "/v1/status" {
        return if wake {
            (
                200,
                json!({"ok":true,"role":"relay","services":{},"shutdown_enabled":false,
            "server_time":SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()}),
            )
        } else {
            proxy(app, r)
        };
    }
    if r.method() != &Method::Post
        || (wake && r.url() != "/v1/wake")
        || (!wake && !allowed(r.url()))
    {
        return (404, error("Unknown endpoint"));
    }
    if r.url() == "/v1/poweroff" && header(r, "X-Aeris-Confirm") != Some("poweroff") {
        return (400, error("Shutdown confirmation required"));
    }
    let Ok(_guard) = app.actions.try_lock() else {
        return (409, error("Another action is running"));
    };
    if !wake {
        return proxy(app, r);
    }
    let mut last = app.last_wake.lock().unwrap();
    if last.is_some_and(|t| t.elapsed() < Duration::from_secs(10)) {
        return (
            429,
            error("Wait ten seconds before sending another wake request"),
        );
    }
    let result = (|| -> std::io::Result<()> {
        let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
        socket.set_broadcast(true)?;
        socket.send_to(&app.packet, (app.broadcast, 9))?;
        Ok(())
    })();
    match result {
        Ok(()) => {
            *last = Some(Instant::now());
            (
                202,
                json!({"ok":true,"message":"Wake packet sent; waiting for Aeris to become reachable"}),
            )
        }
        Err(_) => (502, error("Unable to send wake packet")),
    }
}
fn secret(path: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    if fs::metadata(path)?.permissions().mode() & 0o077 != 0 {
        return Err("Token file must be private".into());
    }
    let token = fs::read_to_string(path)?.trim().to_owned();
    if token.len() != 64 || !token.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err("Expected 64 hexadecimal token characters".into());
    }
    Ok(token)
}
fn route_with_body(app: &App, r: &mut Request, wake: bool) -> (u16, Value) {
    if !["/v1/tomat", "/v1/workout/set"].contains(&r.url()) {
        return route(app, r, wake);
    }
    let token = if wake {
        &app.wake_token
    } else {
        &app.control_token
    };
    if !authorized(header(r, "Authorization"), token) {
        return (401, error("Pairing token rejected"));
    }
    if header(r, "Origin").is_some() {
        return (403, error("Browser requests are not supported"));
    }
    if wake || r.method() != &Method::Post {
        return (404, error("Unknown endpoint"));
    }
    if header(r, "Transfer-Encoding").is_some()
        || header(r, "Content-Type") != Some("application/json")
        || !r.body_length().is_some_and(|n| (1..=4096).contains(&n))
    {
        return (400, error("Expected a JSON body of at most 4096 bytes"));
    }
    let Ok(_guard) = app.actions.try_lock() else {
        return (409, error("Another action is running"));
    };
    let mut bytes = Vec::new();
    if r.as_reader().take(4097).read_to_end(&mut bytes).is_err()
        || bytes.len() > 4096
        || serde_json::from_slice::<Value>(&bytes)
            .ok()
            .is_none_or(|v| !v.is_object())
    {
        return (400, error("Invalid JSON body"));
    }
    proxy_with_body(app, r, Some(&bytes))
}
fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let dir = std::env::var("AERIS_GATEWAY_CONFIG").unwrap_or_else(|_| "/etc/aeris-gateway".into());
    let app = Arc::new(App {
        control_token: secret(&format!("{dir}/control.secret"))?,
        wake_token: secret(&format!("{dir}/wake.secret"))?,
        upstream_token: secret(&format!("{dir}/upstream.secret"))?,
        agent: ureq::Agent::config_builder()
            .proxy(None)
            .max_redirects(0)
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(30)))
            .max_idle_connections(0)
            .build()
            .into(),
        upstream: "http://127.0.0.1:4281".into(),
        packet: packet("2c:f0:5d:57:a2:c2")?,
        broadcast: Ipv4Addr::new(192, 168, 5, 255),
        actions: Mutex::new(()),
        last_wake: Mutex::new(None),
    });
    let mut workers = vec![];
    for (port, wake) in [(4280, false), (4282, true)] {
        let server = Arc::new(Server::http((Ipv4Addr::LOCALHOST, port))?);
        for _ in 0..4 {
            let (server, app) = (server.clone(), app.clone());
            workers.push(thread::spawn(move || {
                for mut request in server.incoming_requests() {
                    let (code, value) = route_with_body(&app, &mut request, wake);
                    let response = Response::from_string(value.to_string())
                        .with_status_code(code)
                        .with_header(
                            Header::from_bytes("Content-Type", "application/json").unwrap(),
                        )
                        .with_header(Header::from_bytes("Cache-Control", "no-store").unwrap())
                        .with_header(
                            Header::from_bytes("X-Content-Type-Options", "nosniff").unwrap(),
                        );
                    let _ = request.respond(response);
                }
            }));
        }
    }
    eprintln!("Aeris gateway: control 127.0.0.1:4280, wake 127.0.0.1:4282");
    for worker in workers {
        let _ = worker.join();
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn workout_json_is_bounded_and_forwarded_once_with_upstream_auth() {
        let server = Server::http((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let mut a = app();
        a.upstream = format!("http://{}", server.server_addr());
        let expected_auth = format!("Bearer {}", a.upstream_token);
        let worker = thread::spawn(move || {
            let mut r = server.recv().unwrap();
            assert_eq!(r.url(), "/v1/workout/set");
            assert_eq!(header(&r, "Authorization"), Some(expected_auth.as_str()));
            assert_eq!(header(&r, "Content-Type"), Some("application/json"));
            let mut body = String::new();
            r.as_reader().read_to_string(&mut body).unwrap();
            assert_eq!(body, r#"{"request_id":"test"}"#);
            r.respond(
                Response::from_string(r#"{"ok":false,"error":"conflict"}"#).with_status_code(409),
            )
            .unwrap();
            assert!(
                server
                    .recv_timeout(Duration::from_millis(100))
                    .unwrap()
                    .is_none()
            );
        });
        let request = || {
            tiny_http::TestRequest::new()
                .with_method(Method::Post)
                .with_path("/v1/workout/set")
                .with_header(
                    Header::from_bytes("Authorization", format!("Bearer {}", a.control_token))
                        .unwrap(),
                )
                .with_header(Header::from_bytes("Content-Type", "application/json").unwrap())
        };
        assert_eq!(
            route_with_body(&a, &mut request().with_body(Box::leak("x".repeat(4097).into_boxed_str())).into(), false).0,
            400
        );
        assert_eq!(
            route_with_body(&a, &mut request().with_body("[]").into(), false).0,
            400
        );
        assert_eq!(
            route_with_body(
                &a,
                &mut request().with_body(r#"{"request_id":"test"}"#).into(),
                false
            )
            .0,
            409
        );
        worker.join().unwrap();
        let mut relay = tiny_http::TestRequest::new()
            .with_method(Method::Post)
            .with_path("/v1/workout/set")
            .with_header(
                Header::from_bytes("Authorization", format!("Bearer {}", a.wake_token)).unwrap(),
            )
            .with_body("{}")
            .into();
        assert_eq!(route_with_body(&a, &mut relay, true).0, 404);
    }
    fn app() -> App {
        App {
            control_token: "a".repeat(64),
            wake_token: "b".repeat(64),
            upstream_token: "c".repeat(64),
            agent: ureq::Agent::config_builder()
                .proxy(None)
                .max_redirects(0)
                .http_status_as_error(false)
                .build()
                .into(),
            upstream: "http://127.0.0.1:1".into(),
            packet: packet("2c:f0:5d:57:a2:c2").unwrap(),
            broadcast: Ipv4Addr::LOCALHOST,
            actions: Mutex::new(()),
            last_wake: Mutex::new(None),
        }
    }
    fn req(method: Method, path: &str, token: &str) -> Request {
        tiny_http::TestRequest::new()
            .with_method(method)
            .with_path(path)
            .with_header(Header::from_bytes("Authorization", format!("Bearer {token}")).unwrap())
            .into()
    }
    #[test]
    fn access_boundaries() {
        let a = app();
        assert_eq!(
            route(&a, &req(Method::Get, "/v1/status", &a.wake_token), false).0,
            401
        );
        assert_eq!(
            route(
                &a,
                &req(Method::Post, "/v1/poweroff", &a.control_token),
                true
            )
            .0,
            401
        );
        assert_eq!(
            route(&a, &req(Method::Post, "/v1/poweroff", &a.wake_token), true).0,
            404
        );
        for path in [
            "/v1/exec",
            "/v1/status?token=x",
            "/v1/wake",
            "/v1/rgb/custom",
            "/v1/../poweroff",
        ] {
            assert_eq!(
                route(&a, &req(Method::Post, path, &a.control_token), false).0,
                404
            );
        }
        assert_eq!(
            route(
                &a,
                &req(Method::Post, "/v1/poweroff", &a.control_token),
                false
            )
            .0,
            400
        );
        assert_eq!(
            route(&a, &req(Method::Get, "/v1/status", &a.wake_token), true).1["role"],
            "relay"
        );
    }
    #[test]
    fn offline_is_not_reported_as_powered_off() {
        let a = app();
        let (code, v) = route(&a, &req(Method::Get, "/v1/status", &a.control_token), false);
        assert_eq!(code, 503);
        assert_eq!(v["ok"], false);
        assert!(!v.to_string().contains(&a.upstream_token));
    }
    #[test]
    fn rejects_browser_and_bodies() {
        let a = app();
        for extra in [
            Header::from_bytes("Origin", "https://bad.example").unwrap(),
            Header::from_bytes("Transfer-Encoding", "chunked").unwrap(),
        ] {
            let r = tiny_http::TestRequest::new()
                .with_method(Method::Post)
                .with_path("/v1/rgb/off")
                .with_header(
                    Header::from_bytes("Authorization", format!("Bearer {}", a.control_token))
                        .unwrap(),
                )
                .with_header(extra)
                .into();
            assert!(matches!(route(&a, &r, false).0, 400 | 403));
        }
    }
    #[test]
    fn configured_wake_packet_and_cooldown() {
        let mut a = app();
        for c in a.packet[6..].chunks(6) {
            assert_eq!(c, &[44, 240, 93, 87, 162, 194]);
        }
        a.last_wake = Mutex::new(Some(Instant::now()));
        assert_eq!(
            route(&a, &req(Method::Post, "/v1/wake", &a.wake_token), true).0,
            429
        );
        assert!(packet("ff:ff:ff:ff:ff:ff").is_err());
    }
    #[test]
    fn proxy_uses_upstream_credential_and_preserves_status() {
        let server = Server::http((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let mut a = app();
        a.upstream = format!("http://{}", server.server_addr());
        let upstream = a.upstream_token.clone();
        let worker = thread::spawn(move || {
            let r = server.recv().unwrap();
            assert_eq!(r.url(), "/v1/status");
            assert_eq!(
                header(&r, "Authorization"),
                Some(format!("Bearer {upstream}").as_str())
            );
            r.respond(Response::from_string(
                r#"{"ok":true,"role":"aeris","services":{"metrics":{"updated_at":123}}}"#,
            ))
            .unwrap();
        });
        let (code, v) = route(&a, &req(Method::Get, "/v1/status", &a.control_token), false);
        assert_eq!(code, 200);
        assert_eq!(v["services"]["metrics"]["updated_at"], 123);
        worker.join().unwrap();
    }
    #[test]
    fn upstream_redirects_are_not_followed() {
        let server = Server::http((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let mut a = app();
        a.upstream = format!("http://{}", server.server_addr());
        let worker =
            thread::spawn(move || {
                let r = server.recv().unwrap();
                r.respond(Response::empty(302).with_header(
                    Header::from_bytes("Location", "http://127.0.0.1:1/secret").unwrap(),
                ))
                .unwrap();
            });
        assert_eq!(
            route(&a, &req(Method::Get, "/v1/status", &a.control_token), false).0,
            502
        );
        worker.join().unwrap();
    }
    #[test]
    fn confirmed_shutdown_is_forwarded_once_without_body() {
        let server = Server::http((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let mut a = app();
        a.upstream = format!("http://{}", server.server_addr());
        let worker = thread::spawn(move || {
            let r = server.recv().unwrap();
            assert_eq!(r.method(), &Method::Post);
            assert_eq!(r.url(), "/v1/poweroff");
            assert_eq!(header(&r, "X-Aeris-Confirm"), Some("poweroff"));
            assert_eq!(r.body_length().unwrap_or(0), 0);
            r.respond(
                Response::from_string(r#"{"ok":true,"message":"mock only"}"#).with_status_code(202),
            )
            .unwrap();
            assert!(
                server
                    .recv_timeout(Duration::from_millis(100))
                    .unwrap()
                    .is_none()
            );
        });
        let r = tiny_http::TestRequest::new()
            .with_method(Method::Post)
            .with_path("/v1/poweroff")
            .with_header(
                Header::from_bytes("Authorization", format!("Bearer {}", a.control_token)).unwrap(),
            )
            .with_header(Header::from_bytes("X-Aeris-Confirm", "poweroff").unwrap())
            .into();
        assert_eq!(route(&a, &r, false).0, 202);
        worker.join().unwrap();
    }
}
