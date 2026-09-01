# Fedora settings

Version-controlled notes for Drei's Fedora KDE workstation.

This repository records intentional system and desktop choices without copying
entire configuration directories. Full KDE configuration files can contain
unrelated personal state, hardware identifiers, and application data.

## Current machine

- Fedora Linux 44, KDE Plasma 6.6
- 3840×2160 primary display at 100% scale
- Samsung 990 PRO 1 TB: Fedora system disk
- Lexar NM620 512 GB: reserved for Hackintosh experiments
- Seagate 4 TB: Btrfs bulk storage mounted at `/mnt/storage`

## Recorded settings

- [Desktop and tiling](settings/desktop.md)
- [Storage](settings/storage.md)
- [Git and GitHub](settings/git.md)
- [KWin tile geometry](settings/kwin-tiles.json)
- [Aeris OpenRGB lighting](settings/rgb.md)

## Restore

Apply the desktop profile from an active KDE Plasma session:

```bash
./scripts/apply-desktop.sh
```

The script requires one 3840×2160 display at 100% scale. It backs up the
existing cursor, KWin, and Plasma panel configuration before changing anything.
It then restores the cursor, split docks, dock-safe six-tile layout, and gutters.

Restore the Git commit identity separately:

```bash
./scripts/apply-git.sh
```

Inspect the live desktop configuration with:

```bash
./scripts/verify-desktop.sh
```

Storage formatting is intentionally not automated because it is destructive.

Restore or synchronize the Aeris/OpenRGB service separately:

```bash
./scripts/install-openrgb.sh
```

Use `./scripts/install-openrgb.sh --check` for a read-only comparison against the
running installation.

Authentication tokens, browser state, drive serial numbers, and other secrets
must not be committed.
