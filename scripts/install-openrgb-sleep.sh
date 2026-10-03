#!/usr/bin/bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
unit=aeris-openrgb-sleep.service
unit_root=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
if [[ ${1:-} == --check && $# == 1 ]]; then
    cmp --silent "$repo_root/systemd/user/$unit" "$unit_root/$unit"
    systemctl --user is-enabled --quiet "$unit"
    systemctl --user is-active --quiet "$unit"
    exit 0
fi
if [[ $# != 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi
bash "$script_dir/build-dashboard-backend.sh"
install -Dm0644 "$repo_root/systemd/user/$unit" "$unit_root/$unit"
systemctl --user daemon-reload
systemctl --user enable "$unit"
systemctl --user restart "$unit"
# Starting the watcher never starts/restarts the RGB hardware services.
systemctl --user --no-pager --full status "$unit"
