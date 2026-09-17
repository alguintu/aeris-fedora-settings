# Aeris dashboard design contract

Established with Drei, 2026-09-05. This codifies the accepted Home and PC Specs
designs, not a new theme or a mandate to flatten every widget into one template.
The goal is a quiet, legible instrument panel: expressive artwork inside a
precise tiled structure. Wallpaper remains visible between tiles.

**Page-plan revision (2026-09-05):** Deep Work and AI Focus are now one **AERIS
AI** hub at IPC index 2 (`WorkPage.qml`). Retain the first AI card at the upper
left, 720×176, and the existing full-height 296px-wide Pomodoro pinned right.
The old Work placeholders and separate AI page are removed from the live UI.
Their retained cards keep existing internal geometry for this move; no implicit
grid migration or redesign. Production order is PC Specs (0), Home (1), Aeris AI
(2); Grid Preview remains a separate inspector at index 3. Home remains startup.
References below to legacy Work/AI styling apply to the retained hub card, not
two future pages to implement.

**Hub population (2026-09-05):** Restore simple CPU/GPU/RAM/VRAM meters in the
remaining upper band, with saved LM Studio presets beneath the identity card
and worker-template links beneath the meters. Preserve 720×176 identity bounds
and the full 296px-wide Pomodoro; derive the middle width from these retained
edges and the 12px gutters. All new/refreshed cards use 12px content insets,
6px internal spacing, and existing 20/18px header/body roles. The full Pomodoro
is unchanged. API status is read-only; templates open files, not execute jobs.
No mock queue, throughput, loaded model, or lifecycle controls. The API reader
polls every five seconds only while the page is presented; resource meters
reuse the existing metrics snapshot and freeze offscreen.

## 1. Geometry comes first

**Grid-system revision:** Drei has selected a universal **12px tile content
inset**, including media and small tiles, and a **6px internal spacing unit**.
Apply padding once per tile, never again to its nested sections. Icon-only
controls retain full-size touch targets. **Home and PC Specs now use this system**;
Home shares its placement map with Grid Preview. Work and AI retain legacy geometry until
their migration; those old values are not exceptions for new grid-based widgets.

All measurements are **logical pixels** at the 1920×480 target. Shared values
are implemented in [Theme.qml](components/Theme.qml); change them deliberately,
not through per-widget approximations.

| Role / Theme token | Value | Contract |
| --- | ---: | --- |
| `pageGutter` | 14 | Equal left/right page margins |
| `pageTopInset` | 14 | First tile top edge |
| `pageBottomInset` | 42 | Space below content, including navigation |
| `tileGap` | 12 | Between sibling tile surfaces, horizontally and vertically |
| `gridContentInset` | 12 | Every Home and PC Specs tile |
| `spacingUnit` | 6 | Internal spacing increments |
| `gridHeaderHeight` | 30 | Shared CPU/GPU/RAM/VRAM header slot |
| `radius` | 12 | Outer tile corners |

`HomeGrid.qml` is the single placement map for Home and Grid Preview. Use
`GridTile { grid: homeGrid; slotName: "…" }` for padded cards; do not enter a
second pixel width. `DashboardGrid.cellRect()` rounds shared track edges and
includes internal gutters in spans. Home uses 18 columns × 4 rows:

| Slot | Column, row (zero-based) | Span |
| --- | --- | --- |
| media | 0, 0 | 5×3 |
| weather | 5, 0 | 4×2 |
| pomodoro | 9, 0 | 4×2 |
| cpu | 13, 0 | 5×2 |
| gpu | 13, 2 | 5×2 |
| awake | 5, 2 | 1×2 |
| storage | 6, 2 | 4×2 |
| downloads | 10, 2 | 3×1 |
| network | 10, 3 | 3×1 |
| controls | 0, 3 | 5×1, split into two equal groups with a 12px gutter |

Each control group has three equal, full-height touch targets without internal
gaps/borders. Centered icons fit inside the group's inset; do not add padding to
both the rack and its groups. Home's hardware sections split their available
width 3:2, separated by 12px; both use 30px header slots and 12px header/body gaps.
Memory fields distribute remaining space into cell gutters to meet all four
edges while retaining integer-sized square cells.

PC Specs uses `SpecsGrid.qml` on the same 18×4 grid: identity occupies columns
0–2 for all four rows (3×4). Processor/motherboard and graphics/storage use
4×2 spans at columns 3 and 7. Memory uses 3×2 at column 11, with fans and ARGB
each 3×1 below it (rows 2 and 3). Chassis/system use 4×2 spans at column 14.
The identity mark fits available width up to 240px; all text retains its approved
size and wording. Compact cards also use the universal 12px inset, with a 6px gap
between their heading and a two-line detail block (normal line spacing within it).
Their 24px icons sit 6px from the text column so full fan details fit at 18px.
The identity card reuses the media placeholder's CH260 pixel field behind its
content, within the same 12px inset. Squares stay square on the portrait card.
Animations are stepped 2-bit pixel art: rain tails, a serpentine chase, and
blinking star sprites. Four low-contrast brightness levels, four held frames per
second, no light-field waves or crossfades. One 250ms timer drives the whole
shader and stops offscreen/minimized; it does not wake the 60Hz decorative clock.
Tapping anywhere on the identity tile advances to the next animation and resets
its automatic cycle. Use drag-threshold tap recognition so page swipes cancel taps.
`GridTile` accepts any `DashboardGrid` placement map, not just Home's.

Legacy tokens `tilePadding` (18), `mediaPadding` (24), `compactTilePadding` (14),
`headerBodyGap` (10), and fixed card widths remain for unmigrated consumers only.
Reusable components with full-bleed art accept the actual `contentInset`; do not
assume an 18px ancestor padding (especially the Pomodoro dial, seek area, picker,
and weather background).

At this target, page content is 1892×424. Two equal Home rows are 206px each,
separated by 12px. These are derived dimensions, not independently tuned values.
The 42px bottom inset is intentional navigation space, not an unequal side gutter.

- **One owner per dimension.** A row owns row height; a column owns width. A
  sibling aligns to that owner, not to a separately eyeballed coordinate.
- **Moving is not resizing.** Preserve the moved tile's approved dimensions and
  unaffected siblings unless the request also changes size.
- **One padded content rectangle.** `DashboardTile` already provides it. Children
  fill/anchor to that rectangle without adding a second inset. The optional built-in
  header consumes part of it; custom hardware headers live inside the body.
- **Anchor to intent.** A bottom control/footer uses the inner bottom edge, not a
  guessed `y` or text-dependent spacer. A left label/grid starts at the same inner
  left edge; right readouts and the grid end at the same inner right edge.
- **Align related content.** RAM header/readout align with RAM cells, not the CPU
  section beside them. Paired headers share a vertical alignment. Equal-height
  fields share their top and bottom edges.
- **Separate spacing roles.** Tile gap, content padding, text-group spacing, and
  control spacing are not interchangeable. Do not replace every literal `12`
  with `tileGap`; small optical/internal adjustments are allowed when documented.
- **Layout owns children OR anchors do.** Use `Layout.*` for items managed by a
  Qt Quick Layout. Use anchors inside their content items. Do not give competing
  layout and anchor instructions for the same item's position/size.
- **Align visible ink when needed.** Font bearings and SVG viewbox whitespace can
  make mathematically aligned objects look wrong. The disk capacity/icon uses
  measured ink bounds; preserve this instead of adding arbitrary negative margins.

Ordinary tile content stays inside the inset. Art can intentionally bleed to the
tile edge (weather, Pomodoro dial/gradient), clipped to rounded tile corners.
That exception does not apply to text, controls, or memory grids. A plain
`clip: true` is rectangular, not a rounded artwork mask.

Page scrolling clips once at the full-screen `PageViewport`. Each page retains
both side gutters: adjacent tile contents stay **28px apart during a swipe**.
Never clip each page to its inset content bounds or remove offscreen pages from
the positioning Row to save work.

## 2. Type, hierarchy, and wording

Use bundled **Share Tech Mono** (`Theme.fontFamily`) for interface text, and the
existing **Iosevka** clock families for time/date display. Keep the approved
chromatic-clock font pairing and geometry; do not add another font casually.

| Role | Established size/style |
| --- | --- |
| Standard section title | `sectionTitleSize`: 20, DemiBold, uppercase |
| Model/detail and right header readouts | `headerDetailSize`: 18, DemiBold |
| Header icon | `headerIconSize`: 26, preceding the model |
| Media title / artist | 24 / 20; existing weight and color hierarchy |
| Specs hierarchy | 22 heading, 32 main value, 20 details; compact details 18 |

These are roles, not a requirement that hero numbers or artwork use body sizes.
13px text in the timer is secondary annotation, not a precedent for new primary
readouts. Old Work/AI 10–13px placeholder copy is **not** the new-widget baseline.

- Hardware headers remain **one line**: icon, model, right-aligned utilization
  and temperature (`12% · 48°C`). Memory headers use `RAM`/`VRAM` with
  `15% · 64GB`/`11% · 16GB`. Keep separators explicit.
- Reserve room for readouts first. Elide variable model/title text if needed;
  shorten curated wording with approval or reconsider geometry before shrinking
  type. Never silently wrap the header to fit.
- Peer facts have equal color/weight. The second fan/ARGB detail line is not
  secondary simply because it is lower. Secondary style means secondary meaning.
- No unrequested title, instructional sentence, provenance line, or status label
  in carefully allocated space. Put supporting information in existing tooltips
  or documentation where appropriate; do not remove required attribution blindly.
- Preserve user-approved wording/units, including `3200 MTs`. Static Specs
  marketing values and live Home telemetry serve different purposes.

## 3. Surfaces, color, and icons

Use `Theme` colors: slate `surface` (#2e3440), `raised` (#3b4252), `inset`
(#4c566a), `text` (#e5e9f0), `muted` (#a7adba), and `inactive` (#727d90).
Accents are blue, cyan, teal, green, yellow, orange, red, and mauve from Theme.
Do not introduce near-duplicate hex colors for ordinary UI. Weather, heatmaps,
and chromatic artwork deliberately have their own rendering palettes.

- Normal tiles have **no outline**. Use subtle accent background tint for active
  Awake/light/fan surfaces (`Theme.tintedSurface`, selected strength 0.24).
- Lighting and fans each form **one unified tile with three independent touch
  targets**, no internal divider borders and no verbose mode text. The group
  tint reflects its state; inactive icons remain neutral gray.
  When the RGB daemon is offline, only the Aeris lighting icon remains tappable
  for an attended, guarded service start. Pending startup accents that icon while
  keeping other mode controls disabled; confirmed daemon state owns selection.
  Keep progress/errors in the existing icon/tooltip, not extra tile labels.
- The **Awake switch** is borderless, including its track and outer tile. It fills
  the 1×2 tile's 12px inset as one rounded rectangle (12px radius), with three
  full-size icon targets: fully awake at top, system-only awake in the middle,
  normal at bottom. One rounded rectangular highlight (12px radius, no track inset,
  full track width and one-third track height)
  slides behind the selected icon. Full is amber, system-only teal, normal gray;
  no text or internal dividers. Horizontal page drags cancel mode taps.
- Use `ThemeIcon` mappings: Feather + Pictogrammers MDI, with the approved Aeris
  mark/wordmark. No Numix, emoji, or improvised substitutes. Preserve upstream
  icon shapes (including the bulb-off slash). Keep icon viewboxes/aspect ratios.
- Wallpaper is visible and blurred between tiles, not covered by a global dark
  fill. Weather can brighten its own daytime tile without changing other cards.
  Use compositor backdrop blur (`BackdropWindow`, Quickshell 0.3+) over the actual
  desktop, never a hardcoded wallpaper copy. The blur region follows the reveal
  slide and becomes null when minimized; KWin controls blur strength.

## 4. Preserve the accepted widget contracts

- **CPU/RAM + GPU/VRAM:** matching outer dimensions, matching header/grid edges;
  two CPU dies, 16 cores, side-by-side thread halves without a dividing border;
  only outer CPU corners chamfered. GPU has 80 cells. Memory uses genuinely square
  small cells; never stretch the final column or let cells escape their section.
  Work out available width, height, integer cell size, and gaps together.
- **Media:** 12px outer inset, rounded art in every state, approved horizontal
  art/text arrangement. Title/artist form one closely spaced group; controls form
  another group below it. Preserve existing title-third placement and control
  breathing room. Transport controls pin to the content bottom without a second
  bottom margin; artwork/text are separated by 12px. No scrubber or extra side
  controls unless requested. Real art,
  crossfade layers, and Silence/Anonymous fallback occupy the same bounds; play,
  pause, loading, and track changes must not resize the tile or shift controls.
- **Clock/weather:** stacked time anchored left; weather top-right, date above
  uppercase weekday at the inner bottom-right. Weekday matches AM/PM size/weight
  but stays yellow. Decorative weather goes behind text without displacing it.
- **Storage:** icon and capacity share ink width; use an 18px (3-unit) gap
  below the icon. Free-space text stays pinned to the inner bottom, not pulled
  up by the capacity label. Drive labels/bars share their own left/right edges.
- **Network/downloads:** two 3×1 horizontal tiles immediately right of storage,
  downloads above network (305×97 each, 12px gutter/inset). Downloads contains
  a mauve DOWNLOADS header matching NETWORK's type size, pinned top-left.
  Both headers have baseline-aligned 18px rates pinned to the right content edge:
  DOWNLOADS shows the combined active FDM speed in mauve; NETWORK shows receive
  (↓ teal) and send (↑ mauve), separated by 6px. Reuse `TransferRateLabel` for
  decimal KBs and MBs, explicitly without slashes (larger units if needed); unavailable is a dash, idle is
  zero for NETWORK. DOWNLOADS hides its speed at zero; a green completed-entry
  count pins to the right content edge on the header baseline, hidden at zero/unknown.
  When both are visible, statistics read `speed · count`, with a 6px gap on
  either side of the muted dot. A lone speed or count pins right without a dot.
  It reflects FDM's own completed-entry count, not a lifetime counter;
  display caps at 99+ for header fit, with the exact count in the tooltip.
  No new polling or timers; readouts freeze with offscreen presentation.
  Four thin full-width gray tracks occupy the area below it with a 6px
  header/body gap and 6px track gaps; the final track pins to the bottom inset.
  Occupied tracks use a 32% mauve tint over `Theme.raised`, including at 0% or
  zero speed, so active downloads cannot be confused with empty gray slots.
  Mauve fills show real byte progress; Rust preserves active
  download slots independently of FDM's UI filters. Unknown totals use a moving
  segment, never a fake percentage. Empty/unavailable states retain the same
  four tracks; diagnostic text stays in the tooltip. Tapping the whole tile
  opens/raises FDM, with drag-threshold cancellation for page swipes. Network has a
  quiet header and two soft GPU-rendered sine ribbons: teal receive, mauve send.
  Amplitude eases from real byte-rate telemetry on a fixed logarithmic scale;
  this is activity, not a historical or percentage-bandwidth plot. No axes or
  extra rows; detailed rates/interfaces remain available in the tooltip. Motion
  shares DecorativeClock, stops at zero traffic, and freezes offscreen/minimized.
- **Pomodoro:** Home uses `CompactPomodoro`, a 4×2 span (411×206 at the target),
  with a simple remaining-time ring around the countdown and focus/break state
  in the center; vertical session dots balance the templates, start/pause, and
  reset stack at the inner bottom-right. The left indicator rail matches the
  52px control rail, with its dots centered vertically; the ring remains 182px.
  Dots follow the shared routine's session count/current session and freeze
  offscreen along with the countdown. The ring supports relative scrubbing (clockwise adds remaining
  time), previewing locally and committing one revision-guarded seek on release.
  Center taps remain available for paging; hiding/cancelling aborts the seek.
  Home's `CompactRoutinePicker` stays inside the same 4×2 tile: browse one named
  routine with arrows, see its durations, then choose Use next or Restart. Deep
  Work retains the full list picker. Minor template/reset icons are 24px muted
  gray within unchanged 52px touch targets; play/pause remains the primary action.
  No quote or ornamental dial ticks. The ring is a scene-graph
  shape, with no local clock or continuous animation; inactive presentation freezes
  its state until the page is shown again.
  Deep Work keeps the full `PomodoroTile` in its unchanged 296px-wide card.
  Both present the same Tomat service/session; neither starts a separate timer.
  In the full tile, the right-aligned quote spans the content width near bottom controls;
  its long soft gradient is background decoration, not an extra box. Reuse the
  shared Tomat session, templates, seek behavior, and notifications.

The cropped timer dial and asymmetric clock artwork remain intentional. Pixel
adjustments in artwork/ink alignment are not spacing tokens. Legacy media and
compact-card padding exceptions do not apply to the grid system.

## 5. State and motion are part of layout quality

Input gets immediate feedback. For Awake, move the thumb to the requested
position first, retain confirmed-state color while pending, then apply the new
color on confirmation; handle failure honestly. Do not make network/service
latency look like an unresponsive touch target or claim success before confirmation.

Reuse existing restrained transitions; no layout reflow on playback/state change.
Hit areas can be larger than icons without shrinking siblings. Keep touch taps
compatible with page flick/cancel behavior and timer seeking.

Pass the page's presentation-active gate to reusable animated widgets. Completely
offscreen/minimized decorative loops pause; partially visible pages remain active
during swipes. Shared services continue independently. Use cached textures,
scene-graph/shader rendering, and the shared decorative clock where suitable;
do not add per-cell timers or high-frequency backend polling for ornamentation.

## 6. Before calling a change done

1. Name the parent bounds, shared dimensions, insets, gaps, and fixed anchor edges.
   Reuse the existing component before inventing a second implementation.
2. Check fit using the longest relevant text/state. If it does not fit, explain
   the geometry tradeoff instead of silently shrinking type or adjacent tiles.
3. Inspect a live render at 1920×480. Check both outer edges, shared row boundaries,
   header-to-grid alignment, bottom anchors, and visible ink—not just item boxes.
4. Exercise the relevant empty/loading/error/active states. For structural changes,
   also check swiping, partial visibility, and minimize/restore. Use the existing
   presentation tests for geometry/lifecycle changes.
5. Record a newly accepted reusable rule here and implement its shared token or
   component when appropriate. Do not turn an unapproved experiment into policy.

### Audit boundary

**Home grid applied:** the inspector page, `GridPreviewPage.qml`, visualizes the same
`HomeGrid.qml` placement map now used by Home. It keeps the current page gutters
and 12px tile gaps, with centrally rounded track edges. Inspector outlines,
coordinate labels, and control-target boundaries are not production tile styling.

Home and PC Specs are migrated; Work and AI retain their previous outer layouts. The older Work/AI placeholder
layouts still need their planned redesign. In particular, their small helper
text, legacy bars, and decorative bordered boxes are not design-approved examples.
Do not bulk-redesign them under the guise of a spacing cleanup.

## Phone workout integration — 2026-09-13

Tomat workout templates expose the same daily set log to both clients. The full
Pomodoro reuses its existing quote/credit area for the next exercise and set
count; the compact timer reuses its break-status line for the count. Outer
bounds, insets, gaps, rings, controls, fonts, and offscreen gating are unchanged.
Completed sets come only from explicit logging, never from timer expiry.
