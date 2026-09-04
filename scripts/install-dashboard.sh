#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
unit_name=aeris-dashboard.service
unit_source=$repo_root/systemd/user/$unit_name
unit_root=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
unit_target=$unit_root/$unit_name

if [[ ${1:-} == "--check" ]]; then
    cmp --silent "$unit_source" "$unit_target"
    systemctl --user is-enabled --quiet "$unit_name"
    systemctl --user is-active --quiet "$unit_name"
    python3 "$repo_root/quickshell/aeris-dashboard/services/sleepctl.py" status
    echo "$unit_name is installed, enabled, and running."
    exit 0
fi

if [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

install -Dm0644 "$unit_source" "$unit_target"
bash "$script_dir/install-sleep-bridge.sh"
systemctl --user daemon-reload
systemctl --user enable "$unit_name"
systemctl --user restart "$unit_name"
systemctl --user --no-pager --full status "$unit_name"
