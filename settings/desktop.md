# Desktop and KZones

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

Both panels use fit-content length and the `WindowsGoBelow` visibility mode.
That mode keeps their floating appearance when a window reaches the bottom of
the screen and does not reserve a work-area strut. The KZones geometry therefore
reserves the bottom 62 pixels explicitly.

## KZones

This profile uses KZones 0.9.2 and requires it to be installed from:

`System Settings → Window Management → KWin Scripts → Get New… → KZones`

The usable zone area is 3840×2098, leaving pixels 2098–2159 for the panels.

- Base columns: 960 px, 1920 px, 960 px
- Base rows: 1049 px, 1049 px
- Six base zones
- Four explicit overlapping span zones
- Gutter/padding: 8 px
- Target activation: normal drag onto a small indicator
- Indicator display: only the target zone, preventing overlapping zones from
  washing out the thumbnail in grey
- Remember and restore pre-snap window geometry: enabled

The four span targets are:

- A: full-height left column
- B: full-height middle column
- C: full-height right column
- E: bottom-middle plus bottom-right

The letters are documentation labels only. KZones shows a miniature of each
target shape rather than an A/B/C/E label. The complete KZones-compatible JSON
is stored in `kzones-layouts.json`.

KZones cannot combine arbitrary zones dynamically like FancyZones. Each desired
span must exist as an explicit overlapping zone in the layout.

## Native KWin tiling

The built-in KWin tiling interface is intentionally dormant:

- `Meta+T` is unbound.
- Native `Meta+Arrow` quick-tile actions are unbound.
- Native custom quick-tile actions are unbound.
- Edge tiling and edge maximization are disabled.

KWin 6.6 hard-codes native Custom tiling when Shift is held during a window
drag. A small KZones 0.9.2 compatibility patch detaches that native tile at the
end of every drag so it does not own the final placement. KWin can still show
its native preview while Shift is held because this happens before KZones sees
the finished event. Use normal dragging with the small KZones targets.

## Automated restoration

Run `scripts/apply-desktop.sh` from an active Plasma session. It validates the
expected display geometry and saves timestamped backups under
`~/.local/state/fedora-settings/backups/` before applying the profile.

The script expects KZones 0.9.2 to already be installed. It applies the local
compatibility patch only when needed, configures the ten zones, restores the
panels and cursor, disables native tiling shortcuts and edges, and reloads
KZones.
