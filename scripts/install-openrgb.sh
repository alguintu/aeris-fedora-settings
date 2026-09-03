#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
app_root=$HOME/.local/share/aeris-openrgb
config_root=$HOME/.config/aeris-openrgb
openrgb_config_root=$HOME/.config/OpenRGB
unit_root=$HOME/.config/systemd/user
venv=$app_root/venv

check_runtime_safety() {
    local source_file=$1
    "$repo_root/scripts/audit-openrgb-daemon.py" "$source_file"
}

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

check_openrgb_packages() {
    local result=0
    rpm -q openrgb || result=1
    if rpm -qf /usr/lib/udev/rules.d/60-openrgb.rules >/dev/null 2>&1; then
        echo "PRESENT  /usr/lib/udev/rules.d/60-openrgb.rules"
    else
        echo "MISSING  /usr/lib/udev/rules.d/60-openrgb.rules" >&2
        result=1
    fi
    return "$result"
}

check_installation() {
    local result=0

    check_runtime_safety "$repo_root/openrgb/aeris_openrgb.py" || result=1
    check_runtime_safety "$app_root/aeris_openrgb.py" || result=1
    check_openrgb_packages || result=1
    check_file "$repo_root/openrgb/aeris_openrgb.py" "$app_root/aeris_openrgb.py" || result=1
    check_file "$repo_root/openrgb/config.yaml" "$config_root/config.yaml" || result=1
    check_file "$repo_root/openrgb/approved-runtime.txt" "$app_root/approved-runtime.txt" || result=1
    check_file "$repo_root/scripts/check-openrgb-safety.sh" "$app_root/check-openrgb-safety.sh" || result=1
    check_file "$repo_root/scripts/audit-openrgb-daemon.py" "$app_root/audit-openrgb-daemon.py" || result=1
    check_file "$repo_root/scripts/configure-openrgb-detectors.py" "$app_root/configure-openrgb-detectors.py" || result=1
    check_file "$repo_root/systemd/user/aeris-openrgb-server.service" "$unit_root/aeris-openrgb-server.service" || result=1
    check_file "$repo_root/systemd/user/aeris-openrgb.service" "$unit_root/aeris-openrgb.service" || result=1
    "$app_root/configure-openrgb-detectors.py" --check || result=1
    if [[ -f "$openrgb_config_root/sizes.ors" ]]; then
        echo "UNSAFE   legacy $openrgb_config_root/sizes.ors is still in OpenRGB's load path" >&2
        result=1
    else
        echo "SAFE     no legacy sizes.ors is in OpenRGB's load path"
    fi

    if [[ -x "$venv/bin/python" ]]; then
        "$venv/bin/python" -c 'compile(open("'"$app_root/aeris_openrgb.py"'", encoding="utf-8").read(), "aeris_openrgb.py", "exec")'
        "$venv/bin/python" -c 'import pathlib, yaml; yaml.safe_load(pathlib.Path("'"$config_root/config.yaml"'").read_text())'
        "$venv/bin/pip" check
        "$venv/bin/pip" freeze
    else
        echo "MISSING  $venv" >&2
        result=1
    fi

    for unit in aeris-openrgb.service aeris-openrgb-server.service; do
        if systemctl --user is-enabled --quiet "$unit"; then
            echo "UNSAFE   $unit is enabled" >&2
            result=1
        else
            echo "SAFE     $unit is disabled"
        fi
        if systemctl --user is-active --quiet "$unit"; then
            echo "UNSAFE   $unit is active" >&2
            result=1
        else
            echo "SAFE     $unit is inactive"
        fi
    done
    if "$app_root/check-openrgb-safety.sh"; then
        echo "READY    installed OpenRGB runtime is explicitly approved"
    else
        echo "BLOCKED  OpenRGB runtime remains quarantined"
    fi
    return "$result"
}

if [[ ${1:-} == "--check" ]]; then
    check_installation
    exit
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

check_runtime_safety "$repo_root/openrgb/aeris_openrgb.py"

check_openrgb_packages >/dev/null
command -v python3 >/dev/null

systemctl --user disable --now aeris-openrgb.service aeris-openrgb-server.service 2>/dev/null || true

timestamp=$(date +%Y%m%d-%H%M%S)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/fedora-settings
backup_dir=$state_root/backups/$timestamp/openrgb
mkdir -p "$backup_dir"

for installed_file in \
    "$app_root/aeris_openrgb.py" \
    "$app_root/approved-runtime.txt" \
    "$app_root/check-openrgb-safety.sh" \
    "$app_root/audit-openrgb-daemon.py" \
    "$app_root/configure-openrgb-detectors.py" \
    "$config_root/config.yaml" \
    "$openrgb_config_root/OpenRGB.json" \
    "$unit_root/aeris-openrgb-server.service" \
    "$unit_root/aeris-openrgb.service"; do
    if [[ -f "$installed_file" ]]; then
        cp -a "$installed_file" "$backup_dir/$(basename "$installed_file")"
    fi
done

if [[ -f "$openrgb_config_root/sizes.ors" ]]; then
    mv "$openrgb_config_root/sizes.ors" "$backup_dir/sizes.ors.quarantined"
fi

python3 -m venv "$venv"
"$venv/bin/pip" install --upgrade pip
"$venv/bin/pip" install --requirement "$repo_root/openrgb/requirements.txt"

install -Dm0644 "$repo_root/openrgb/aeris_openrgb.py" "$app_root/aeris_openrgb.py"
install -Dm0644 "$repo_root/openrgb/approved-runtime.txt" "$app_root/approved-runtime.txt"
install -Dm0755 "$repo_root/scripts/check-openrgb-safety.sh" "$app_root/check-openrgb-safety.sh"
install -Dm0755 "$repo_root/scripts/audit-openrgb-daemon.py" "$app_root/audit-openrgb-daemon.py"
install -Dm0755 "$repo_root/scripts/configure-openrgb-detectors.py" "$app_root/configure-openrgb-detectors.py"
install -Dm0644 "$repo_root/openrgb/config.yaml" "$config_root/config.yaml"
install -Dm0644 "$repo_root/systemd/user/aeris-openrgb-server.service" "$unit_root/aeris-openrgb-server.service"
install -Dm0644 "$repo_root/systemd/user/aeris-openrgb.service" "$unit_root/aeris-openrgb.service"

systemctl --user daemon-reload
"$app_root/configure-openrgb-detectors.py" --quarantine

echo "Aeris OpenRGB files installed in quarantine; no service was enabled or started."
echo "Backup: $backup_dir"
check_installation
