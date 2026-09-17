# Initial companion verification — 2026-09-11

## Built and tested

- Native Kotlin / Compose debug APK: `app/build/outputs/apk/debug/app-debug.apk`
  (11,722,231 bytes at this verification).
- `:app:assembleDebug`, `:app:testDebugUnitTest`, `:app:lintDebug`: passed.
  Two URL/transport tests passed. Lint: zero errors, eight non-blocking warnings
  (pinned dependency updates and configuration/style suggestions).
- Full Rust `cargo test`: 55 tests passed, including seven companion tests.
- Rust release binary built and installed by `scripts/install-companion.sh`.
- Installer shell syntax and generated systemd unit verification passed.

## Live Aeris checks

- User service is enabled and active at `127.0.0.1:4280`.
- Authenticated status returned fresh metrics, RGB `work`, cooling `default`,
  and Awake `full`.
- Unauthenticated status returned HTTP 401.
- `login1.CanPowerOff` returned `yes`; no shutdown was executed.
- Existing Quickshell and OpenRGB services remained active.

## Android emulator checks

Tested on API 36 using a read-only emulator instance and the debug-only
`http://10.0.2.2:4280` connection to the real Aeris API. Pairing was entered
through the UI and encrypted by Android Keystore. Updating/relaunching the APK
preserved pairing.

- Live CPU/GPU utilization, temperatures, memory/VRAM capacity, and current
  lighting/cooling/Awake modes rendered successfully.
- Tapping the already-selected Default cooling mode returned “Mode applied”
  and confirmed `DEFAULT`. No new fan curve or mode transition was tested.
- Stopping only the companion API caused all three mode panels to show
  `UNAVAILABLE`. Restarting it recovered the connection and live readings.
- Wake remains disabled without a configured relay.
- Dashboard and control screenshots were visually inspected after correcting
  text/system-bar contrast and telemetry field names.

Screenshots: [Dashboard](evidence/dashboard-live.png),
[Controls](evidence/controls-live.png). These contain live readings, not fixtures.
The emulator's SwiftShader configurations crashed before app startup; host
graphics with Vulkan disabled successfully ran the verification. The test
emulator was shut down afterward without saving its temporary state.

## Initial outstanding items (superseded by follow-ups below)

- No physical Android phone is paired.
- Tailscale is not installed/configured on Aeris by this task.
- CasaOS host details/access have not been provided; its relay is not deployed.
- Firmware/NIC Wake-on-LAN support, wake from suspend, wake from shutdown,
  and an outside-the-house connection remain unverified.
- The shutdown route is implemented and gated, but actual shutdown is untested.
- API startup before desktop login is not implemented.
- This APK is debug signed; durable release signing remains to be configured.

The first local implementation is usable in the emulator; this is not a claim
that the complete remote power cycle works yet.


## CasaOS gateway deployment — 2026-09-11

Deployed the standalone Rust gateway in `gateway/`, separate control/wake tokens,
restricted reverse SSH tunnel, and private Tailscale Serve on CasaOS ports 443
and 8443. No Tailscale installation on Aeris and no Funnel. See
`gateway/README.md` for exact boundaries and verification. Seven gateway tests
and clippy passed. Verified live status and same-active cooling profile, normal
HTTPS certificate validation, rejected credentials/origins/routes/unconfirmed
shutdown, loopback binding, tunnel restrictions, and outage/recovery. Actual
shutdown, firmware/NIC wake capability, physical phone pairing, and off-site
wake remain unverified.

Wake follow-up: exact LAN packet and cooldown verified while Aeris remained
awake. NetworkManager `LAN` WoL is now `magic`; successful device reapply changed
PCI `power/wakeup` from disabled to enabled without reconnecting. Physical
power-cycle and BIOS behavior remain untested.

## Android connection-state fix — 0.1.1, 2026-09-11

Drei confirmed physical phone connectivity, then reported the connected/offline
title alternating every two seconds. A successful response could arrive after
the UI's last clock tick; the negative computed age incorrectly invalidated
both the connection and service readings.

- Use monotonic elapsed time and publish payload/receipt as one snapshot.
  A receipt ahead of the UI tick has age zero, so a fresh response stays fresh.
- Keep the last good snapshot through transport/HTTP 5xx retries, with an
  explicit retrying label. Failed polls never extend the ten-second expiry.
  Authentication/configuration failures still invalidate the snapshot.
- Preserve readings during mode changes, then refresh confirmed state.
  An accepted shutdown still invalidates the snapshot.
- Preserve individual service timestamps; a fresh HTTP response cannot revive
  stale telemetry or mode data.
- Version code 2 / version 0.1.1, same app identity, Keystore alias and signer.
  Update APK: `/home/drei/Downloads/aeris-companion-0.1.1.apk`.

Build, six unit tests (including four timing regressions), and lint passed.
Lint: zero errors, eight existing configuration/dependency/style warnings.
API 36 emulator with a temporary loopback test proxy forwarding real telemetry:
ten successive UI observations stayed connected; injected 503 retained readings
and disclosed retries; a sustained outage expired the title and telemetry;
recovery reconnected automatically; injected 401 invalidated state immediately.
Reinstalling the APK preserved encrypted pairing and reconnected. Screenshot:
[0.1.1 dashboard](evidence/dashboard-0.1.1.png).
The test proxy accepted no physical power or mode changes. Phone verification
of this updated APK and off-site/power-cycle tests remain pending.

## Mobile design and steady offline state — 0.1.2, 2026-09-13

Drei confirmed 0.1.1 is stable when connected and that the phone controls work.
The remaining offline flicker came from presenting each polling request as a
connection-state transition. The dashboard now derives its single “Off” or
“Online” label only from snapshot freshness. Polling has no visible in-flight
state. Error details appear in Connection settings; the same ten-second expiry
and authentication rejection behavior remain.

Applied the `mobile-android-design` skill (wshobson/agents) and its Compose /
Material 3 guidance while preserving Aeris branding. Imported the actual custom
wordmark/mark and Quickshell Feather/MDI icons as Android vectors, including an
adaptive launcher icon. Packaged their licenses. Removed subtitle/footer text,
repeated mode/status labels, preset explanations, and telemetry waiting text.
Added a fixed app bar, accessible icon navigation, system Back handling, and
transient action snackbars. Power actions wrap on narrow screens.

`:app:assembleDebug`, six unit tests, and lint passed (zero errors, eight existing
warnings). The API 36 emulator upgraded from 0.1.1 with encrypted pairing intact.
A temporary loopback fixture injected repeated 503 responses: ten offline UI
observations had no connecting/retrying/error-text flicker. Restoring live Aeris
telemetry recovered automatically. No physical control or shutdown commands were
sent during this verification. Screenshots: [dashboard](evidence/dashboard-0.1.2.png),
[controls](evidence/controls-0.1.2.png), [offline](evidence/offline-0.1.2.png).

Version code 3; update APK `/home/drei/Downloads/aeris-companion-0.1.2.apk`.
Install over the existing app. Physical-phone review of 0.1.2 remains pending.

Also visually checked the compact 320dp layout and adaptive launcher artwork.
Connection opens through its accessible icon and Android Back returns to the
dashboard. The design skill is installed locally for subsequent mobile work.

## Drive updater — 0.1.3, 2026-09-13

- Production APK: `/home/drei/Downloads/aeris-companion-0.1.3.apk`; version code 4.
- Build, 17 JVM tests, and lint passed (zero errors, nine warnings).
- Read the actual user-provided Drive folder anonymously from both the host
  and the API 36 emulator. Its valid public listing was empty; the app correctly
  displayed “No releases yet”. There was no live APK in that folder to download.
- Unit tests cover numeric release ordering, resource keys, wrong-host links,
  URL credentials, TLS/redirect restrictions, confirmation forms, interrupted /
  oversized transfers, HTML instead of APK bytes, package identity, rollback,
  and signer mismatches. Network transfer tests use controlled HTTP fixtures.
- Emulator used an updater build with version code 3 to test real APK handling.
  Injected cached same-version and wrong-signer APKs were rejected and deleted.
  The normal version-code-4 APK was accepted, and the app opened Android's
  “Allow from this source” settings followed by the system update confirmation.
  Approved installation through Android's UI; package manager then reported
  0.1.3 / code 4. Opened the updated app and verified encrypted pairing restored.
  No developer-options action was part of the in-app installation flow; ADB was
  used only to prepare and inspect the emulator fixtures.
- The final deliverable was rebuilt with default production version metadata,
  not the lower-version test override. No test key or fixture APK is shipped.
- Screenshots: [updates](evidence/updates-0.1.3.png),
  [ready update](evidence/update-ready-0.1.3.png),
  [Android installer](evidence/update-installer-0.1.3.png).

Still pending: first real APK download from the user's currently empty Drive
folder, and physical-phone confirmation. User must manually install 0.1.3 once;
subsequent uploads keep their supplied versioned filenames.


## Compact tiles — 0.1.4, 2026-09-13

- Version code 5; same application ID and signing certificate as 0.1.3.
- CPU/RAM and GPU/VRAM tiles include processor utilization/temperature and
  memory utilization/capacity. Compact power row and three icon mode racks.
- Build, all 17 existing unit tests, and lint pass (0 errors / 9 warnings).
- API 36 emulator upgraded from 0.1.3 with encrypted pairing intact.
- Isolated loopback fixture verified all 12 preset buttons dispatch their exact
  routes and update selections. No real fan, lighting, Awake, or power actions
  were executed. Canceling the shutdown dialog dispatched no command.
- At 320dp width all mode choices remain visible with at least 48dp targets.
  100% utilization / 100°C and missing-sensor cases were visually inspected.
- Repeated fixture 503s expire into stable Off with disabled mode controls;
  successful status restores Online. No loading/retry text was introduced.
- At 1.5x system font size, resource tiles stack, both power actions remain
  available, and scrolling reaches Awake.
- Final APK: `/home/drei/Downloads/aeris-companion-0.1.4.apk`.

Screenshots use explicit simulated telemetry, not live measurements:
[Dashboard](evidence/tiles-0.1.4.png),
[320dp](evidence/tiles-narrow-0.1.4.png),
[Maximum values](evidence/tiles-max-0.1.4.png),
[Missing sensors](evidence/tiles-missing-0.1.4.png),
[Offline](evidence/tiles-offline-0.1.4.png),
[Large text](evidence/tiles-large-text-0.1.4.png).


## Connected Pomodoro and workout logs — 0.1.5, 2026-09-13

- Android code 6, same app ID/signing identity; upgraded from paired 0.1.4.
- 19 Android unit tests pass; lint reports no errors. Countdown and actual-set
  validation tests added. Narrow-screen keyboard overlap was found visually
  and corrected with IME-aware dialog layout.
- Rust backend suite passes, including four new workout persistence tests.
  Strict Clippy is blocked by an existing `collapsible_if` in `src/fdm.rs:291`;
  the suite passes with that lint allowed. No unrelated FDM behavior changed.
- Eight gateway tests and strict gateway Clippy pass. ARM64 musl build deployed
  on CasaOS. Build emitted Zig's known linker message; executable is verified
  running and serves private HTTPS successfully.
- Real-daemon end-to-end test: `AERIS_TEST_TOMAT=~/.local/bin/tomat python3 -m
  unittest discover -s tests -p test_companion_pomodoro.py`. Uses isolated socket,
  selection, template and log directories and a separate loopback API port.
  Checks revision rejection, start/pause/resume/skip/reset, explicit set save,
  idempotent retry, stale conflict, desktop visibility and API restart.
- API 36 emulator against isolated real Tomat/API: selected Upper body,
  started/paused/resumed/skipped, logged test sets, rejected a missing side,
  and restored progress after app force-stop/reopen. Test logs were confined
  to temporary files and did not become real workout records.
- Forced outage of only the isolated API verified stable Off/Offline labels,
  disabled timer buttons, retained read-only workout progress and automatic
  reconnection. No real service was stopped for that outage test.
- 21 existing QML presentation tests pass, with a new compact set-count
  assertion. Full and compact workout text inspected in a 1920×480 software
  render; software rendering omits some decorative/icon layers.
- API, shared desktop backend and CasaOS gateway deployed. Live Tomat phase
  and revision compared before/after deployment and remained unchanged. Five
  valid routines available through private HTTPS; invalid action rejection
  verified through the gateway without executing a timer command.
- Local binary rollback copies: `~/.local/share/aeris-companion/backups/0.1.4/`.

Evidence in `mobile/evidence/`: `pomodoro-idle-0.1.5.png`,
`pomodoro-break-0.1.5.png`, `workout-day-0.1.5.png`,
`workout-keyboard-0.1.5.png`, `workout-per-side-0.1.5.png`,
`pomodoro-narrow-0.1.5.png`, and `desktop-workout-0.1.5.png`.
Timer and workout data in these screenshots are isolated test sessions.

## Routine selection clarity — 0.1.6, 2026-09-13

Reproduced reported state by read-only live inspection: active Classic paused
on break, selected Lower body, no template errors. New UI displays queued
selection, provides confirmed Switch now, and a workout-only picker.

- Android build, 19 unit tests, lint: 0 errors, 9 existing warnings.
- Isolated real Tomat + API on 4289 and read-only Android emulator: Classic
  active / Lower queued visible; workout picker contains Upper and Lower;
  selecting Upper updates queued label; confirmed switch yields Ready with
  floor press visible; opening workout exposes set buttons.
- No commands sent to the live timer during verification.
- Signing certificate matches 0.1.5; version code 7, APK copied to Downloads.
- Screenshots: pomodoro-queued-0.1.6.png, workout-picker-0.1.6.png,
  routine-switch-0.1.6.png, workout-ready-0.1.6.png in mobile/evidence.
