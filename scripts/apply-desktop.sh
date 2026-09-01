#!/usr/bin/bash
set -euo pipefail

required_commands=(busctl gdbus jq kscreen-doctor kwriteconfig6)
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
done

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
for config_file in kcminputrc kwinrc plasma-org.kde.plasma.desktop-appletsrc; do
    if [[ -f "$HOME/.config/$config_file" ]]; then
        cp -a "$HOME/.config/$config_file" "$backup_dir/$config_file"
    fi
done

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
centerPanel.hiding = "none";
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
statusPanel.hiding = "none";
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

cat >"$temp_dir/tiles.js" <<'KWIN_SCRIPT'
const Floating = 0;
const root = workspace.tilingForScreen(workspace.activeScreen).rootTile;

let guard = 0;
while (root.tiles.length > 0 && guard++ < 100) {
    let leaf = root;
    while (leaf.tiles.length > 0) {
        leaf = leaf.tiles[0];
    }
    leaf.remove();
}
if (root.tiles.length !== 0) {
    throw new Error("Unable to clear the existing tile tree safely");
}

root.split(Floating);
while (root.tiles.length < 6) {
    root.tiles[root.tiles.length - 1].split(Floating);
}

const halfUsableHeight = 1049 / 2160;
const targets = [
    {x: 0.00, y: 0,                width: 0.25, height: halfUsableHeight},
    {x: 0.00, y: halfUsableHeight, width: 0.25, height: halfUsableHeight},
    {x: 0.25, y: 0,                width: 0.50, height: halfUsableHeight},
    {x: 0.25, y: halfUsableHeight, width: 0.50, height: halfUsableHeight},
    {x: 0.75, y: 0,                width: 0.25, height: halfUsableHeight},
    {x: 0.75, y: halfUsableHeight, width: 0.25, height: halfUsableHeight},
];

for (let index = 0; index < targets.length; ++index) {
    root.tiles[index].relativeGeometry = targets[index];
}
root.padding = 8;
KWIN_SCRIPT

plugin_name=fedora-settings-$timestamp
script_id=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$temp_dir/tiles.js" "$plugin_name" | awk '{print $2}')
if [[ -z "$script_id" || "$script_id" == "-1" ]]; then
    echo "KWin refused to load the tile restoration script." >&2
    exit 1
fi

busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting start >/dev/null
sleep 3
busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s "$plugin_name" >/dev/null

echo "Desktop profile applied."
echo "Backup: $backup_dir"
