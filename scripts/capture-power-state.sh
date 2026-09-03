#!/usr/bin/bash
set -euo pipefail

duration=60
interval=1
output=/dev/stdout

usage() {
    echo "Usage: $0 [--duration SECONDS] [--interval SECONDS] [--output FILE]" >&2
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --duration) duration=${2:?missing duration}; shift 2 ;;
        --interval) interval=${2:?missing interval}; shift 2 ;;
        --output) output=${2:?missing output path}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

[[ $duration =~ ^[0-9]+$ ]] && (( duration > 0 )) || { echo "Duration must be a positive integer." >&2; exit 2; }
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "Interval must be a positive number." >&2; exit 2; }

gpu_hwmon=
for candidate in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [[ -r $candidate/name ]] || continue
    [[ $(<"$candidate/name") == amdgpu ]] && { gpu_hwmon=$candidate; break; }
done
[[ -n $gpu_hwmon ]] || { echo "No amdgpu hwmon device found." >&2; exit 1; }

cpu_hwmon=
for candidate in /sys/class/hwmon/hwmon*; do
    [[ -r $candidate/name ]] || continue
    [[ $(<"$candidate/name") == k10temp ]] && { cpu_hwmon=$candidate; break; }
done

read_value() {
    local path=$1 divisor=${2:-1}
    [[ -r $path ]] || { printf 'NA'; return; }
    awk -v divisor="$divisor" '{ printf "%.2f", $1 / divisor }' "$path"
}

cpu_temp() {
    local label_file label input_file
    [[ -n $cpu_hwmon ]] || { printf 'NA'; return; }
    for label_file in "$cpu_hwmon"/temp*_label; do
        [[ -r $label_file ]] || continue
        label=$(<"$label_file")
        if [[ $label == Tctl ]]; then
            input_file=${label_file%_label}_input
            read_value "$input_file" 1000
            return
        fi
    done
    printf 'NA'
}

gpu_temp() {
    local wanted=$1 label_file label input_file
    for label_file in "$gpu_hwmon"/temp*_label; do
        [[ -r $label_file ]] || continue
        label=$(<"$label_file")
        if [[ $label == "$wanted" ]]; then
            input_file=${label_file%_label}_input
            read_value "$input_file" 1000
            return
        fi
    done
    printf 'NA'
}

gpu_device=$(dirname "$(dirname "$gpu_hwmon")")
mkdir -p "$(dirname "$output")"
echo 'timestamp,cpu_tctl_c,gpu_edge_c,gpu_junction_c,gpu_mem_c,gpu_load_pct,gpu_power_w,gpu_cap_w,gpu_fan_rpm,gpu_sclk_mhz,gpu_mclk_mhz,gpu_voltage_mv' >"$output"

end=$((SECONDS + duration))
while (( SECONDS < end )); do
    printf '%s,' "$(date --iso-8601=seconds)" >>"$output"
    printf '%s,' "$(cpu_temp)" >>"$output"
    printf '%s,' "$(gpu_temp edge)" >>"$output"
    printf '%s,' "$(gpu_temp junction)" >>"$output"
    printf '%s,' "$(gpu_temp mem)" >>"$output"
    printf '%s,' "$(read_value "$gpu_device/gpu_busy_percent")" >>"$output"
    printf '%s,' "$(read_value "$gpu_hwmon/power1_average" 1000000)" >>"$output"
    printf '%s,' "$(read_value "$gpu_hwmon/power1_cap" 1000000)" >>"$output"
    printf '%s,' "$(read_value "$gpu_hwmon/fan1_input")" >>"$output"
    printf '%s,' "$(read_value "$gpu_hwmon/freq1_input" 1000000)" >>"$output"
    printf '%s,' "$(read_value "$gpu_hwmon/freq2_input" 1000000)" >>"$output"
    printf '%s\n' "$(read_value "$gpu_hwmon/in0_input")" >>"$output"
    sleep "$interval"
done

[[ $output == /dev/stdout ]] || echo "Wrote telemetry to $output"
