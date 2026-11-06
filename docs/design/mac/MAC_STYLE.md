# ShotDex for Mac — drawing brief for canvas agents

You are drawing artboards for the **ShotDex Mac** Design canvas (native macOS 26 SwiftUI app, not Catalyst,
not an iPad app blown up). Repo: `/Users/hoangtuan/Project/shotdex-ios`. Product context: `CLAUDE.md`,
`DESIGN.md`, `docs/02-functional-spec/FS-*`. Decisions already taken by the user:

- Native macOS app with the **whole** iOS feature set (Library, viewer, search, compare, collections,
  statistics, settings, editor, Video Studio, collage, compress, duplicates, places, servers…).
- Three photo sources in one library: **Photos Library** (PhotoKit), **folders on disk / external volumes**,
  **servers/NAS** (SMB/WebDAV/SFTP… as on iOS). An unplugged volume's photos stay in the library, marked offline.
- Edits never overwrite originals in a folder; same edit recipe as iOS (rendered by ShotDexKit).

## The template — read first, copy verbatim

`docs/design/mac/project/Main.dc.html` is the Library window and **the template for every board**:
copy its `LIGHT`/`DARK` token objects, `SKIES`/`tile()` photo placeholders, icon path map `I`, the window root,
the sidebar (traffic lights, groups, index-status foot) and the toolbar capsule groups. Render of it:
`build/design/render/Main.png` (render it first). Do not restyle these; extend them.

## macOS geometry (CSS px = points)

| Thing | Value |
|---|---|
| Main window board | **1440×900**, root `border-radius:16px; overflow:hidden` |
| Sidebar | floating glass panel, inset 8 from window edges, **228 wide**, radius 18; traffic lights at 14,16 inside it |
| Sidebar rows | 28 tall, radius 8, 13px label, 16px icon in accent, count 11px secondary right; group header 24 tall 11px semibold |
| Toolbar | no title bar; one 44px row at top 8, left edge 256 (after sidebar) to right 16. Items are **glass capsules 36 tall**, buttons 34–36 wide inside, 16px glyphs, gap 12 between groups. Title 15 semibold + optional 11px subtitle at the left |
| Content | starts at x 244, scrolls **under** the toolbar with the 64px scroll-edge fade from Main |
| Inspector (right) | **300 wide**, full height below y 0, background `t.content`, 1px `t.sep` left edge; sections with 11px semibold uppercase-free headers, 13px rows 24–28 tall |
| Body text | 13px; secondary 11–12px; section title 15 semibold; window/large title 22 bold max |
| Push button | 28 tall, radius 8 (bordered: `t.fill` bg; default: accent bg, `t.onAccent` text); popup button same + chevron.up.down glyph |
| Text field | 28 tall, radius 8, 1px `t.sep` border, 13px |
| Checkbox / switch | checkbox 14×14 radius 4; mini switch 32×18 |
| Segmented control | 28 tall, radius 8 container, selected segment `t.content` raised |
| Menus / context menus | radius 10, padding 5, rows 22 tall 13px, shortcut right-aligned in `t.label2` (e.g. `⌘E`, `⇧⌘N`), 1px separators, glass background |
| Popover | radius 14, glass, 12px arrow toward its toolbar button |
| Sheet | slides down from under the toolbar, centered, radius 22, glass/solid, window behind dimmed `rgba(0,0,0,0.18)` light / `0.35` dark |
| Secondary windows (Settings, Get Info, panels) | their own board at their real size, same traffic lights + root radius 16 |

Spacing scale 4/8/12/16/20/24. Radii 8/12/16/22/28 (+18 sidebar, 16 window, 10 menu). Numbers that change
(EXIF, counts, %) use `font-variant-numeric: tabular-nums`.

## Mac mindset — what makes it a Mac app (non-negotiable)

- **Pointer and keyboard first.** No 44pt touch padding, no bottom tab bar, no floating round glass buttons
  over photos, no "Select" mode: selection is click / ⌘-click / ⇧-click / drag-rectangle. Hover states exist.
- **Every command lives in the menu bar** with a shortcut; toolbar holds the frequent subset; right-click
  gives the contextual subset. Draw shortcuts in menus and tooltips.
- **Sidebar + content + inspector**, not pushed full-screen pages. Navigation back/forward in the toolbar.
- **Multiple windows** where it helps (viewer, editor or Video Studio may open in their own window; Settings is
  its own window with a toolbar of panes; Get Info is a utility panel).
- **Drag and drop**: drag photos to albums in the sidebar, to Finder, into Video Studio's timeline; drop folders
  onto the sidebar to add a source.
- Density: a Mac user expects more on screen — 7+ grid columns, tables with sortable columns, inspectors open.
- Tier rule from DESIGN.md still holds: **pixel-editing surfaces (Editor, Compare, Compress, Collage, Video
  Studio) are tier D — always dark**, from `ShotDex/Features/Editing/EditorTheme.swift`: background `#000000`,
  panel `#0E0E0E`, panelSolid `#0F1012`, control `#1C1C1C`, sliderTrack `#2A2A2A`, hairline
  `rgba(255,255,255,0.09)`, secondaryText `rgba(255,255,255,0.55)`, dimText `rgba(255,255,255,0.35)`,
  accent `#EB9526`, timelineSelection `#57BFD1`. Their window chrome (sidebar/toolbar glass) goes dark too.
  Other boards keep the `dark` boolean tweak exactly as Main does.
- Accent is ShotDex amber (`t.accent`), never macOS blue.

## Board file rules (each one fails silently if broken)

- Skeleton exactly as Main: `<!doctype html>`, `<script src="./support.js"></script>` in head, `<x-dc>`,
  `<helmet><style>` with the same three rules, one root div at the board's fixed size, then the
  `<script type="text/x-dc" data-dc-script data-props='{"dark":{"editor":"boolean","default":false},"$preview":{"width":W,"height":H}}'>`
  block with `class Component extends DCLogic { renderVals() {…} }` (classic JS, no imports).
- Close every element, quote every attribute. `{{hole}}` is a dotted lookup into `renderVals()` only — never
  an expression. Repeats `<sc-for list="{{x}}" as="i" hint-placeholder-count="N">`, branches
  `<sc-if value="{{c}}" hint-placeholder-val="{{true}}">`. No `innerHTML`/DOM scripting.
- Icons: inline stroke `<svg>` (one `<path d>` per icon is fine). **No emoji, no images, no `data:` URIs.**
  Photos are the `tile()` gradients — **never draw people/faces**.
- Real `<button>`, `<input>`+`<label>`, `<a>`; `aria-label` on every icon-only button (the label is also what
  the parity tool matches against the app later — use the real command name: "Show Inspector", "Rotate Left").
- Text contrast ≥ 4.5:1; `t.label3` is for disabled only.
- English UI copy, realistic photographer data (Canon EOS R6 Mark II, Sony A7 IV, Fujifilm X-T5, RF 85mm F1.2,
  ISO 3200, 1/250 s…). No lorem, no invented marketing stats.
- No fake macOS menu bar or Dock on window boards. The menu-bar board is the only exception (its menus are the
  subject).

## File names and how to check your work

- Write boards to `docs/design/mac/project/MAC_<Name>.dc.html` (only your assigned names).
- Check each board: syntax-check its script with node, then render it in place (`--dark` for the dark tweak):

  ```bash
  Tools/design-board render docs/design/mac/project/MAC_X.dc.html -o build/design/render-<you>
  Tools/design-board render --dark docs/design/mac/project/MAC_X.dc.html -o build/design/render-<you>-dark
  ```

  **Look at every PNG** (Read tool) and fix overlap, clipping, empty loops, literal `{{…}}`, misalignment before you finish.
  Do not open a browser and do not publish anything — the lead publishes the canvas.
- Return a list: `file · w×h · title`, title in Vietnamese in the canvas style, e.g.
  `MAC_Viewer.dc.html · 1440×900 · Mac · Xem ảnh: filmstrip dưới, inspector EXIF phải`. Plus any open
  design question you had to decide alone (one line each).

---

# v2 rules — after the review round (2026-10-04). These override anything above.

Review reports: `review/hig.md`, `review/pro.md`, `review/consistency.md`, `review/challenge.md`.

## Canonical sidebar (every main-window board)
Exactly the drawing in `review/consistency.md` §1 "Canonical sidebar": groups (Library, no header) · **Sources**
`[+]` · **Collections** `[+]` (On This Day, Albums ›, smart albums) · **Utilities** (Statistics,
Duplicates 53, Collages 12, Video Projects 7, On Server 712). No "Memories", no "Tools", no "Creations", no
"Uploaded to Server", no "Client Proofs" (use **Client Shoots 2026** when a 5th source is needed). Albums row
always has a disclosure chevron; expanded = flat list, no folders. Source row states drawn one way each (§1 rules).
Foot: idle "Up to date · indexed 2 min ago"; progress only on boards about a running task. Toggle labels
"Hide Sidebar"/"Show Sidebar" everywhere. Max 2 levels.

## Tokens (add to every board's LIGHT/DARK, replacing local variants)
- `accentFill` light `#A35E0A` / dark `#EB9526`, text on it `onAccentFill` light `#FFFFFF` / dark `#000000` — every
  filled default button, menu highlight, filled selection. Plain `accent` stays for glyphs, rings, progress.
- `menu` (opaque, light `rgba(246,246,248,0.97)` / dark `rgba(40,40,44,0.97)`), `menuShadow`
  `0 10px 30px rgba(0,0,0,0.22)`; one `sheet` (light `#F6F6F8` / dark `#2A2A2D`); `scrim` light `rgba(0,0,0,0.18)` /
  dark `rgba(0,0,0,0.35)` drawn ABOVE sidebar and toolbar; `rowAlt` light `rgba(0,0,0,0.03)` / dark
  `rgba(255,255,255,0.04)`; `field` = `t.content` with 1px `t.sep`.
- Tier D menu highlight = `#EB9526` with black text.
- Selection rule: amber ring (grid tiles) · `accentFill` (menus, filled rows when focused) · grey `rowSel` (sidebar,
  unfocused tables) · white ring (tier D filmstrip/presets) · `#57BFD1` **only on the Video Studio timeline** ·
  red = marked for deletion.
- Checkbox on = `accentFill` box + white/black check, in every tier. Destructive button = bordered, red text.

## Type, size, structure
- Text floor **10px** everywhere (badges, chart axes, frame numbers). Monospace only for timecode.
- Tables: rows 28 tall (20px thumb), alternating `rowAlt`, header 28 with dividers.
- Toolbar: ≤3 capsule groups + search. Leading: sidebar toggle, ◀▶, title/subtitle. Trailing: inspector toggle,
  search, then ONE prominent action at the far right. Never a destructive prominent action. Text buttons 36 tall.
- **Nothing actionable in the bottom 60pt** of a window except the filmstrip/timeline themselves; bottom bars carry
  status text. (Cull/Compare key legends: keep for now — pending user decision.)
- Sheets ≤ **640×560** (body scrolls) — except a sheet whose body is a results list the user reviews before acting (Find Common Photos): up to **640×640**, so the list keeps at least four rows under its options; popovers ≤ **360×480** with a 12px arrow; bigger content = panel/sheet.
  Long-running work (upload, merge render) = Activity panel / sidebar foot, never a modal sheet.
- Context menus: no shortcut column, hide unavailable items, ≤ 12 rows + submenus.
- No iOS controls: no `− n +` steppers (use field + NSStepper arrows), no 40–50pt tile pickers for >5 choices (pop-up
  button), no round floating buttons over photos.
- Secondary windows (Settings, Get Info, Onboarding, Support): minimize/zoom lights drawn disabled (grey `#D0D0D3`
  light / `#4A4A4E` dark). Settings: one fixed width **720**, panes General · Sources · Editing · Servers · Cameras
  (5 tabs on every Settings board), height ≤ 640 (content scrolls), no Save button.
- Menu bar order: ShotDex, File, Edit, View, Image, Go, Window, Help (Tools items live in Go/Window as needed).

## Shortcuts (canonical; fix every board, menus and tooltips)
Use `review/consistency.md` §6a with these changes: ⌘R Rotate Counterclockwise · ⌥⌘R Rotate Clockwise ·
⌥⌘N New Smart Album… (no New Window shortcut) · ⇧⌘A Deselect All · Advanced Search… and Go to Date… menu-only ·
⇧⌘U Upload to Server… · no ⌃ in ShotDex-defined shortcuts (system ones ⌃⌘F full screen, ⌃⌘S sidebar stay) ·
Go: ⌥⌘1–5 = All Photos, Favorites, Videos, RAW, Recently Added; ⌥⌘6 Statistics; other destinations menu-only ·
Zoom toggle = **Z** in Viewer, Full Screen, Compare, Cull · Space = Quick Look in grids, Play in Video ·
⌘⌫ labelled exactly like the button it triggers · Rescan, Merge N Groups…, Show in Library: no shortcut ·
"Clear Flag" (U), not Unflag · modifier order ⌃⌥⇧⌘.

## Names and data
"Resize" (not Compress) · "Combine Photos" for panorama/HDR/focus/stack exposures · "Merge" only in Duplicates ·
"Copy Edits/Paste Edits" · "Rotate Counterclockwise/Clockwise" · "On Server" · US spelling, title case for
commands/buttons, sentence case for descriptions. Camera names as in `ShotDex/Resources/sensor_database.json`
("Sony A7 IV"). Sample library is ONE library: Canon EOS R6 Mark II 18,240 is the top camera everywhere
(Statistics too), then Sony A7 IV, Fujifilm X-T5, iPhone 16 Pro. Today = **Sunday, October 4, 2026**; Sep 28, 2026
is a Monday. 12-hour clock. On This Day = Kyoto. Totals: 55,231 items = 54,027 photos + 1,204 videos.

## Follow the spec (board decisions reverted)
No Memories screen (On This Day per FS-06.07; Trips removed 2026-10-24) · no per-clip Framing in Video (FS-12.10) · merges are
photos, not Creations entries (FS-06.01b) · Duplicates has no "Keep Both" (FS spec) · no colour labels in Cull.

---

# v3 — user decisions 2026-10-04 (`.planboard/macos-app/DECISIONS.md`). Override everything above.

- **Accent: always ShotDex amber** (not the system accent). No Accent Color setting.
- **Tier D exactly as DESIGN.md**: Editor, Compare, Resize, Collage, Combine Photos, Video Studio always dark. The
  Viewer is NOT tier D: its image area uses the window background (no dark well).
- **Viewer and Editor open inside the main window** (Return opens, Esc/Back returns to the grid at the same scroll
  and selection; sidebar hides). "Open in New Window" ⌥⌘O is the option. No second-display viewer.
- **Compare is the Duplicates A/B screen** (2026-10-24; the Viewer's Single · 2-Up · Survey is gone on every device):
  two panes, Keep | Delete per photo, synced zoom, Delete N on the top bar — FS-01.08. Cull keeps its key strip with a
  Hide button.
- **Saving edits**: folder/NAS photos autosave (toolbar shows "Edited · Saved" + Revert, no Done). Photos-library
  photos have Done + Revert (Done writes to Photos). Export has no "Save Edit" segment.
- **Metadata**: ratings, flags, keywords, title, caption are read from and written to `.xmp` sidecars next to the
  file (Settings › Sources toggle, on by default). Copy: "ShotDex never edits file contents; it writes .xmp sidecars."
- **Photo identity = content hash**: identical copies in two sources are ONE photo (counted once; ratings shared;
  sidecars written to every online copy). Duplicates only groups within one source.
- **Servers are indexed sources** like folders (no "Import to Library"). Uploading stays.
- **Deleting**: Photos → Recently Deleted; folder/volume files → macOS Trash with a confirmation naming count and
  destination; NAS files cannot be deleted from ShotDex (only "Hide").
- **Card ingest exists**: File › Import from Card… (board `MAC_Ingest`).
- **First run** = the main window's empty state (no Onboarding window).
- Statistics: Source popup + Time of Day / Weekday charts stay; no shared date popup.
- Albums: no album folders, no counts under covers (counts stay in the sidebar).
- Export: colour-space popup Original · sRGB · Display P3 · Adobe RGB (default Original).

## Charts — style C (user, 2026-10-04) — applies to iOS and Mac
- **Single series** (bars, columns, histograms, bar lists, single line): one amber hue. Ordinary marks = accent at
  **38% opacity light / 45% dark** (`rgba(198,115,14,0.38)` / `rgba(235,149,38,0.45)`); the mark that matters
  (largest, hovered, selected) = full accent `#C6730E` / `#EB9526`, its value labelled. Flat fills (no gradient), bars
  ≤ 24px thick with ≥ 8px air, 4px rounded data-end, no grey track under bar-list bars. Single line = 2px accent, area
  fill accent at 10% light / 14% dark.
- **Multi-series / donut** (categorical, fixed order, never cycled), validated with the dataviz validator:
  light `#C6730E #3D6FB6 #1E9180 #9A4FA0 #6F8A1E #B83E8C` · dark `#CF7F18 #5C88E0 #1F9C84 #B070C8 #7C962A #D35E98`.
  ≥ 2 series always has a legend; text never in series colour.
