#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tomat/source.env"
binary=$HOME/.local/bin/tomat
config_root=${XDG_CONFIG_HOME:-$HOME/.config}
share_root=${XDG_DATA_HOME:-$HOME/.local/share}/tomat
unit=$config_root/systemd/user/tomat.service
backend=$repo_root/quickshell/aeris-dashboard/bin/aeris-dashboard-backend
tomat_cache=${XDG_CACHE_HOME:-$HOME/.cache}/aeris-tomat-build
source_dir=$tomat_cache/source/$tomat_revision
built_binary=$tomat_cache/target/$tomat_revision/release/tomat

check_running() {
    for attempt in {1..30}; do
        if state=$("$backend" tomat status) && [[ $state == *'"canSeek":true'* ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

if [[ ${1:-} == --check && $# == 1 ]]; then
    [[ $("$binary" --version) == "tomat $tomat_version" ]]
    cmp "$repo_root/tomat/source.env" "$share_root/aeris-source.env"
    cmp "$repo_root/systemd/user/tomat.service" "$unit"
    systemctl --user is-enabled tomat.service
    systemctl --user is-active tomat.service
    check_running
    "$binary" --version
    "$binary" status
    exit 0
fi
if [[ $# != 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi
if [[ -e $unit ]] && ! cmp -s "$repo_root/systemd/user/tomat.service" "$unit"; then
    echo 'Existing Tomat unit differs; leaving it untouched.' >&2
    exit 1
fi
if [[ -e $binary ]]; then
    current_version=$("$binary" --version)
    if [[ $current_version != 'tomat 2.13.0' && $current_version != "tomat $tomat_version" ]]; then
        if [[ ! -f $share_root/aeris-source.env || $current_version != 'tomat '*+aeris.* ]]; then
            echo 'Existing Tomat is not a recognized Aeris installation; leaving it untouched.' >&2
            exit 1
        fi
    fi
fi
# Keep the adapter protocol in sync even when an older executable already exists.
bash "$repo_root/scripts/build-dashboard-backend.sh"
bash "$repo_root/scripts/build-tomat.sh"

mkdir -p -- "$(dirname -- "$binary")" "$share_root/backups"
changed=false
backup=
if [[ ! -e $binary ]] || ! cmp -s "$built_binary" "$binary"; then
    backup=$(mktemp -d "$share_root/backups/install.XXXXXXXX")
    [[ ! -e $binary ]] || cp -p -- "$binary" "$backup/tomat"
    runtime_root=${TOMAT_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}
    [[ ! -f $runtime_root/tomat.state ]] || cp -p -- "$runtime_root/tomat.state" "$backup/tomat.state"
    [[ ! -f $share_root/aeris-source.env ]] || cp -p -- "$share_root/aeris-source.env" "$backup/aeris-source.env"
    staging=$(mktemp "${binary}.install.XXXXXXXX")
    trap 'rm -f -- "$staging"' EXIT
    install -m0755 "$built_binary" "$staging"
    mv -f -- "$staging" "$binary"
    changed=true
fi
if [[ ! -e $config_root/tomat/config.toml ]]; then
    install -Dm0644 "$repo_root/tomat/config.toml" "$config_root/tomat/config.toml"
fi
install -Dm0644 "$repo_root/systemd/user/tomat.service" "$unit"
systemctl --user daemon-reload
systemctl --user enable tomat.service
service_started=true
if $changed; then
    systemctl --user restart tomat.service || service_started=false
else
    systemctl --user start tomat.service || service_started=false
fi
if ! $service_started || ! check_running; then
    if [[ -n $backup && -f $backup/tomat ]]; then
        staging=$(mktemp "${binary}.rollback.XXXXXXXX")
        install -m0755 "$backup/tomat" "$staging"
        mv -f -- "$staging" "$binary"
        systemctl --user restart tomat.service
        echo "Fork health check failed; previous binary restored from $backup." >&2
    else
        echo 'Fork health check failed; inspect tomat.service logs.' >&2
    fi
    exit 1
fi
install -Dm0644 "$source_dir/LICENSE" "$share_root/LICENSE"
install -Dm0644 "$repo_root/tomat/source.env" "$share_root/aeris-source.env"
"$binary" --version
[[ -z $backup ]] || echo "Previous binary/state backed up to $backup"
