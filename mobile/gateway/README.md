# CasaOS gateway

The deployed route is Android + Tailscale → private Tailscale Serve on CasaOS →
Rust gateway → restricted reverse SSH tunnel → Aeris's existing loopback API.
Aeris does not need Tailscale. The always-on CasaOS Pi also sends wake packets.
The existing Android APK works without an update.

## Current deployment (2026-09-11)

- CasaOS: `raspberrypi.local`, Debian 12 ARM64, LAN `192.168.5.94`.
- Tailscale: `100.66.31.37`, `raspberrypi.taile902e7.ts.net`.
- Control address: `https://raspberrypi.taile902e7.ts.net`.
- Wake address: `https://raspberrypi.taile902e7.ts.net:8443`.
- Serve is tailnet-only; Funnel is disabled. No router port forwarding.
- Both endpoints require separate 256-bit bearer tokens.
- The private four-field phone setup is at
  `~/.config/aeris-companion/gateway/phone-setup.txt` on Aeris (mode 600).
  It is not part of this repository; do not copy its tokens into documentation.

On Android, connect Tailscale with the same account, then enter the two URLs and
corresponding tokens in the existing Aeris app's Connection screen. Physical
phone pairing, off-site access, and actual power-cycle wake still need testing.

## Services and boundaries

`aeris-gateway.service` runs as unprivileged `aeris-gateway` on CasaOS:

- `/opt/aeris-gateway/aeris-gateway`: static ARM64 Rust executable.
- `127.0.0.1:4280`: authenticated control proxy; only fixed dashboard routes.
- `127.0.0.1:4282`: authenticated wake status and `/v1/wake` only.
- `/etc/aeris-gateway/{control,wake,upstream}.secret`: private gateway-owned files.
- No arbitrary upstream, shell command, MAC, or fan speed from HTTP requests.
- No browser origins, redirects, environment proxies, or automatic
  application-level command retries. Hardware routes accept no bodies. The
  explicit `/v1/tomat` and `/v1/workout/set` routes accept JSON up to 4096 bytes. Upstream responses are bounded to 256 KiB.
- Downstream status preserves Aeris's original service timestamps. An unreachable
  tunnel returns 503 rather than implying that the PC is powered off.
- Wake uses fixed MAC `2c:f0:5d:57:a2:c2`, broadcast `192.168.5.255`, UDP 9, and a
  ten-second cooldown. Sending a packet is not evidence the PC woke.

`aeris-casaos-tunnel.service` runs under Drei's user systemd on Aeris. It connects
outward to `aeris-tunnel@raspberrypi.local`, exposing only CasaOS loopback 4281,
forwarded to Aeris loopback 4280. It reconnects after network interruption.
The Pi account has no sudo and uses a dedicated key, restricted by source LAN IP,
`restrict,port-forwarding`, `permitlisten="127.0.0.1:4281"`,
`permitopen="127.0.0.1:1"`, and `command="/bin/false"`. The unusable local-forward
target prevents arbitrary local forwarding; shell commands are denied. The
independent administrative recovery key is never used by the tunnel service.
Host-key checking is mandatory. No sshd-wide configuration was changed.

The desktop API and Plasma integration require Drei's desktop session after a
cold boot. The tunnel runs with the user session. Pre-login control remains
unsupported. Reserve the LAN addresses in the router before relying on this
configuration long-term; the tunnel key's source restriction must match Aeris.

## Build and checks

This is a separate small crate so deploying to the Pi doesn't require building
Quickshell's desktop libraries or installing a compiler on its nearly-full SD.

```sh
cargo test --manifest-path mobile/gateway/Cargo.toml
cargo clippy --manifest-path mobile/gateway/Cargo.toml --all-targets -- -D warnings
rustup target add aarch64-unknown-linux-musl
# cargo-zigbuild and Zig must be on PATH
cargo zigbuild --locked --release --target aarch64-unknown-linux-musl \
  --manifest-path mobile/gateway/Cargo.toml
```

The host toolchain was installed with `uv tool install cargo-zigbuild --with
ziglang`. Zig's executable directory is inside that tool's Python environment;
add it to PATH when running cargo-zigbuild.

Seven tests cover credential separation, route/body/origin rejection, shutdown
confirmation, upstream token substitution, timestamp preservation, refusal to
follow redirects, a mocked shutdown forwarded once, offline semantics, and wake
packet/cooldown. The shutdown test uses a mock server and never powers off Aeris.

Verified deployment: both HTTPS endpoints with normal certificate validation;
all four live service payloads; 401/403/404/400 rejection paths; same-active
Default cooling command; loopback-only listeners; restricted tunnel rejecting
another port and a shell command; controls returning 503 while the stopped
tunnel leaves wake status usable; restored controls after tunnel restart.

## Operations

```sh
# On Aeris
systemctl --user status aeris-casaos-tunnel aeris-companion
ssh aeris-casaos

# On CasaOS
sudo systemctl status aeris-gateway
sudo tailscale serve status
sudo journalctl -u aeris-gateway -n 30
```

Disabling `aeris-gateway` and `aeris-casaos-tunnel` stops this route without
changing the desktop dashboard. Serve can be disabled for ports 443 and 8443
individually. Token rotation requires updating the matching private files,
restarting the gateway, and updating the phone. Upstream token rotation must also
update Aeris's API token; do not use the wake credential for live control.

Wake packet delivery was also checked on the LAN: exactly 102 bytes with the
configured MAC, followed by HTTP 429 for an immediate repeat. Aeris was awake;
no shutdown/suspend cycle was performed. NetworkManager `LAN` now persists WoL
`magic`; reapplying the connection changed PCI `power/wakeup` to `enabled`
without disconnecting. BIOS/ErP and physical wake still need attended checks.


## Pomodoro extension — 2026-09-13

Deployed the bounded JSON forwarding routes for the phone's shared Tomat and
workout UI. Eight gateway tests pass, including body limits, unchanged payload
forwarding with the upstream credential, conflict status preservation, no retry,
and rejection on the wake endpoint. Verified timer/templates through private
HTTPS and rejected an invalid JSON action without changing the live timer.
Previous binary retained at `/opt/aeris-gateway/aeris-gateway.pre-pomodoro`.
