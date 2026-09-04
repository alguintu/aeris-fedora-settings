use aeris_dashboard_backend::{
    artwork, awake, cooling,
    metrics::{Collector, CpuSamples, Paths},
    rgb, templates, tomat, weather,
};
use serde::Serialize;
use serde_json::{Value, json};
use std::env;
use std::io::{self, Write};
use std::process::ExitCode;
use std::sync::mpsc::{self, SyncSender};
use std::thread;
use std::time::{Duration, Instant};

fn emit(value: &impl Serialize) -> io::Result<()> {
    let mut output = io::stdout().lock();
    serde_json::to_writer(&mut output, value)?;
    output.write_all(b"\n")?;
    output.flush()
}

fn metrics_loop(mut publish: impl FnMut(Value) -> bool) {
    let mut collector = Collector::new(Paths::default());
    let started = Instant::now();
    let mut previous = CpuSamples::read(&collector.paths.proc_stat).ok();
    thread::sleep(Duration::from_millis(250));
    loop {
        let value = match CpuSamples::read(&collector.paths.proc_stat) {
            Ok(current) => {
                let snapshot = collector.collect(
                    previous.as_ref().unwrap_or(&current),
                    &current,
                    started.elapsed().as_secs_f64(),
                );
                previous = Some(current);
                match snapshot {
                    Ok(snapshot) => json!({"ok": true, "data": snapshot}),
                    Err(error) => json!({"ok": false, "error": error.to_string()}),
                }
            }
            Err(error) => json!({"ok": false, "error": error.to_string()}),
        };
        if !publish(value) {
            return;
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn send(sender: &SyncSender<Value>, service: &str, payload: Value) -> bool {
    sender
        .send(json!({"service": service, "payload": payload}))
        .is_ok()
}

fn watch() -> io::Result<()> {
    // A bounded queue prevents growth if the UI stops reading. RGB's deadline
    // and independent worker keep missing/restarting daemons off the metrics path.
    let (sender, receiver) = mpsc::sync_channel(4);
    let metrics_sender = sender.clone();
    thread::Builder::new()
        .name("aeris-metrics".into())
        .spawn(move || metrics_loop(|value| send(&metrics_sender, "metrics", value)))?;
    let cooling_sender = sender.clone();
    thread::Builder::new()
        .name("aeris-cooling".into())
        .spawn(move || {
            let mut client = cooling::Client::default();
            loop {
                if !send(&cooling_sender, "cooling", client.execute(None)) {
                    return;
                }
                thread::sleep(Duration::from_secs(1));
            }
        })?;
    let tomat_sender = sender.clone();
    thread::Builder::new()
        .name("aeris-tomat".into())
        .spawn(move || {
            let mut catalog = templates::Catalog::default();
            loop {
                let value = tomat::execute("watch", None, None, &mut catalog);
                let healthy = value["ok"] == true;
                if !send(&tomat_sender, "tomat", value) {
                    return;
                }
                thread::sleep(Duration::from_millis(if healthy { 500 } else { 2000 }));
            }
        })?;
    let awake_sender = sender.clone();
    thread::Builder::new()
        .name("aeris-awake".into())
        .spawn(move || awake::watch(|value| send(&awake_sender, "awake", value)))?;
    thread::Builder::new()
        .name("aeris-rgb".into())
        .spawn(move || {
            loop {
                if !send(&sender, "rgb", rgb::request(None)) {
                    return;
                }
                thread::sleep(Duration::from_secs(1));
            }
        })?;
    for value in receiver {
        emit(&value)?;
    }
    Ok(())
}

fn run(args: &[String]) -> io::Result<bool> {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["watch"] => {
            watch()?;
            Ok(true)
        }
        ["metrics", "--once"] => {
            let mut collector = Collector::new(Paths::default());
            let previous = CpuSamples::read(&collector.paths.proc_stat)?;
            thread::sleep(Duration::from_millis(250));
            let current = CpuSamples::read(&collector.paths.proc_stat)?;
            emit(&collector.collect(&previous, &current, 0.0)?)?;
            Ok(true)
        }
        ["metrics"] => {
            let mut error = None;
            metrics_loop(|value| {
                let result = if value["ok"] == true {
                    emit(&value["data"])
                } else {
                    emit(&value)
                };
                if let Err(err) = result {
                    error = Some(err);
                    false
                } else {
                    true
                }
            });
            if let Some(error) = error {
                return Err(error);
            }
            Ok(true)
        }
        ["rgb", "status"] | ["rgb", "set", _] => {
            let mode = if args.len() == 3 {
                Some(args[2].as_str())
            } else {
                None
            };
            let value = rgb::request(mode);
            emit(&value)?;
            Ok(value["ok"] == true)
        }
        ["rgb", "watch"] => loop {
            emit(&rgb::request(None))?;
            thread::sleep(Duration::from_secs(1));
        },
        ["cooling", "status"] | ["cooling", "set", _] => {
            let mut client = cooling::Client::default();
            let value = client.execute(args.get(2).map(String::as_str));
            emit(&value)?;
            Ok(value["ok"] == true)
        }
        ["cooling", "watch"] => {
            let mut client = cooling::Client::default();
            loop {
                emit(&client.execute(None))?;
                thread::sleep(Duration::from_secs(1));
            }
        }
        ["sleep", "status"] | ["sleep", "attach-bridge"] | ["sleep", "set", "on" | "off"] => {
            let value = awake::execute(args.last().unwrap());
            emit(&value)?;
            Ok(value["ok"] == true)
        }
        ["sleep", "watch"] => {
            let mut error = None;
            awake::watch(|v| match emit(&v) {
                Ok(()) => true,
                Err(e) => {
                    error = Some(e);
                    false
                }
            });
            if let Some(e) = error {
                return Err(e);
            }
            Ok(true)
        }
        ["tomat", "watch"] => {
            let mut catalog = templates::Catalog::default();
            loop {
                let value = tomat::execute("watch", None, None, &mut catalog);
                let healthy = value["ok"] == true;
                emit(&value)?;
                thread::sleep(Duration::from_millis(if healthy { 500 } else { 2000 }));
            }
        }
        ["tomat", "seek", elapsed, revision] => {
            let value = tomat::seek(elapsed, revision, &mut templates::Catalog::default());
            emit(&value)?;
            Ok(value["ok"] == true)
        }
        ["tomat", _] | ["tomat", "select", _, "next" | "now"] => {
            let value = tomat::execute(
                &args[1],
                args.get(2).map(String::as_str),
                args.get(3).map(String::as_str),
                &mut templates::Catalog::default(),
            );
            emit(&value)?;
            Ok(value["ok"] == true)
        }
        ["weather"] | ["weather", "--refresh"] => {
            emit(&weather::collect(args.len() > 1))?;
            Ok(true)
        }
        ["artwork", "--title", _] | ["artwork", "--title", _, "--artist", _] => {
            emit(&artwork::resolve(
                &args[2],
                args.get(4).map(String::as_str).unwrap_or(""),
            ))?;
            Ok(true)
        }
        ["--version"] => {
            println!("aeris-dashboard-backend {}", env!("CARGO_PKG_VERSION"));
            Ok(true)
        }
        ["--help"] => {
            println!(
                "aeris-dashboard-backend watch | metrics [--once] | rgb/cooling status|watch|set MODE | sleep status|watch|set on|off|attach-bridge | tomat ACTION [ID next|now] | weather [--refresh] | artwork --title TITLE [--artist ARTIST]"
            );
            Ok(true)
        }
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Use --help for supported commands",
        )),
    }
}

fn main() -> ExitCode {
    match run(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("aeris-dashboard-backend: {error}");
            ExitCode::FAILURE
        }
    }
}
