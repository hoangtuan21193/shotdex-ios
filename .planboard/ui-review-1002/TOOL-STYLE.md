# Tier-D tools in the photo editor's panel style (2026-10-03)

User request: Resize, Combine (Focus Stack, HDR, Stack Exposures, Panorama), Collage Export and Video Trim use too much
accent. Make them like the photo editor (FS-03.12 / DESIGN §10.3 "Panel điện thoại của photo editor"): **one accent
control per screen state — the primary save/run action**; chips, sliders, switches and selection outlines use the
editor's white language.

## The one accent
| Screen | Accent control | Look |
|---|---|---|
| Resize | bottom primary "Resize N Photos" / "Save to Photos" | full width, 50pt, r12, fill `#EB9526`, **black** 16pt semibold text + glyph |
| Collage Export | bottom primary "Save to Photos" | same |
| Focus Stack / HDR / Stack Exposures / Panorama | top-bar **Save** | text button, `#EB9526` semibold 17pt (disabled = white 35%) |
| Video Trim | top-bar **Save** | same |
State screens where Save is unavailable (Panorama "This will take a while" → Continue; iCloud failure → Retry) keep one accent capsule (black text) for that state's primary — still one per state.

## Everything else (white language)
- **Chip / segmented choice** (Format, Metadata, Size, Deghost, Method, Mode, Projection): a row 40pt tall; chips 30pt,
  radius 8, gap 8, equal width when ≤ 5; text 13pt white; selected = `rgba(255,255,255,0.20)` + semibold; idle =
  `rgba(255,255,255,0.06)` medium; no border, no accent. Optional 15pt SF glyph 4pt before the title.
- **Preset cards** (Resize sizes): same colours as chips (selected white 20%, idle white 6%), radius 12, no accent border;
  title 15pt white semibold when selected, detail 11pt white 55%.
- **Slider** (Quality, Strength, Radius, Smoothing, Brush, Boundary Warp, Size): one 40pt row — label 78pt wide, 12pt
  white 60%; track 3pt `rgba(255,255,255,0.14)`; anchor notch 1×7 white 22%; round **white knob 18pt**
  with shadow `0 1px 3px rgba(0,0,0,0.4)`; fill white 50% from anchor to knob only when the value is off its default;
  value 44pt wide, 11.5pt monospaced white 60%, right-aligned. No accent, no system slider.
- **Switch** (Delete Originals, Keep EXIF of first photo): 44×26 capsule; on = solid white track + dark knob `#0F1012`
  22pt; off = `rgba(255,255,255,0.14)` track + white knob. Whole row is the target.
- **Text actions** (Retouch, Done, Retry inside a panel, Arrange / Done Arranging): white 13pt semibold, min 44pt target.
  Active toggle-like state (Arranging) = white text on chip-selected background, not accent.
- **Selection outline** on a thumbnail (Focus Stack frame picked, Auto): 2pt white; the frame Auto picked = 2pt white 55%.
- **Trim handles and window** (Video Trim): white handles + 3pt white border, dimmed outside; playhead white.
- **Progress** (spinners, bars inside overlays): white.
- **Paint overlay** (Focus Stack retouch): the editor's red mask overlay colour, not accent.
- Panel background `#0F1012`, hairline `rgba(255,255,255,0.10)`, group labels 11.5pt bold white 55% uppercase.

## The primary button lives top right (approved 2026-10-03)
One component on every tier-D tool screen — photo editor, Focus Stack, HDR, Stack Exposures, Panorama, Video Trim, Collage,
Collage Export, Resize:
- **Place**: right end of the top band, same vertical centre as the band's other buttons; right margin 20 (16 on Duo cover
  inside x 0–382). Top-left is always Cancel / Back. Undo · Redo, when the screen has them, sit just right of Back.
- **Shape**: capsule, height **34** on compact (iPhone, Duo cover) / **44** on regular (iPad, Duo inner); horizontal padding
  14 / 18; fill accent `#EB9526`; label short verb **Save · Export · Resize**, 15pt (17pt regular) semibold, **black**.
  Disabled: fill `rgba(255,255,255,0.12)`, label white 35%. No glyph inside (the verb is the label).
- **No bottom primary** anywhere on these screens; the space goes back to the panel / preview.
- **Consequences are a line, not the button**: e.g. Resize puts "8 originals go to Recently Deleted after saving" as the
  first line of its options (12pt, white 60%, trash glyph 12pt) when Delete Originals is on; Collage Export keeps
  "Added to your ShotDex Collages album" as a caption line.
- Not for tier-A system sheets (their confirm is already the nav bar's trailing item) and not for Onboarding's Continue.
