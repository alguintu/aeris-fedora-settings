#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
dashboard_dir=$repo_root/quickshell/aeris-dashboard

# The system Qt/RHI runtime and shipped QSB shaders support Vulkan on Aeris.
# Keep an explicit OpenGL escape hatch for comparisons or driver regressions.
export QSG_RHI_BACKEND=${QSG_RHI_BACKEND:-vulkan}

if [[ ${AERIS_DASHBOARD_BACKEND:-rust} != python && ! -x $dashboard_dir/bin/aeris-dashboard-backend ]]; then
    echo 'Rust dashboard backend is missing. Run: bash scripts/build-dashboard-backend.sh' >&2
    echo 'Temporary rollback: AERIS_DASHBOARD_BACKEND=python bash scripts/run-dashboard.sh' >&2
    exit 1
fi

if ! command -v quickshell >/dev/null; then
    echo 'Quickshell 0.3+ is required for compositor backdrop blur. See the dashboard README.' >&2
    exit 1
fi

# Fail clearly instead of silently falling back to the incompatible 0.2.1 bundle.
runtime_version=$(quickshell --version)
if [[ ! $runtime_version =~ Quickshell\ ([0-9]+)\.([0-9]+) ]]; then
    echo "Cannot identify Quickshell runtime: $runtime_version" >&2
    exit 1
fi
if (( BASH_REMATCH[1] == 0 && BASH_REMATCH[2] < 3 )); then
    echo 'Quickshell 0.3+ is required. Upgrade the runtime and matching Qt packages; see the dashboard README.' >&2
    exit 1
fi

export QS_NO_RELOAD_POPUP=1

exec quickshell --no-duplicate --path "$dashboard_dir" "$@"
