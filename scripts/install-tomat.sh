#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=2.13.0
checksum=3d055adc3aef70c676fab1009b7231fb1edc32b14a99e7be31901cb22e73b86f
binary=$HOME/.local/bin/tomat
config_root=${XDG_CONFIG_HOME:-$HOME/.config}
unit=$config_root/systemd/user/tomat.service

python3 -c 'import yaml' || {
    echo "Obsidian routines require PyYAML: sudo dnf install python3-pyyaml" >&2
    exit 1
}

if [[ ${1:-} == --check ]]; then
    "$binary" --version
    cmp "$repo_root/systemd/user/tomat.service" "$unit"
    systemctl --user is-enabled tomat.service
    systemctl --user is-active tomat.service
    for attempt in {1..20}; do
        if "$binary" status | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(d.get("class") == "disconnected")'; then
            "$binary" status
            exit 0
        fi
        sleep 0.1
    done
    echo "Tomat service is active but its socket is unavailable." >&2
    exit 1
fi
if [[ $# != 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi
[[ $(uname -m) == x86_64 ]] || { echo "This pinned package is for x86_64." >&2; exit 1; }
if [[ -e $binary ]]; then
    [[ $("$binary" --version) == "tomat $version" ]] || {
        echo "Existing Tomat differs; not replacing it automatically." >&2; exit 1;
    }
else
    staging=$(mktemp -d /tmp/aeris-tomat-install.XXXXXX)
    curl -fL --retry 2 "https://github.com/jolars/tomat/releases/download/v$version/tomat-x86_64-unknown-linux-gnu.tar.gz" -o "$staging/tomat.tar.gz"
    actual=$(sha256sum "$staging/tomat.tar.gz")
    [[ ${actual%% *} == "$checksum" ]] || { echo "Checksum mismatch." >&2; exit 1; }
    tar -xzf "$staging/tomat.tar.gz" -C "$staging" ./tomat ./LICENSE
    "$staging/tomat" --version
    install -Dm0755 "$staging/tomat" "$binary"
    install -Dm0644 "$staging/LICENSE" "$HOME/.local/share/tomat/LICENSE"
fi
if [[ ! -e $config_root/tomat/config.toml ]]; then
    install -Dm0644 "$repo_root/tomat/config.toml" "$config_root/tomat/config.toml"
fi
if [[ -e $unit ]] && ! cmp -s "$repo_root/systemd/user/tomat.service" "$unit"; then
    echo "Existing Tomat unit differs; leaving it untouched." >&2
    exit 1
fi
install -Dm0644 "$repo_root/systemd/user/tomat.service" "$unit"
systemctl --user daemon-reload
systemctl --user enable --now tomat.service
"$binary" --version
