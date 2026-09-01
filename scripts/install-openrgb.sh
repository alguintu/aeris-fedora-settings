#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
app_root=$HOME/.local/share/aeris-openrgb
config_root=$HOME/.config/aeris-openrgb
openrgb_config_root=$HOME/.config/OpenRGB
unit_root=$HOME/.config/systemd/user
venv=$app_root/venv

check_file() {
    local source_file=$1
    local installed_file=$2
    if [[ ! -f "$installed_file" ]]; then
        echo "MISSING  $installed_file"
        return 1
    elif cmp -s "$source_file" "$installed_file"; then
        echo "MATCH    $installed_file"
    else
        echo "DIFFERS  $installed_file"
        return 1
    fi
}

check_installation() {
    local result=0

    rpm -q openrgb openrgb-udev-rules || result=1
    check_file "$repo_root/openrgb/aeris_openrgb.py" "$app_root/aeris_openrgb.py" || result=1
    check_file "$repo_root/openrgb/config.yaml" "$config_root/config.yaml" || result=1
    check_file "$repo_root/openrgb/sizes.ors" "$openrgb_config_root/sizes.ors" || result=1
    check_file "$repo_root/systemd/user/aeris-openrgb-server.service" "$unit_root/aeris-openrgb-server.service" || result=1
    check_file "$repo_root/systemd/user/aeris-openrgb.service" "$unit_root/aeris-openrgb.service" || result=1

    if [[ -x "$venv/bin/python" ]]; then
        "$venv/bin/python" -c 'compile(open("'"$app_root/aeris_openrgb.py"'", encoding="utf-8").read(), "aeris_openrgb.py", "exec")'
        "$venv/bin/python" -c 'import pathlib, yaml; yaml.safe_load(pathlib.Path("'"$config_root/config.yaml"'").read_text())'
        "$venv/bin/pip" check
        "$venv/bin/pip" freeze
    else
        echo "MISSING  $venv" >&2
        result=1
    fi

    systemctl --user is-enabled aeris-openrgb.service || result=1
    systemctl --user is-active aeris-openrgb.service || result=1
    systemctl --user is-active aeris-openrgb-server.service || result=1
    return "$result"
}

if [[ ${1:-} == "--check" ]]; then
    check_installation
    exit
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

sudo dnf install -y openrgb openrgb-udev-rules python3

timestamp=$(date +%Y%m%d-%H%M%S)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/fedora-settings
backup_dir=$state_root/backups/$timestamp/openrgb
mkdir -p "$backup_dir"

for installed_file in \
    "$app_root/aeris_openrgb.py" \
    "$config_root/config.yaml" \
    "$openrgb_config_root/sizes.ors" \
    "$unit_root/aeris-openrgb-server.service" \
    "$unit_root/aeris-openrgb.service"; do
    if [[ -f "$installed_file" ]]; then
        cp -a "$installed_file" "$backup_dir/$(basename "$installed_file")"
    fi
done

python3 -m venv "$venv"
"$venv/bin/pip" install --upgrade pip
"$venv/bin/pip" install --requirement "$repo_root/openrgb/requirements.txt"

install -Dm0644 "$repo_root/openrgb/aeris_openrgb.py" "$app_root/aeris_openrgb.py"
install -Dm0644 "$repo_root/openrgb/config.yaml" "$config_root/config.yaml"
install -Dm0644 "$repo_root/openrgb/sizes.ors" "$openrgb_config_root/sizes.ors"
install -Dm0644 "$repo_root/systemd/user/aeris-openrgb-server.service" "$unit_root/aeris-openrgb-server.service"
install -Dm0644 "$repo_root/systemd/user/aeris-openrgb.service" "$unit_root/aeris-openrgb.service"

systemctl --user daemon-reload
systemctl --user enable aeris-openrgb.service
systemctl --user restart aeris-openrgb.service

echo "Aeris OpenRGB profile installed."
echo "Backup: $backup_dir"
check_installation
