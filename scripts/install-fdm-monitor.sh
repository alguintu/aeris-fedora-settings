#!/usr/bin/bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
binary=$repo_root/quickshell/aeris-dashboard/bin/aeris-dashboard-backend
test -x "$binary" || { echo 'Build the dashboard backend first.' >&2; exit 1; }
flatpak info --user org.freedownloadmanager.Manager >/dev/null
# Read the embedded UI for the scoped native Move-picker correction.
flatpak override --user --env=QML_XHR_ALLOW_FILE_READ=1 org.freedownloadmanager.Manager
install -Dm644 "$repo_root/quickshell/fdm/Monitor.qml" \
    "$HOME/.var/app/org.freedownloadmanager.Manager/config/aeris/Monitor.qml"
install -Dm644 "$repo_root/quickshell/fdm/MoveFolderFix.js" \
    "$HOME/.var/app/org.freedownloadmanager.Manager/config/aeris/MoveFolderFix.js"
# Rust selects launcher behavior from argv[0]; no long-lived shell or Python host.
mkdir -p "$HOME/.local/bin"
ln -sfn "$binary" "$HOME/.local/bin/aeris-fdm"
install -Dm644 "$repo_root/quickshell/fdm/org.freedownloadmanager.Manager.desktop" \
    "$HOME/.local/share/applications/org.freedownloadmanager.Manager.desktop"
update-desktop-database "$HOME/.local/share/applications"
echo 'FDM monitor installed. Quit an already-open stock FDM once, then launch normally.'
