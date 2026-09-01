#!/usr/bin/bash
set -euo pipefail

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

echo "KWin tiles"
grep -E '^(padding|tiles)=' "$HOME/.config/kwinrc"
