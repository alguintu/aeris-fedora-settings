#!/usr/bin/env python3
"""Temporary presentation ablation; does not stop hardware/media/timer services."""
import argparse
import json
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


class PresentationChanged(RuntimeError):
    pass


def ipc(*args):
    return subprocess.check_output(["bash", "scripts/run-dashboard.sh", "ipc", *args],
                                   cwd=ROOT, text=True).strip()


def frame(samples, second, heavy=True):
    sample = dict(samples[second % len(samples)])
    sample["gpuUsage"] = [99, 45, 90, 15][(second // 5) % 4] if heavy else 99
    return json.dumps(sample, separators=(",", ":"))


def replay(samples, seconds, heavy=True, collapsed=False):
    start = time.monotonic()
    for second in range(seconds):
        ipc("call", "dashboard", "profileFrame", frame(samples, second, heavy))
        if (ipc("prop", "get", "dashboard", "mode") != "1"
                or ipc("prop", "get", "dashboard", "collapsed") != str(collapsed).lower()):
            raise PresentationChanged("Dashboard page/visibility changed; discard this sample")
        time.sleep(max(0, start + second + 1 - time.monotonic()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", default="baseline,no-weather,no-cpu,no-gpu,no-memory,no-heatmaps,no-media,no-pomodoro,static,collapsed,baseline-end")
    parser.add_argument("--seconds", type=int, default=40, choices=(20, 40))
    parser.add_argument("--output", required=True)
    parser.add_argument("--telemetry", help="Reuse a previously recorded .telemetry.json trace")
    args = parser.parse_args()
    cases = {
        "baseline": "", "baseline-end": "", "no-weather": "weather",
        "no-cpu": "weather,cpu", "no-gpu": "weather,gpu",
        "no-memory": "weather,memory", "no-heatmaps": "weather,cpu,gpu,memory",
        "no-media": "weather,media", "no-pomodoro": "weather,pomodoro",
        "static": "weather,cpu,gpu,memory,metrics", "collapsed": "weather,cpu,gpu,memory,metrics",
        "frozen-end": "weather",
        "no-gpu-blend": "weather,gpu-blend", "no-gpu-paint": "weather,gpu-paint",
    }
    chosen = args.cases.split(",")
    if any(name not in cases for name in chosen):
        parser.error("Unknown case")
    original_mode = ipc("prop", "get", "dashboard", "mode")
    original_collapsed = ipc("prop", "get", "dashboard", "collapsed")
    if args.telemetry:
        samples = json.loads(Path(args.telemetry).read_text())
        if not samples:
            raise ValueError("Empty telemetry trace")
    else:
        samples = []
        collector = subprocess.Popen(["python3", "quickshell/aeris-dashboard/services/metrics.py"],
                                     cwd=ROOT, stdout=subprocess.PIPE, text=True)
        try:
            for _ in range(10):
                samples.append(json.loads(collector.stdout.readline()))
        finally:
            collector.terminate()
            collector.wait(timeout=5)
    with open(args.output + ".telemetry.json", "x") as trace:
        json.dump(samples, trace)
    profiler = None
    layout_changed = False
    try:
        ipc("call", "dashboard", "setMode", "1")
        ipc("call", "dashboard", "showDashboard")
        ipc("call", "dashboard", "simulateGpu", "-1")
        # Exclusive output avoids accidentally overwriting another experiment.
        with open(args.output, "x") as output:
            for name in chosen:
                print("WARMUP " + name, flush=True)
                ipc("call", "dashboard", "showDashboard")
                ipc("call", "dashboard", "profile", "", "true")
                replay(samples, 13, heavy=False)
                ipc("call", "dashboard", "profile", cases[name], "true")
                if name == "collapsed":
                    ipc("call", "dashboard", "hideDashboard")
                # Let existing color transitions/visibility changes settle.
                replay(samples, 2, heavy=False, collapsed=name == "collapsed")
                print("MEASURE " + name, flush=True)
                profiler = subprocess.Popen(["python3", "scripts/profile-dashboard.py", "--seconds",
                                             str(args.seconds), "--label", name], cwd=ROOT,
                                            stdout=subprocess.PIPE, text=True)
                replay(samples, args.seconds, collapsed=name == "collapsed")
                data, _ = profiler.communicate(timeout=10)
                if profiler.returncode:
                    raise RuntimeError("Profiler failed")
                profiler = None
                result = json.loads(data)
                result["paused"] = cases[name]
                output.write(json.dumps(result) + "\n")
                output.flush()
                print(json.dumps(result), flush=True)
    except PresentationChanged:
        layout_changed = True
        raise
    finally:
        if profiler and profiler.poll() is None:
            profiler.terminate()
            profiler.wait(timeout=5)
        ipc("call", "dashboard", "profile", "", "false")
        ipc("call", "dashboard", "simulateGpu", "-1")
        if not layout_changed:
            ipc("call", "dashboard", "setMode", original_mode)
            ipc("call", "dashboard", "hideDashboard" if original_collapsed == "true" else "showDashboard")


if __name__ == "__main__":
    def terminate(signum, frame):
        raise KeyboardInterrupt("Interrupted; restoring live dashboard")
    signal.signal(signal.SIGTERM, terminate)
    main()
