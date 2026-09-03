#!/usr/bin/bash
set -euo pipefail

app_root=${XDG_DATA_HOME:-$HOME/.local/share}/aeris-openrgb
approval_file=$app_root/approved-runtime.txt
daemon_file=$app_root/aeris_openrgb.py
daemon_auditor=$app_root/audit-openrgb-daemon.py

if [[ ! -f $approval_file ]]; then
    echo "Aeris OpenRGB safety gate: missing $approval_file" >&2
    exit 1
fi

if [[ ! -x $daemon_auditor || ! -f $daemon_file ]]; then
    echo "Aeris OpenRGB safety gate: missing daemon safety auditor or daemon" >&2
    exit 1
fi

"$daemon_auditor" "$daemon_file"

if pgrep -x openrgb >/dev/null; then
    echo "Aeris OpenRGB safety gate: another OpenRGB process is already running" >&2
    exit 1
fi

approved_nevra=$(sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*(#|$)/d; s/^[[:space:]]+//; s/[[:space:]]+$//' "$approval_file" | head -n 1)
if [[ -z $approved_nevra ]]; then
    echo "Aeris OpenRGB safety gate: runtime is quarantined; no package is approved" >&2
    exit 1
fi

installed_nevra=$(rpm -q openrgb 2>/dev/null || true)
if [[ $installed_nevra != "$approved_nevra" ]]; then
    echo "Aeris OpenRGB safety gate: approved '$approved_nevra', installed '$installed_nevra'" >&2
    exit 1
fi

installed_version=$(rpm -q --qf '%{VERSION}' openrgb 2>/dev/null || true)
if [[ $installed_version == 0.9.2026\^1.0rc3.1* \
    || $installed_version == 1.0~rc3.1* \
    || $installed_version =~ ^1\.0~rc([4-9]|[1-9][0-9]+) \
    || $installed_version =~ ^1\.([1-9][0-9]*)(\.|$) \
    || $installed_version =~ ^([2-9][0-9]*)(\.|$) ]]; then
    :
else
    echo "Aeris OpenRGB safety gate: version $installed_version predates the rc3.1 safety floor" >&2
    exit 1
fi

echo "Aeris OpenRGB safety gate: approved runtime $installed_nevra"
