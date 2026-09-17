# Dashboard implementation rules

Read [DESIGN.md](DESIGN.md) before any dashboard UI change. It is the local
design contract; `components/Theme.qml` is the source of shared token values.
Drei's explicit new directions take precedence. Record an accepted new rule or
intentional exception there instead of letting it become unexplained magic.

- Home (`IdlePage.qml`) and PC Specs are approved visual references. Work/AI
  placeholders are not precedents for typography, spacing, or extra borders.
- Use shared tiles, headers, icons, and existing widget components. Use semantic
  tokens for their roles, not unrelated tokens that happen to have equal values.
- Home uses the shared `HomeGrid` placement map and `GridTile` with a universal
  12px content inset and 6px internal spacing unit. Do not reintroduce fixed widths
  or the old media/compact padding exceptions there. Grid Preview reads the same
  map. PC Specs uses `SpecsGrid` with the same grid primitives and inset rules;
  Work/AI retain legacy geometry until explicitly migrated.
- State the geometry before editing: outer bounds, content inset, sibling gap,
  anchor edges, and what must remain unchanged. Moving a tile is not permission
  to resize it or its siblings. Derive shared edges/dimensions from one source.
- `DashboardTile` already pads its content. Do not double-pad. Anchor ordinary
  content inside it; full-bleed decorative layers are explicit, rounded-clipped
  exceptions. Never use clipping to hide overflowing text or broken layout.
- Keep hardware headers on one line and readouts legible. Do not solve overflow
  by shrinking fonts, stretching cells, or adding unrequested rows/labels.
- Check the rendered result at 1920×480, not just the QML syntax. Inspect relevant
  loading, empty, unavailable, long-text, and active states. Check sibling edges,
  bottom margins, rounded real artwork, and swipe gutters when affected.
- Preserve offscreen/minimized presentation gating and shared service state.
  Reusing Tomat on another page must not start another timer or service.
- New/rewritten runtime backends and helpers must be Rust in
  `../aeris-backend/`. QML/JS is presentation/interaction, shaders are rendering;
  neither is a loophole for moving backend work out of Rust. Historical Python
  adapters are comparison/rollback only; minimal build shell glue is allowed.
  Approved exception (2026-09-05): FDM's in-process QML adapter may export an
  allowlisted live-download snapshot while loading its stock UI. Rust owns
  transport, validation, freshness, slot assignment, and dashboard delivery.
- Run relevant existing tests from the repo root (presentation suite:
  `python3 -m unittest discover -s tests -p test_dashboard_presentation.py`). Add
  a regression test for behavior/geometry bugs, not every cosmetic adjustment.
  Preserve unrelated edits and do not commit/push unless requested.
