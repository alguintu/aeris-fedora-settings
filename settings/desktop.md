# Desktop and KZones

## Cursor

- Theme: Breeze
- Configured size: 36 px

Open the cursor settings page with:

```bash
kcmshell6 kcm_cursortheme
```

## Secondary touchscreen display

The TeNizo R7-series panel is connected as `DP-3`. Its native 480×1920 mode is
rotated into a 1920×480 desktop surface at 100% scale and positioned directly
beneath the 3840×2160 primary display:

- Geometry: `1920×480+960+2160`
- KScreen rotation: `8`
- Output UUID: `a8010dcd-95c3-4fb2-b1a4-73dd48a2cc37`

The horizontal offset is `(3840 - 1920) / 2 = 960`, so the two displays share
the same center line. Restore the position from an active Plasma session with:

```bash
kscreen-doctor output.DP-3.position.960,2160
```

The USB touch controller is `TeNizo TeNizo_R7Series_TC` (`1a86:e5e3`). KWin
maps it to `DP-3` and persists the association in `kcminputrc` as:

```ini
[Libinput][6790][58851][TeNizo TeNizo_R7Series_TC]
OutputUuid=a8010dcd-95c3-4fb2-b1a4-73dd48a2cc37
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
- Nine base zones; the upper-left and upper-right quarters are each divided
  into two equal stacked targets, while the lower-right quarter is divided into
  two equal side-by-side vertical targets
- Thirty-four explicit overlapping alternate zones: fourteen broad spans, ten
  additional corner subdivisions, two three-quarter-height center views, and
  eight center-half subdivisions
- Gutter/padding: 8 px
- Target activation: normal drag onto a small indicator
- Indicator display: only the target zone, preventing overlapping zones from
  washing out the thumbnail in grey
- The upper and lower center-half targets form the same compact cross pattern
  as the corner targets: left/right arms are 240 px from center, and top/bottom
  arms are 262.25 px from center. The full-width upper/lower-half target sits
  another 134 px beyond the cross's outer arm, with a 34 px invisible
  activation bridge across the remaining gap.
- The vertical target order is whole upper half → top arm → upper-middle center,
  mirrored below as lower-middle center → bottom arm → whole lower half.
- Remember and restore pre-snap window geometry: enabled
- Enabled output: `HDMI-A-1` (3840×2160)
- Disabled output: `DP-3` (1920×480); KZones overlays, mouse snapping,
  and keyboard zone moves remain inactive there

During an interactive drag, the output under the pointer determines which
layout is active and supplies the zone geometry. This avoids losing the main
display's KZones target when a tall window's center crosses onto `DP-3` before
its title bar does. Keyboard zone moves continue to use the window's output.

The broad span targets are:

- A: full-height left column
- B: full-height middle column
- C: full-height right column
- D: merged upper-left stack
- E: merged upper-right stack
- F: merged lower-right emulator pair
- G: bottom-middle plus bottom-right
- H: full-width lower half
- I: full-height middle plus right columns; its thumbnail is centered between
  the full-middle and full-right thumbnails
- J: bottom-left plus bottom-middle
- K: top-middle plus top-right
- L: top-left plus top-middle
- M: full-width upper half
- N: full-height left plus middle columns

Two further center-lane targets cover three quarters of its height. One is
top-aligned (`y=0–72.847222%`); its mirror is bottom-aligned
(`y=24.282407–97.129630%`). Their thumbnails naturally sit above and below the
full-height center target.

Each upper and lower center half also has a complete cross of subdivisions:
left and right vertical halves plus top and bottom horizontal halves. The eight
added geometries use `x=25–50%` and `x=50–75%` for their vertical splits, and
24.282407%-high bands for their horizontal splits. Their thumbnails mirror the
corner crosses: the vertical-half targets sit 240 px to either side of the
whole-half target, while the horizontal-half targets retain their natural
262.25 px vertical offsets. The three-quarter-height thumbnails are shifted
120 px inward toward the full-center target so they do not overlap the inner
horizontal-half thumbnails.

All four corners have a pair of vertical half-width slots. The left corners use
`x=0–12.5%` and `x=12.5–25%`, with thumbnails centered at x=240 and x=720 around
their whole-corner target at x=480. The right corners use `x=75–87.5%` and
`x=87.5–100%`, with thumbnails centered at x=3120 and x=3600 around their
whole-corner target at x=3360. The lower-right pair is part of the base grid;
the other six slots are explicit overlapping alternatives. Every corner also
has two stacked horizontal halves around the whole-corner target: the upper
pairs are in the base grid, while the four lower slots are mirrored
alternatives.

The letters are documentation labels only. KZones shows a miniature of each
target shape rather than an A/B/C/D/E/F/G/H/I/J/K/L/M/N label. The complete KZones-compatible JSON
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
native-tiling, per-output, and indicator activation-margin compatibility patches
only when needed, configures the forty-three zones, restores the panels and cursor,
disables native tiling shortcuts and edges, disables KZones on `DP-3`, and reloads
KZones.
