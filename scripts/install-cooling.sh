#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
expected_board='MAG B550M MORTAR WIFI (MS-7C94)'
driver_version='0.20260901-1.git5997c92.fc44'
driver_url='https://gitlab.com/api/v4/projects/79884554/packages/generic/nct6687d-dkms/0.20260901/nct6687d-dkms-0.20260901-1.git5997c92.fc44.noarch.rpm'
driver_sha256='2c687a1a3f96c4c87c0915c3d979e3f803a166186ca063b0655906833e657a34'
driver_rpm=

cleanup() {
    if [[ -n $driver_rpm && -f $driver_rpm ]]; then
        rm -f -- "$driver_rpm"
    fi
}

trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: install-cooling.sh --install|--activate|--check

  --install   Install pinned packages and boot configuration, but do not start
              CoolerControl or take manual control of any fan.
  --activate  Load the verified driver and start CoolerControl. Refuses to
              proceed unless every PWM channel is in firmware mode.
  --check     Read-only audit of packages, driver, channels, and service state.
EOF
}

run_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        pkexec "$@"
    fi
}

require_target() {
    local board_name
    board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)
    if [[ $board_name != "$expected_board" ]]; then
        echo "Refusing: expected '$expected_board', found '${board_name:-unknown}'." >&2
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ ${ID:-} != fedora || ${VERSION_ID:-} != 44 ]]; then
        echo "Refusing: the pinned driver RPM targets Fedora 44, found ${PRETTY_NAME:-unknown}." >&2
        exit 1
    fi
}

firmware_mode_is_safe() {
    local found=0 candidate mode_file mode
    for candidate in /sys/class/hwmon/hwmon*; do
        [[ -r $candidate/name ]] || continue
        [[ $(<"$candidate/name") == nct6687 ]] || continue
        found=1
        for mode_file in "$candidate"/pwm*_enable; do
            [[ -r $mode_file ]] || continue
            mode=$(<"$mode_file")
            if [[ $mode != 2 ]]; then
                echo "Unsafe: $mode_file is mode '$mode', expected firmware mode 2." >&2
                return 1
            fi
        done
    done
    (( found == 1 ))
}

restore_firmware_mode() {
    local candidate mode_file
    for candidate in /sys/class/hwmon/hwmon*; do
        [[ -r $candidate/name ]] || continue
        [[ $(<"$candidate/name") == nct6687 ]] || continue
        for mode_file in "$candidate"/pwm*_enable; do
            [[ -e $mode_file ]] || continue
            printf '2\n' | run_root tee "$mode_file" >/dev/null
        done
    done
}

install_cooling() {
    local calculated_sha
    driver_rpm=$(mktemp --suffix=.nct6687d.rpm)

    echo "Downloading pinned nct6687d DKMS package $driver_version"
    curl --fail --location --silent --show-error "$driver_url" --output "$driver_rpm"
    calculated_sha=$(sha256sum "$driver_rpm" | awk '{print $1}')
    if [[ $calculated_sha != "$driver_sha256" ]]; then
        echo "Refusing: nct6687d RPM checksum mismatch." >&2
        exit 1
    fi

    run_root dnf install -y dnf-plugins-core dkms "kernel-devel-$(uname -r)" lm_sensors
    run_root dnf copr enable -y codifryed/CoolerControl
    run_root dnf install -y coolercontrol-4.3.1 coolercontrold-4.3.1 "$driver_rpm"

    run_root systemctl disable --now coolercontrold.service
    run_root install -Dm0644 \
        "$repo_root/modprobe/aeris-nct6687.conf" \
        /etc/modprobe.d/aeris-nct6687.conf
    run_root install -Dm0644 \
        "$repo_root/modules-load/aeris-nct6687.conf" \
        /etc/modules-load.d/aeris-nct6687.conf

    echo
    echo 'Cooling packages are installed in quarantine; CoolerControl remains disabled.'
    if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
        echo 'Secure Boot is enabled. Enroll the DKMS key before activation:'
        echo '  sudo mokutil --import /var/lib/dkms/mok.pub'
        echo 'Then reboot and choose Enroll MOK -> Continue -> Yes in the firmware screen.'
    else
        echo 'Reboot once so the dedicated nct6687 module is loaded cleanly.'
    fi
    echo 'After reboot, run ./scripts/check-cooling.sh --firmware and then --activate.'
}

activate_cooling() {
    # --activate is the discovery-only first start, never the restored-profile
    # startup path. Reject saved control assignments before starting anything.
    python3 - <<'PY'
from pathlib import Path
import tomllib
p = Path('/etc/coolercontrol/config.toml')
if p.exists():
    config = tomllib.loads(p.read_text())
    for channels in config.get('device-settings', {}).values():
        for setting in channels.values():
            if setting.get('profile_uid', '0') != '0' or any(
                key in setting for key in ('speed_fixed', 'lighting', 'lcd')
            ):
                raise SystemExit('Refusing discovery activation: saved controls exist. See settings/cooling.md.')
PY
    if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
        if ! mokutil --test-key /var/lib/dkms/mok.pub 2>/dev/null | grep -qi 'is already enrolled'; then
            echo 'Refusing: Secure Boot is enabled but the DKMS key is not enrolled.' >&2
            exit 1
        fi
    fi
    if grep -q '^nct6683[[:space:]]' /proc/modules; then
        echo 'Refusing: nct6683 is loaded. Reboot so the blacklist can take effect.' >&2
        exit 1
    fi

    if [[ ! -e /sys/module/nct6687 ]]; then
        run_root modprobe nct6687
    fi
    if ! firmware_mode_is_safe; then
        echo 'Refusing to start CoolerControl: nct6687 is absent or a channel is already manual.' >&2
        exit 1
    fi

    run_root systemctl enable --now coolercontrold.service
    if ! systemctl is-active --quiet coolercontrold.service; then
        run_root systemctl disable --now coolercontrold.service
        restore_firmware_mode
        echo 'CoolerControl failed to start; firmware mode was restored.' >&2
        exit 1
    fi
    if ! firmware_mode_is_safe; then
        run_root systemctl disable --now coolercontrold.service
        restore_firmware_mode
        echo 'CoolerControl changed a PWM channel before profiles were approved; stopped and restored firmware mode.' >&2
        exit 1
    fi

    echo 'CoolerControl is active. Every motherboard PWM channel remains in firmware mode.'
    echo 'For an unchanged Aeris reinstall, next run ./scripts/restore-cooling.sh --check.'
    echo 'Then --restore installs the saved modes/calibrations. See settings/cooling.md.'
}

if [[ (${1:-} == --install || ${1:-} == --activate) && $EUID != 0 ]]; then
    exec pkexec "$repo_root/scripts/install-cooling.sh" "$@"
fi

case ${1:-} in
    --install)
        require_target
        install_cooling
        ;;
    --activate)
        require_target
        activate_cooling
        ;;
    --check)
        exec "$repo_root/scripts/check-cooling.sh"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
