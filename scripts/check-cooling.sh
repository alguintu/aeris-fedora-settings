#!/usr/bin/bash
set -uo pipefail

expected_board='MAG B550M MORTAR WIFI (MS-7C94)'
result=0
audit_mode=${1:---runtime}
if [[ $audit_mode != --runtime && $audit_mode != --firmware ]]; then
    echo 'Usage: check-cooling.sh [--runtime|--firmware]' >&2
    exit 2
fi

pass() {
    printf 'PASS     %s\n' "$*"
}

warn() {
    printf 'WARN     %s\n' "$*" >&2
}

fail() {
    printf 'FAIL     %s\n' "$*" >&2
    result=1
}

board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)
if [[ $board_name == "$expected_board" ]]; then
    pass "board is $board_name"
else
    fail "expected '$expected_board', found '${board_name:-unknown}'"
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ ${ID:-} == fedora && ${VERSION_ID:-} == 44 ]]; then
        pass "operating system is Fedora 44"
    else
        fail "the pinned RPM is for Fedora 44; found ${PRETTY_NAME:-unknown}"
    fi
else
    fail 'cannot read /etc/os-release'
fi

secure_boot_enabled=false
if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
    secure_boot_enabled=true
    pass 'Secure Boot is enabled'
else
    warn 'Secure Boot is disabled or unreadable; MOK enrollment is required only when enabled'
fi

for package in coolercontrol coolercontrold dkms nct6687d-dkms; do
    if installed=$(rpm -q "$package" 2>/dev/null); then
        pass "installed $installed"
    else
        fail "$package is not installed"
    fi
done

kernel_release=$(uname -r)
if installed=$(rpm -q "kernel-devel-$kernel_release" 2>/dev/null); then
    pass "installed $installed"
else
    fail "kernel-devel-$kernel_release is not installed"
fi

if dkms status 2>/dev/null | grep -q "nct6687.*$kernel_release"; then
    pass "nct6687 DKMS build exists for $kernel_release"
else
    fail "no nct6687 DKMS build found for $kernel_release"
fi

if [[ $secure_boot_enabled == false ]]; then
    pass 'MOK enrollment gate not applicable while Secure Boot is disabled'
elif [[ -r /var/lib/dkms/mok.pub ]]; then
    mok_test=$(LC_ALL=C mokutil --test-key /var/lib/dkms/mok.pub 2>&1 || true)
    if grep -Fqi 'is already enrolled' <<<"$mok_test"; then
        pass 'DKMS signing key is enrolled'
    else
        fail 'DKMS signing key is not enrolled; import it and complete MOK enrollment at reboot'
    fi
else
    fail 'missing DKMS public signing key /var/lib/dkms/mok.pub'
fi

if grep -q '^nct6683[[:space:]]' /proc/modules; then
    fail 'conflicting in-tree nct6683 module is loaded'
else
    pass 'conflicting nct6683 module is not loaded'
fi

if grep -q '^nct6687[[:space:]]' /proc/modules; then
    pass 'nct6687 module is loaded'
else
    fail 'nct6687 module is not loaded'
fi

hwmon_path=
for candidate in /sys/class/hwmon/hwmon*; do
    [[ -r $candidate/name ]] || continue
    if [[ $(<"$candidate/name") == nct6687 ]]; then
        hwmon_path=$candidate
        break
    fi
done

if [[ -z $hwmon_path ]]; then
    fail 'nct6687 hwmon device is not present'
else
    pass "nct6687 hwmon device is $hwmon_path"
    printf '\n%-8s %-18s %10s %8s %8s\n' CHANNEL EXPECTED_HEADER RPM PWM MODE
    expected_headers=('CPU_FAN' 'PUMP' 'SYSFAN1' 'SYSFAN2' 'SYSFAN3' 'unused' 'unused' 'unused')
    for number in {1..8}; do
        fan_file=$hwmon_path/fan${number}_input
        pwm_file=$hwmon_path/pwm${number}
        mode_file=$hwmon_path/pwm${number}_enable
        [[ -e $fan_file || -e $pwm_file || -e $mode_file ]] || continue

        rpm='-'
        pwm='-'
        mode='-'
        [[ -r $fan_file ]] && rpm=$(<"$fan_file")
        [[ -r $pwm_file ]] && pwm=$(<"$pwm_file")
        [[ -r $mode_file ]] && mode=$(<"$mode_file")
        printf 'fan%-4s %-18s %10s %8s %8s\n' \
            "$number" "${expected_headers[$((number - 1))]}" "$rpm" "$pwm" "$mode"

        if [[ $audit_mode == --firmware && $mode != 2 ]]; then
            fail "pwm${number}_enable is '$mode', expected firmware/automatic mode 2"
        elif [[ $audit_mode == --runtime && $number -le 5 && $mode != 1 && $mode != 2 ]]; then
            fail "pwm${number}_enable is '$mode', expected manual 1 or firmware 2"
        elif [[ $number -ge 6 && $mode != 2 ]]; then
            fail "unused pwm${number}_enable is '$mode', expected firmware 2"
        fi
    done
    printf '\n'
fi

if systemctl is-enabled --quiet coolercontrold.service 2>/dev/null; then
    pass 'coolercontrold is enabled'
else
    warn 'coolercontrold is disabled (expected before activation)'
fi

if systemctl is-active --quiet coolercontrold.service 2>/dev/null; then
    pass 'coolercontrold is active'
else
    warn 'coolercontrold is inactive (expected before activation)'
fi

exit "$result"
