# Duo inner review loop

One screen per pass, on the Duo's inner display (951×669, open). Each pass:
screenshot with `Tools/sim-shot <udid> … inner` (driven by `Tools/ui-drive`),
look for defects, run `duo-ux-review` against the HIG pages it fetches, fix,
re-shoot, then update the matching board in `project/` and publish it to the
Duo canvas <https://claude.ai/artifact/N91F3p5AZWgSQiMWVtZYrL>. One commit per screen.

**How a pass runs (read this first every pass — it is the memory):**
- Device: simulator "Compare Duo" `307B259D-86F8-443A-A974-0BCBC07DCC2B` (iOS 27, shared — never erase it). Build:
  `xcodebuild -project ShotDex.xcodeproj -scheme ShotDex -destination "id=<udid>" -derivedDataPath build/sim build`.
  A build for the iOS 27 sim does not run on iOS 18.6 (`libswiftCompatibilitySpan.dylib` missing) — rebuild with that sim's id to check iPhone.
- Disk: `df` under-reports (Time Machine snapshots); the real free space is `volumeAvailableCapacityForImportantUsage` (swift -e one-liner). Stop only if that is < 25 GB.
- Capture: write `ShotDexUITests/scripts/duo-loop-<screen>.json` (launch → taps → `dump` → long `wait`), run `Tools/ui-drive <udid> <script> build/duo-loop/drive-NN` while a background loop takes `Tools/sim-shot <udid> build/duo-loop/burst-NN/sNN.png inner` every 15s; the ~1.4 MB frames are the app, ~5 MB ones the home screen (delete those after). Downscale with `sips -Z 1400` (1.472 px/pt) to look.
- Duo inner facts found so far: the window class is `.duoInner` (`VideoStudioWindowClass.resolve` via `onGeometryChange`, see `LibraryScreen`); content is < 860pt wide, so `WideLayout.minimumWidth` alone misses it; the vertical toolbar rail only takes **icon** items; the safe area top is 0 in landscape and the top corners are ~66pt — keep controls at y ≥ 32 near them (`CompareLayout.duoInnerTopInset`); a plain `.sheet` is a ~652pt form sheet; the Search tab reads as compact.
- Review: `duo-ux-review` agent, told to fetch HIG pages via `/tutorials/data/design/human-interface-guidelines/<page>.json` (HTML comes back empty); the Duo page is `designing-for-iphone-duo`.
- Canvas: `Artifact read` the board path before editing (publish is refused otherwise); edit in `docs/design/duo/project/`, render light + `--dark`, `Tools/design-board compare`, publish with `root` = `docs/design/duo`.
- Commit: other sessions leave uncommitted edits in the same files — stage only your own hunks (`git diff <file> > p; keep your @@ hunks; git apply --cached --recount`), then plain `git commit`. Record the hash in the row.
- End of pass: schedule the next wakeup. Do **not** clear the session — clearing it also dropped the pending wakeup and stopped the loop after row 6 (2026-10-24).

Status: `todo` · `doing` · `done` · `blocked` (needs a decision beyond a layout fix — reason in Findings).

| # | Screen | Board(s) | Status | Findings | Commit |
|---|--------|----------|--------|----------|--------|
| 1 | Library grid | `Main` | done (2026-10-24) | Fixed: tile captions cut mid-value (`ISO 400 · 35m…`) at the 96pt tiles of 9 columns — trailing fields now drop off whole until the line fits. Board: Settings/Filter/tabs/Search redrawn in the system's vertical rail (HIG *Designing for iPhone Duo*: toolbars and tab bars move to the side), tab labels gone, captions as the app draws them. Rejected: even column count (HIG "prefer an even number of columns") — the grid is 867pt beside an 84pt rail, so column edges miss the hinge at x≈475 either way. Open: `Select` stays in the horizontal row while every other bar item moves to the rail — needs an experiment on why (text item? principal slot?), see row 1a. Checked: Duo inner light, iPhone 16 iOS 18.6. | 04fc2485 |
| 1a | Library — `Select` placement in the rail | `Main` | done (2026-10-24) | Measured: the Duo's vertical toolbar takes icon items only — a text `Select` stayed alone in the horizontal row, a `Label` with `checkmark.circle` moves into the rail under Filter (y 240–288). On the Duo inner (`VideoStudioWindowClass == .duoInner`) `Select` is now that icon; iPhone and iPad keep the spelled-out word. A wide-but-short iPad Stage Manager window also resolves to `.duoInner` and gets the icon. Board: Select drawn in the rail. Checked: Duo inner, iPhone 16 iOS 18.6. Tap into selection not re-driven (same action, label `Select photos` kept). | e29b2db5 |
| 2 | Library select | `DI_LibrarySelect` | done (2026-10-24) | Fixed: (a) captions ran under the 22pt selection circle — the line now refits to the width left of it while selecting (VoiceOver still reads every value); (b) Compare and Edit stayed in a horizontal row while Filter/⋯/× stood in the rail — on the Duo inner they are now icon items (`rectangle.split.2x1`, `slider.horizontal.3`) and move into the rail; (c) that emptied the bar's row, so the grid jumped 58pt up on entering selection — on the Duo inner the date now stays while selecting; (d) grid cells had no `.selected` trait, so VoiceOver could not tell picked photos apart. Board redrawn as measured: rail Compare 120 · Edit 180 · Filter+⋯ 240 · × 352, 9 columns, bottom bar at y 577, ⋯ menu anchored to the rail with the app's rows. ⋯ menu itself is the system's, fine. Checked: Duo inner browse, select, select + ⋯ open (light). iPhone not re-shot: every change but (a)/(d) is gated on the Duo inner; the 18.6 test photos carry no EXIF, so (a) has nothing to show there. | f8315a12 |
| 2b | Library select — bottom bar into the rail? | `DI_LibrarySelect` | blocked — needs your decision | HIG *Designing for iPhone Duo*: bars at the top and bottom "move to the side" on the inner display in landscape. Share · Show Selected · Delete are a custom overlay (`SelectionBarViews.swift` `SelectionBottomBar`), so the system leaves them at the bottom. Moving them would put Delete next to Done (×) in the rail — a flow change, not a layout fix. Would give back ~58pt of height. | |
| 3 | Search | `DI_Search` | done (2026-10-24) | Fixed: the five suggestion capsules stood one per line in the left 300pt of a 951pt screen — on the Duo inner (`.duoInner`) or ≥ 860pt they now run in rows (`KeywordFlowLayout`). The 860 test alone missed the Duo: its inner display's own insets leave the content under 860. Found: the Search tab reads as **compact** on the Duo inner, so the field stays at the bottom above the keyboard — the board's field-at-top state is unreachable there. Board redrawn as measured (field 152,349 647×48, keyboard from y 405). Checked: Duo inner, empty query, keyboard up. Not checked: Recents (sim has none) — see 3c. | d34dcd42 |
| 3b | Advanced Search (and the other sheets of `c8c28d8d`) | `DI_AdvancedSearch` | blocked — needs your decision | A plain `.sheet` on the Duo inner is a ~652pt form sheet (measured x 150–801), never 951pt, so the two-column form at ≥ 860 (`AdaptiveFormColumns`) never appears — the same goes for Upload to Server, Add Connection, Edit Smart Album and Photo Info. DESIGN.md §10.1c and the `DI_AdvancedSearch` board describe a layout the app cannot draw. HIG *Sheets*: "Avoid displaying a sheet that covers most or all of its window"; *Designing for iPhone Duo*: "show an additional level of hierarchy on the larger inner display". Either keep the form sheet (fix board + §10.1c, drop the dead two-column branch) or present larger on the Duo only (`.presentationSizing(.page)`, else `fullScreenCover` when ≥ 860 wide and < 700 tall). Also: the sheet's content runs under the home indicator. | |
| 3c | Search — Recents at 951pt | `DI_Search` | blocked — needs your decision | Predicted from code, not seen: 3 flexible square cards ≈ 295pt each — cut by the keyboard and "bigger, not more". Fix needs a count: cap cards near 140–160pt and show more than `SearchRecentsModel.maximumCards = 3` when wide. | |
| 4 | Date range | `DI_DateRange` | todo | Only reachable from the chart editor (`ChartEditorSheet` → `DateRangePickerSheet`) — check it with row 13. | |
| 5 | Empty library / Onboarding | `DI_EmptyLibrary`, `DI_Onboarding` | todo (last) | Needs an empty library or a fresh install — wipes data on the shared Duo simulator, so it goes last. | |
| 6 | Viewer | `DI_Viewer` | done (2026-10-24) | Fixed: in landscape the inner display's safe area starts at y 0 (status bar is in the rail), so the top row sat at y 8 and the Close circle was tangent to the ~66pt top-left corner curve. On `.duoInner` the viewer's top row, the Single/2-Up/Survey picker, the zoomed download ring and Compare's top bar now start at `CompareLayout.duoInnerTopInset` = 32 (~15pt clear of the curve). Board: mode picker added, info capsule 576 wide (it stops at the picker), Delete and the action pill inside the 84pt rail as DESIGN.md §10.1b says. Not a leak: the Library controls in the dump sit under a `fullScreenCover`, which takes them out of VoiceOver. Checked: Duo inner viewer + 2-Up. `DI_ViewerCloudDownload` not reachable here (no iCloud placeholder on the sim). | 44465e3b |
| 7 | Metadata / Info keywords | `DI_Metadata`, `DI15_InfoKeywords` | blocked — needs your decision (3b) | Measured: Photo Info is the same ~652pt form sheet as row 3b (x 149–802), so the three-column layout of `DI_Metadata` (`MetadataPanel` ≥ `WideLayout.minimumWidth`) never draws; and the two boards disagree — `DI_Metadata` is full-screen, `DI15_InfoKeywords` a 540pt sheet. Fixed now (holds under either 3b answer): the sheet opened at the medium detent, 385pt (y 276–661) on the 669pt display — caption, keywords and the top of the map, not one camera or exposure value; on `.duoInner` it now opens large only. Even at large, Camera & Lens starts at y≈610 under the map — the case for 3b's bigger layout. Add Keyword turns into an inline field (184,189 122×34) as the board draws. Boards not changed: which one is right is the 3b decision. Checked: Duo inner, Info open, Add Keyword tapped. | 5f064c47 |
| 8 | Collections (Albums) | `DI_Collections` | todo | | |
| 9 | Album detail | `DI_AlbumDetail` | todo | | |
| 10 | Smart album + editor | `DI_SmartAlbum`, `DI_SmartAlbumEditor` | todo | | |
| 11 | Hidden | `DI_Hidden` | todo | | |
| 12 | Utilities tab | `DI_Utilities` | todo | | |
| 13 | Statistics + chart editor | `DI_Statistics`, `DI_ChartEditor` | todo | | |
| 14 | Duplicates + compare | `DI_Duplicates`, `DI_DuplicatesCompare`, `DI_DeleteCopies` | todo | | |
| 15 | Burst frames | `DI_BurstFrames` | todo | | |
| 16 | Compare viewer | `DI_Compare`, `DI_CompareSurvey` | todo | | |
| 17 | Cull | `DI14_Cull` | todo | | |
| 18 | On This Day | `DI_OnThisDay` | todo | | |
| 19 | On This iPhone / Keep | `DI_OnThisIPhone`, `DI_KeepOnIPhone` | todo | | |
| 20 | Editor — main panel | `DI1_Edit`, `DIP1_Edit` | todo | | |
| 21 | Editor — presets / My Looks | `DI2_Presets`, `DIP3_Presets`, `DI9_MyLooks`, `DIP9_MyLooks` | todo | | |
| 22 | Editor — transform | `DI3_Transform`, `DIP4_Transform` | todo | | |
| 23 | Editor — mask / new mask / layer | `DI4_Mask`, `DIP2_Mask`, `DI10_NewMask`, `DIP10_NewMask`, `DI11_NewLayer`, `DIP11_NewLayer` | todo | | |
| 24 | Editor — heal / markup | `DI5_Heal`, `DIP5_Heal`, `DI6_Markup`, `DIP6_Markup` | todo | | |
| 25 | Editor — curve | `DI8_Curve`, `DIP8_Curve` | todo | | |
| 26 | Editor — save / edit which | `DI12_Save`, `DIP12_Save`, `DI13_EditWhich`, `DIP13_EditWhich` | todo | | |
| 27 | Batch edit | `DI7_Batch`, `DIP7_Batch` | todo | | |
| 28 | Bulk keywords | `DI16_BulkKeywords`, `DIP16_BulkKeywords` | todo | | |
| 29 | Watermark | `DI17_Watermark`, `DIP17_Watermark` | todo | | |
| 30 | Export / file name | `DI18_Export`, `DIP18_Export`, `DI19_FileName`, `DIP19_FileName` | todo | | |
| 31 | Share / Compress / presets | `DI_Share`, `DI_Compress`, `DI_CompressionPresets` | todo | | |
| 32 | Delete permanently | `DI_DeletePermanent` | todo | | |
| 33 | More menus | `DI_MoreMenus`, `DI_MoreMenus2` | todo | | |
| 34 | Collage + export | `DI_Collage`, `DI_CollageExport` | todo | | |
| 35 | Creations | `DI_Creations` | todo | | |
| 36 | Panorama / Focus stack / Stack exposures | `DI_Panorama`, `DI_FocusStack`, `DI_StackExposures` | todo | | |
| 37 | Video projects / trim | `DI_VideoProjects`, `DI_VideoProjectsDelete`, `DI_VideoTrim` | todo | | |
| 38 | Video Studio | `DI2_ClipSelected`, `DI3_TextOverlay`, `DI4_Music`, `DI5_RatioBackground`, `DI6_Export` | todo | | |
| 39 | Sources / add source / ingest | `DI_Sources`, `DI_AddSource`, `DI_Ingest`, `DI_IngestProgress` | todo | | |
| 40 | Server list / form / browser / upload | `DI_ServerList`, `DI_ServerForm`, `DI_ServerBrowser`, `DI_ServerUpload`, `DI_UploadedToServer` | todo | | |
| 41 | Backup | `DI_Backup`, `DI_BackupNew`, `DI_BackupOrganize`, `DI_BackupCustomDate`, `DI_BackupRunning` | todo | | |
| 42 | Settings | `DI_Settings`, `DI_SettingsSources`, `DI_SettingsAI`, `DI_SettingsAIProvider`, `DI_CameraDatabase` | todo | | |
| 43 | Widget settings | `DI_WidgetSettings` | todo | | |
| 44 | Support | `DI_Support`, `DI_SupportThread` | todo | | |
