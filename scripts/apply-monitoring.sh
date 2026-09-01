#!/usr/bin/bash
set -euo pipefail

overview_page=${XDG_DATA_HOME:-$HOME/.local/share}/plasma-systemmonitor/overview.page
required_packages=(lm_sensors stress-ng vkmark)
cpu_sensor=cpu/all/averageTemperature
gpu_sensor=gpu/gpu1/temperature

check_profile() {
    local failed=0

    echo "Packages"
    for package_name in "${required_packages[@]}"; do
        if rpm -q "$package_name" >/dev/null 2>&1; then
            echo "  $package_name: installed"
        else
            echo "  $package_name: missing"
            failed=1
        fi
    done

    echo "Plasma System Monitor"
    if [[ ! -f "$overview_page" ]]; then
        echo "  overview page: missing ($overview_page)"
        return 1
    fi

    if grep -Fq "$cpu_sensor" "$overview_page"; then
        echo "  CPU average temperature: configured"
    else
        echo "  CPU average temperature: missing"
        failed=1
    fi

    if grep -Fq "$gpu_sensor" "$overview_page"; then
        echo "  GPU temperature: configured"
    else
        echo "  GPU temperature: missing"
        failed=1
    fi

    return "$failed"
}

if [[ ${1:-} == "--check" ]]; then
    check_profile
    exit
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

if pgrep -f '^/usr/bin/plasma-systemmonitor$' >/dev/null; then
    echo "Close Plasma System Monitor before applying this profile." >&2
    exit 1
fi

sudo dnf install -y "${required_packages[@]}"

if [[ ! -f "$overview_page" ]]; then
    echo "Open Plasma System Monitor once so it creates $overview_page, then rerun this script." >&2
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/fedora-settings
backup_dir=$state_root/backups/$timestamp
mkdir -p "$backup_dir"
cp -a "$overview_page" "$backup_dir/overview.page"

python3 - "$overview_page" "$cpu_sensor" "$gpu_sensor" <<'PYTHON'
import configparser
import json
import sys
from pathlib import Path

page_path = Path(sys.argv[1])
cpu_sensor = sys.argv[2]
gpu_sensor = sys.argv[3]

config = configparser.RawConfigParser(interpolation=None, strict=True)
config.optionxform = str
with page_path.open(encoding="utf-8") as page_file:
    config.read_file(page_file)

faces = {}
for section in config.sections():
    if not section.endswith("][Appearance"):
        continue
    title = config.get(section, "Title", fallback="")
    if title in {"CPU", "GPU"}:
        faces[title] = section.removesuffix("][Appearance")

missing = {"CPU", "GPU"} - faces.keys()
if missing:
    raise SystemExit(f"Missing System Monitor face(s): {', '.join(sorted(missing))}")

def add_sensor(face, sensor, color):
    sensor_section = f"{face}][Sensors"
    color_section = f"{face}][SensorColors"
    if not config.has_section(sensor_section):
        config.add_section(sensor_section)
    if not config.has_section(color_section):
        config.add_section(color_section)

    configured = json.loads(config.get(sensor_section, "totalSensors", fallback="[]"))
    if sensor not in configured:
        configured.append(sensor)
    config.set(sensor_section, "totalSensors", json.dumps(configured, separators=(",", ":")))
    config.set(color_section, sensor, color)

add_sensor(faces["CPU"], cpu_sensor, "233,120,61")
add_sensor(faces["GPU"], gpu_sensor, "233,120,61")

with page_path.open("w", encoding="utf-8") as page_file:
    config.write(page_file, space_around_delimiters=False)
PYTHON

echo "Monitoring profile applied."
echo "Backup: $backup_dir/overview.page"
echo "Reopen Plasma System Monitor to load the temperature sensors."
