use crate::common::{self, Result, err};
use serde_json::{Value, json};
use std::{fs, os::unix::fs::MetadataExt, path::PathBuf, time::Duration};
pub const MODES: [(&str, &str); 4] = [
    ("default", "c156cd38-8428-4e6e-8c98-3ac7699c8bd8"),
    ("quiet", "013d1402-c9d8-4770-bf1a-fe52a20467e5"),
    ("performance", "0d23d4f7-13e8-49bd-95f2-410134ea5752"),
    ("firmware", "85327be8-d445-4397-b62a-df285c97326f"),
];
pub struct Client {
    agent: ureq::Agent,
    path: PathBuf,
    key: Option<(u64, i64, i64, u64)>,
    cookie: String,
}
impl Default for Client {
    fn default() -> Self {
        Self::new(common::home().join(".config/org.coolercontrol.CoolerControl/CoolerControl.conf"))
    }
}
impl Client {
    pub fn new(path: PathBuf) -> Self {
        Self {
            agent: common::agent(Duration::from_millis(1500), true),
            path,
            key: None,
            cookie: String::new(),
        }
    }
    pub fn cookie(&mut self) -> Result<String> {
        let info = fs::metadata(&self.path).map_err(err)?;
        let key = (info.ino(), info.mtime(), info.mtime_nsec(), info.len());
        if self.key != Some(key) {
            let source = fs::read_to_string(&self.path).map_err(err)?;
            self.cookie = source
                .lines()
                .find_map(|line| {
                    line.strip_prefix("networkCookies=\"@ByteArray(")
                        .and_then(|s| s.split_once(';'))
                        .map(|(value, _)| value)
                        .filter(|v| v.starts_with("cc=") && v.len() > 3)
                })
                .ok_or("CoolerControl session is unavailable")?
                .to_owned();
            self.key = Some(key);
        }
        Ok(self.cookie.clone())
    }
    fn request(&mut self, path: &str, post: bool) -> Result<Value> {
        // The only unverifiable certificate belongs to this fixed loopback service.
        let url = format!("https://127.0.0.1:11987{path}");
        self.request_url(&url, post)
    }
    fn request_url(&mut self, url: &str, post: bool) -> Result<Value> {
        for attempt in 0..if post { 1 } else { 2 } {
            let cookie = self.cookie()?;
            let response = if post {
                self.agent
                    .post(url)
                    .header("Cookie", &cookie)
                    .header("Content-Type", "application/json")
                    .send("{}")
            } else {
                self.agent.get(url).header("Cookie", &cookie).call()
            };
            match response {
                Ok(mut response) => {
                    let status = response.status().as_u16();
                    let body = response
                        .body_mut()
                        .with_config()
                        .limit(131072)
                        .read_to_vec()
                        .map_err(err)?;
                    if status == 401 || status == 403 {
                        self.key = None;
                        if !post && attempt == 0 {
                            continue;
                        }
                    }
                    if !(200..300).contains(&status) {
                        return Err(format!("CoolerControl returned HTTP {status}"));
                    }
                    return if body.is_empty() {
                        Ok(json!({}))
                    } else {
                        serde_json::from_slice(&body).map_err(err)
                    };
                }
                Err(_) if !post && attempt == 0 => continue,
                Err(_) => return Err("CoolerControl connection failed".into()),
            }
        }
        Err("CoolerControl request failed".into())
    }
    pub fn status(&mut self) -> Result<Value> {
        Ok(map_status(&self.request("/modes-active", false)?))
    }
    pub fn execute(&mut self, mode: Option<&str>) -> Value {
        let result = (|| {
            if let Some(mode) = mode {
                let uid = MODES
                    .iter()
                    .find(|(name, _)| *name == mode)
                    .ok_or("Invalid cooling mode")?
                    .1;
                self.request(&format!("/modes-active/{uid}"), true)?;
            }
            let value = self.status()?;
            if let Some(mode) = mode
                && value["mode"] != mode
            {
                return Err("CoolerControl did not confirm the selected mode".into());
            }
            Ok(value)
        })();
        result.unwrap_or_else(
            |error: String| json!({"ok":false,"mode":"unknown","uid":"","error":error}),
        )
    }
}

pub fn map_status(value: &Value) -> Value {
    let uid = value["current_mode_uid"].as_str().unwrap_or("");
    let mode = MODES
        .iter()
        .find(|(_, id)| *id == uid)
        .map(|(mode, _)| *mode)
        .unwrap_or("unknown");
    json!({"ok":true,"mode":mode,"uid":uid,"error":if mode=="unknown" {"No recognized cooling mode is active"} else {""}})
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::thread;

    fn read_request(reader: &mut BufReader<TcpStream>) -> String {
        let mut headers = String::new();
        loop {
            let mut line = String::new();
            assert!(reader.read_line(&mut line).unwrap() > 0);
            if line == "\r\n" {
                break;
            }
            headers.push_str(&line);
        }
        let length = headers
            .lines()
            .find_map(|s| {
                s.to_lowercase()
                    .strip_prefix("content-length: ")
                    .map(|v| v.parse::<usize>().unwrap())
            })
            .unwrap_or(0);
        reader.read_exact(&mut vec![0; length]).unwrap();
        headers.to_lowercase()
    }

    #[test]
    fn pooled_status_reuses_connection_and_refreshes_auth_cookie() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("cookie.conf");
        fs::write(&path, "networkCookies=\"@ByteArray(cc=first; Path=/)\"\n").unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/modes-active", listener.local_addr().unwrap());
        let rotate_path = path.clone();
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            let mut reader = BufReader::new(stream);
            assert!(read_request(&mut reader).contains("cookie: cc=first"));
            fs::write(
                rotate_path,
                "networkCookies=\"@ByteArray(cc=second; Path=/)\"\n",
            )
            .unwrap();
            reader
                .get_mut()
                .write_all(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 2\r\n\r\n{}")
                .unwrap();
            assert!(read_request(&mut reader).contains("cookie: cc=second"));
            reader
                .get_mut()
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
                .unwrap();
            assert!(read_request(&mut reader).starts_with("get "));
            reader
                .get_mut()
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
                .unwrap();
        });
        let mut client = Client::new(path);
        assert_eq!(client.request_url(&url, false).unwrap(), json!({}));
        assert_eq!(client.request_url(&url, false).unwrap(), json!({}));
        server.join().unwrap();
    }

    #[test]
    fn ambiguous_mode_post_is_never_replayed() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("cookie.conf");
        fs::write(&path, "networkCookies=\"@ByteArray(cc=test; Path=/)\"\n").unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/mode", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            let mut reader = BufReader::new(stream);
            assert!(read_request(&mut reader).starts_with("post "));
            // The server accepted the command but lost its response.
            drop(reader);
            thread::sleep(Duration::from_millis(250));
            listener.set_nonblocking(true).unwrap();
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock
            );
        });
        assert!(Client::new(path).request_url(&url, true).is_err());
        server.join().unwrap();
    }
}
