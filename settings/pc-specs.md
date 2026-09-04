# PC specs page — first content pass

The leftmost dashboard page is a curated **2026-09-04 build snapshot**, not live
telemetry. Values live together in `SpecsPage.qml` for easy layout changes.
Recheck after hardware, OS, or firmware upgrades.

Read-only checks: `lscpu`, `lspci`, `lsblk`, `/proc/meminfo`, DRM VRAM size, DMI
board/BIOS strings, `/etc/os-release`, `uname -r`, and `plasmashell --version`.
No serial numbers, UUIDs, account names, or network identifiers are displayed.

- CPU: Ryzen 9 5950X, 16 cores/32 threads, two L3-sharing groups, 64 MiB L3.
- GPU: RX 6900 XT, 16 GB VRAM. Exact ASUS TUF Gaming OC branding is corroborated
  by the audited inventory in `settings/rgb.md`; the existing dashboard hardware
  model uses 80 compute units, not per-unit telemetry.
- RAM: 64 GB DDR4, 4 × 16 GB, recorded 3200 MT/s. Capacity agrees with the live
  OS reading (~62.7 GiB usable). Module count/type/speed come from the Obsidian
  build inventory; current speed was not re-read because privileged DMI access
  was unavailable. The tile explicitly labels speed as recorded.
- Board: MSI MAG B550M MORTAR WIFI (MS-7C94), BIOS 1.O1, AM4.
- Storage: five detected drives, including the unmounted Lexar NM620 512 GB.
  The others are Samsung 990 PRO 1 TB, Samsung 860 EVO 1 TB, Seagate BarraCuda
  500 GB, and Seagate IronWolf 4 TB. Capacities use drive marketing units.
  Unlike Idle's storage tile, this lists installed rather than only mounted drives.
- System: Fedora Linux 44, KDE Plasma 6.7.4, Linux 7.1.12-200.fc44.x86_64.
- Chassis: DeepCool CH260; Thermalright Grand Vision 360 White AIO; MSI MAG
  A850GL PCIE5 850 W PSU, recorded in the final-build inventory. The AIO is
  additionally corroborated by the newer PWM/cooling note.
- Fans: eight chassis/radiator fans across four physical control zones:
  3× TL-H12W-X28-S radiator exhausts, 1× TL-H12W-X28-S rear intake,
  2× TL-C12RW-S V2 front intakes, and 2× TL-B4010W GPU-pocket exhausts.
  This count excludes the separate AIO pump and the GPU card's own fans.
- RGB: two JRAINBOW ARGB chains (accents and fans), four ENE RAM devices, and
  ASUS GPU lighting. These are software-controlled by the existing OpenRGB
  runtime; fan curves remain under CoolerControl. Configured LED slots are not
  presented as a physical LED count.

The first layout now uses four columns and two equal-height rows beside the
brand tile. Font sizes, 18 px tile margins, and 12 px gutters are unchanged.

Obsidian cross-check: `Workstation/Imported-2026-08-28/final-build-specs-and-values.md`
(Aeris table), `workstation-inventory.md` (historical RAM detail), and
`Aeris/PWM and Cooling Control.md` (current CPU/GPU/board). Historical storage
assignments and the older 3900X/RX 580 platform are not carried into this page.
