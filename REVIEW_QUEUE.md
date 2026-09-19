# Review queue — 2026-09-19

Produced by `/review-sweep` over the tier-A/B screens and the tier-D tools.
Sources: `hig-components` (two passes), `device-layout` (iPhone 17 + iPad Pro 13").

## Blockers

- [x] `ShotDex/Features/Settings/SettingsScreen.swift:93` — three destructive confirmations used `.confirmationDialog`, which iOS 26 draws as a popover with the Cancel button hidden → `.alert` with an explicit Cancel _(hig-components)_
- [x] `ShotDex/Features/Library/PhotoDetailScreen.swift:831` — `Hide` wrote a one-way change with no confirmation, and the hidden album is unreadable to third-party apps → confirm first, and say Photos is the only way back _(hig-components)_

## Should fix

- [x] `SettingsScreen.swift:284` — `Clear Results` deleted the subject scan with no confirmation _(hig-components)_
- [x] `SettingsSheet.swift` — Settings sheet had no Done button _(hig-components)_
- [x] `SelectionBarViews.swift:169` — Compare and Edit merge into one glass pill on iOS 26 without a `ToolbarSpacer` _(hig-components)_
- [x] `SelectionBarViews.swift:201,227` — Collage and Export EXIF icons drifted from the DESIGN §8 dictionary _(hig-components)_
- [x] `PhotoDetailScreen.swift:690` — "Add to Album" vs "Add to Collection" for the same sheet _(hig-components)_
- [x] `CompareScreen.swift:744` — the card's Delete/Keep target was a caption's glyph box, under 44pt _(hig-components)_
- [x] `CompareSurveyViews.swift:153` — `.combine` swallowed the survey tile's Remove button, leaving VoiceOver no way to press it _(hig-components)_
- [x] `EditorLayoutMetrics.swift:137` — `editorFloatingCommandButtonSize` is 34pt: under the 44pt minimum on the phone, and a stray dot in Video Studio's and Collage's command bands on a 1032pt screen _(device-layout)_
- [x] `VideoStudioToolbar.swift:118` — the nine toolbar cells are 52×52 with 9.5pt labels and clump at the leading edge, leaving ~560pt of the bar empty on iPad _(device-layout)_
- ~~`VideoStudioMetrics.swift:142` — the centred playhead's padding is half the screen width~~ — **struck**: the padding and the playhead are the same number. Capping it moves the playhead off centre, and a timeline you scrub *to the centre* is the model CapCut and Final Cut both use; the empty lead-in at 0s is what that model looks like, not a bug. _(device-layout)_
- [x] `CollageMetrics.swift:17` — the 216pt panel under a ~900pt canvas on iPad → **side inspector, 320pt**, tabs on top, Export pinned bottom _(device-layout)_
- [x] `CollageMetrics.swift:76` — 28pt aspect chips with no extended hit area, where Video Studio's equivalent band already extends its 28pt chips to 44 _(device-layout)_
- [x] `CollageMetrics.swift:81` — 52pt template cells under a canvas seventeen times their area _(device-layout)_

## Nits

- [ ] `VideoStudioMetrics.swift:139` — 20pt lane glyphs in the timeline gutter, decorative but hard to read at iPad distance _(device-layout)_
- [ ] `CollageMetrics.swift:70,72` — the counter (32pt) and Export pill (38pt) are legible but phone-scaled _(device-layout)_
- [x] `PhotoDetailScreen.swift:733` — the Flag or Rate submenu did not mark the state already in effect _(hig-components)_

## Decided (2026-09-19)

- **Collage's panel on iPad** → side inspector, not a scaled-up sheet. Done: 320pt, tabs at the top, Export pinned to the bottom.
- **Video Studio's toolbar** → vertical rail on regular width, not a spread row. Done: 92pt rail, and the 62pt the row cost goes back to the preview.

## Closed by spec.md

- Photo editor on iPad — `device-layout` found no layout problem: the sidebar (`EditorLayoutMetrics.sidebarMinCanvasWidth` 700, width clamped 280…420) is the model the other two tools should follow. spec §10.3 already documents it.
- 40pt icons in the viewer's action bar — DESIGN §6 records the exception.


---

# Sweep 2 — whole app, then editor + Video Studio (2026-09-19)

Agents: `copy-consistency`, `data-migration` (done) · `component-consistency`, `perf-profiler`, `device-layout`, `a11y-voiceover`, `ux-reviewer`, `challenger` (running).

## Blockers

- [x] `Features/Shared/PhotoTileContextMenu.swift:68` + `AddToCollectionSheet.swift:91` — "Add to Album" survived the rename in the tile menu and in the sheet's own error alert, so the same sheet had two names _(copy-consistency)_

## Should fix

- [x] `Data/Database/MetadataStore.swift:113` — `photo_cull` was never pruned: eight deletion paths all call `deleteAssets`, none called the cull store's own prune, so rate → reject → delete left the row and `culledCount()` counted it forever _(data-migration)_
- [x] `Features/Settings/SettingsScreen.swift` — "on the next index run": `IndexPipeline`'s vocabulary on a user-facing alert _(copy-consistency)_
- [x] `Data/Sources/AssetMetadataReader.swift` — Info panel section called "Asset" beside "Camera & Lens", "Exposure", "File" _(copy-consistency)_
- [ ] `Features/Editing/PhotoEditorScreen.swift:165,2146,2153,2215` — four user-facing strings say "asset" instead of "photo", one of them in an alert _(copy-consistency)_ — deferred while the editor agents are still reading the file

- [x] `Features/VideoStudio/VideoStudioScreen.swift` + `Features/Collage/CollageScreen.swift` — the iPad rail and inspector gated on `horizontalSizeClass`, so a ~500pt Split View half got a 92pt rail and a 320pt inspector; now measured on window width like the editor's sidebar _(challenger)_
- [x] `Features/Import/ImportScreen.swift:311` — its own single-tone selection badge instead of the documented white-check-on-accent-disc _(component-consistency)_
- [x] `Features/Albums/CustomizeCollectionsSheet.swift:75` — the one checkmark in the app reading `Color.accentColor`, so it would render system blue among amber _(component-consistency)_
- [x] `Features/Albums/AlbumsScreen.swift:122` + `Features/Library/AdvancedSearchSheet.swift:56` — "New Album" and "Save as Smart Album" wore the add-to-album glyph; creating and adding now have one glyph each _(component-consistency)_
- [x] `Features/Shared/PhotoGridCollectionView.swift:1435` — the aspect grid built a level (a walk of the whole library, ~23ms at 55k) synchronously inside the pinch; the reachable levels are warmed at gesture start _(perf-profiler)_

## Nits

- [ ] `Data/Sources/AssetMetadataReader.swift:210` — "Resource 1 / Resource 2" in the Info panel for what a photographer calls the RAW and the JPEG _(copy-consistency)_
- [ ] `Features/Import/ImportScreen.swift:381` — the import picker says "Add to Album"; its list really is PhotoKit albums, so this may be correct as-is _(copy-consistency)_

## Closed by spec.md

- Compress → Resize: swept and complete everywhere, including the presets screen and spec _(copy-consistency)_
- Migrations v1–v14: clean, additive, never edited after shipping; Clear Index deliberately leaves `photo_cull` alone because asset ids are stable and the culling is user input _(data-migration)_
- `LookPresetStore` and `CollectionPinStore` belong in UserDefaults, not the database: neither is keyed by asset id nor touched by the indexer's row-replace _(data-migration)_

- [ ] `Domain/Grid/GridBadgeCache.swift:24` — unbounded until the next reload; a full scroll during first index can hold ~55k entries _(perf-profiler)_
- [ ] `Features/Settings/CompressionPresetsScreen.swift:44` — "Add Preset" uses bare `plus` where the app's list rows use `plus.circle.fill` _(component-consistency)_
- [ ] `Features/Collage/CollageMetrics.swift:42` — `commandButtonSize` duplicates `EditorLayoutMetrics.editorFloatingCommandButtonSize` with identical values _(component-consistency)_

## Needs a decision (sweep 2)

- **One "leave the tool" control for tier D.** Five variants today: Compare uses `xmark` in a 52pt `.editorGlass` circle; the editor, Collage and Video Studio each hand-roll a chevron at 38/44pt with a raw colour fill; Resize uses a system nav-bar Cancel. The glyph is the real question — chevron reads "back", ✕ reads "leave" — and the tools that can lose unsaved work are not the same as the ones that cannot. My proposal: chevron + `.editorGlass(Circle())` at the shared command size for editor/Collage/Video Studio, ✕ for Compare, and Resize keeps its nav bar because it is the only one that is a form. _(component-consistency, blocker)_
- **The editor sidebar's width picker.** `EditorSidebar.swift:152` claims the ⋯ menu carries the same three widths "for anyone who cannot drag"; it does not — there is no width picker anywhere. Either add three presets to the menu or delete the claim. _(challenger)_

## Sweep 2 — editor and Video Studio (agents: ux-reviewer, a11y-voiceover, device-layout, challenger)

### Blockers

- [x] `Features/Editing/PhotoEditorScreen.swift:126` — the discard guard asked only the photo on screen, so a multi-photo run whose live photo happened to net back to baseline dismissed silently and threw away every parked draft _(ux-reviewer)_
- [x] `Features/VideoStudio/VideoStudioModel.swift:337,807` — clips whose media failed to resolve were dropped from the timeline with no word; the usual cause is an iCloud original that has not arrived _(ux-reviewer)_
- [ ] **Accessibility: four tools cannot be operated without sight** — tone curve, gradient masks, Video Studio overlay placement, and the whole timeline (trim/reorder/scrub). Each needs a real fallback, not a label. → Needs a decision _(a11y-voiceover)_

### Should fix

- [x] `Features/Editing/EditorBatchSaver.swift:89` — Cancel dropped the scrim while the current photo was still being written to the library _(ux-reviewer)_
- [x] `Features/VideoStudio/VideoStudioModel.swift:868,888,977` — filter, per-clip effect and background were not in the undo stack _(ux-reviewer)_
- [x] `Features/Editing/PhotoEditorController.swift:619` — Upright fell back to the *edited* preview when the original render was missing, which is the compounding-correction bug its own comment forbids _(ux-reviewer)_
- [x] `Features/VideoStudio/VideoStudioScreen.swift:282` — the contextual panel covered the new 92pt rail; confirmed on the iPad and now inset past it _(device-layout)_
- [x] `Features/VideoStudio/VideoStudioCommandBand.swift` — the sheet's own command cells stayed 52×54 with 9.5pt labels while the band and rail beside them grew _(device-layout)_
- [ ] `Features/VideoStudio/VideoStudioSheetHost.swift` — every metric in the contextual sheet (264pt height, 36/112pt tiers, 22pt chips, 40pt add button) is phone-only with no regular-width branch _(device-layout)_

### Nits

- [x] `Domain/Editing/LookPresetStore.swift:69` — re-saving a look under the same name kept the old timestamp, so the strip re-ordered itself after relaunch _(ux-reviewer)_
- [x] `Features/Editing/PhotoEditorScreen.swift:607` — Save Look with a cleared name closed the alert as though it had saved _(ux-reviewer)_
- [ ] `Features/Editing/EditorOverlayGuides.swift:207` — the on-canvas move target has no `accessibilityHidden`, so VoiceOver may stop on a blank rectangle _(a11y-voiceover)_
- [ ] Editor Back/Save buttons on the band stay 38/42pt while the circles beside them went to 44 _(device-layout)_

### Needs a decision

- **The accessibility gaps above.** Curve points, gradient-mask placement and Video Studio overlay position all want the same remedy the photo editor already built for text overlays: numeric sliders beside the gesture. That is a panel each. The timeline wants adjustable actions on the selected clip and the timecode. Worth doing, none of it small, and it changes panels you have opinions about — so it waits for you rather than being decided inside a sweep.
- **`device-layout` could not drive the UI.** Subagents have no tap tool in this session, so its report is source-only by its own admission. Either the agent file should say "ask the parent to drive", or the sweep should hand it screenshots. I verified its one testable claim (the panel over the rail) myself and it was right.
