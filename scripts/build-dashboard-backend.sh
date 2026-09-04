#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
crate_dir=$repo_root/quickshell/aeris-backend
destination=$repo_root/quickshell/aeris-dashboard/bin/aeris-dashboard-backend

if ! command -v cargo >/dev/null; then
    echo 'Rust/Cargo is required to build the dashboard backend.' >&2
    exit 1
fi

# Keep build products local and deterministic regardless of a caller's CARGO_TARGET_DIR.
cargo build --manifest-path "$crate_dir/Cargo.toml" --target-dir "$crate_dir/target" --release --locked --bin aeris-dashboard-backend "$@"
mkdir -p -- "$(dirname -- "$destination")"
staging=$(mktemp "${destination}.build.XXXXXX")
trap 'rm -f -- "$staging"' EXIT
install -m0755 "$crate_dir/target/release/aeris-dashboard-backend" "$staging"
# Atomic replacement works even while the previous executable is running.
mv -f -- "$staging" "$destination"
"$destination" --version
