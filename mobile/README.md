# Aeris phone companion

Android-only Kotlin / Jetpack Compose app, with a Rust API alongside the existing
Quickshell backend. Lighting, cooling, and Awake use the same adapters and modes
as the desktop dashboard. No independent fan curves or RGB hardware controller.

## Connection design

The deployed setup uses CasaOS as the always-on gateway. **Aeris does not need
Tailscale.** The existing Android APK supports this configuration.

```text
Android + Tailscale → CasaOS private HTTPS :443 → Rust gateway
                                                   ↓ restricted SSH tunnel
                                               Aeris loopback API :4280
                                                   ↓ existing desktop adapters
Android + Tailscale → CasaOS private HTTPS :8443 → Rust wake relay → LAN wake packet
```

Use `https://raspberrypi.taile902e7.ts.net` for Aeris and
`https://raspberrypi.taile902e7.ts.net:8443` for the wake relay, with their separate
pairing tokens. The private setup file on Aeris is
`~/.config/aeris-companion/gateway/phone-setup.txt`; credentials are never stored
in the repository. See [gateway/README.md](gateway/README.md) for deployment,
security boundaries, tests, and operations.

CasaOS remains powered on and shares Aeris's Ethernet broadcast domain. Serve is
private to the tailnet; Funnel and router port forwarding are not used. The phone
must run Tailscale under the same account. The app encrypts configuration with
Android Keystore and disables backup. Both Rust listeners and the Aeris API bind
only to loopback. Redirects and automatic action retries are disabled.

Physical phone pairing, off-site testing, and actual wake cycles are still
pending; successful local HTTPS checks do not establish those results.

## Build the Android APK

Requires JDK 21, Android SDK 36, and the checked-in Gradle wrapper. Versions are
pinned to the workstation's compatible toolchain, including Compose BOM
2025.10.01. The app supports Android 8 (API 26) and later.

```bash
cd mobile
JAVA_HOME=/home/drei/.local/share/jdk-21 \
ANDROID_HOME=/home/drei/Android/Sdk \
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`. This is a debug-signed first
build. A durable release signing key and release APK are a later packaging
step; do not commit keystores. Install using Android's APK installer or
`adb install -r app/build/outputs/apk/debug/app-debug.apk` with your phone
connected and USB debugging authorized.

## Install the Aeris API

Run `scripts/install-companion.sh` from the repository. It builds only the new
binary, installs a user service, and generates a private pairing secret if one
does not already exist. The Quickshell binary is not rebuilt or replaced.

The service runs with the desktop session to reach Plasma and the existing
Awake watcher. After cold boot it requires Drei's desktop session to be running;
remote pre-login dashboard control is not implemented. It survives a screen
lock. Normal shutdown goes through login1, checks `CanPowerOff`, and allows no
interactive privilege prompt. No forced shutdown or broad Polkit rule is added.

The following is the original optional direct-to-PC alternative, **not the
current deployment**. It requires Tailscale on Aeris:

```bash
sudo tailscale serve --bg http://127.0.0.1:4280
tailscale serve status
```

Use the reported HTTPS address in the Android app. Enter the contents of
`~/.config/aeris-companion/pairing.secret` as the Aeris pairing token. Keep it
private. To rotate access, replace the file with a fresh `openssl rand -hex 32`
value, preserve mode 600, restart the service, and update the phone.

## Original wake-only relay alternative

The current deployment is the combined [CasaOS gateway](gateway/README.md).
The following describes the earlier standalone relay design, retained as an
alternative.

`relay.service.example` records the intended native systemd deployment on the
CasaOS host. The host address, OS/architecture, SSH access, and existing VPN
configuration must be checked before installation. Build the Rust binary on a
compatible host/container; a Fedora-built dynamic binary is not assumed to run
unchanged on a Debian CasaOS host.

Create a dedicated unprivileged `aeris-relay` user. Install the compatible binary
at `/opt/aeris-companion/aeris-companion`. Generate a **different** 64-hex secret
at `/etc/aeris-companion/pairing.secret`, owned by that user with mode 600.
Install the reviewed unit as `/etc/systemd/system/aeris-wake-relay.service` and
enable/start it. Keep the relay on the host network if containerizing it; an
isolated Docker bridge will not send the packet onto Aeris's physical LAN.
Expose its loopback port using Tailscale Serve as above. Add its HTTPS URL and
separate token in the app's wake-relay fields.

Observed on Aeris, 2026-09-11:

- Ethernet: `enp42s0`, `192.168.5.115/24`, MAC `2c:f0:5d:57:a2:c2`.
- Matching directed broadcast: `192.168.5.255`; confirm CasaOS is on this LAN.
- NetworkManager connection `LAN` has Wake-on-LAN set to `default`.
- Unprivileged `ethtool` did not reveal the current WoL setting.

Wake still needs firmware/NIC verification. Check BIOS wake by PCI-E/PME and
shutdown standby power/ErP behavior, then inspect `sudo ethtool enp42s0`. To
persist magic-packet wake on this connection after confirming support:

```bash
sudo nmcli connection modify LAN 802-3-ethernet.wake-on-lan magic
sudo ethtool -s enp42s0 wol g
```

Validate waking from suspend and from normal shutdown separately while someone
can reach the physical power button. A successful HTTP wake response means the
packet was sent; only Aeris becoming reachable proves that waking succeeded.
Shutdown and real wake-cycle verification must not interrupt active work.

## API contract

Every request requires `Authorization: Bearer <secret>`. Status and controls
return JSON. POSTs have no body. The relay only supports status and wake.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/v1/status` | Role, server time, shutdown setting, independently timestamped service payloads |
| POST | `/v1/rgb/work\|night\|day\|off\|party` | Existing RGB mode selection |
| POST | `/v1/cooling/default\|quiet\|performance\|firmware` | Existing CoolerControl mode selection |
| POST | `/v1/awake/normal\|system\|full` | Existing desktop sleep policy |
| POST | `/v1/poweroff` | Normal shutdown; also requires `X-Aeris-Confirm: poweroff` and server opt-in |
| POST | `/v1/wake` | Relay only; fixed configured MAC/broadcast, 10-second cooldown |

Each `services.<name>` entry contains `updated_at` and the existing adapter's
`payload`. Metrics use `payload.data`; other adapters report `mode` directly.
The Android UI expires service data after ten seconds and stops polling while
backgrounded. It distinguishes unreachable from known-off, disables unavailable
controls, and confirms shutdown in a dialog. Wake remains usable when the Aeris
API is unreachable.

## Verification and limitations

Rust tests cover authentication, fixed routes, browser-origin/body rejection,
relay isolation, shutdown gates, status freshness metadata, command contention,
and magic-packet content. Android unit tests cover URL/transport restrictions.
Run `cargo test --bin aeris-companion` in `quickshell/aeris-backend`.

Deployment and end-to-end evidence for this checkout is recorded in
`VERIFICATION.md`. Do not infer successful off-site wake from a build or a local
status check. No phone has yet been paired at the time of initial implementation.

References: [Android Compose](https://developer.android.com/compose),
[Tailscale's wake-relay architecture](https://tailscale.com/blog/wake-on-lan-tailscale-upsnap).

## Shared dashboard artwork and status presentation

Android 0.1.2 uses the custom Aeris wordmark in the header and the matching mark
in its adaptive launcher icon. Control icons follow Quickshell's `ThemeIcon.qml`,
including Work/Aeris, Night/moon, Day/sun, Off/slashed bulb, Party/four-point star;
Default/fan, Quiet/wind, Performance/bolt, BIOS/chip; and Normal/moon,
System/coffee, Full/monitor. CPU and GPU use the same processor/card header glyphs.
Android VectorDrawable files preserve the vendored SVG paths and stroke styling;
there is no runtime SVG dependency. Icon licenses are included in the APK.

To re-import after dashboard artwork changes, resolve Android build dependencies
with Gradle, then run `JAVA_HOME=/path/to/jdk-21 python scripts/import-dashboard-icons.py`
from `mobile/`. The script uses Android's SVG importer from the Gradle cache.

Availability is separate from polling activity. The main card shows a steady
“Off” until fresh status is available, then “Online”. This is an availability
label; there is no independent hardware power-state measurement. Background retries do not change the card's label
or height. Connection diagnostics remain available in Connection settings.

The compact mobile layout follows the `mobile-android-design` skill. It keeps
Aeris branding, uses a fixed app bar and accessible icon navigation, removes
redundant state/preset explanations and footer text, and shows action results
in transient Material snackbars. Pairing help and failures stay in Settings.

Version 0.1.4 uses two resource tiles: CPU with RAM, and GPU with VRAM. Each
processor shows utilization and temperature; memory shows utilization and
used/total GiB. Slim mode racks reuse the Quickshell icons, highlight the active
mode, and show its name in the header. Long-press an icon for its label; screen
readers receive named radio-button choices. Touch targets remain at least 48dp.
The complete dashboard fits a 320dp-wide phone at normal text size. Larger
system text stacks the resource tiles and allows scrolling.

Current APK: `/home/drei/Downloads/aeris-companion-0.1.4.apk` (version code 5).
Install over the existing app to retain pairing; the app ID and signer are unchanged.

## Google Drive updates — 0.1.3

The app's Settings → Updates card uses the shared release folder:
https://drive.google.com/drive/folders/1YrDgjdrF_TVoKSSzqK14nAo45tfBIngk

Install 0.1.3 or newer manually once to bootstrap the updater. Thereafter, upload the
versioned APKs to that same public folder without renaming them, then use
Check for updates → Download → Install in Aeris. Files must be named
`aeris-companion-MAJOR.MINOR.PATCH.apk`. Numeric version ordering handles, for
example, 0.1.10 correctly after 0.1.9. No release manifest, API key, Google login,
PC connection, or developer options are required. Android asks once to allow
installs from Aeris and still requires confirmation for each installation.
Phone management policies can independently restrict APK installation.

The folder and its APKs must remain readable by anyone with the link. Only put
shareable release files there; pairing tokens are never uploaded or sent to
Drive. The updater reads Drive's public embedded-folder HTML and handles Google
redirects and download-confirmation forms. This is not the authenticated Drive
API; a future Google markup change may require a manual APK update. Failed or
unrecognized listings do not claim the app is up to date.

Downloads use HTTPS with Google-host restrictions, finite connection/read
limits, an 80 MB APK cap, bounded HTML responses, cancellable foreground work,
and separate temporary files. Before offering installation, the app checks
package identity, increasing Android version code, matching signing certificate,
and filename/package version agreement. It rechecks cached APKs before granting
the Android installer read access through a narrowly scoped FileProvider.
Android performs the final package/signature verification. Updates preserve the
existing Android Keystore pairing; no broad storage permission is requested.
Cached ready updates survive process restarts and obsolete/invalid packages are
removed. Keep using the same signing key and raise both version name/code for
each release. `aerisVersionCode` / `aerisVersionName` Gradle properties support
version-specific test builds; normal builds default to 4 / 0.1.3.

## Pomodoro and workout sets — 0.1.5

The Pomodoro tile controls the existing Tomat daemon through CasaOS. Tap the
routine name to choose a template; while running, a selection applies to the
next fresh run. Play/pause, skip, and confirmed reset share the desktop session.
This iteration requires an active connection to Aeris. The displayed countdown
interpolates fresh daemon readings; it does not start a separate phone timer.

Upper body and Lower body are new, manually selected draft routines based on
`Workout/home_running_rebuild_2026-09.md`. They use three two-set exercise breaks
and editable 25/7/15 timings. They are additional routines; Classic, Deep Work,
and Light Work remain. Wednesday trunk-control alternatives and running are
not automatically scheduled by these two templates. No load is guessed.

During a workout break, use the set buttons beneath the timer. Tap the exercise
to see all of today's sets. Record actual reps, both sides where applicable,
and optional load/reps left. Save, skip and clear are explicit actions. Timer
expiry, phase skipping and timer reset never complete or delete a set. A stale
edit is rejected; Reload saved set explicitly loads the newer result. Repeating
the same submitted request after an uncertain response is idempotent.

Aeris stores daily prescription snapshots and logs separately from timer
selection under `~/.local/state/aeris-pomodoro/workouts/`. App closure and API
restart retain saved progress. The server's local date owns day boundaries.
The first view of each plan each day freezes its prescription; later edits
affect a new day. Prior days remain on disk; the phone currently shows today's
selected plan, not an archive browser. Skipped/missed sets are not carried into
tomorrow automatically. Unsent form entries are not saved workout progress.

The shared desktop adapter reads the same daily log. The compact desktop timer
shows the set count during workout breaks; the full tile replaces its quote
with the next exercise and count. Detailed set entry is currently in the phone.

Transport additions: authenticated `POST /v1/tomat` and `POST /v1/workout/set`
accept only JSON up to 4096 bytes. All existing hardware routes remain body-free.
The gateway forwards only these explicitly named routes, substitutes the
upstream credential, and never retries actions. See the template guide for the
optional structured `workout` fields and daily snapshot rules.

APK: `/home/drei/Downloads/aeris-companion-0.1.5.apk`, code 6. Keep the filename
when uploading to the existing Drive folder; install over the current app.

## Routine selection clarity — 0.1.6

Selecting a routine during a run queues it. The widget now shows `Next: <name>`
with `Switch now`; confirmation ends the current timer and leaves the selected
routine ready to start. Saved workout sets remain intact. The picker marks
Active/Next/Selected, and `Choose workout` opens a workout-only list when the
current timer has no workout. This uses existing select/reset actions; no server
update or pairing change is needed.
