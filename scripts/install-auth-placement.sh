#!/usr/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
package_dir=$repo_root/kwin/aeris-auth-primary
plugin_id=aeris-auth-primary
installed_dir=$HOME/.local/share/kwin/scripts/$plugin_id

if [[ ${1:-} == "--check" ]]; then
    if [[ ! -d $installed_dir ]]; then
        echo "$plugin_id is not installed"
        exit 1
    fi

    if ! diff -qr --exclude=.git "$package_dir" "$installed_dir"; then
        echo "$plugin_id differs from the repository copy"
        exit 1
    fi

    enabled=$(kreadconfig6 --file kwinrc --group Plugins --key "${plugin_id}Enabled" --default false)
    loaded=$(gdbus call --session \
        --dest org.kde.KWin \
        --object-path /Scripting \
        --method org.kde.kwin.Scripting.isScriptLoaded "$plugin_id")

    echo "installed: yes"
    echo "enabled: $enabled"
    echo "loaded: $loaded"
    [[ $enabled == true && $loaded == "(true,)" ]]
    exit
fi

if [[ ${1:-} == "--remove" ]]; then
    gdbus call --session \
        --dest org.kde.KWin \
        --object-path /Scripting \
        --method org.kde.kwin.Scripting.unloadScript "$plugin_id" >/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key "${plugin_id}Enabled" --delete
    kpackagetool6 --type KWin/Script --remove "$plugin_id"
    echo "Removed $plugin_id"
    exit
fi

if [[ -d $installed_dir ]]; then
    kpackagetool6 --type KWin/Script --upgrade "$package_dir"
else
    kpackagetool6 --type KWin/Script --install "$package_dir"
fi

kwriteconfig6 --file kwinrc --group Plugins --key "${plugin_id}Enabled" --type bool true

gdbus call --session \
    --dest org.kde.KWin \
    --object-path /Scripting \
    --method org.kde.kwin.Scripting.unloadScript "$plugin_id" >/dev/null || true
gdbus call --session \
    --dest org.kde.KWin \
    --object-path /Scripting \
    --method org.kde.kwin.Scripting.loadScript \
    "$installed_dir/contents/code/main.js" "$plugin_id" >/dev/null
gdbus call --session \
    --dest org.kde.KWin \
    --object-path /Scripting \
    --method org.kde.kwin.Scripting.start >/dev/null

"$0" --check
