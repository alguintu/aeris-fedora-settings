#!/usr/bin/bash
set -euo pipefail

required_commands=(busctl gdbus jq kscreen-doctor kwriteconfig6 patch rg)
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
kzones_dir=$HOME/.local/share/kwin/scripts/kzones
kzones_main=$kzones_dir/contents/ui/main.qml
kzones_metadata=$kzones_dir/metadata.json

if [[ ! -f "$kzones_main" || ! -f "$kzones_metadata" ]]; then
    echo "KZones is not installed." >&2
    echo "Install it from System Settings > Window Management > KWin Scripts > Get New." >&2
    exit 1
fi

kzones_version=$(jq -r '.KPlugin.Version // empty' "$kzones_metadata")
if [[ "$kzones_version" != 0.9.2 ]]; then
    echo "This profile expects KZones 0.9.2; found ${kzones_version:-unknown}." >&2
    echo "Review patches/kzones-detach-native-tiling.patch before applying it to another version." >&2
    exit 1
fi

display_json=$(kscreen-doctor -j)
enabled_outputs=$(jq '[.outputs[] | select(.enabled)] | length' <<<"$display_json")
display_width=$(jq -r '[.outputs[] | select(.enabled)][0].size.width' <<<"$display_json")
display_height=$(jq -r '[.outputs[] | select(.enabled)][0].size.height' <<<"$display_json")
display_scale=$(jq -r '[.outputs[] | select(.enabled)][0].scale' <<<"$display_json")

if [[ "$enabled_outputs" != 1 || "$display_width" != 3840 || "$display_height" != 2160 || "$display_scale" != 1 ]]; then
    echo "This profile requires one enabled 3840x2160 display at 100% scale." >&2
    echo "Detected: outputs=$enabled_outputs size=${display_width}x${display_height} scale=$display_scale" >&2
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/fedora-settings
backup_dir=$state_root/backups/$timestamp
temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT

mkdir -p "$backup_dir"
for config_file in kcminputrc kglobalshortcutsrc kwinrc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc; do
    if [[ -f "$HOME/.config/$config_file" ]]; then
        cp -a "$HOME/.config/$config_file" "$backup_dir/$config_file"
    fi
done
cp -a "$kzones_main" "$backup_dir/kzones-main.qml"

kwriteconfig6 --notify --file kcminputrc --group Mouse --key cursorTheme breeze_cursors
kwriteconfig6 --notify --file kcminputrc --group Mouse --key cursorSize 36

cat >"$temp_dir/panels.js" <<'PLASMA_SCRIPT'
function widgetWithType(panel, type) {
    for (const widget of panel.widgets()) {
        if (widget.type === type) {
            return widget;
        }
    }
    return null;
}

function ensureWidget(panel, type) {
    let widget = widgetWithType(panel, type);
    if (!widget) {
        panel.addWidget(type);
        widget = widgetWithType(panel, type);
    }
    return widget;
}

let centerPanel = null;
let statusPanel = null;
for (const panel of panels()) {
    if (!centerPanel && widgetWithType(panel, "org.kde.plasma.icontasks")) {
        centerPanel = panel;
    }
    if (!statusPanel
        && widgetWithType(panel, "org.kde.plasma.systemtray")
        && widgetWithType(panel, "org.kde.plasma.digitalclock")) {
        statusPanel = panel;
    }
}

if (!centerPanel) {
    centerPanel = panels().length > 0 ? panels()[0] : new Panel;
}
if (!statusPanel || statusPanel.id === centerPanel.id) {
    statusPanel = new Panel;
}

centerPanel.location = "bottom";
centerPanel.alignment = "center";
centerPanel.lengthMode = "fit";
centerPanel.hiding = "windowsgobelow";
centerPanel.floating = true;
centerPanel.height = 46;
centerPanel.offset = 0;

ensureWidget(centerPanel, "org.kde.plasma.kickoff");
ensureWidget(centerPanel, "org.kde.plasma.pager");
ensureWidget(centerPanel, "org.kde.plasma.icontasks");

const statusTypes = [
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop",
];
for (const widget of centerPanel.widgets()) {
    if (statusTypes.includes(widget.type)) {
        widget.remove();
    }
}

statusPanel.location = "bottom";
statusPanel.alignment = "right";
statusPanel.lengthMode = "fit";
statusPanel.hiding = "windowsgobelow";
statusPanel.floating = true;
statusPanel.height = 46;
statusPanel.offset = 0;

ensureWidget(statusPanel, "org.kde.plasma.systemtray");
ensureWidget(statusPanel, "org.kde.plasma.digitalclock");
ensureWidget(statusPanel, "org.kde.plasma.showdesktop");
PLASMA_SCRIPT

panel_script=$(<"$temp_dir/panels.js")
gdbus call --session \
    --dest org.kde.plasmashell \
    --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript \
    "$panel_script" >/dev/null

patch_marker='including when the cursor misses a KZones indicator'
if ! rg -Fq "$patch_marker" "$kzones_main"; then
    patch --batch --forward -p1 -d "$kzones_dir" \
        <"$repo_root/patches/kzones-detach-native-tiling.patch"
fi

layouts_json=$(jq -c . "$repo_root/settings/kzones-layouts.json")
kwriteconfig6 --file kwinrc --group Script-kzones --key autoSnapAllNew false
kwriteconfig6 --file kwinrc --group Script-kzones --key enableEdgeSnapping false
kwriteconfig6 --file kwinrc --group Script-kzones --key enableZoneOverlay true
kwriteconfig6 --file kwinrc --group Script-kzones --key enableZoneSelector false
kwriteconfig6 --file kwinrc --group Script-kzones --key layoutsJson "$layouts_json"
kwriteconfig6 --file kwinrc --group Script-kzones --key rememberWindowGeometries true
kwriteconfig6 --file kwinrc --group Script-kzones --key zoneOverlayHighlightTarget 0
kwriteconfig6 --file kwinrc --group Script-kzones --key zoneOverlayIndicatorDisplay 1
kwriteconfig6 --file kwinrc --group Script-kzones --key zoneOverlayShowWhen 0

kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderMaximize false
kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderTiling false

disable_shortcut() {
    local action_name=$1
    local action_label=$2
    busctl --user call \
        org.kde.kglobalaccel \
        /kglobalaccel \
        org.kde.KGlobalAccel \
        setShortcut asaiu \
        4 kwin "$action_name" KWin "$action_label" \
        0 4 >/dev/null
}

disable_shortcut "Edit Tiles" "Toggle Tiles Editor"
disable_shortcut "Window Quick Tile Left" "Quick Tile Window to the Left"
disable_shortcut "Window Quick Tile Right" "Quick Tile Window to the Right"
disable_shortcut "Window Quick Tile Top" "Quick Tile Window to the Top"
disable_shortcut "Window Quick Tile Bottom" "Quick Tile Window to the Bottom"
disable_shortcut "Window Quick Tile Top Left" "Quick Tile Window to the Top Left"
disable_shortcut "Window Quick Tile Top Right" "Quick Tile Window to the Top Right"
disable_shortcut "Window Quick Tile Bottom Left" "Quick Tile Window to the Bottom Left"
disable_shortcut "Window Quick Tile Bottom Right" "Quick Tile Window to the Bottom Right"
disable_shortcut "Window Custom Quick Tile Left" "Custom Quick Tile Window to the Left"
disable_shortcut "Window Custom Quick Tile Right" "Custom Quick Tile Window to the Right"
disable_shortcut "Window Custom Quick Tile Top" "Custom Quick Tile Window to the Top"
disable_shortcut "Window Custom Quick Tile Bottom" "Custom Quick Tile Window to the Bottom"

kwriteconfig6 --file kwinrc --group Plugins --key kzonesEnabled false
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key kzonesEnabled true
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null
sleep 2

loaded=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting isScriptLoaded s kzones)
if [[ "$loaded" != "b true" ]]; then
    echo "KZones did not reload successfully: $loaded" >&2
    exit 1
fi

echo "Desktop profile applied."
echo "Backup: $backup_dir"
