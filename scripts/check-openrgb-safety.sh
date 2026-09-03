#!/usr/bin/bash
set -euo pipefail

app_root=${XDG_DATA_HOME:-$HOME/.local/share}/aeris-openrgb
approval_file=$app_root/approved-runtime.txt

if [[ ! -f $approval_file ]]; then
    echo "Aeris OpenRGB safety gate: missing $approval_file" >&2
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

case $installed_nevra in
    *1.0~rc3.1*|*1.0~rc[4-9]*|*1.[1-9]*|*[2-9].*) ;;
    *)
        echo "Aeris OpenRGB safety gate: $installed_nevra predates the rc3.1 safety floor" >&2
        exit 1
        ;;
esac

echo "Aeris OpenRGB safety gate: approved runtime $installed_nevra"
