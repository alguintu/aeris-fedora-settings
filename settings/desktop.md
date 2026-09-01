# Desktop and tiling

## Cursor

- Theme: Breeze
- Configured size: 36 px

Open the cursor settings page with:

```bash
kcmshell6 kcm_cursortheme
```

## Plasma panels

Two independent floating panels occupy the bottom 62-pixel band:

1. Center panel, 46 px high
   - Application Launcher
   - Pager
   - Icons-only Task Manager
2. Right panel, 46 px high
   - System Tray
   - Digital Clock
   - Show Desktop

Both panels are always visible, use fit-content length, and remain floating.

## KWin custom tiles

The usable tile area is 3840×2098, leaving pixels 2098–2159 for the panels.

- Columns: 960 px, 1920 px, 960 px
- Rows: 1049 px, 1049 px
- Six total tiles
- Gutter/padding: 8 px
- Placement: hold `Shift` while dragging a window
- Editor: `Meta+T`

The layout uses independent floating KWin tiles so the bottom panel band remains
outside every tile. The normalized geometry is stored in `kwin-tiles.json`.

## Automated restoration

Run `scripts/apply-desktop.sh` from an active Plasma session. It validates the
expected display geometry and saves timestamped backups under
`~/.local/state/fedora-settings/backups/` before applying the profile.
