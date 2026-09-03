#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
kzones_dir=$HOME/.local/share/kwin/scripts/kzones

echo "Display"
kscreen-doctor -j | jq -r '.outputs[] | select(.enabled) | "  \(.name): \(.size.width)x\(.size.height) scale=\(.scale)"'

echo "Cursor"
echo "  theme=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)"
echo "  size=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorSize)"

echo "Panels"
gdbus call --session \
    --dest org.kde.plasmashell \
    --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript \
    'for (const p of panels()) { print("  id="+p.id+" alignment="+p.alignment+" length="+p.lengthMode+" floating="+p.floating+" height="+p.height); for (const w of p.widgets()) print("    "+w.type); }'
awk '
    /^\[PlasmaViews\]\[Panel / { panel=$0 }
    /^panelVisibility=/ { print "  " panel " " $0 }
' "$HOME/.config/plasmashellrc"

echo "KZones"
if [[ -f "$kzones_dir/metadata.json" ]]; then
    jq -r '"  version=" + (.KPlugin.Version // "unknown")' "$kzones_dir/metadata.json"
else
    echo "  not installed"
fi
echo "  loaded=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting isScriptLoaded s kzones)"
for key in \
    autoSnapAllNew \
    disabledOutputs \
    enableEdgeSnapping \
    enableZoneOverlay \
    enableZoneSelector \
    rememberWindowGeometries \
    zoneOverlayHighlightTarget \
    zoneOverlayIndicatorDisplay \
    zoneOverlayShowWhen; do
    value=$(kreadconfig6 --file kwinrc --group Script-kzones --key "$key")
    echo "  $key=$value"
done

live_layout=$(kreadconfig6 --file kwinrc --group Script-kzones --key layoutsJson)
echo "$live_layout" | jq -r '.[0] | "  layout=\(.name) padding=\(.padding) zones=\(.zones | length)"'
if diff -q \
    <(jq -S . "$repo_root/settings/kzones-layouts.json") \
    <(jq -S . <<<"$live_layout") >/dev/null; then
    echo "  layout matches repository"
else
    echo "  WARNING: live layout differs from repository"
fi

if rg -Fq 'including when the cursor misses a KZones indicator' "$kzones_dir/contents/ui/main.qml"; then
    echo "  native-tile detach patch=present"
else
    echo "  native-tile detach patch=MISSING"
fi

if rg -Fq 'outputs where KZones should remain inactive' "$kzones_dir/contents/ui/main.qml"; then
    echo "  disabled-output patch=present"
else
    echo "  disabled-output patch=MISSING"
fi

echo "Native KWin tiling"
echo "  ElectricBorderTiling=$(kreadconfig6 --file kwinrc --group Windows --key ElectricBorderTiling)"
echo "  ElectricBorderMaximize=$(kreadconfig6 --file kwinrc --group Windows --key ElectricBorderMaximize)"

shortcut_state() {
    local action_name=$1
    local action_label=$2
    busctl --user call \
        org.kde.kglobalaccel \
        /kglobalaccel \
        org.kde.KGlobalAccel \
        shortcut as \
        4 kwin "$action_name" KWin "$action_label"
}

echo "  Edit Tiles: $(shortcut_state "Edit Tiles" "Toggle Tiles Editor")"
echo "  Quick Tile Left: $(shortcut_state "Window Quick Tile Left" "Quick Tile Window to the Left")"
echo "  Quick Tile Right: $(shortcut_state "Window Quick Tile Right" "Quick Tile Window to the Right")"
echo "  Quick Tile Top: $(shortcut_state "Window Quick Tile Top" "Quick Tile Window to the Top")"
echo "  Quick Tile Bottom: $(shortcut_state "Window Quick Tile Bottom" "Quick Tile Window to the Bottom")"
