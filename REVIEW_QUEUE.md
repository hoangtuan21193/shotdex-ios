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

- [x] ~~`VideoStudioMetrics.swift:139` — 20pt lane glyphs in the timeline gutter~~ — done 2026-09-20: the glyph box and symbol follow the lane tier (20/13 compact, 26/16 regular) and the column centres the whole glyph-plus-name stack on the lane. Screenshotted on iPad Pro 13" and iPhone 17.
- [x] ~~`CollageMetrics.swift:70,72` — the counter (32pt) and Export pill (38pt) are phone-scaled~~ — done 2026-09-20: 44 and 48 at regular width, and the compact counter's step buttons reach 44 through the hit shape.
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
- [x] ~~`Features/Editing/PhotoEditorScreen.swift:165,2146,2153,2215` — four user-facing strings say "asset"~~ — re-checked 2026-09-20: no user-facing "asset" is left in that file, or anywhere else in the app. Fixed by an earlier commit in the editor batch.

- [x] `Features/VideoStudio/VideoStudioScreen.swift` + `Features/Collage/CollageScreen.swift` — the iPad rail and inspector gated on `horizontalSizeClass`, so a ~500pt Split View half got a 92pt rail and a 320pt inspector; now measured on window width like the editor's sidebar _(challenger)_
- [x] `Features/Import/ImportScreen.swift:311` — its own single-tone selection badge instead of the documented white-check-on-accent-disc _(component-consistency)_
- [x] `Features/Albums/CustomizeCollectionsSheet.swift:75` — the one checkmark in the app reading `Color.accentColor`, so it would render system blue among amber _(component-consistency)_
- [x] `Features/Albums/AlbumsScreen.swift:122` + `Features/Library/AdvancedSearchSheet.swift:56` — "New Album" and "Save as Smart Album" wore the add-to-album glyph; creating and adding now have one glyph each _(component-consistency)_
- [x] `Features/Shared/PhotoGridCollectionView.swift:1435` — the aspect grid built a level (a walk of the whole library, ~23ms at 55k) synchronously inside the pinch; the reachable levels are warmed at gesture start _(perf-profiler)_

## Nits

- [x] ~~`Data/Sources/AssetMetadataReader.swift:210` — "Resource 1 / Resource 2"~~ — done: `resourceHeading` names each section by format (`RAW`, `HEIC`, `Paired Video · MOV`) and only appends an index when two headings would collide.
- [x] ~~`Features/Import/ImportScreen.swift:381` — the import picker says "Add to Album"~~ — correct as-is; its list is PhotoKit user albums. But it points at a real split, now under Needs a decision below.

## Closed by spec.md

- Compress → Resize: swept and complete everywhere, including the presets screen and spec _(copy-consistency)_
- Migrations v1–v14: clean, additive, never edited after shipping; Clear Index deliberately leaves `photo_cull` alone because asset ids are stable and the culling is user input _(data-migration)_
- `LookPresetStore` and `CollectionPinStore` belong in UserDefaults, not the database: neither is keyed by asset id nor touched by the indexer's row-replace _(data-migration)_

- [x] `Domain/Grid/GridBadgeCache.swift:24` — unbounded until the next reload; a full scroll during first index can hold ~55k entries _(perf-profiler)_
- [x] `Features/Settings/CompressionPresetsScreen.swift:44` — "Add Preset" uses bare `plus` where the app's list rows use `plus.circle.fill` _(component-consistency)_
- [x] `Features/Collage/CollageMetrics.swift:42` — `commandButtonSize` duplicates `EditorLayoutMetrics.editorFloatingCommandButtonSize` with identical values _(component-consistency)_

## Needs a decision (sweep 2)

- **One "leave the tool" control for tier D.** Five variants today: Compare uses `xmark` in a 52pt `.editorGlass` circle; the editor, Collage and Video Studio each hand-roll a chevron at 38/44pt with a raw colour fill; Resize uses a system nav-bar Cancel. The glyph is the real question — chevron reads "back", ✕ reads "leave" — and the tools that can lose unsaved work are not the same as the ones that cannot. My proposal: chevron + `.editorGlass(Circle())` at the shared command size for editor/Collage/Video Studio, ✕ for Compare, and Resize keeps its nav bar because it is the only one that is a form. _(component-consistency, blocker)_
- [x] ~~**The editor sidebar's width picker.**~~ — **decided 2026-09-20: delete the claim.** There is no ⋯ width picker and never was, but the handle already carries an `accessibilityAdjustableAction` that moves it 40pt a step, which is the route the comment was worried about. The comment says that now, and says what it used to claim.

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
- [x] ~~`Features/VideoStudio/VideoStudioSheetHost.swift` — every metric in the contextual sheet is phone-only~~ — partly struck, partly fixed 2026-09-20. The sheet becomes a fixed 320pt column at regular width, so its heights are not "phone-scaled" — the column is narrow on both. What *was* wrong is the touch targets: the typeface button (40) and Bold/Italic toggles (36) now reach 44 through the hit shape. The 22pt badge is decorative, not a control.

### Nits

- [x] `Domain/Editing/LookPresetStore.swift:69` — re-saving a look under the same name kept the old timestamp, so the strip re-ordered itself after relaunch _(ux-reviewer)_
- [x] `Features/Editing/PhotoEditorScreen.swift:607` — Save Look with a cleared name closed the alert as though it had saved _(ux-reviewer)_
- [x] `Features/Editing/EditorOverlayGuides.swift:207` — the on-canvas move target has no `accessibilityHidden`, so VoiceOver may stop on a blank rectangle _(a11y-voiceover)_
- [x] ~~Editor Back/Save buttons on the band stay 38/42pt~~ — done 2026-09-20: both take the band's own size at regular width, and the row's height follows it instead of being pinned to 42.

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

- [x] **Docked contextual panel, taken out of the surplus** (2026-09-20). With landscape-locking ruled out, the portrait surplus had to be spent. `challenger`'s objection to the side-inspector plan was that `VideoStudioSheetHost` is a full-bleed *horizontal* band and squeezing it into a 300pt column is a rewrite — so it is docked full width under the timeline instead, where that shape is already right. It only docks where the frame keeps its natural size afterwards, so the phone and landscape iPad are untouched. Measured on the iPad: nothing covered, timeline does not move.

- **A side inspector for Video Studio at ≥700pt, beyond the docked panel** (`prior-art` #2, `challenger` objection 2). Every tablet NLE docks the inspector beside or above the timeline instead of covering it; ShotDex's editor and Collage already switched at this threshold. But `VideoStudioSheetHost` is a full-bleed horizontal band — a 36pt title row, a 112pt parameter zone built for the width of a phone, and a row of command cells — so making it work in a 300pt column is a rewrite of the panel, not a flag flip. `challenger` also warns this and the lane change spend the same freed pixels, so they must not land together. The lane change has landed; the surplus left in portrait is now about 230pt. Worth doing, and it is your call because it changes a panel you have opinions about.
- ~~**Video Studio in portrait at all.**~~ — **decided 2026-09-20: do not lock landscape.** Portrait has to work, so the surplus it produces has to be given something to do rather than designed around.

## Found by the driver, not yet chased

- [ ] **The Video Studio's accessibility hierarchy cannot be snapshotted on the phone.** XCUITest times out enumerating it — even `app.buttons` never returns — while the same screen on the iPad dumps fine.
  **Measured 2026-09-20, and the original theory is wrong.** Reproduced on iPhone 17 / iOS 26.5: the run reaches the screenshot step and then hangs on the first `dump`. But `sample` on the app while it sits on that screen shows the **main thread completely idle** — 2295 of 2295 samples in `mach_msg2_trap` on the run loop. Nothing is spinning, so "a hierarchy that never settles" is not what is happening, and the VoiceOver worry the item raised is not supported by anything measured.
  What is left is the driver: `tree()` reads `label`, `identifier`, `value`, `isEnabled`, `isSelected` and `isHittable` off every element, and each of those is its own round trip into the app — `isHittable` the most expensive of them. The next step is a tool change (read fewer properties, bound the element count, make `isHittable` opt-in), not an app change. Re-file under the driver, not under accessibility.

## Still open from sweep 2

- `Features/VideoStudio/VideoStudioSheetHost.swift` — every metric in the contextual sheet is phone-only with no regular-width branch. Overlaps the inspector decision above; do not fix twice.
- `Features/Editing/PhotoEditorScreen.swift:165,2146,2153,2215` — four user-facing strings say "asset" instead of "photo".
- Nits carried over: `AssetMetadataReader.swift:210` "Resource 1 / 2", `ImportScreen.swift:381` "Add to Album", `GridBadgeCache` unbounded, `CompressionPresetsScreen:44` bare `plus`, `CollageMetrics.commandButtonSize` duplicating the editor token, `EditorOverlayGuides.swift:207` missing `accessibilityHidden`, editor Back/Save still 38/42pt, `VideoStudioMetrics.swift:139` 20pt lane glyphs, `CollageMetrics.swift:70,72` phone-scaled counter and Export pill.


---

# Sweep 4 — Video Studio on iPad and the Duo (2026-09-20)

Agent: `video-nle-survey` (new), against Final Cut Pro for iPad, LumaFusion,
CapCut iPad, iMovie, Videoleap, Premiere Rush and DaVinci Resolve for iPad.
Its arithmetic reproduced the measured layout exactly, so its build order was
taken as given and worked top-down.

## Done

- [x] **The frame had no edge.** The compositor letterboxes onto the project background — black — and the stage behind it is black, so a 3:2 photo in a 16:9 project looked like a 3:2 project. 1pt hairline on `contentRect`. This was most of why the surrounding black read as a bug.
- [x] **Export was at the bottom, where the panel covered it.** Back · read-out · Export move into the top band at rail width and the bottom band is not drawn; its 50pt goes back to the preview. Every tablet editor surveyed puts the primary action in the top bar, and spec §7.9 already described a top-band read-out that was never built.
- [x] **The timeline was 7pt short of its own lanes on every regular-width window** — the preview's clamp reserved the phone's 248 floor against 255 of regular lanes. And `Lanes.for(size:)` now needs 750pt of height as well as 700 of width: the Duo's inner display is 867×669, where regular lanes pushed the preview to its floor.
- [x] **The inspector stands beside the stage on a wide window** — 320pt trailing column when width > height, bottom dock when height is the spare dimension, band on the phone. +67% frame area in iPad landscape, +190% on the Duo inner.

## Struck

- ~~"The timeline clamps at three lanes."~~ — it already reserves what the project's own lane counts need (`timelineContentHeight(overlayLanes:musicLanes:)` is called with the live counts). The real defect was the 248-vs-255 clamp, which is fixed.

## Open

- [x] **64pt track headers at regular width.** The gutter is 30pt, `allowsHitTesting(false)`, 13pt glyphs, no name and no controls; LumaFusion's carries lock, meters, levels and visibility. Costs 34pt of row width out of 1284.
- [x] **A resize handle on the timeline divider**, persisted. Final Cut publishes one and CapCut Pad has resizable panels. spec §7.9's rule is about what the app does *unasked*; it does not say the user may not ask.
- [x] **Keyboard shortcuts.** The whole feature has no `keyboardShortcut`, no `contextMenu` and no hover, while DESIGN.md §10.3 records all three as settled for the photo editor. Space / ← / → / ⌘Z / ⌘E are the universal bindings and cost no screen space.
- [x] **The Duo cover display should stop pretending to be an editor.** Measured at 382×644 in a prior session: every band is at its floor before the user touches anything, and the first selection puts all three regions below their minimums. The survey's proposal is viewer + transport + a video-lane-only filmstrip, with "Unfold to edit" on any editing tap; Export still works. Needs a decision, and needs the Duo photographed first — no run has reached the Video Studio on it yet.

## Corrected after measuring

- The survey's **Duo inner-display case cannot occur.** It computed from an 867×669 landscape scene; the iPhone target is portrait-locked, so the app's scene there is **669×951**, compact, phone layout — frame 669×376, timeline 248, nothing near a floor. The inspector-column rule it proposed stands on its own merits; that example of it was wrong, and the test now says so.
- The **cover display's numbers were right**: 382×644, and opening the panel put the preview on its 150pt floor with the timeline 108pt under its own. Fixed by standing the timeline down, gated at 660pt of height so an iPhone SE (667) keeps its timeline.
- **Hover** was dropped from the shortcuts item: there is no pointer affordance to add to a timeline whose drags are already routed through UIKit, and inventing one without a device to test it on is guessing.
- **Per-lane controls were left off the track headers** deliberately. LumaFusion's carry lock, meters, levels and visibility; ShotDex has no model state for any of those per lane, and one invented state is worse than a legible label. The header names the lane and stays non-interactive.

## Still not photographed

- **The iPhone Duo.** The driver reaches the Video Studio there — every step of the script succeeds — but no screenshot path works: `XCUIScreen.main` is the display the system calls main, which on a Duo is the one switched off, and `app.screenshot()` comes back black too. A host-side `simctl io` burst catches the home screen either side of the run but not the app. Everything reported for the Duo is computed from the pure metrics against scene sizes the driver confirmed (inner 669×951, cover 382×644 from a prior session).

## Not verified on hardware

The Duo numbers throughout are computed from `stackLayout` against confirmed
scene sizes (inner 867×669 re-measured today; cover 382×644 from a prior
session), not photographed: the drive script's tap fractions do not land on
the Duo's inner-display grid and the run never reached the studio. A
Duo-specific script with label-based taps is the fix, and belongs with the
cover-display item above.


## Sweep 5, second pass (2026-09-20)

- [x] **The editor's three sidebar keys are scene-local**, like the Video Studio's divider — an `@AppStorage` binding resized the other window's canvas mid-edit.
- [x] **Collage's drag out carries the photo**, not the asset id as plain text: the tray hands out a `PhotoDragItem` provider, and the cell drop reads ShotDex's private identifier type.
- [x] **Pointer affordance** where a control is drawn rather than composed: library grid tiles, the tone curve, the colour wheel. Collage's seam handles and command buttons landed in the first pass.
- [x] **Esc leaves selection mode.**
- [x] **The timeline's lead-in is no longer empty** (see above).

## Needs a decision

- **Should a photo dragged in from another app be imported?** Collage and the Video Studio both work from PHAsset ids, so accepting an image from Photos in Split View or from Files means writing it into the user's library first. That is an import with a real side effect, not a layout fix.

## Still open

- [x] **The Video Studio accepts drops** — media dropped on the timeline appends to it, importing first when it came from another app.
- [x] **Apple Pencil pressure and double-tap.** Pressure varies the stroke width (`BrushStroke.pressures`, additive and back-compatible); double-tap swaps brush and eraser, honouring the system preference. Not verifiable in the simulator — no Pencil to press — so it is covered by tests and wants a look on a real iPad. Old note:  `EditorPaintTouchLayer` reads raw `UITouch` with no `.force`, so flow is uniform, and there is no double-tap tool switch. Carrying pressure means threading it through the touch arbiter and into ShotDexKit's brush rasterizer — a real change through the render core, not a modifier.
- [x] **`EditorPaintTouchLayer` has a pointer shaped like the brush** — a ring at `brushCursorDiameter`, only while a brush is selected. A highlight would have lit up the photo being painted; what a trackpad user needs is the brush's size before they press. `EditorMaskGuides`' handles are composed views and take the system pointer as they are.
- [x] Info panel per-file headings — **photographed**: Show All Raw Metadata on a Live Photo now reads `HEIC` and `Paired Video · MOV` where it used to say `Resource 1` and `Resource 2`. (They sit near the top of that sheet, not the bottom, which is why three earlier attempts scrolling down missed them.)


---

# Sweep 6 — Swift concurrency (2026-09-20)

Agent: `swift-concurrency`, pointed at the code written in the last hour plus
the long-running hot spots. All four findings were in the new code.

- [x] **Collage's and the Video Studio's cross-app drop fired untracked tasks.** Leaving the tool mid-import kept writing to the user's library and then updated a model nobody was looking at — in the studio's case after `close()` had torn down the player. Both are held and cancelled now, and check `Task.isCancelled` before touching the model.
- [x] **`PhotoDropImport`'s continuation ignored cancellation** — it keeps the `Progress` and cancels it from `withTaskCancellationHandler`.
- [x] **The export pump hopped to the main actor once per sample buffer** — thirty times a second for the length of the video, to report a fraction finer than the bar can draw. Once per percent now.

Read and found sound, recorded so the next pass does not redo it: `IndexPipeline`
(cancellation at every batch, no reentrancy window), `PhotoLibraryService` (every
PhotoKit completion either fires once or is documented as `.opportunistic` and
hopped per call; `photoLibraryDidChange` hops before touching state),
`BackgroundIndexService` (no `self` captured from the registration closure),
`VideoExportWriter`'s continuation (single `DispatchGroup.notify`, every branch
returns after resume), and the GRDB call sites.


---

# Sweep 7 — memory and caches (2026-09-20)

Agent: `memory-leak`, pointed at the two caches I added today plus the
long-standing surfaces.

- [x] **The photo-editing extension accepted recipes it cannot render.** `canHandle` checked the format identifier only, so a photo edited in the full app with a mask, a Markup drawing or a text overlay could be continued in ShotDexEdit — where each of those rasterizes a full-extent bitmap (~195MB of RGBA at 48MP for one layer) in a process with a fraction of an app's memory. It declines them now, so Photos offers Revert and the photo opens in the full app with its edit intact.
- [x] **Scratch directories outlived the app.** Swept at launch, the one moment nothing can be using them, and tested to leave everything else in `/tmp` alone.
- [x] **The prewarm task could refill a released cache.** Cancelled on disappear, and it checks cancellation before inserting.
- [x] **A freeze clip held a full-native-resolution decoded frame for the session** — ~33MB per clip from a 4K source, when the composition renders into the project canvas anyway. Extracted at canvas size now.

Read and found sound: `GridBadgeCache` (the cap and eviction are right, and
`order` stays in step with `entries` because an existing key does not
re-append), `PhotoDropImport`'s `defer` (runs on every path including
cancellation), `PhotoGridCollectionView` cell reuse (both the thumbnail
request and the metadata task are cancelled, and the task re-checks the
cell's asset id), `PhotoLibraryService`'s three `NSCache`s (all capped, the
change observer unregistered in `deinit`), and `PhotoEditHistory` (value
structs, capped at 100).

## Still open

- [ ] The extension blocker's **other** half: the full app renders those same
  full-extent layers monolithically too. It has the memory to survive it
  today, but a 48MP RAW with several mask components is close to the edge,
  and the honest fix is a tiled `CIContext` render rather than one
  `CGContext` the size of the image. Needs Instruments on a real device with
  a real 48MP file before anyone decides how much work it is worth.


---

# Sweep 8 — privacy manifests and the extension boundary (2026-09-20)

Agents: `privacy-manifest`, `extension-boundary`.

- [x] **No `PrivacyInfo.xcprivacy` existed in the repository**, for any of the five targets — a submission blocker, and the app does use a required-reason API. App: UserDefaults `CA92.1`, File Timestamp `C617.1` + `3B52.1`. The other four: empty declarations. Verified in the built product.
- [x] **The photo usage string described an app that only reads.** It also writes edits, favourites, albums, duplicates and videos. No key was missing — the sentence was.
- [x] **ShotDexShare declared an App Group it never touches.** Removed.
- [x] **The extension held the whole compressed file in memory to write it** — `writeJPEGRepresentation(of:to:)` streams it instead.
- [x] **`needsFullExtentLayers` over-declined**, counting hidden masks and empty captions that the renderer skips anyway.

Checked and found clean: the kit's public surface (everything newly public has a cross-module caller), kit purity for today's additions, `BrushStroke`'s hand-written decoder against its synthesized encoder (round-trips, and a pre-pressure recipe still decodes), and forbidden reach from all three extensions.

## Still open

- [ ] **The extension renders the base pipeline at full resolution even for a plain slider edit.** `EditExtensionModel.renderOutput` calls `render(source:recipe:)` with no bound: a 48MP source is ~195MB of RGBA before Core Image's own working space, against an extension's ceiling. Streaming the write helps the tail, not the peak. The honest fix is a tiled render, and it wants Instruments on a real device with a real 48MP file first — the same measurement the app-side blocker below needs.
- [ ] **The full app renders full-extent mask/drawing/overlay layers monolithically too.** It has the memory to survive today; a 48MP RAW with several mask components is close to the edge.
- [x] ~~`ShotDexKit/Render/PhotoRenderService+Drawing.swift` imports `PencilKit`~~ — struck 2026-09-20. The rule the kit actually carries is "no SwiftUI, no GRDB" (CLAUDE.md). PencilKit here is `PKDrawing(data:)` and `PKDrawing.image(from:scale:)` — a model type and a rasterizer, both available to app extensions, and the kit's whole job is rasterizing a recipe. Nothing to remove.
- [x] **Reverse geocoding sends photo coordinates to Apple's geocoder** — and the photo-library permission string said "Nothing leaves your device." Fixed 2026-09-20: the string now says the photos stay put and a rounded location goes to Apple's map service. No manifest change (platform service, and CoreLocation is not a required-reason API). **Still to do at submission:** answer Location in the App Store Connect questionnaire as used-but-not-linked, not for tracking. Only the `PlaceCellKey` cell centre is ever sent (0.001 degrees, ~110 m), never the photo's own coordinate.


---

# Sweep 9 — DESIGN.md compliance on today's chrome (2026-09-20)

Agent: `design-reviewer`. It confirmed the three rules written into
`DESIGN.md` today match what the code does — including the sub-clause about a
filmstrip requesting its thumbnail at the cell's own pixel size — and then
found where I worked from taste instead of tokens.

- [x] **Three hand-picked faint whites.** `0.04` for the empty lane rail, `0.12` for the ruler baseline, `0.08` for the timecode pill — and the same values already retyped at six more sites. Now `EditorTheme.emptyLane` / `trackBorder` / `trackChip`, with the reasoning for each in the token, and `DESIGN.md` says to name rather than pick.
- [x] **Back changed material when the window crossed 700pt** — a flat `0.08` disc in the bottom bar, `.editorGlass` in the top band, and widening an iPad window moves the button from one to the other. Both glass now, and the "one action, one place" principle in `DESIGN.md` extends to "and one material".
- [x] **The centre play button was a hand-rolled colour plus `.ultraThinMaterial`** — a system material in tier D, which §9 permits through three entry points, none of them this. `.editorGlass(Circle())`, checked on screen. (It dated from the feature's first commit, not from a deliberate move away from glass — I checked the history before changing it.)
- [x] `spacing: 5`, `padding(.horizontal, 14)`, and a `size: 11` font that was a near-copy of `EditorTheme.rowValue`. On the scale, and on the token.
- [x] `topBandHeight`'s `max(66, safeTop + 18)` — derived from the button and its inset now, so it follows them instead of drifting.

Read and found compliant: `ToolChromeEnvironment`, the hover additions in the
editor and Collage, the `UIPointerInteraction` ring, Collage's height gate,
the canvas-edge hairline, and the sizing constants in `VideoStudioMetrics`
(the per-feature metrics file is the sanctioned home for them).

---

# Sweep 10 — parity nits and the strings behind them (2026-09-20)

Closing out `ios26-parity`, `copy-consistency` and `localization` leftovers.

## Done

- [x] Five screens each carried their own `#available(iOS 26.0)` branch for the
  bottom chrome clearance, four saying 100 and `DuplicatesScreen` saying 90 with
  no reason. One token now: `AppTheme.Size.bottomChromeClearance`, documented in
  `DESIGN.md` §6. Screenshotted on iOS 18.6 — Duplicates still clears the tab bar
  with the extra 10pt.
- [x] The two 54pt chip rows in `VideoInspectorControls` clipped a label longer
  than English; `.minimumScaleFactor(0.7)`, same as the command cells.
- [x] `NSPhotoLibraryUsageDescription` no longer claims nothing leaves the device.
- [x] The new-album alert built its plural with a ternary; one catalogue key with
  `one`/`other` now. Verified on device: singular reads "This photo will be
  added to the new album."

## Struck

- [x] ~~A second `More` accessibility node beside `More selection actions`~~ —
  driven and dumped on iOS 26.5. The extra node is the `Image(systemName:
  "ellipsis")` inside the `Menu` label: `hittable: false`, 4.3pt tall, i.e. an
  XCUITest-tree artifact, not something VoiceOver reaches — SwiftUI combines a
  button's label content. The same dump shows one `circle` image node per grid
  cell for the same reason, and the cell sets `isAccessibilityElement = true`,
  so VoiceOver reads the cell alone. Nothing to fix; worth remembering when
  reading a dump, because these nodes look like findings.

## Needs a decision

- [x] ~~**Is the destination an Album or a Collection?**~~ — **decided
  2026-09-20 by the user: it stays "Collection"** ("để nguyên là collection").
  The rename I had staged was reverted before it shipped. `spec.md` §391 and
  `DESIGN.md` §269 already said so and stand. The split inside the sheet
  ("Your Albums", "New Album…") is the accepted cost.

## Sweep 10, continued — the device-layout leftovers (2026-09-20)

All four `device-layout` items above are closed, each verified on the device
it was reported against rather than on the build alone. What is left in this
file is the list below, and none of it is a layout number:

- the four tools with no sightless path (**Needs a decision**),
- the two tiled-render items, which want Instruments on real hardware,
- the Video Studio's accessibility tree not settling at compact width,
- Album vs Collection (**Needs a decision**).

---

# Sweep 11 — the Collections tab rework (2026-09-20)

Not an agent sweep: a run of user-directed changes to the Collections tab,
landed across `fa80a2d`, `c093a2d` and the two commits before them. Listed
here so the next sweep knows what is new and what was deliberately decided.

## Landed

- [x] Album groups browse by **cover tile** (112 compact / 168 regular) instead
  of a 60pt settings-style row. Four near-identical token structs collapsed
  into `AlbumCoverTile` + `AlbumCoverWell`.
- [x] **Media Types and Utilities** are one-line cards, 190/240 wide, packed up
  to three rows and scrolled sideways. Row count follows how many cards fit
  (two on a phone, four on a 13" iPad), not a hardcoded three.
- [x] **Folders removed** — the section, the model, and six PhotoKit calls.
- [x] **Recents removed**; On This Day is a full-width hero at 180/260.
- [x] **Creations** split into `Collages` and `Video Projects`, always present,
  each also the place a new one starts.
- [x] Recipes are Codable and live in a `creations` table, so a collage or
  video reopens in the editor that made it.

## Deliberate, do not "fix"

- "Add to Collection" is the user's chosen wording. See above.
- The Utilities row for made videos is "Video Projects" because Media Types
  already has a PhotoKit-named "Videos".
- Cover tiles growing at regular width is a written exception to
  `DESIGN.md` §10.1c, argued in §10.1d.

## Open

- [ ] **Recently Deleted cannot be built.** No `PHAssetCollectionSubtype` for
  it at all (iOS 26.1 SDK), and no public URL that opens Photos on it. Asked
  for, and the answer is the platform's.
- [x] Reviewed by `a11y-voiceover`, `copy-consistency` and `design-reviewer`.
  Everything they raised is applied (`ffaebcf` and the commit after it):
  the "Collages" name collision, accent used where DESIGN.md wants state,
  "Remove from Creations" and the two dead-end alerts, a spoken "Video"
  that reopened the ambiguity the row name exists to prevent, 6pt spacing
  and five other literal spacings, §10.1d not being able to tell
  `AlbumCoverTile` from `MemoryCard`, §13 naming a deleted type, the hero's
  spoken label dropping its date, and `CollectionListRow` scaling on
  `.body` while its text is `.subheadline`.
  Two notes from those runs worth keeping:
  - `a11y-voiceover` could not get PhotoKit to report `.authorized` on the
    iOS 26 phone simulator at all — `simctl privacy grant` plus a TCC reset
    still left "No Access to Photos" with `auth_value=2` in the database. So
    its Dynamic Type conclusions are read from the `@ScaledMetric`
    declarations, not from a screenshot, and it said so.
  - The `MemoryCard` inconsistency was the useful finding: it showed the
    rule, not the code, was the thing that was wrong.

## Cover tile — the two paths the first commit could not show (2026-09-20)

`f0abd3f` said plainly that two paths were code rather than screenshots.
Both are verified now, on iPhone 16 Pro / iOS 18.6:

- **Scrim off over a dark cover.** Added a deliberately dark PNG to that
  simulator with `simctl addmedia` so it became the newest photo and so the
  Recently Added cover; the tile draws no gradient and the white name is
  readable on the shadow alone.
- **A name on two lines.** Made an album called "Iceland Winter Road Trip"
  through the app's own Add to Collection → New Album flow; it wraps to two
  lines inside the tile, over a bright cover with the scrim on.

Both left behind on that simulator on purpose — they are the only fixtures
there that exercise either path. The dark PNG also shows up in the library
grid as a near-black frame; that is the fixture, not a bug.


## Sweep 2026-09-22 — tìm thấy trong lúc `/plan FS-03.09` task 0

- [ ] **Deep link tới một ảnh không có trong lưới thất bại lặng lẽ.**
  [`LibraryScreen.swift:319`](ShotDex/Features/Library/LibraryScreen.swift:319) — `openSavedPhoto` dò
  **25 lần × 0,12s = 3 giây** tìm asset trong lưới, không thấy thì `return`, không nói gì. Người dùng chạm
  widget (hoặc kết quả Spotlight), app mở ra tab Library và **không có gì xảy ra**: không lỗi, không lý do,
  không lối đi tiếp. Ba đường dẫn tới đây đều có thật: quyền `.limited` mà ảnh nằm ngoài tập được chọn, ảnh
  đã xoá kể từ lúc widget chụp snapshot, và bộ lọc/sắp xếp hiện tại loại ảnh đó khỏi lưới. Action extension
  *Edit in ShotDex* ([EX-05](docs/03-extensions-and-integrations/EX-05-edit-action-extension.md)) sẽ là
  đường thứ tư và là đường hay trượt nhất, vì nó **dò ngược** ra assetId.
  Cần: sau khi hết vòng dò thì nói rõ vì sao và cho một lối đi (bỏ lọc, hoặc mở Manage của limited access).
  _(phát hiện khi đối chiếu AC-15; là lỗi có sẵn, không do FS-03.09 đẻ ra)_

- [ ] **Eval `040-spec-before-code` nhiễu ~50% ngay cả khi không đổi gì.** Đo 2026-09-23: không có dòng mới
  trong `CLAUDE.md` thì trượt 2/4 lần, có thì 1/3. Lần trượt, model hỏi lại phạm vi (theo luật "yêu cầu mơ
  hồ thì hỏi lại") mà không nhắc `intent`/`/spec` — hai luật cùng đúng đánh nhau trong một prompt. Hoặc làm
  prompt của eval bớt mơ hồ, hoặc cho `checks` chấp nhận "hỏi lại phạm vi" là một cách đi qua giai đoạn Plan.
  _(tìm thấy khi chạy `Tools/evals` sau lần sửa `CLAUDE.md` của task 0b)_

## Sweep 2026-09-23 — tìm thấy trong lúc làm FS-03.11 tasks 2–13

- [x] ~~**iPad 18.6 / Duo 27.1: mở sheet New Mask thì ảnh phía sau phóng to (~2×)**~~ — **không phải lỗi**
  (kiểm lại 2026-09-23). Cắt cùng một vùng ảnh ở khung trước và sau khi mở sheet, full-res qua
  `Tools/sim-shot`: trùng khít từng pixel, cả iPad Pro 11 (M4) 18.6 (`ipad-newmask-zoom.json`, ảnh chân dung
  CC0) lẫn Duo inner 27.1 (`duo-newmask.json`) — chỉ khác lớp dim của sheet. Báo cáo cũ đến từ việc so ảnh
  thu nhỏ: sheet che nửa dưới và làm tối, nên phần trên trông như to ra.
- [x] ~~**`Tools/ui-drive`: `tap` "Cancel" khi sheet đang mở**~~ — sửa 2026-09-23. Nút Cancel của thanh commit, nằm
  dưới lớp dim, đứng **trước** Cancel của sheet trong cây phần tử (dump trên Duo: `hittable` false ở (729,595)
  rồi true ở (169,298)). Driver lấy phần tử đầu tiên, nên trên Duo 27.1 tap rơi vào lớp dim và không có gì xảy ra,
  còn trên iPad 18.6 thì chờ hittable mãi. Giờ một nhãn khớp nhiều phần tử mà script không ghi `index` thì driver
  lấy phần tử **hittable** đầu tiên (xét tối đa 8). Đã kiểm: `ipad-newmask-zoom.json` trên iPad 18.6 đóng sheet
  và vẫn ở chặng Mask; `duo-newmask.json` trên Duo đóng sheet (dump sau Cancel không còn các dòng của sheet).
- [ ] **`Tools/ui-drive` trên iPad 18.6 kẹt ở bước `dump` màn Presets** (cây phần tử lớn — 49 thẻ film look có
  ảnh). Không có timeout, lượt chạy bị cắt ở mốc 10 phút của Bash và chồng lên lượt sau. Cần timeout cho từng
  bước.

## FS-14 sweep (2026-09-23)

- `CLAUDE.md:82` says the widget and share extension link `ShotDexKit`. `ShotDex.xcodeproj/project.pbxproj`
  shows only the app and `ShotDexTests` link it. One of the two is wrong; fix whichever it is.
- `PhotoStackScreen.save()` (`ShotDex/Features/Editing/PhotoStackScreen.swift:210`) saves the new asset
  and dismisses, without `indexPipeline.indexSingle(assetId:)` or `photoLibrary.publishAppCreatedAsset()`.
  Collage does both (`CollageEditorModel.swift:683`), so a combined photo is missing from the index until
  the next incremental pass. **Fixed** (FS-01.09, 2026-09-24): the save moved to `PhotoStackModel.save()`,
  which calls both.
- `import Accelerate` at `ShotDexKit/Render/PhotoRenderService.swift:1` is unused — no vImage, vDSP,
  BNNS or simd symbol appears anywhere in the repo.

## Found while building FS-01.09 / FS-01.10 (2026-09-24, shotdex-ios-2)

### Should fix

- [ ] `ShotDex/Features/Editing/PhotoStackModel.swift` `excludedFramesMessage` — "1 of 3 frames couldn't be lined up and were left out." reads wrong in the singular; needs a plural variant in `Localizable.xcstrings` (not added: the catalog has a large uncommitted rewrite from another session) _(built, seen on `focus-stack-excluded.json`)_
- [ ] FS-01.10 §4 — the panel says how many frames were left out but not **which**; the spec asks for a way to see them (mark them in the Retouch strip, or list their file names) _(spec gap)_
- [ ] FS-01.10 AC-5 — Depth Map reaches 32.3 dB on the 16-frame bracket (33.0 at best, Radius 8) against a 33 dB target; Weighted is 35.5. Recorded as `withKnownIssue` in `FocusStackBracketTests` _(measured)_
- [ ] Combine results (Focus Stack, Stack Exposures) are not added to the Creations album the way panoramas and collages are _(ux)_

### Nits

- [ ] iPad Pro 13" iOS 18.6: after a reinstall the Library grid showed a single row of tiny tiles until relaunch _(seen during FS-01.09 UI proof, not reproduced)_
- [ ] Stack Exposures (Average / Lighten / Darken) combines frames without aligning them — fine on a tripod, ghosts on a handheld sequence; say so on the panel or align like Focus Stack _(ux)_

# Sweep — intent 2026-09-24-editor-phone-panel (2026-09-24)

Scope: `docs/_intents/2026-09-24-editor-phone-panel.md` + its design handoff, read against today's editor
code. Rule from the product owner: **no function may be lost — only look and layout change.** No code exists
yet, so every fix is a sentence in the intent. Agents: ux-reviewer ×2 (mask/point/presets; markup),
general-purpose (sliders/curve/grade/heal/crop/shell), challenger (scope, PencilKit).

## Blockers — functions the intent/handoff would drop
- [x] Markup text rows = "Font · Size · Color" only; drops Opacity, Outline, Shadow, Width, Leading, Tracking, Bold, Italic, Alignment (`EditorTextDetailPanel.swift:98-330`) → intent: rows keep every property, scrolling under the first three _(ux-reviewer)_
- [x] Markup shape/image/magnifier rows = "Size · Opacity · Color"; drops shape style switch, fill, Filled, Thickness, Height; Choose Image; magnifier **Zoom**, rim colour/width (`EditorTextDetailPanel.swift:347-509`) → intent: per-kind row list _(ux-reviewer)_
- [x] Placement sliders Rotate / Across / Down have no home (`EditorTextDetailPanel.swift:520-551`) → intent: last rows of every layer _(ux-reviewer)_
- [x] Layer Hide/Show missing from the new ⋯ (`EditorTextPanel.swift:199`) → add to ⋯ _(ux-reviewer)_
- [x] Signature preset library + "Save Preset" have no entry point; "Sign" chip undefined (`EditorSignatureSheet.swift`, `EditorTextDetailPanel.swift:68`) → Sign chip opens the library; ⋯ "Save as Preset" _(ux-reviewer)_
- [x] Mask rows = "Light/Color" only; masks carry Light/Color/Detail/Effects (`EditorMaskPanels.swift:303-311`) → all four _(ux-reviewer)_
- [x] Mask component picker, "Delete This Shape", Add/Subtract as a live mode, one-tap Undo in the mask nav row (`EditorMaskPanels.swift:264-270,494-544`, `:382-400`) → a shape row inside the zone _(ux-reviewer)_
- [x] Inline mask chips lose `unavailableReason` text shown in the sheet (`EditorMaskPanels.swift:762`) → tap a dimmed chip shows the reason _(challenger, ux-reviewer)_
- [x] Presets source strip: Save Current, Import .cube, per-item delete, deleted-LUT banner unplaced (`EditorToolPanels.swift:89-231`) → leading tile per source + context menu kept _(ux-reviewer)_

## Should fix
- [x] "Optics / Geometry: rows only" would drop Lens Profile section and Upright chips + note (`EditorLensProfileSection.swift`, `EditorToolPanels.swift:601-660`) → named in intent _(general-purpose)_
- [x] Switches (B&W, Chromatic Aberration, Lens Correction) tinted accent; RAW header in Detail; dependent rows dimmed with VoiceOver hint (`EditorAdjustmentPanel.swift:52-102,221`) → kept, "on" state visible without accent _(general-purpose)_
- [x] Edited markers carry VoiceOver "Edited" and sidebar dots / per-section ↺ (`EditorColorPanel.swift:710,735`, `EditorSidebar.swift:170-268`) → removal is phone-panel visual only _(general-purpose, challenger)_
- [x] Sidebar slider 44pt min + label-only keypad zone (`EditorSliderRow.swift:95-103,176-183`) → kept _(general-purpose)_
- [x] Command band accent (Before/After held) — "accent only on Save" ambiguous → band out of scope _(general-purpose)_
- [x] Handoff §5 Curve still says Input/Output + remove Reset/hint/presets, contradicting chốt #9 → banner of overrides at the top of the handoff _(challenger)_
- [x] Ink variety (Pencil, Fountain, Watercolor, Crayon, Monoline), Ruler, finger-vs-Pencil policy unplaced (`EditorDrawingCanvas.swift:91-101`) → ink row + ruler in draw rows _(ux-reviewer, challenger)_

- [x] Re-check pass (challenger): Point Color "Delete Point" + swatch menu missing from the keep-table (`EditorColorPanel.swift:138-260`); RAW header placement → both added _(challenger, re-run)_

## Needs a decision
- **Chốt #5/#13 — replace PencilKit with a custom kit brush.** Engine + data-model change, not UI; loses prediction, ink physics, pixel/vector eraser, ruler, Scribble, Pencil double-tap/squeeze unless each is rebuilt. Alternative (challenger): keep PencilKit, hide `PKToolPicker`, drive `canvas.tool` from the panel rows. **Asked 2026-09-24: owner keeps "bỏ PencilKit".** Resolved by widening chốt #13 into a full parity gate (every ink, both erasers, lasso, ruler, prediction, Pencil double-tap/squeeze, finger policy, vector export) — "thiếu một thứ = chưa được bỏ PencilKit". **Revised same day: owner switched to keep PencilKit** — chốt #5 now hides `PKToolPicker` and the panel drives `canvas.tool`; chốt #13 is the panel→PencilKit mapping. No new renderer.

## Closed / not a finding
- Grade colour wheel — none today; replaced by rows in 30c (`EditorColorPanel.swift:371-376`).
- `isActive` — only "finger is dragging this row"; no VoiceOver or edited meaning. Losing its tint loses nothing else.
- Aside: `PhotoEditorController.duplicateSelectedOverlay()` (`:1471`) is unreachable in the photo editor today; the new layer ⋯ Duplicate would wire it.

## Build-time findings (2026-09-25, while coding FS-03.12)
- [x] Wheel tap could leave Grade centred over a Point Color panel (SE 375 / iOS 18.6, 2 of 4 runs, only without logging): the tap's debounced select was cancelled by a scroll write-back that `onChange` then coalesced away → a tap now selects at once and ignores write-backs until the target lands; settle reads the current chip; iOS 18 selects on scroll idle too (`PhotoEditorScreen.swift`, `EditorGroupWheel`)
- [x] Grade chip strip showed a glyph on three chips and none on "Highlights" → the strip drops glyphs together (`EditorStripLayout.showsIcons`)
- [x] 48MP drawing layer spanning the frame built a ~192MB stamp beside the ~192MB overlay bitmap → bands ≤ 24MB (`PhotoRenderService+Drawing.swift`) _(memory-leak)_
- [x] Markup swatches Cream / Red both read "Colour swatch", Recent colours indistinguishable, palette eyedropper stateless → named, numbered + hex, Armed/Off _(a11y-voiceover)_
- [x] Mask deleted mid-detection left its id in `detectingMaskComponentIDs` → pruned to live components on resolve _(swift-concurrency)_
- [ ] `PhotoRenderService.emptyAutomaticComponents` / `foundAutomaticComponents` grow for the life of the actor (`PhotoRenderService.swift:106`) → evict with `automaticMaskCacheOrder` _(swift-concurrency, nit)_
- [ ] `DrawingLayerCache` (192MB) and the full-frame overlay bitmap (~192MB at 48MP) are not scaled for an extension's ~120MB ceiling; nothing gates `render(maximumDimension: nil)` there (`PhotoRenderService+Drawing.swift:20`, `+Overlay.swift:161`) — predates this work; run `extension-boundary` before any extension renders markup _(memory-leak)_
- [ ] Tone curve points cannot be moved with VoiceOver — presets and Reset are reachable, points are not (`EditorCurveOverlay.swift:73`); predates this work _(a11y-voiceover)_

### Needs a decision
- **On-photo selection frame is still accent** (dashed amber box round a selected layer, `EditorOverlayGuides.swift:176` via `EditorImageStage.swift:361`; mask pins `EditorOverlayGuides.swift:317,323`). DESIGN.md says "accent chỉ trên Save trong toàn photo editor" but lists only wheel, band, chip, slider and switch, and AC-3 measures the band and panel only. Options: (a) leave — the stage guides are not panel chrome, and amber reads well over any photo; (b) white dashed frame like Photos' markup, costs contrast over bright skies. Not changed while the scope is "look and layout of the panel".
