# ShotDex iPad in the Mac style — drawing brief

Intent: `docs/_intents/2026-10-04-ipad-mac-style.md`. The user saw the Mac canvas and wants the iPad to look like it.
Read first: `docs/design/mac/MAC_STYLE.md` (whole file; v2 + v3 + chart style C apply unless overridden below),
the Mac boards in `docs/design/mac/project/` (the visual source), and the CURRENT iPad boards you are replacing in
`docs/design/ipad/project/` (the content source: every control, state and copy on them must still have a home).

## What stays from the Mac
Floating Liquid Glass sidebar (Library · Sources · Collections · Utilities groups), glass toolbar capsules on top,
inspector column on the right, dense grid, tokens (LIGHT/DARK, accentFill, menu, sheet, scrim, rowAlt), amber
accent always, tier D exactly as DESIGN.md (Editor, Compare, Resize, Collage, Combine, Video Studio dark), chart
style C, one prominent toolbar action, no destructive prominent action, 10px text floor → **iPad floor 11px**.

## What changes for iPad (touch first)
| Thing | iPad value |
|---|---|
| Landscape board | **1376×1032**, root radius 18 (display corners), **no traffic lights, no fake status bar**: keep the top **24pt** clear (system status bar); toolbar row starts at y 24 |
| Portrait board | **1032×1376** (only where the current set has a portrait board: editor `IPP*`, video `IP1_Main…`, `*_IP_*`) — sidebar hidden (shown as an overlay board only where useful), inspector becomes a bottom sheet or a popover |
| Sidebar | floating glass, inset 8, **320 wide**, radius 22; rows **44** tall, **17px** label, 22px icon, count 15px secondary; group header 15px semibold |
| Toolbar | glass capsules **44** tall, buttons **44** wide, 20px glyphs, gap 12; title 20 semibold + 13px subtitle |
| Inspector | **360** wide; rows 44, 17px labels, 15px values; sliders with 28px knobs |
| Body text | 17px; secondary 15/13px; section title 20 semibold; large title 28 bold max |
| Buttons / fields | 44 tall (36 inside a toolbar capsule is not allowed — use 44), radius 12; segmented 36 tall |
| Grid | landscape 7 columns with sidebar (6 with inspector open); EXIF overlay 12px |
| Selection | tap selects in Select mode **or** two-finger drag / pointer drag; keep the Select button (touch needs it) but as a toolbar text button |
| Context menus | long-press menus, same opaque menu look as Mac (rows 44, 17px), **no shortcut column** |
| Keyboard | ⌘ shortcuts exist (iPadOS menu bar when a keyboard is attached) — one board `IP_MenuBar` shows the iPadOS 26 menu bar (pulled down) with ShotDex menus; no keyboard legends on other boards |
| Hover | never required; pointer hover may add highlights only |
| Sheets | form sheets ≤ **700×640**, centered, dimming scrim; popovers ≤ 400×560 with arrow |
| Tab bar | **gone** — the sidebar replaces Library/Collections tabs (Statistics lives under Collections › Utilities since 2026-10-17); Search is the toolbar search field |

## Rules for this round
- **Replace boards in place, same file names** (`IP_Library` is now `Main`; keep every other name) so specs that
  cite a board still find it. Old versions stay in git history (commit before this round).
- New boards only when the Mac pattern needs one the iPad set lacks (e.g. `IP_MenuBar`, `IP_LibraryList`,
  `IP_Inspector`); name them `IP_<Name>` / `IP<n>_<Name>` / `IL<n>_<Name>` like their row.
- Board size = the board's existing size (landscape or portrait). Update `$preview` only if you change it.
- Same board-file rules as the Mac brief (support.js line, closed tags, holes are lookups only, no emoji,
  aria-labels with the real command name, no faces, sample data per Mac v2: Canon EOS R6 Mark II 18,240 top camera,
  Sunday October 4 2026, Kyoto…).
- Render and LOOK at every board, light + dark where it has the tweak:
  `Tools/design-board render docs/design/ipad/project/<Board>.dc.html -o build/design/render-ipad-<you>` and
  `--dark`. Syntax-check scripts with node (watch `'` inside single-quoted JS strings — use ’).
- Do not touch `canvas.json`, do not publish. Return: one line per board, new boards as `file · w×h · Vietnamese
  title ("iPad · …")`, and any decision you made alone.
