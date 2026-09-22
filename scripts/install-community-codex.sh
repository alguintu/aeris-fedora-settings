#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/install-community-codex.sh [--dry-run | --help]

Build and install ChatGPT Community (codex-desktop) on non-Atomic Fedora.
Run as your normal user; package installation uses sudo.
Close existing ChatGPT / Codex desktop apps before installing.

CODEX_COMMUNITY_DIR overrides the new checkout directory.
Default: $HOME/.local/share/codex-community/source
Existing paths are never reused, updated, or removed.
EOF
}

dry_run=false
case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --dry-run) dry_run=true ;;
    '') ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || fail 'Run as your normal user, not with sudo.'
# shellcheck source=/etc/os-release
source /etc/os-release
[[ ${ID:-} == fedora ]] || fail 'This helper supports Fedora only.'
[[ ! -e /run/ostree-booted ]] || fail 'Fedora Atomic needs the upstream AppImage/container build flow.'
case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) fail 'Upstream supports x86_64 and aarch64 only.' ;;
esac

checkout=${CODEX_COMMUNITY_DIR:-"$HOME/.local/share/codex-community/source"}
[[ $checkout == /* ]] || fail 'CODEX_COMMUNITY_DIR must be an absolute path.'
[[ ! -e $checkout && ! -L $checkout ]] || fail "Checkout path already exists: $checkout. Choose a new CODEX_COMMUNITY_DIR, or use upstream's update instructions."

run() {
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    if ! "$dry_run"; then
        "$@"
    fi
}

# Rust/Cargo are needed for the native updater. Upstream installs the remaining
# build dependencies and verifies its current official application payload.
run sudo dnf install git make rust cargo
run mkdir -p -- "$(dirname -- "$checkout")"
run git clone -- https://github.com/ilysenko/codex-desktop-linux.git "$checkout"
run git -C "$checkout" rev-parse HEAD
run make -C "$checkout" bootstrap-native
run rpm -q codex-desktop

if ! "$dry_run"; then
    printf '\nInstalled. Launch ChatGPT Community from the app menu or run codex-desktop.\n'
    printf 'Sign in with your own account and open your project folder.\n'
fi
