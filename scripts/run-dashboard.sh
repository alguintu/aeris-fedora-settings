#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
dashboard_dir=$repo_root/quickshell/aeris-dashboard

# The bundled Qt/RHI runtime and shipped QSB shaders support Vulkan on Aeris.
# Keep an explicit OpenGL escape hatch for comparisons or driver regressions.
export QSG_RHI_BACKEND=${QSG_RHI_BACKEND:-vulkan}

if [[ ${AERIS_DASHBOARD_BACKEND:-rust} != python && ! -x $dashboard_dir/bin/aeris-dashboard-backend ]]; then
    echo 'Rust dashboard backend is missing. Run: bash scripts/build-dashboard-backend.sh' >&2
    echo 'Temporary rollback: AERIS_DASHBOARD_BACKEND=python bash scripts/run-dashboard.sh' >&2
    exit 1
fi

if command -v quickshell >/dev/null; then
    exec quickshell --no-duplicate --path "$dashboard_dir" "$@"
fi

runtime_root=$HOME/.local/opt/quickshell-fedora-0.2.1
runtime_bin=$runtime_root/usr/bin/quickshell

if [[ ! -x "$runtime_bin" ]]; then
    echo "Quickshell is not installed." >&2
    echo "Install it with: sudo dnf install quickshell" >&2
    exit 1
fi

export LD_LIBRARY_PATH=$runtime_root/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export QT_PLUGIN_PATH=$runtime_root/usr/lib64/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
export QML2_IMPORT_PATH=$runtime_root/usr/lib64/qt6/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
export QT_QPA_PLATFORMTHEME=
export QS_NO_RELOAD_POPUP=1

exec "$runtime_bin" --no-duplicate --path "$dashboard_dir" "$@"
