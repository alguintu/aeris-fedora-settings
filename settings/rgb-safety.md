# OpenRGB hardware-safety policy

Last reviewed: 2026-09-03

This policy is a hard gate for Aeris, not a troubleshooting suggestion. OpenRGB
itself warns that it talks to hardware through reverse-engineered protocols and
that hardware has previously been damaged or bricked. The project says affected
code was disabled or fixed, but cannot guarantee that the problem will not
recur. See the [upstream warning](https://gitlab.com/CalcProgrammer1/OpenRGB/-/blob/master/README.md).

## Current Aeris state

- `aeris-openrgb.service` and `aeris-openrgb-server.service` are disabled and
  inactive.
- The installed Fedora package is
  `openrgb-1.0~rc2-3.20260126git74cbdcc.fc44.x86_64` and is **not approved**.
- OpenRGB's maintainer says invalid ENE-controller SMBus writes were fixed only
  in 1.0rc3. Aeris must use an audited 1.0rc3.1-or-newer package before any
  further hardware access. See [issue #3821](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/3821)
  and the [1.0rc3.1 release](https://gitlab.com/CalcProgrammer1/OpenRGB/-/releases).
- The runtime approval file is deliberately empty. The SDK server cannot start
  until it contains an exact, audited RPM package identity.
- All OpenRGB hardware detectors in the live configuration are quarantined.
- The recovered MSI controller is `MS-7C94`, USB VID:PID `1462:7c94`, current
  serial `A02021090806`. Its firmware was recovered with MSI's signed
  `SUtility_7C94_v06.exe` / `MSI_MB_7C94_v0006.bin`.
- A manually authorized, one-time firmware-idle save was completed on
  2026-09-03 with the exact upstream 1.0rc3.1 commit `5e81e26f`. Only the MSI
  board and ASUS GPU detectors were enabled; ENE RAM was neither detected nor
  written. The saved state is JRAINBOW1 static `#007878`, JRAINBOW2 static
  `#005332`, ASUS GPU static `#007878`, and the pre-existing RAM red Chase Fade.
  The temporary writer was not installed and this exception is permanently
  closed.

## What has actually been reported

These categories distinguish confirmed upstream warnings from individual field
reports. A report is evidence of a hazard, not proof that every device in the
family will fail.

| Risk class | Evidence | Aeris decision |
|---|---|---|
| MSI Mystic Light motherboard controllers | OpenRGB's MSI detector source carries a specific historical bricking warning and keeps untested boards behind a compile-time opt-in. Earlier MSI support was disabled because it bricked boards. See the [detector warning](https://gitlab.com/CalcProgrammer1/OpenRGB/-/blob/master/Controllers/MSIMotherboardController/MSIMotherboardControllerDetect.cpp) and [issue #430](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/430). | Treat every MSI mode/configuration write as high risk even though `MS-7C94` is in the supported list. |
| MSI mode/effect changes | On X570 Gaming Pro Carbon/ACE boards, selecting an effect produced red flicker, I/O errors, disappearance of the Mystic Light USB device, and hardware-programmer recovery. See [issue #389](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/389). | Direct mode only. No firmware effects, experiments, or mode cycling. |
| MSI suspend/resume | An X570 Unify report links setting colors followed by standby/wake to broken LED firmware, loss of lighting, `00` debug display, and fan-curve failure until MSI reflashed the LED firmware. See [issue #1523](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/1523). | Stop OpenRGB before suspend. Never issue a post-resume write on an old connection. |
| MSI profile replay | An MSI B450 report says loading an old all-black profile caused yellow headers, loss of OpenRGB control, and a malfunctioning USB hub. See [issue #4092](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/4092). | Never load `.orp` or legacy `sizes.ors` data made by another OpenRGB version or controller firmware. |
| ENE SMBus DRAM, especially DDR5 | OpenRGB's DDR5 meta-thread collects repeated detection/rescan/sleep failures, missing SPD data, warm-boot failures, and worst-case SPD corruption that prevents boot. The maintainer later attributed the fixed case to invalid ENE SMBus writes. See [issues #4934](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/4934) and [#3821](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/3821). | No ENE access on rc2. Broad SMBus probing and repeated detection are forbidden on every memory generation. |
| ENE RGB controllers on DDR4 RAM | Multiple G.Skill Trident Z users reported one RGB controller becoming permanently dark after OpenRGB, including after cold power and DIMM reseating. See [issue #2367](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/2367). | Aeris's PNY DDR4 is not proven affected, but it uses the same generic ENE path and remains high risk. Never use Save to Device. |
| Zalman Z Sync ARGB hub, especially firmware 0.7.1 | The OpenRGB owner reported lockups while changing modes and a bricked recovery attempt; later guidance warned 0.7.1 users to stay in Direct mode. See [issue #628](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/628). | Never attach one to Aeris automation without a separate audit; Direct mode only if ever approved. |
| Sinowealth/Redragon-family keyboards | Upstream disables a detector because reused VID/PID pairs caused commands for one protocol to brick different Redragon keyboards. See the [current detector source](https://gitlab.com/CalcProgrammer1/OpenRGB/-/blob/master/Controllers/SinowealthController/SinowealthControllerDetect.cpp) and [issue #3365](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/3365). | Never enable a disabled/untested detector merely because a VID/PID appears to match. |
| Gigabyte RGB Fusion motherboard paths | Reports include reversed calibration and, on Z690, reboot-triggered boot failure/BIOS reset after OpenRGB access. See [issues #610](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/610) and [#2276](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/2276). | Treat low-level motherboard SMBus access as high risk across vendors, not as an MSI-only problem. |
| ASUS Aura and Corsair Commander | Reports describe an Aura controller becoming uncontrollable after reboot and a Commander making fans run incorrectly or disappear from its software. These are serious loss-of-control reports, but not confirmed permanent bricks. See [issues #4793](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/4793) and [#304](https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/304). | Keep detection allowlisted and never run competing hardware-control applications. RGB access must not be allowed to disturb cooling control. |

OpenRGB's own [SMBus documentation](https://gitlab.com/CalcProgrammer1/OpenRGB/-/blob/master/Documentation/SMBusAccess.md)
describes SMBus as a low-level interface used by all RGB DDR4/DDR5 modules and
some motherboards. Its CLI also warns that invalid I2C/SMBus transactions can
brick a motherboard, RGB controller, or RAM. This is why “just detecting” a
device is not assumed read-only.

## Non-negotiable Aeris rules

1. **No further persistent device writes.** Never call SDK `SaveMode`, Python
   `save_mode()`, `set_mode(..., save=True)`, “Save to Device,” firmware-update,
   calibration-save, or equivalent hardware-persistence paths. The SDK defines
   `SaveMode` as saving the current mode to the device; see the
   [SDK/API documentation](https://gitlab.com/CalcProgrammer1/OpenRGB/-/blob/master/Documentation/RGBControllerAPI.md).
   The completed 2026-09-03 idle save above was a single user-authorized
   exception, not a reusable procedure or permission for another save.
2. **No shutdown, boot, suspend, or resume handoff.** Shutdown only stops the
   processes. It sends no last color, mode, profile, firmware, or autonomous
   effect. BIOS-visible lighting is not an Aeris requirement.
3. **Direct mode only.** Never select an MSI or ENE hardware effect. Switching
   to Direct is allowed once per audited process start and only if the device is
   not already in Direct mode.
4. **No broad detection or rescans.** The OpenRGB detector configuration must be
   either fully quarantined or restricted to exactly:
   `MSI Mystic Light MS_7C94`, `ENE SMBus DRAM`, and
   `ASUS TUF Radeon RX 6900 XT Gaming OC`. No GUI Rescan button and no repeated
   OpenRGB process launches.
5. **No untested controller flags.** Never compile with
   `ENABLE_UNTESTED_MYSTIC_LIGHT`, uncomment a disabled detector, add a guessed
   VID/PID, or guess an MSI report/packet size.
6. **No raw bus experiments.** Never use OpenRGB's I2C Tools page, raw `i2cset`,
   write-capable SPD tools, or `acpi_enforce_resources=lax` for this lighting
   stack. `i2cdetect` scans are also excluded from routine checks.
7. **No cross-version hardware profiles.** Do not replay old `.orp`,
   `sizes.ors`, or another machine's configuration. Rebuild only the two 75-LED
   zone sizes under the approved OpenRGB build, then verify the result before
   any animation starts.
8. **One owner only.** Never run OpenRGB GUI, another OpenRGB instance, MSI
   Center/Mystic Light, Armoury Crate/Aura, SignalRGB, vendor RGB services, or
   another SMBus monitor concurrently with the Aeris server.
9. **Fail closed on the first anomaly.** A missing device, unexpected device,
   identity mismatch, wrong zone count, HID/SMBus error, timeout, disconnect, or
   partial update terminates the daemon. There are no automatic reconnects,
   rescans, or systemd restarts.
10. **Pin the exact hardware and software identity.** The daemon requires six
    devices exactly: one named/serialized MSI board, four exact `ENE DRAM`
    devices, one exact ASUS GPU, and exactly `JRGB1=1`, `JRAINBOW1=75`, and
    `JRAINBOW2=75`. The SDK server requires an exact approved RPM NEVRA.
11. **Minimize traffic.** Do not write unchanged frames. SMBus accent updates
    remain slower than motherboard HID updates. Any future increase in update
    frequency requires a fresh hardware-risk review, not only a visual test.
12. **A lighting failure never triggers persistence or recovery automation.**
    Stop, collect logs, verify USB/HID enumeration without OpenRGB, and decide
    the next step manually. Firmware recovery uses only the exact signed MSI
    package for `7C94`.

## Reactivation gate

All of these must be completed in order. A later failure returns the system to
full quarantine.

1. Install a packaged OpenRGB 1.0rc3.1-or-newer build and record its exact RPM
   identity and source commit. Do not use an arbitrary pipeline/master build.
2. Review changes in the MSI 185-byte controller and every ENE SMBus path since
   the approved source baseline.
3. Start the new binary once with `--nodetect --noautoconnect` solely to generate
   its configuration schema. Do not let it scan.
4. Run `configure-openrgb-detectors.py --quarantine`, inspect the resulting JSON,
   then run `--allow-aeris`. If the expected detector names are absent, stop.
5. Recreate the 75/75 zone configuration under that exact version. Do not copy
   the rc2 `sizes.ors` file.
6. Put the exact `rpm -q openrgb` output in `openrgb/approved-runtime.txt` and
   deploy it. Confirm `check-openrgb-safety.sh` passes.
7. Perform one controlled enumeration. Require the exact six-device and
   three-zone inventory before the daemon sends any command.
8. Apply Direct mode and one low-rate static canary frame. Observe all devices,
   stop cleanly, cold boot once, and confirm controller enumeration again.
9. Run a brief workload transition with logs visible. Any error is a permanent
   stop until reviewed.
10. Only after those checks, explicitly enable the user service. Installation
    itself never enables or starts it.

## Recovery trigger

Immediately stop both services and do not relaunch OpenRGB if any one of these
occurs: unexplained blink/off state, one missing DIMM, failed warm boot, MSI
controller absent from USB/HID, unexpected device count, bus error, server
disconnect, GUI crash during detection, or cooling/fan behavior changing. Do
not “try again” to see whether the failure repeats.
