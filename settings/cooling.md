# Aeris PWM cooling — reinstall and recovery

Recorded 2026-09-04: Fedora 44, CoolerControl 4.3.1,
nct6687d-dkms 0.20260901-1.git5997c92.fc44, MSI MAG B550M MORTAR WIFI
(MS-7C94), Ryzen 9 5950X, RX 6900 XT. Default is active. Mode switching,
calibration, and explicit BIOS hand-back were tested. Extended thermal/load
plateau tests and shutdown/stop fallback tests are **not yet certified**.

## What is preserved

The allowlisted [snapshot](../cooling/snapshot/) contains:

- `config.toml`: 19 Aeris profiles plus Unmanaged, three response functions
  plus Identity, startup assignments, device settings, and disabled phantom
  channels. Default has the more generous 40% rear/front intake floor.
- `modes.json`: Default, Quiet, Performance, BIOS / Firmware, original UIDs,
  mode order, and Default as the saved active mode.
- `calibrations.json`: accepted duty/RPM sweeps and effective maxima. The pump
  is not fan-calibrated; it stays fixed at 100% in all three Linux modes.
- `config-ui.json`: recognizable channel/device names and GUI preferences.
  `alerts.json` currently contains no configured alerts.
- `manifest.json`: capture date, target versions, SHA-256 checksums.

No passwords, session cookies, API tokens, TLS private keys, DKMS private keys,
or MOK material are included. Fresh installs generate their own keys and local
authentication. Do not copy all of /etc/coolercontrol or the GUI's
CoolerControl.conf into Git.

## Confirmed physical mapping

| Channel | Header | GUI label / purpose | Fan model |
|---|---|---|---|
| fan1 / pwm1 | CPU_FAN | 5950X — 3 radiator exhausts | Thermalright TL-H12W-X28-S White |
| fan2 / pwm2 | PUMP | GrandVision 360 — circulation | Grand Vision 360 White pump, fixed 100% |
| fan3 / pwm3 | SYS_FAN1 | Rear Intake — 1 external rear intake | TL-H12W-X28-S White |
| fan4 / pwm4 | SYS_FAN2 | Front Intake — 2 front intakes | TL-C12RW-S V2, user shorthand TL-C12RBW V2 |
| fan5 / pwm5 | SYS_FAN3 | GPU Exhaust — 2 pocket exhausts | TL-B4010W, 40 mm |
| fan6–8 | No physical headers | Unused, disabled | None |

The GPU card's own fans remain unmanaged. Radiator/rear intake use CPU Tctl;
GPU-pocket exhaust uses GPU junction. Front intake uses the **maximum of two
separate CPU/GPU demand curves**, not the maximum raw temperature.

Accepted start/sustain duties: radiator 0/4%, rear 40/40%, front 26/35%,
GPU exhaust 24/24%. Effective maxima: radiator/rear 100%, front 95%,
GPU exhaust 45%. Keep these records on unchanged hardware; do not reinterpret
the unusual GPU-exhaust sweep or recalibrate just for a reinstall. Changed
fans, wiring, or motherboard require a fresh mapping/calibration review.

## Reinstall on the same hardware

Run from this repository. Installer/restore writes use **graphical Polkit
password prompts**, not terminal password input. Quit the CoolerControl GUI
before restoring so it cannot overwrite restored preferences.

1. Install the pinned driver and CoolerControl version:

   ```bash
   ./scripts/install-cooling.sh --install
   ```

   Validates the board and Fedora version, checks the driver RPM checksum,
   blacklists nct6683, and loads nct6687 at boot. Leaves CoolerControl disabled.
   If a pinned package is unavailable, stop and review version migration;
   do not silently substitute a different schema.

2. Reboot to load the dedicated driver. Check `mokutil --sb-state`:
   **only if Secure Boot is enabled** is DKMS key enrollment needed. Aeris had
   Secure Boot enabled and an enrolled key at capture. A fresh installation's
   key is different. Use `mokutil --import /var/lib/dkms/mok.pub` as root, then
   complete the firmware's Enroll MOK flow with the temporary enrollment
   password. Firmware interaction is attended and cannot be automated.
   Secure Boot disabled means no MOK enrollment requirement.

3. Perform fresh firmware-only discovery and verify the restore target:

   ```bash
   ./scripts/check-cooling.sh --firmware
   ./scripts/install-cooling.sh --activate
   ./scripts/restore-cooling.sh --check
   ```

   --activate is for an **initial empty configuration only**. It rejects saved
   control assignments before starting the daemon. The restore preflight
   compares CPU/GPU/controller UIDs against fresh discovery. Changed IDs must
   be deliberately remapped across profiles, modes, calibrations, and labels;
   never bypass the check.

4. Restore the saved setup:

   ```bash
   ./scripts/restore-cooling.sh --restore
   ```

   Stops/disables the daemon, requires every channel to return to firmware
   mode 2, backs up the five data files to the printed directory under
   /var/backups/aeris-cooling/restore-*, and installs the snapshot.
   **Leaves the daemon stopped and BIOS controlling fans.** Existing TLS and
   authentication files are untouched. If copying fails, keep the daemon
   stopped and recover the five data files from that backup.

5. Start the restored Default profile (do not use --activate again):

   ```bash
   pkexec systemctl enable --now coolercontrold.service
   ./scripts/check-cooling.sh --runtime
   ```

   Open CoolerControl and authenticate locally to create a fresh GUI session.
   The helper reads that session without storing credentials in the repo:

   ```bash
   ./quickshell/aeris-dashboard/services/coolingctl.py status
   ./scripts/install-dashboard.sh
   ./scripts/run-dashboard.sh ipc prop get dashboard coolingMode
   ```

The runtime audit accepts manual mode 1 for the five controlled headers and
firmware mode 2 for BIOS hand-back; unused channels must remain mode 2.

## Controls and recovery

Icon-only cooling controls: [Default] [Quiet ↔ Performance] [BIOS]. The middle
tile enters Quiet from another mode, then alternates. Selection follows the
daemon; unavailable authentication/daemon disables controls.

The PWM commit includes functional dashboard wiring independently of later
theme/media work. Placement/styling may evolve without changing these calls:

```bash
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode default
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode quiet
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode performance
./scripts/run-dashboard.sh ipc call dashboard setCoolingMode firmware
```

The helper also supports status, watch, and set MODE directly. It uses only
the supported loopback HTTPS API, never sysfs duty writes or its own curves.
Closing the GUI does not stop daemon fan control.

BIOS / Firmware deliberately has no motherboard channel assignments:
activation returns all five headers to firmware mode 2; Default restores
profile/manual mode 1. BIOS curves themselves are **not exported or changed**
by this backup. If BIOS is reset too, reconfigure its known-safe fallback
curves separately before relying on this setup.

To undo a data restore, stop the daemon and recover the five files from the
printed backup, then start only after reviewing ownership. Never restore
old authentication/signing material from Git.

Optional popup preference: KDE Notifications → Application Settings →
CoolerControl → turn off Show popups. This suppresses **all** CoolerControl
popups, including warnings; keep history enabled. No desktop/window-manager
configuration is changed by the cooling scripts.

## Validate before committing/updating

```bash
python3 scripts/validate-cooling.py
python3 -m unittest discover -s tests -p 'test_cooling*.py'
bash -n scripts/install-cooling.sh scripts/check-cooling.sh scripts/restore-cooling.sh
./scripts/restore-cooling.sh --check
```

Snapshot data is captured exactly from allowlisted live files, with JSON
formatting normalized. Update the manifest checksums when deliberately
recapturing data. Do not run a restore on the working machine just to test
backup packaging.
