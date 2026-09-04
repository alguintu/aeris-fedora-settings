//! Matched implementation comparison. No hardware controls or timer commands.
//! Uses the retained read-only profiler and records proportional resident memory.
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn run(root: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new(args[0])
        .args(&args[1..])
        .current_dir(root)
        .output()?;
    if !output.status.success() {
        return Err(format!(
            "{}: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}
fn ipc(root: &Path, args: &[&str]) -> Result<String> {
    let mut command = vec!["bash", "scripts/run-dashboard.sh", "ipc"];
    command.extend_from_slice(args);
    run(root, &command)
}
fn call(root: &Path, target: &str, method: &str, args: &[&str]) -> Result<String> {
    let mut command = vec!["call", target, method];
    command.extend_from_slice(args);
    ipc(root, &command)
}

struct Session {
    root: PathBuf,
    override_path: PathBuf,
    mode: String,
    collapsed: String,
    armed: bool,
    weather: String,
}
impl Session {
    fn new(root: PathBuf) -> Result<Self> {
        let state: Value = serde_json::from_str(&call(&root, "dashboard", "backendStatus", &[])?)?;
        if state["implementation"] != "rust" {
            return Err("Start from the default Rust service".into());
        }
        let mode = ipc(&root, &["prop", "get", "dashboard", "mode"])?;
        let collapsed = ipc(&root, &["prop", "get", "dashboard", "collapsed"])?;
        let runtime = PathBuf::from(env::var("XDG_RUNTIME_DIR")?);
        let override_path =
            runtime.join("systemd/user/aeris-dashboard.service.d/90-aeris-benchmark.conf");
        fs::create_dir_all(override_path.parent().unwrap())?;
        // Refuse to overwrite an existing experiment or user drop-in.
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&override_path)?;
        Ok(Self {
            root,
            override_path,
            mode,
            collapsed,
            armed: true,
            weather: "rain".into(),
        })
    }
    fn ready(&self, implementation: &str) -> Result<()> {
        for _ in 0..100 {
            if let Ok(raw) = call(&self.root, "dashboard", "backendStatus", &[])
                && let Ok(status) = serde_json::from_str::<Value>(&raw)
                && status["implementation"] == implementation
                && [
                    "metricsHealthy",
                    "lightingHealthy",
                    "coolingHealthy",
                    "tomatHealthy",
                ]
                .iter()
                .all(|k| status[*k] == true)
            {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(150));
        }
        Err(format!("{implementation} dashboard failed its readiness check").into())
    }
    fn switch(&self, implementation: &str) -> Result<()> {
        fs::write(
            &self.override_path,
            format!(
                "# aeris-dashboard-benchmark owned runtime override\n[Service]\nEnvironment=AERIS_DASHBOARD_BACKEND={implementation}\n"
            ),
        )?;
        self.restart(implementation)
    }
    fn switch_renderer(&self, renderer: &str) -> Result<()> {
        if !["opengl", "vulkan"].contains(&renderer) {
            return Err("Unsupported renderer".into());
        }
        fs::write(
            &self.override_path,
            format!(
                "# aeris-dashboard-benchmark owned runtime override\n[Service]\nEnvironment=AERIS_DASHBOARD_BACKEND=rust\nEnvironment=QSG_RHI_BACKEND={renderer}\nEnvironment=QSG_INFO=1\n"
            ),
        )?;
        self.restart("rust")?;
        let info: Value =
            serde_json::from_str(&call(&self.root, "dashboard", "renderingStatus", &[])?)?;
        if info["api"] != renderer {
            return Err(format!("Requested {renderer} but dashboard reports {info}").into());
        }
        Ok(())
    }
    fn restart(&self, implementation: &str) -> Result<()> {
        run(&self.root, &["systemctl", "--user", "daemon-reload"])?;
        run(
            &self.root,
            &["systemctl", "--user", "restart", "aeris-dashboard.service"],
        )?;
        self.ready(implementation)?;
        call(&self.root, "dashboard", "setMode", &["1"])?;
        call(&self.root, "dashboard", "showDashboard", &[])?;
        call(&self.root, "dashboard", "decorationRate", &["60"])?;
        call(&self.root, "dashboard", "simulateGpu", &["-1"])?;
        Ok(())
    }
    fn check_view(&mut self) -> Result<()> {
        let mode = ipc(&self.root, &["prop", "get", "dashboard", "mode"])?;
        let collapsed = ipc(&self.root, &["prop", "get", "dashboard", "collapsed"])?;
        if mode != "1" || collapsed != "false" {
            self.mode = mode;
            self.collapsed = collapsed;
            return Err(
                "Page/visibility changed; discard sample and preserve the user's selection".into(),
            );
        }
        Ok(())
    }
    fn restore(&mut self) -> Result<()> {
        if !self.armed {
            return Ok(());
        }
        if self.override_path.exists() {
            fs::remove_file(&self.override_path)?;
        }
        run(&self.root, &["systemctl", "--user", "daemon-reload"])?;
        run(
            &self.root,
            &["systemctl", "--user", "restart", "aeris-dashboard.service"],
        )?;
        self.ready("rust")?;
        call(&self.root, "dashboard", "setMode", &[&self.mode])?;
        call(
            &self.root,
            "dashboard",
            if self.collapsed == "true" {
                "hideDashboard"
            } else {
                "showDashboard"
            },
            &[],
        )?;
        self.armed = false;
        Ok(())
    }
}
impl Drop for Session {
    fn drop(&mut self) {
        if let Err(e) = self.restore() {
            eprintln!(
                "RESTORE FAILED: {e}. Remove only {} and restart the dashboard.",
                self.override_path.display()
            );
        }
    }
}

#[derive(Clone)]
struct ProcessSample {
    start: String,
    ticks: u64,
    pss_kib: f64,
    name: String,
    helper: bool,
}
fn processes(group: &Path) -> Result<BTreeMap<String, ProcessSample>> {
    let mut result = BTreeMap::new();
    for pid in fs::read_to_string(group.join("cgroup.procs"))?.split_whitespace() {
        let directory = PathBuf::from(format!("/proc/{pid}"));
        let Ok(raw) = fs::read_to_string(directory.join("stat")) else {
            continue;
        };
        let parts: Vec<_> = raw[raw.rfind(')').ok_or("Invalid /proc stat")? + 2..]
            .split_whitespace()
            .collect();
        let args = fs::read_to_string(directory.join("cmdline"))?;
        let fields: Vec<_> = args.split('\0').collect();
        let name = fields
            .iter()
            .find(|a| a.ends_with(".py"))
            .copied()
            .unwrap_or(fields[0]);
        let name = Path::new(name)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        let smaps = fs::read_to_string(directory.join("smaps_rollup"))?;
        let pss_kib = smaps
            .lines()
            .find_map(|l| l.strip_prefix("Pss:"))
            .ok_or("No PSS counter")?
            .split_whitespace()
            .next()
            .ok_or("Empty PSS")?
            .parse()?;
        result.insert(
            pid.to_owned(),
            ProcessSample {
                start: parts[19].into(),
                ticks: parts[11].parse::<u64>()? + parts[12].parse::<u64>()?,
                pss_kib,
                helper: name != "quickshell",
                name,
            },
        );
    }
    Ok(result)
}
fn frame(samples: &[Value], second: usize, warmup: bool) -> Value {
    let mut result = samples[second % samples.len()].clone();
    result["gpuUsage"] = json!(if warmup {
        99
    } else {
        [99, 45, 90, 15][(second / 5) % 4]
    });
    result
}
fn tick(session: &mut Session, samples: &[Value], second: usize, warmup: bool) -> Result<()> {
    call(
        &session.root,
        "dashboard",
        "profileFrame",
        &[&frame(samples, second, warmup).to_string()],
    )?;
    if second.is_multiple_of(10) {
        call(&session.root, "weather", "preview", &[&session.weather])?;
    }
    session.check_view()
}
fn warmup(session: &mut Session, samples: &[Value], seconds: usize) -> Result<()> {
    let start = Instant::now();
    for second in 0..seconds {
        tick(session, samples, second, true)?;
        thread::sleep(
            (start + Duration::from_secs(second as u64 + 1))
                .saturating_duration_since(Instant::now()),
        );
    }
    Ok(())
}
fn measure(session: &mut Session, samples: &[Value], seconds: usize, label: &str) -> Result<Value> {
    let cg = run(
        &session.root,
        &[
            "systemctl",
            "--user",
            "show",
            "aeris-dashboard.service",
            "-p",
            "ControlGroup",
            "--value",
        ],
    )?;
    if cg.is_empty() || cg == "/" {
        return Err("No dashboard cgroup".into());
    }
    let group = Path::new("/sys/fs/cgroup").join(cg.trim_start_matches('/'));
    let first = processes(&group)?;
    let mut profiler = Command::new("python3")
        .args([
            "scripts/profile-dashboard.py",
            "--seconds",
            &seconds.to_string(),
            "--label",
            label,
        ])
        .current_dir(&session.root)
        .stdout(Stdio::piped())
        .spawn()?;
    let started = Instant::now();
    let mut memory = Vec::new();
    let replay = (|| -> Result<()> {
        for second in 0..seconds {
            tick(session, samples, second, false)?;
            if second.is_multiple_of(5) {
                memory.push(processes(&group)?);
            }
            thread::sleep(
                (started + Duration::from_secs(second as u64 + 1))
                    .saturating_duration_since(Instant::now()),
            );
        }
        Ok(())
    })();
    if let Err(error) = replay {
        let _ = profiler.kill();
        let _ = profiler.wait();
        return Err(error);
    }
    let last = processes(&group)?;
    let elapsed = started.elapsed().as_secs_f64();
    let output = profiler.wait_with_output()?;
    if !output.status.success() {
        return Err("Profiler failed".into());
    }
    let mut result: Value = serde_json::from_slice(&output.stdout)?;
    let ticks_per_second = run(&session.root, &["getconf", "CLK_TCK"])?.parse::<f64>()?;
    let mut cpu = BTreeMap::<String, f64>::new();
    let mut helper_cpu = 0.0;
    for (pid, current) in &last {
        if let Some(before) = first.get(pid)
            && before.start == current.start
        {
            let usage = (current.ticks - before.ticks) as f64 / ticks_per_second / elapsed * 100.0;
            *cpu.entry(current.name.clone()).or_default() += usage;
            if current.helper {
                helper_cpu += usage;
            }
        }
    }
    if first.keys().ne(last.keys()) {
        return Err("Process population changed during measurement; discard sample".into());
    }
    let mut pss = BTreeMap::<String, f64>::new();
    let mut helper_pss = 0.0;
    for sample in &memory {
        for process in sample.values() {
            *pss.entry(process.name.clone()).or_default() +=
                process.pss_kib / 1024.0 / memory.len() as f64;
            if process.helper {
                helper_pss += process.pss_kib / 1024.0 / memory.len() as f64;
            }
        }
    }
    result["processCpuPercent"] = json!(cpu);
    result["helpersCpuPercentOneLogicalCPU"] = json!(helper_cpu);
    result["processPssMiBMean"] = json!(pss);
    result["helpersPssMiBMean"] = json!(helper_pss);
    result["totalPssMiBMean"] = json!(pss.values().sum::<f64>());
    result["helperProcesses"] = json!(last.values().filter(|p| p.helper).count());
    Ok(result)
}
fn latency_summary(values: &[f64]) -> Value {
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let mid = sorted.len() / 2;
    json!({"samplesMs": values,
        "medianMs": (sorted[(sorted.len()-1)/2] + sorted[mid]) / 2.0,
        "p95Ms": sorted[(sorted.len() as f64 * 0.95).ceil() as usize-1],
        "minMs": sorted[0], "maxMs": sorted[sorted.len()-1]})
}

fn worker(root: &Path, implementation: &str) -> Result<()> {
    let commands: Vec<Vec<String>> = match implementation {
        "rust" => vec![vec![
            root.join("quickshell/aeris-dashboard/bin/aeris-dashboard-backend")
                .display()
                .to_string(),
            "watch".into(),
        ]],
        "python" => [
            "metrics.py",
            "rgbctl.py",
            "coolingctl.py",
            "sleepctl.py",
            "tomatctl.py",
        ]
        .into_iter()
        .map(|script| {
            let mut command = vec![
                "python3".into(),
                root.join("quickshell/aeris-dashboard/services")
                    .join(script)
                    .display()
                    .to_string(),
            ];
            if script != "metrics.py" {
                command.push("watch".into());
            }
            command
        })
        .collect(),
        _ => return Err("Expected rust or python worker".into()),
    };
    let mut children = Vec::new();
    for command in commands {
        match Command::new(&command[0])
            .args(&command[1..])
            .stdout(Stdio::null())
            .spawn()
        {
            Ok(child) => children.push(child),
            Err(error) => {
                for child in &mut children {
                    let _ = child.kill();
                    let _ = child.wait();
                }
                return Err(error.into());
            }
        }
    }
    // systemd owns the entire cgroup and stops every child on cleanup/timeout.
    // Equal sleeping Rust supervisors are included for both implementations.
    loop {
        for child in &mut children {
            if child.try_wait()?.is_some() {
                for child in &mut children {
                    let _ = child.kill();
                    let _ = child.wait();
                }
                return Err("A benchmark watcher exited".into());
            }
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn cpu_usec(group: &Path) -> Result<u64> {
    let data = fs::read_to_string(group.join("cpu.stat"))?;
    Ok(data
        .lines()
        .find_map(|s| s.strip_prefix("usage_usec "))
        .ok_or("Missing CPU accounting")?
        .parse()?)
}

fn helper_comparison(root: &Path, destination: &Path) -> Result<()> {
    struct Units {
        root: PathBuf,
        names: Vec<String>,
    }
    impl Drop for Units {
        fn drop(&mut self) {
            for name in &self.names {
                let _ = run(&self.root, &["systemctl", "--user", "stop", name]);
            }
        }
    }
    let mut units = Units {
        root: root.into(),
        names: Vec::new(),
    };
    let executable = env::current_exe()?;
    let mut groups = Vec::new();
    for implementation in ["python", "rust"] {
        let unit = format!(
            "aeris-backend-benchmark-{implementation}-{}",
            std::process::id()
        );
        run(
            root,
            &[
                "systemd-run",
                "--user",
                "--quiet",
                "--collect",
                "--service-type=exec",
                "--unit",
                &unit,
                "--property=RuntimeMaxSec=120",
                "--property=StandardOutput=null",
                executable.to_str().unwrap(),
                "--worker",
                implementation,
                root.to_str().unwrap(),
            ],
        )?;
        units.names.push(unit.clone());
        let path = run(
            root,
            &[
                "systemctl",
                "--user",
                "show",
                &unit,
                "-p",
                "ControlGroup",
                "--value",
            ],
        )?;
        if path.is_empty() || path == "/" {
            return Err("No isolated helper cgroup".into());
        }
        groups.push((
            implementation,
            Path::new("/sys/fs/cgroup").join(path.trim_start_matches('/')),
        ));
    }
    println!("HELPERS warming both isolated stacks for 10 seconds; no controls are sent.");
    std::io::stdout().flush()?;
    thread::sleep(Duration::from_secs(10));
    let first_pids: Vec<_> = groups
        .iter()
        .map(|(_, path)| processes(path))
        .collect::<Result<_>>()?;
    let mut previous: Vec<_> = groups
        .iter()
        .map(|(_, path)| cpu_usec(path))
        .collect::<Result<_>>()?;
    let mut samples = Vec::new();
    println!("HELPERS measuring three consecutive 20-second windows simultaneously.");
    std::io::stdout().flush()?;
    for block in 0..3 {
        let start = Instant::now();
        thread::sleep(Duration::from_secs(20));
        let elapsed = start.elapsed().as_secs_f64();
        for (index, (implementation, path)) in groups.iter().enumerate() {
            let current = cpu_usec(path)?;
            let pids = processes(path)?;
            if first_pids[index].keys().ne(pids.keys()) {
                return Err("Helper process population changed".into());
            }
            let row = json!({"implementation":implementation,"window":block+1,"seconds":elapsed,
                "cpuPercentOneLogicalCPU":(current-previous[index]) as f64/1e6/elapsed*100.0,
                "includesEqualSleepingSupervisor":true});
            previous[index] = current;
            samples.push(row.clone());
            println!("HELPER_RESULT {row}");
            std::io::stdout().flush()?;
        }
    }
    let mut output = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)?;
    serde_json::to_writer_pretty(
        &mut output,
        &json!({"method":"Both backend stacks run concurrently in separate temporary cgroups; 10s warmup then three 20s windows; microsecond CPU accounting; stdout discarded equally; each includes an equal Rust supervisor; no QML/rendering in these groups; normal dashboard remains on Rust", "results":samples}),
    )?;
    Ok(())
}

fn command_latencies(root: &Path, destination: &Path) -> Result<()> {
    let binary = root.join("quickshell/aeris-dashboard/bin/aeris-dashboard-backend");
    let services = root.join("quickshell/aeris-dashboard/services");
    let mut results = Vec::new();
    for (name, script, args) in [
        ("cooling-status", "coolingctl.py", vec!["cooling", "status"]),
        ("awake-status", "sleepctl.py", vec!["sleep", "status"]),
        ("tomat-status", "tomatctl.py", vec!["tomat", "status"]),
        ("weather-cached", "weather.py", vec!["weather"]),
        (
            "artwork-cached",
            "media_art.py",
            vec![
                "artwork",
                "--title",
                "The Night We Met",
                "--artist",
                "Lord Huron",
            ],
        ),
    ] {
        let mut python = Vec::new();
        let mut native = Vec::new();
        for iteration in 0..22 {
            // Two warm-up pairs, followed by twenty measured pairs. Alternate
            // order to reduce cache/order bias. Every call starts a fresh process.
            for implementation in if iteration % 2 == 0 {
                ["python", "rust"]
            } else {
                ["rust", "python"]
            } {
                let started = Instant::now();
                let output = if implementation == "rust" {
                    Command::new(&binary).args(&args).output()?
                } else {
                    Command::new("python3")
                        .arg(services.join(script))
                        .args(&args[1..])
                        .output()?
                };
                let elapsed = started.elapsed().as_secs_f64() * 1000.0;
                if !output.status.success() {
                    return Err(format!("{name} {implementation} failed").into());
                }
                let value: Value = serde_json::from_slice(&output.stdout)?;
                if name == "artwork-cached" {
                    if value["url"].as_str().is_none_or(str::is_empty) {
                        return Err("Artwork cache unavailable".into());
                    }
                } else if value["ok"] != true {
                    return Err(format!("{name} not healthy").into());
                }
                if name == "weather-cached"
                    && iteration > 1
                    && aeris_dashboard_backend::common::now()
                        - value["fetchedAt"].as_f64().unwrap_or(0.0)
                        >= 600.0
                {
                    return Err("Weather cache expired during latency sample".into());
                }
                if iteration >= 2 {
                    if implementation == "rust" {
                        native.push(elapsed);
                    } else {
                        python.push(elapsed);
                    }
                }
            }
        }
        let result = json!({"command":name,"python":latency_summary(&python),"rust":latency_summary(&native)});
        println!("COMMAND {result}");
        results.push(result);
    }
    let result = json!({"method":"20 new-process read-only calls per implementation after two warm-up pairs; interleaved order; warm OS/filesystem caches; dashboard stays on Rust; no hardware commands", "results":results});
    let mut output = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)?;
    serde_json::to_writer_pretty(&mut output, &result)?;
    Ok(())
}

fn renderer_comparison(root: &Path, telemetry: &Path, output: &Path) -> Result<()> {
    let samples: Vec<Value> = serde_json::from_str(&fs::read_to_string(telemetry)?)?;
    if samples.is_empty() {
        return Err("Empty telemetry trace".into());
    }
    fs::create_dir(output)?;
    fs::write(
        output.join("telemetry.json"),
        serde_json::to_vec_pretty(&samples)?,
    )?;
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(output.join("results.jsonl"))?;
    let mut session = Session::new(root.to_owned())?;
    let order = ["opengl", "vulkan", "vulkan", "opengl"];
    fs::write(
        output.join("method.json"),
        serde_json::to_vec_pretty(&json!({
            "order":order,"weather":["clear","rain","storm"],"secondsPerSample":30,
            "warmupSeconds":8,"gpuCycle":[99,45,90,15],"secondsPerGpuStep":5,
            "physicalGpuStress":false,"backend":"rust","decorativeFps":60,
            "mediaPresentation":"hidden equally; actual player and hardware controls untouched",
            "frameTiming":"QQuickWindow frameSwapped delivery intervals, millisecond wall clock; not physical scanout",
            "originalPage":session.mode,"originalCollapsed":session.collapsed,
            "restore":"Remove owned runtime drop-in; restart configured renderer and restore original page/visibility"
        }))?,
    )?;
    for (block, renderer) in order.into_iter().enumerate() {
        println!("SWITCH {} -> {renderer}", block + 1);
        std::io::stdout().flush()?;
        session.switch_renderer(renderer)?;
        for weather in ["clear", "rain", "storm"] {
            session.weather = weather.into();
            call(root, "dashboard", "profile", &["media", "true"])?;
            call(root, "weather", "freeze", &["-1"])?;
            println!("WARMUP {renderer} {weather}");
            std::io::stdout().flush()?;
            warmup(&mut session, &samples, 8)?;
            call(root, "dashboard", "frameTiming", &["true"])?;
            println!("MEASURE {renderer} {weather} (30 seconds)");
            std::io::stdout().flush()?;
            let mut result = measure(
                &mut session,
                &samples,
                30,
                &format!("{renderer}-{weather}-{}", block + 1),
            )?;
            result["frameTiming"] =
                serde_json::from_str(&call(root, "dashboard", "frameTiming", &["false"])?)?;
            result["renderer"] = json!(renderer);
            result["weather"] = json!(weather);
            result["block"] = json!(block + 1);
            writeln!(file, "{result}")?;
            file.flush()?;
            println!("RESULT {result}");
            std::io::stdout().flush()?;
        }
    }
    session.restore()?;
    println!("RESTORED configured renderer, live presentation, original page/visibility.");
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() == 5 && args[1] == "--renderers" {
        return renderer_comparison(
            Path::new(&args[2]),
            Path::new(&args[3]),
            Path::new(&args[4]),
        );
    }
    if args.len() == 4 && args[1] == "--worker" {
        return worker(Path::new(&args[3]), &args[2]);
    }
    if args.len() == 4 && args[1] == "--helpers" {
        return helper_comparison(Path::new(&args[2]), Path::new(&args[3]));
    }
    if args.len() == 4 && args[1] == "--commands" {
        return command_latencies(Path::new(&args[2]), Path::new(&args[3]));
    }
    if args.len() != 4 {
        return Err(
            "Usage: aeris-dashboard-benchmark REPO_ROOT TELEMETRY_JSON NEW_OUTPUT_DIRECTORY".into(),
        );
    }
    let root = PathBuf::from(&args[1]);
    let output = PathBuf::from(&args[3]);
    fs::create_dir(&output)?;
    let samples: Vec<Value> = serde_json::from_str(&fs::read_to_string(&args[2])?)?;
    if samples.is_empty() {
        return Err("Empty telemetry trace".into());
    }
    fs::write(
        output.join("telemetry.json"),
        serde_json::to_vec_pretty(&samples)?,
    )?;
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(output.join("results.jsonl"))?;
    let mut session = Session::new(root)?;
    fs::write(
        output.join("method.json"),
        serde_json::to_vec_pretty(&json!({
            "order":["python","rust","rust","python","python","rust"],"secondsPerSample":40,
            "warmupSeconds":15,"gpuCycle":[99,45,90,15],"secondsPerGpuStep":5,"physicalGpuStress":false,
            "weatherPreview":"rain","mediaPresentation":"hidden in both cases; playback untouched",
            "decorativeFps":60,"originalPage":session.mode,"originalCollapsed":session.collapsed,
            "restore":"Remove only the experiment runtime drop-in, restart default Rust, restore page/visibility"
        }))?,
    )?;
    for (block, implementation) in ["python", "rust", "rust", "python", "python", "rust"]
        .into_iter()
        .enumerate()
    {
        println!("SWITCH block {} → {implementation}", block + 1);
        std::io::stdout().flush()?;
        session.switch(implementation)?;
        for case in ["animated", "frozen"] {
            println!("WARMUP {implementation} {case}");
            std::io::stdout().flush()?;
            call(&session.root, "dashboard", "profile", &["media", "true"])?;
            call(&session.root, "weather", "freeze", &["-1"])?;
            warmup(&mut session, &samples, 13)?;
            if case == "frozen" {
                call(
                    &session.root,
                    "dashboard",
                    "profile",
                    &["media,weather,cpu,gpu,memory,metrics,pomodoro", "true"],
                )?;
                call(&session.root, "weather", "freeze", &["7"])?;
            }
            warmup(&mut session, &samples, 2)?;
            println!("MEASURE {implementation} {case} (40 seconds)");
            std::io::stdout().flush()?;
            let mut result = measure(
                &mut session,
                &samples,
                40,
                &format!("{implementation}-{case}-{}", block + 1),
            )?;
            result["implementation"] = json!(implementation);
            result["case"] = json!(case);
            result["block"] = json!(block + 1);
            writeln!(file, "{result}")?;
            file.flush()?;
            println!("RESULT {result}");
            std::io::stdout().flush()?;
        }
    }
    session.restore()?;
    println!("RESTORED Rust backend, live presentation, original page/visibility.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gpu_replay_is_identical_and_does_not_mutate_cpu_trace() {
        let samples = vec![
            json!({"gpuUsage":2,"cpuUsage":3}),
            json!({"gpuUsage":4,"cpuUsage":7}),
        ];
        for (second, usage) in [(0, 99), (5, 45), (10, 90), (15, 15), (20, 99)] {
            assert_eq!(frame(&samples, second, false)["gpuUsage"], usage);
        }
        assert_eq!(frame(&samples, 3, false)["cpuUsage"], 7);
        assert_eq!(frame(&samples, 15, true)["gpuUsage"], 99);
        assert_eq!(samples[1]["gpuUsage"], 4);
    }
    #[test]
    fn latency_median_uses_both_middle_samples() {
        assert_eq!(latency_summary(&[4.0, 1.0, 3.0, 2.0])["medianMs"], 2.5);
        assert_eq!(latency_summary(&[4.0, 1.0, 3.0])["medianMs"], 3.0);
    }
}
