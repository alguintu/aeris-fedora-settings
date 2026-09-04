#!/usr/bin/bash
# Restore only reviewed cooling data. Never copy authentication or signing keys.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:---check}
if [[ $action != --check && $action != --restore ]]; then
    echo 'Usage: restore-cooling.sh [--check|--restore]' >&2
    exit 2
fi

if [[ $action == --restore && $EUID != 0 ]]; then
    # Use the desktop authentication prompt, not a terminal password request.
    exec pkexec "$repo_root/scripts/restore-cooling.sh" --restore
fi

[[ $(cat /sys/class/dmi/id/board_name) == 'MAG B550M MORTAR WIFI (MS-7C94)' ]] || {
    echo 'Refusing: this snapshot is only for the Aeris B550M Mortar WiFi.' >&2; exit 1;
}
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]] || {
    echo 'Refusing: this restore was prepared for Fedora 44.' >&2; exit 1;
}
[[ $(rpm -q --qf '%{VERSION}' coolercontrold) == 4.3.1 ]] || {
    echo 'Refusing: snapshot schema was verified with CoolerControl 4.3.1.' >&2; exit 1;
}
python3 "$repo_root/scripts/validate-cooling.py" --device-config /etc/coolercontrol/config.toml
if [[ $action == --check ]]; then
    echo 'PASS: restore preflight only; no files, services, or fans changed.'
    exit 0
fi

# Discovery must already have run once. The check above rejects changed IDs
# before stopping anything. Stop before copying so the daemon cannot overwrite.
systemctl disable --now coolercontrold.service
found=0
for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r $hwmon/name && $(<"$hwmon/name") == nct6687 ]] || continue
    found=1
    for mode in "$hwmon"/pwm*_enable; do
        [[ -r $mode && $(<"$mode") == 2 ]] || {
            echo 'Refusing: a channel did not return to firmware control; reboot and recheck.' >&2
            exit 1
        }
    done
done
[[ $found == 1 ]] || { echo 'Refusing: nct6687 is absent.' >&2; exit 1; }

install -d -m0700 /var/backups/aeris-cooling
backup=$(mktemp -d /var/backups/aeris-cooling/restore-XXXXXXXX)
files=(config.toml modes.json calibrations.json config-ui.json alerts.json)
for name in "${files[@]}"; do
    if [[ -e /etc/coolercontrol/$name ]]; then
        cp -a -- "/etc/coolercontrol/$name" "$backup/$name"
    fi
done
echo "Previous cooling data backed up to $backup"
for name in "${files[@]}"; do
    install -m0644 "$repo_root/cooling/snapshot/$name" "/etc/coolercontrol/$name"
done
echo 'Saved cooling setup restored. CoolerControl remains disabled/stopped; BIOS owns the fans.'
echo 'After reviewing the files, start the restored Default profile with:'
echo '  pkexec systemctl enable --now coolercontrold.service'
echo 'Then open CoolerControl, authenticate locally, and run coolingctl.py status.'
