# Dashboard visual assets

The matte slate / pastel palette in `components/Theme.qml` is inspired by Nord
and the user's dashboard reference. Geometry and hardware-mode semantics remain
independent of this visual theme.

- Active outline icons: Feather 4.29.2, from
  https://github.com/feathericons/feather/tree/v4.29.2/icons.
  MIT; see `feather/LICENSE.txt`. SVG filenames match upstream. Strokes are
  normalized to white for tinting and 2.5px to match the reference moon's weight.
  Used for lighting/power, coffee, wind, bolt, CPU, music, navigation, and Work
  launch actions. Pie-chart and battery are also bundled for the reference look.
- Active filled icons: Pictogrammers Material Design Icons 7.4.47, from
  https://github.com/Templarian/MaterialDesign-SVG/tree/9e04201d4557e729822fb57f62a316c3dea1d4a8.
  Apache 2.0; see `icons/LICENSE.txt`. SVG path fills are normalized to white for
  runtime tinting. Used for fan, four-point party star, and media controls.
  Lights-off uses MDI `lightbulb-off-outline`, a slashed bulb, instead of a power symbol.
  Hardware headers use MDI `memory` (processor-shaped glyph) and
  `expansion-card` (graphics card), mapped as `processor` and `graphics-card`.
  The storage tile uses `harddisk-tight.svg`, the same upright `harddisk` paths
  with the viewBox cropped to `4 2 16 20` so the visible icon width matches its
  capacity label. The original padded asset is also retained.
- Previous, inactive trial: Numix base, revision
  `c876b63326530034e3ac3f9cc66a13b445aca230`, from
  https://github.com/numixproject/numix-icon-theme. GPL-3.0+; see
  `numix/LICENSE.txt`. Mostly scalable symbolic SVGs; the coffee, wind, and
  processor use Numix's 24px/48px SVG variants. Paint colors are normalized
  to white for runtime tinting. Exact upstream paths are in `numix/sources.json`.
  The normal LTR playback icons are used (not the RTL mirrored variants).
- Previous custom fan/bolt drawings in `custom/` are retained but unused.
- `components/ThemeIcon.qml` explicitly maps semantic names to Feather or MDI;
  it does not rely on the desktop icon theme. Branded MPRIS player logos still
  use the system-provided app icon.
- Font: Share Tech Mono, from Google Fonts' `ofl/sharetechmono` directory.
  SIL Open Font License; see `fonts/OFL.txt`. Loaded privately by QML, without
  changing the desktop's font settings.
- Clock font: the user's `Downloads/iosevka-nerd-font.ttf`, bundled unchanged
  (SHA-256 `434b3e0adcdf080018b2813dfd72a53e983633311d40ad1ff954d8f8d7ff4fe7`).
  Loaded only for the clock/date tile. See `fonts/Iosevka-OFL.txt` for the Iosevka
  license. No system font settings are changed.
- The Aeris logo is `custom/aeris.svg`, a vector redraw of the user's supplied
  filled-A reference (2026-09-04), with its single swept crossbar. It replaces
  the earlier outlined airflow-A and uses the same selected/inactive tinting.
- `custom/aeris-wordmark.svg` redraws the user's complete AERIS wordmark as
  paths, including the matching A mark and spaced ERIS lettering. It has no
  font dependency or background and appears beneath AERIS AI on page three.
- Clock digits and AM/PM use a separately bundled **Iosevka Nerd Font Bold**
  face, rather than relying on synthesized bold from the user's regular font.
  Source: https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/Iosevka/IosevkaNerdFont-Bold.ttf
  (Git blob `52297cad6da96820ff2bed8ccd577b91b37f2629`).
  SIL OFL; see `fonts/Iosevka-OFL.txt`. Dates retain the original regular face.

These assets are local; normal dashboard startup needs no network requests.
