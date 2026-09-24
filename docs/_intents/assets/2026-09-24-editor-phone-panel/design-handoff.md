# ShotDex Editor — Phone panel "8a" (match `ShotDex Editor Prototype.dc.html`)

> Bản bàn giao từ Claude Design, người dùng dán vào hội thoại ngày 2026-09-24. Lưu nguyên văn làm tài liệu
> tham chiếu cho intent [2026-09-24-editor-phone-panel](../../2026-09-24-editor-phone-panel.md).
> Đây **chưa phải spec đã duyệt**: chỗ nào lệch với code hoặc với luật của repo được liệt kê trong mục
> Open questions của intent. File prototype `.dc.html` chưa nằm trong repo.
>
> **Đã bị intent ghi đè — đừng làm theo bản này ở các chỗ sau** (bảng "Đã chốt" và "Chức năng phải giữ"
> trong intent thắng): §5 Curve (giữ nguyên bố cục, không Input/Output, không dời Reset/gợi ý/preset); §5
> Color Mix (giữ "All", 9 mục chia đều); §5 Markup (mô hình layer như Mask, đủ mọi thuộc tính); §5 Mask (hàng
> 1 có Face skin · Eyes · Lips; hàng thông số đủ Light/Color/Detail/Effects; hàng shape; ⋯ không có
> Add/Subtract); §5 Presets (có strip nguồn); §5 "rows only" cho Optics/Geometry (giữ Lens Profile, Upright);
> §3/§4 cũng áp cho sidebar; §5 Crop (theo bố cục prototype, đủ chức năng); §6 "accent only on Save" áp cho
> **toàn editor**, kể cả băng lệnh (nút giữ/bật = nền trắng).

Scope: **phone layout only** (`EditorLayoutMetrics.usesSidebar == false`). Do not touch the wide sidebar, Collage or Video Studio. Reference: the interactive prototype `ShotDex Editor Prototype.dc.html` (open it and click through every group). Where a code comment contradicts this spec (e.g. "There is no round knob", "accent fill"), this spec wins — update the comment.

## 0. Current vs target (summary)

| Area | Code today | Target (8a) |
|---|---|---|
| Panel height | 246 (`editorPanelHeight`) | **264** |
| Param zone | 167, target strip 36 eats into it | **185**, top inset 8, then a strict **40pt row grid** |
| Panel top | 1pt `panelTopHairline` overlay, square corners | **No hairline**. Top corners radius **22** (continuous). Colour stays `panelSolid` #0F1012 |
| Target strip | only Grade; 36pt; bottom hairline | Every group that picks a target; **40pt = one row**; no hairline |
| Slider row | 34pt inline (`editorRowHeight`), label 88 UPPERCASE 10.5 semibold | **40pt**, label 78pt, sentence case 12 regular |
| Slider cursor | 4×14 white bar + glow | **18pt white circle**, shadow `black .55, r 4, y 1` |
| Slider fill | accent fill + accent glow | **White 50%** fill from anchor, 3–4pt, no glow. Accent is never used in sliders |
| Label/value when changed | label → white, value → accent (`isActive`) | **No change**. Label and value always `white .6` |
| "Edited" dots | on Color Mix swatches, Curve chips, Grade region dot tint | **Remove all** edited markers in the phone panel |
| Chip style | `EditorChipButtonStyle`: 28pt, selected = accent fill, unselected text secondary | **One style everywhere** (see §3) — never accent |
| Curve panel | chips + Reset + hint text + preset row | Channel strip (4 even chips) + Input/Output rows. No hint text |
| Crop panel | action row + Straighten + scrolling ratio chips + footnote | **Unchanged in structure** — keep exactly as in code (see §5 Crop) |
| Mask (no masks) | list panel with "New Mask" button → sheet | Mask types shown **inline in the param zone** (no sheet) |
| Markup tools | mixed chip / icon-only / label-on-select | Same chip style with icon + label |

Accent (`EditorTheme.accent`) remains only on **Save** in the group strip.

## 1. Metrics (`EditorLayoutMetrics`)

```swift
static let editorPanelHeight: CGFloat = 264
static let editorParamZoneHeight: CGFloat = 185   // 264 − 54 − 25
static let editorParamZoneTopInset: CGFloat = 8
static let editorPanelRowHeight: CGFloat = 40     // slider rows, target strip, toggle/font/color rows
static let editorTargetStripHeight: CGFloat = 40  // == one row
static let editorPanelCornerRadius: CGFloat = 22
static let editorSliderThumbDiameter: CGFloat = 18
static let editorRowLabelWidth: CGFloat = 78      // phone inline
static let editorRowValueWidth: CGFloat = 44
```
- `editorParamAreaHeight(hasTargetStrip:)` → `185 − 8 − (strip ? 40 : 0)`.
- **Alignment rule:** row *n* of every group sits at the same y. A group without a strip starts its first slider where the strip would be. Every row type in the zone (slider, toggle, font, colour, hint) is exactly 40pt. Add a test in `EditorPanelLayoutTests` asserting all phone row heights == 40 and zone = 185.
- Update `PhotoEditorScreen` stage/inset math that assumed 246 (e.g. line ~1111 `editorPanelHeight + Spacing.md`, toast/bottom offsets, curve plot stage rect).

## 2. Panel shell (`PhotoEditorScreen.panel`)

- Remove the `.overlay(alignment: .top) { panelTopHairline }` and the strip's bottom hairline.
- `.background(EditorTheme.panelSolid, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))`; clip the param zone to the same shape.
- Param zone: `VStack(spacing: 0) { Color.clear.frame(height: 8); strip?; rows }`. Rows scroll inside; add a 22pt bottom fade to `panelSolid`.
- `panelHasTargetStrip` returns true for: `.curve, .colorMix, .pointColor (when ≥1 point), .grade, .mask (when ≥1 mask), .markup`. **Not `.crop`.**

## 3. The one chip style (replace `EditorChipButtonStyle` for phone panel strips)

```
height 30 · corner 8 (continuous) · padding h 8 · HStack spacing 5
leading glyph 15pt (SF Symbol, weight .regular) or 8pt colour dot
text 13pt, white; weight .semibold when selected, .medium otherwise
background: selected white .20 · unselected white .06 · pressed −30% opacity
```
- Strips with ≤5 items: chips share the width equally (`frame(maxWidth: .infinity)`, `minWidth 0`, `lineLimit(1)`, `minimumScaleFactor(0.85)`), strip padding h 12, spacing 6, **no scrolling**.
- Strips with >5 items: horizontal scroll, natural widths.
- No accent, no edited dot, no border.
- Keep the old `EditorChipButtonStyle` for sheets/sidebar if still used there; name the new one `EditorPanelChipStyle`.

**Swatch strips** (Color Mix bands, Point Color points, mask thumbnails) are the only exception: selected = `ring` (2pt panel-colour gap + 1.5pt white ring); unselected swatch opacity .7. No edited dot.

## 4. Slider (`EditorValueSlider`, inline/phone path only)

- Row: `HStack(spacing: 8)` label (78, 12pt regular, `white .6`, sentence case — drop `.uppercased()` and tracking) · track · value (44, 11.5 monospaced, `white .6`).
- Track: 3pt (neutral `white .14`) or 4pt when `trackGradient` (opacity .8). Centre notch for bipolar stays (1×7, `white .22`).
- Fill: `white .5`, 3pt, from anchor to value, **no shadow**; omit when `trackGradient != nil` (keep `showsTrailOverGradient` trail but white .5, no shadow).
- Cursor: `Circle().fill(.white).frame(18)` + `.shadow(black .55, r 4, y 1)`; offset clamps to `[0, width − 18]` centred on value. Remove `CursorGlow` for the phone path.
- `isActive` must **not** change label/value colour or row background on phone. Gestures unchanged.

## 5. Per-group content

Strip icons are SF Symbols; pick the closest match.

- **Presets:** thumbnails row on top (62pt tiles, selected = ring), then `Amount` row. No strip.
- **Light / Color / Effects / Detail / Optics / Geometry:** rows only, starting at row 1.
- **Curve** (`EditorCurvePanel`): strip `RGB · Red · Green · Blue`, each chip with an 8pt dot (RGB `#E8E8E8`, R `#FF453A`, G `#30D158`, B `#0A84FF`). Rows: `Input`, `Output` (0–255) for the selected point. Remove the Reset button, the hint text and the preset row from the panel (Reset channel → ⋯ menu; presets → ⋯ "Curve presets…").
- **Color Mix:** band swatch strip (8 swatches, 18pt, equal width, ring). **Drop the "All" stop and the edited dots** on phone. Rows: Hue (band hue gradient), Saturation, Luminance.
- **Point Color:**
  - 0 points: no strip; zone shows centred 40pt dark disc (`white .08`, eyedropper glyph white) + text "Tap the photo to pick a color, then adjust only that color" (13pt, `white .55`). Photo is in pick mode. No pill on the photo.
  - ≥1: strip = point swatches (20pt, ring on selected) + trailing eyedropper chip (panel chip style, selected when pick mode armed). Rows: Hue shift, Sat shift, Lum shift, Range.
- **Grade:** strip `Shadows · Midtones · Highlights · Global` with glyphs (half-filled circle / circle with dot / sun / globe). Remove the region tint dot. Rows: Hue (full hue gradient), Saturation, Luminance, Blending, Balance.
- **Crop: keep `EditorCropPanel` as it is** — Rotate / Flip / Reset action row, Straighten, the full scrolling `CropAspect` list, and the footnote all stay, in the same order. Do not move anything to ⋯ and do not drop any aspect. The only changes are the global ones: the ratio chips and action buttons adopt `EditorPanelChipStyle` (§3; selected ratio = white .20, not accent), and Straighten picks up the new slider look (§4). Do not force Crop onto the 40pt grid if it would clip its content.
- **Mask:**
  - 0 masks (or after tapping +): param zone shows header "Choose an area to adjust" (13pt, `white .55`; a ‹ back chip when masks exist) and three 40pt rows of chips, no row labels, each row horizontally scrollable:
    1. Subject · Sky · Background · People/Face (detect)
    2. Brush · Linear · Radial (draw)
    3. Color · Luminance · Depth (range)
    Chips use §3 style with the option's `systemImage`. Disabled options (see `EditorNewMaskOption` availability) render at .35 opacity. Tapping creates the mask immediately — **no sheet**.
  - Detecting: new thumbnail with spinner; rows at `EditorTheme.rowDisabled`; photo shows faint outline.
  - ≥1 mask: strip = mask thumbnails 40×30 (radius 6, red mask preview, ring on selected) · `+` (30×30 panel chip) · mask name (13 semibold, white, truncates) · `⋯` (Rename / Invert / Duplicate / Add / Subtract / Delete). Rows: the mask's Light/Color sliders.
- **Markup:** strip `Pen · Marker · Text · Shape · Sign` with tool icons, label always visible. Rows: Text → Font (40pt row: label + font name in its face + chevron), Size, Color; other tools → Size, Opacity, Color.
  - **Color row:** 6 swatches (white, black, red, yellow, green, blue; 20pt; ring on selected) · 1pt divider · custom swatch (22pt conic hue ring, core = current custom colour).
  - Tapping custom replaces the zone (panel height unchanged) with: header row `‹  Color  [● F2C14E]  eyedropper` · Recent (6 swatches) · Hue / Saturation / Brightness sliders (gradient tracks). ‹ returns.

## 6. Clean-up
- Delete phone-path uses of `EditorTheme.activeRow`, accent value text, accent fill, `CursorGlow`.
- Update DESIGN.md §7 (tier D) with: panel 264/185/40 grid, 22pt top radius, no hairline, one chip style, round thumb, no edited markers, accent only on Save.
- Update `ShotDexUITests/scripts/duo-editor-panel.json` / `ipad-*` snapshots if they assert 246.

## Acceptance
1. Switching between any two groups: slider row 1 y-position identical (±0.5pt) on iPhone 16 Pro.
2. No accent colour anywhere in the panel except Save.
3. All strips ≤5 items fit without scrolling on a 375pt-wide phone. Crop's content and behaviour are unchanged apart from chip and slider styling.
4. Mask tab on a fresh photo shows mask types inline; one tap creates a mask.
5. Markup custom colour picker opens and closes without the panel changing height.
6. Tests green; add layout tests for §1.
