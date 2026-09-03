# CPU efficiency tuning

The Ryzen 9 5950X efficiency profile is a manual BIOS setting. It is documented
here rather than automated so boost behavior remains under AMD Precision Boost
Overdrive and recovery does not depend on an operating system utility.

## Primary profile

In the MSI firmware, set Precision Boost Overdrive to Advanced/Manual and use:

```text
PPT: 120 W
TDC: 80 A
EDC: 120 A
Curve Optimizer: All Cores, Negative, 10
Boost Clock Override: 0 MHz
Scalar: Auto / 1X
```

Do not set fixed clocks. Do not advance beyond Negative 10 until this profile
passes the validation below and normal mixed use without WHEA/MCE errors.

## Validation

After booting Fedora, capture telemetry in one terminal:

```bash
./scripts/capture-power-state.sh --duration 660 --output cpu-pbo-120w-co-n10.csv
```

Then run in a second terminal:

```bash
stress-ng --cpu 32 --metrics-brief --timeout 10m
sudo journalctl -k -b | grep -iE 'mce|hardware error|edac|error|fail'
```

The broad journal filter can include unrelated messages. Review the timestamp
and subsystem before treating a match as a CPU stability failure. Record the
result in `efficiency-baseline.md`.

If Negative 10 is fully stable, Negative 15 may be tested as a separate profile.
Return to Negative 10 at the first error, crash, freeze, or reboot. Per-core
optimization is out of scope for the first milestone.

## Optional quiet profile

Only after the primary profile is stable:

```text
PPT: 88 W
TDC: 60 A
EDC: 90 A
Curve Optimizer: retain only the proven-stable value
```

## Rollback

Set Curve Optimizer and PBO limits back to `Auto`. If the machine cannot boot
reliably, use the motherboard's documented CMOS-clear procedure and reapply only
known-good firmware settings.
