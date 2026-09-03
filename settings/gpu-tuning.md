# GPU efficiency tuning

Hardware: ASUS TUF RX 6900 XT OC in Performance BIOS mode, using the in-kernel
`amdgpu` driver.

## Observed stock control range

On 2026-09-01, sysfs reported:

```text
default power cap: 272 W
minimum power cap: 231 W
maximum power cap: 272 W
amdgpu ppfeaturemask: 0xfff7bfff
```

The first power-cap profile must therefore use **231 W** (the hardware/driver
minimum) or 240 W. A requested 230 W cap is not exposed by this card.

## Install and verify LACT

LACT's upstream Fedora instructions recommend its COPR package. Install it and
start the daemon:

```bash
sudo dnf copr enable ilyaz/LACT
sudo dnf install lact
sudo systemctl enable --now lactd
lact cli list-gpus
lact cli info
```

Confirm that the output identifies the RX 6900 XT and that the GUI shows the
272 W default and 231-272 W power-cap range. Do not apply a tuning profile yet.

Voltage/clock overdrive is currently not exposed in sysfs. Use LACT's
**Enable Overclocking** action; upstream documents that this writes the required
`amdgpu` module setting and regenerates initramfs on standard Fedora. Reboot,
then verify the controls in LACT. Prefer this supported action over manually
forcing `amdgpu.ppfeaturemask=0xffffffff`.

## Stage A: power cap only

After collecting a stock full-load baseline, create a LACT profile with:

```text
Power cap: 231 W (preferred first test) or 240 W
Voltage: stock
Core clock: stock/default
VRAM clock: stock/default
Fan control: firmware/default
```

Apply and confirm it in LACT. LACT's confirmation timer automatically reverts an
unconfirmed change. Run at least one suitable synthetic workload and one real
game/application workload for 10-15 minutes each. `vkmark` is supplemental only;
the existing two-minute run drew about 68 W and did not approach full load.

Do not begin undervolting in the first milestone. Once Stage A is proven stable,
test 1100 mV separately, followed by 1075 mV and 1050 mV only in 25 mV steps.

## Persistence and rollback

LACT stores the active machine configuration in `/etc/lact/config.yaml` and
reloads settings after resume. Record the human-readable settings and results in
this repository; do not commit the live config because its GPU ID contains the
PCI slot and subsystem identifiers.

To roll back a profile, restore stock/default controls in LACT and confirm the
change. If the GUI is inaccessible after a bad setting, disable `lactd` from a
text console or recovery boot and follow LACT's recovery procedure. Disable
overclocking from LACT's dropdown to remove the module setting it created, then
reboot. Removing LACT itself is optional:

```bash
sudo systemctl disable --now lactd
sudo dnf remove lact
sudo dnf copr remove ilyaz/LACT
```

References:

- <https://github.com/ilya-zlobintsev/LACT#installation>
- <https://github.com/ilya-zlobintsev/LACT/wiki/Overclocking-(AMD)>
- <https://github.com/ilya-zlobintsev/LACT/wiki/Recovering-from-a-bad-overclock>
