#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/aeris-companion"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
binary_dir="$HOME/.local/bin"
umask 077
mkdir -p "$config_dir" "$unit_dir" "$binary_dir"
cargo build --manifest-path "$repo_dir/quickshell/aeris-backend/Cargo.toml" --release --bin aeris-companion
install -m 755 "$repo_dir/quickshell/aeris-backend/target/release/aeris-companion" "$binary_dir/aeris-companion"
if [[ ! -f "$config_dir/pairing.secret" ]]; then
    openssl rand -hex 32 > "$config_dir/pairing.secret"
fi
chmod 600 "$config_dir/pairing.secret"
cat > "$unit_dir/aeris-companion.service" <<EOF
[Unit]
Description=Aeris private phone companion API
After=graphical-session.target aeris-dashboard.service
PartOf=graphical-session.target

[Service]
ExecStart="$binary_dir/aeris-companion"
Environment="AERIS_COMPANION_TOKEN_FILE=$config_dir/pairing.secret"
Environment=AERIS_ALLOW_POWEROFF=1
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
UMask=0077

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable aeris-companion.service
systemctl --user restart aeris-companion.service
systemctl --user is-active aeris-companion.service
echo "Private API installed at 127.0.0.1:4280. Pairing secret: $config_dir/pairing.secret"
echo 'Next: expose this loopback port with Tailscale Serve; see mobile/README.md.'
