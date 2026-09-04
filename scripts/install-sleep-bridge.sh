#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
package=$repo_root/plasma/org.aeris.sleepbridge
backend=$repo_root/quickshell/aeris-dashboard/bin/aeris-dashboard-backend
if [[ ! -x $backend ]]; then
    bash "$script_dir/build-dashboard-backend.sh"
fi

if kpackagetool6 --type Plasma/Applet --show org.aeris.sleepbridge >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$package"
else
    kpackagetool6 --type Plasma/Applet --install "$package"
fi
"$backend" sleep attach-bridge

# Retire only our previous independent inhibitor, never another application's.
if systemctl --user is-active --quiet aeris-keep-awake.service; then
    systemctl --user stop aeris-keep-awake.service
fi
