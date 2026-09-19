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

---

# Sweep 3 — compare chrome, the UI driver, Video Studio on iPad (2026-09-20)

Agents: `prior-art`, `challenger`, `ux-reviewer`, plus a pass driven by hand on
the iPhone 17 and the iPad Pro 13" with the new `Tools/ui-drive`.

## Blockers

- [x] `Features/VideoStudio/VideoStudioScreen.swift:416` — `Preparing clips…` had no exit: `fullScreenCover` has no swipe to dismiss and one iCloud original holds the state for minutes, so the only way out was force-quitting _(ux-reviewer)_
- [x] `Features/VideoStudio/VideoStudioModel.swift:1045` — export held no background assertion, so leaving the app mid-run could suspend the writer with the sheet still showing a percentage; the indexer has done this since it shipped _(ux-reviewer)_

## Should fix

- [x] `Features/Library/CompareScreen.swift:597,619` — the compare screen's controls do not say what they do: three bare layout glyphs top right, and a crown between two chevrons underneath. Now a text segmented picker, a 2.5s summary on switch, and Previous · Swap · Keep · Next under their glyphs _(reported from the device)_
- [x] `Features/VideoStudio/VideoStudioScreen.swift:227` — the timeline's content cap only applied above 700pt, so the **phone** drew three lanes at the top of a ~330pt black field, which is the bug the cap was added for _(measured)_
- [x] `Features/VideoStudio/VideoStudioScreen.swift:214` — the preview's aspect-fit height came from the whole window width even where it is drawn in the column beside the 92pt rail _(prior-art, challenger — both, independently)_
- [x] `Features/VideoStudio/VideoStudioMetrics.swift` — 66pt video lane and 54pt clip cells on a 1032pt iPad. `Lanes.compact` / `.regular` (44/104/52, cell 88) chosen on window width, carried by `\.videoLaneMetrics` _(prior-art #1, with the condition `challenger` set: change the constants, not just the cap, and fix the thumbnail request with them)_
- [x] `Features/VideoStudio/VideoTimelineTracks.swift:353` — the filmstrip asked for a flat 240px thumbnail; an 88pt cell at 3x wants 264 _(challenger)_
- [x] `Features/VideoStudio/VideoStudioScreen.swift:505` — deleting an imported music file already on the timeline left the bed drawn and silent in preview and export _(ux-reviewer)_
- [x] `Features/VideoStudio/VideoStudioCommandBand.swift` — `setShowsOriginal` was fully implemented and wired to nothing, so hold-to-see-original (spec §7.9) did not exist _(ux-reviewer)_

## Struck

- ~~`Features/VideoStudio/VideoInspectorControls.swift:238` — three glyph-only alignment buttons~~ — the DESIGN.md rule exempts glyphs whose meaning is fixed outside the app, and left/centre/right alignment is as fixed as bold and italic. The rule is for a tool's *own* verb (promote, survey), not for the three icons every text editor on earth uses. _(ux-reviewer)_
- ~~iPad selection bar controls under 44pt (`Done selecting` 26×36, `Compare` 94×36, `Filter and sort` 31×36)~~ — measured with the new element dump, then checked: these are system navigation-bar items, whose hit area is the height of the bar regardless of the glyph's frame. The dump reports the *visual* frame. `device-layout`'s brief now says so. _(driver dump)_
- ~~The timeline's empty left half at t=0 on iPad~~ — struck again, now with the landscape evidence `challenger` asked for: the playhead is centred by the same model Final Cut and CapCut use, and the lead-in is what that model looks like at zero.

## Needs a decision

- **A persistent inspector for Video Studio at ≥700pt** (`prior-art` #2, `challenger` objection 2). Every tablet NLE docks the inspector beside or above the timeline instead of covering it; ShotDex's editor and Collage already switched at this threshold. But `VideoStudioSheetHost` is a full-bleed horizontal band — a 36pt title row, a 112pt parameter zone built for the width of a phone, and a row of command cells — so making it work in a 300pt column is a rewrite of the panel, not a flag flip. `challenger` also warns this and the lane change spend the same freed pixels, so they must not land together. The lane change has landed; the surplus left in portrait is now about 230pt. Worth doing, and it is your call because it changes a panel you have opinions about.
- **Video Studio in portrait at all.** iPad is not orientation-locked and landscape now looks right (measured, both orientations). If the studio should simply prefer landscape on iPad, that is a smaller change than any inspector work.

## Found by the driver, not yet chased

- [ ] **The Video Studio's accessibility hierarchy cannot be snapshotted on the phone.** XCUITest times out enumerating it — even `app.buttons` never returns — while the same screen on the iPad dumps 172 elements fine. Something on the compact layout keeps the tree from settling (the horizontally scrolling tool row and the timeline's drag zones are the suspects). This is not only a tooling problem: a hierarchy that never settles is what VoiceOver walks too. Worth an `a11y-voiceover` pass aimed at it.

## Still open from sweep 2

- `Features/VideoStudio/VideoStudioSheetHost.swift` — every metric in the contextual sheet is phone-only with no regular-width branch. Overlaps the inspector decision above; do not fix twice.
- `Features/Editing/PhotoEditorScreen.swift:165,2146,2153,2215` — four user-facing strings say "asset" instead of "photo".
- Nits carried over: `AssetMetadataReader.swift:210` "Resource 1 / 2", `ImportScreen.swift:381` "Add to Album", `GridBadgeCache` unbounded, `CompressionPresetsScreen:44` bare `plus`, `CollageMetrics.commandButtonSize` duplicating the editor token, `EditorOverlayGuides.swift:207` missing `accessibilityHidden`, editor Back/Save still 38/42pt, `VideoStudioMetrics.swift:139` 20pt lane glyphs, `CollageMetrics.swift:70,72` phone-scaled counter and Export pill.
