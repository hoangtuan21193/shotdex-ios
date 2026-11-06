# Mac screens loop

Builds every Mac screen the canvas draws and the app lacks, one screen per pass
(started 2026-11-06, user request: no intent, no plan — spec + code per screen).
Canvas: <https://claude.ai/artifact/HEj8sG21jAEWd7Mgvuyxgj>, boards in `docs/design/mac/project/`.

**Hard rule (user, 2026-11-06): never edit or delete real photos — not in the iCloud Photos library,
not on the Windows server.** Every click-test runs on `-ShotDexDemoLibrary` (in-memory) and, for
server flows, the local test SMB in the scratchpad (memory `mac-app-testing`). A destructive button
(Delete, Move to Trash, Revert, Save over original, Upload/Move to server, Free Up Space) is clicked
only when the app is on demo data; otherwise assert it exists and stop. Never point a test at the
real NAS/Windows share or at PhotoKit writes. Code paths that write PhotoKit get proven on demo data only.

## How a pass runs (read this first every pass — it is the memory)

1. Take the first row below whose status is `todo` (skip `blocked`). Set it `doing`.
2. **Board**: read `project/<board>.dc.html` (visible strings, layout, states, dark tweak).
   Render it: `Tools/design-board render docs/design/mac/project/<board>.dc.html -o build/design/render`
   (+ `--dark`). The board is the target; `MAC_STYLE.md` + `DESIGN.md` the rules.
3. **Spec**: add/update the screen's section with numbered acceptance criteria in
   `docs/02-functional-spec/FS-18-mac-app/` (the FS doc the row names; reuse the FS-xx the
   iOS screen already has for behaviour). Every button on the board gets an AC saying what it does.
4. **Code**: `ShotDexMac/<Area>/Mac<Screen>.swift`. Shared iOS models go into the Mac target via
   `Tools/mac-membership.shared` + `Tools/mac-membership` (re-run after adding files). Add a DEBUG
   `-ShotDexSection <value>` that opens the screen on the demo library. Build:
   `xcodebuild -project ShotDex.xcodeproj -scheme ShotDexMac -destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac build | grep -E "error:|warning:|BUILD"`.
   Also build the iOS `ShotDex` scheme when a shared file changed.
5. **Review ×2**: round 1 — `caveman:cavecrew-reviewer` on the diff + `design-reviewer`
   (MAC_STYLE/DESIGN). Fix. Round 2 — `ux-reviewer` (+ `swift-concurrency` if Tasks/actors).
   Fix. Note both rounds in the row.
6. **UI check**: launch `build/mac/.../ShotDex.app` with `-ShotDexDemoLibrary -ShotDexSection <value>`
   (args need the reopen trick, see memory `mac-app-testing`), `Tools/mac-shot`, light and
   `-ShotDexAppearance dark`. Look at shot vs board PNG side by side; fix until it matches.
   **Never** shoot without the demo library (real library has faces).
7. **Click-test**: `Tools/mac-ui-drive <script.json>` (XCUITest driver, Automation Mode enabled
   2026-11-06) — click every button/menu on the screen, dump after each, assert the result
   (sheet opened, state changed, row added). Scripts in `ShotDexMacUITests/scripts/`. Fix failures.
7b. **Performance (user 2026-11-06: "UI hay lag khi bấm — logic nặng chạy nền, không bao giờ bắt UI chờ")**:
   the DEBUG build's `MacHangWatchdog` logs every main-thread stall > 100 ms; `Tools/mac-ui-drive` prints them
   split by `Tools/mac-ui-hangs.py`: **app hangs** (started in `launch` or a `wait` step) fail the pass;
   **suspects** (after a click/key `pressAt`) need `MAC_UI_SAMPLE=1 Tools/mac-ui-drive …`, whose
   `mac-ui-sample.py` summary lists ShotDex's own main-thread frames with XCTest's accessibility reads taken
   out — any ShotDex frame ≥ 50 ms fails the pass. Dumps/screenshots/element lookups also stall the app
   (XCTest reads the AX tree on the main thread); those are ignored. Every click is followed by a `wait`
   ≥ 1 s so its work lands in a measured window. Run once on the 273-row demo and once at 45k:
   `-ShotDexDemoLibrary -ShotDexDemoDatabase demo55k.sqlite -ShotDexDemoScale 200` (`perf-55k.json`).
   A launch argument with a value makes AppKit skip the first window — the driver presses ⌘N.
   Fix = move work off the main actor (GRDB `await reader.read`, `Task.detached`), never a sync DB read or
   PhotoKit fetch in a click path, rebuild only on a generation change; `perf-profiler` joins review round 2.
8. **Close**: board drift fixed on the board too if code is right and board is wrong (publish to canvas,
   read url first). Commit only this pass's paths (`git commit -- <paths>`, never `add -A`).
   Row → `done <hash>` + one line (what was checked). **Push to main** (user 2026-11-06; several
   sessions code in this checkout at once): `/usr/bin/git fetch origin`; if origin is ahead,
   `/usr/bin/git pull --no-rebase origin main` (a merge leaves other sessions' uncommitted files alone —
   never `stash`, `rebase --autostash`, `reset` or `checkout -- <file>`); then `/usr/bin/git push origin main`.
   A conflict in a file another session owns: stop and ask. Before staging, `git status` — files you
   did not touch this pass belong to someone else; never stage them.
   Then ScheduleWakeup, same /loop prompt. Never clear session.

**Build and test in the private worktree** (other sessions leave half-saved edits that break the shared
build): `WT=<scratchpad>/wt` — before each pass `/usr/bin/git -C $WT checkout -f --detach main` and
`/usr/bin/git -C $WT clean -fdq -e '*.mlpackage' -e build`; edit in the main checkout, `cp` the changed files
into `$WT`, build and run `Tools/mac-ui-drive` from `$WT` (its own `build/mac`). Commit from the main checkout.
zsh does not split `$VAR` into words: pass path lists as an array (`P=(a b); git add "${P[@]}"`).

Disk: stop if `volumeAvailableCapacityForImportantUsage` < 25 GB. Quit the app by pid, not `pkill`
(kills the helper). `blocked` rows need the user — write why.

## Queue

| # | Board(s) | FS doc | Status |
|---|---|---|---|
| 0 | Tooling: `Tools/mac-ui-drive` (macOS XCUITest driver, same JSON as ui-drive) | — | done (87cfc553) — smoke.json: launch demo, menu ShotDex>Settings…, waitFor, window shots + dump pass. Seen: Settings Focal Length segmented is system blue, not amber (fix in a Settings row) |
| 1 | Main shell: route sidebar places to own query, wire search text, empty state | 01-window-and-navigation | done (87cfc553) — places as `LibraryModel.place`, counts off-main, search + ⌘F + Go ⌥⌘1–5, grey `rowSel` selection, empty places, pending-place stand-in; grid built off-main on `rowsGeneration`, assets via cache. Reviews: cavecrew + design-reviewer, then ux + perf-profiler — all blockers fixed. Click-test `mac-places.json` (85 steps), `mac-places-dark.json`, `perf-55k.json` pass, 0 app hangs after clicks. Left for later rows: day-header place name ("· Kyoto"), "indexed 2 min ago" foot, counts on Collections/Utilities rows, Back/Forward, launch hang 0.4 s, inspector content |
| 2 | MAC_EmptyLibrary | 01-window-and-navigation §7 | done (f08a4986) — welcome screen, no Photos prompt at launch (asked on Add Photos Library…, refused → alert; re-read on app active), folder drop on content + sidebar, File › Add Folder… ⇧⌘O / Add Photos Library… / Connect to Server… ⌘K, + menu offers Photos while not added. Reviews: cavecrew + design-reviewer, ux + a11y — blockers fixed. `mac-empty.json` + dark pass; board compare ≤ 1 pt vertical. Left: drag from Finder untestable; one 160 ms stall when the grid first appears after Add Photos |
| 2b | Shell chrome vs board | 01 §1–3 | done (b4691109) — foot "Up to date · indexed 2 min. ago" (system relative format, re-read at run end incl. no-work runs, every minute); sidebar float/inset, row size & font, header style, search width, toolbar capsules measured as **macOS 27 system chrome** (SDK 27, no compat flag) and written into FS-18.01 §1 as accepted; Albums chevron → row 16. Reviews: cavecrew (refresh/race/clock) + localization (plural, whole sentences, wrap) — fixed. `mac-chrome.json`, `mac-empty.json`, `mac-addsource.json` pass. Left: vi strings for new keys (shared catalog) |
| 3 | MAC_Onboarding | 01 §7, FS-09 | skipped — superseded: D13 / FS-18.01 §7 / MAC_STYLE "no Onboarding window"; the first run is MAC_EmptyLibrary (row 2). The board stays on the canvas until the user says to delete it |
| 4 | MAC_AddSource | FS-19 01 | done (9a77bff4) — sidebar + and File › Add Source… open the sheet; kinds pick by click or ↑↓, primary per kind, open panel on the sheet (cancel keeps it), Photos added = done row; sheet/content/sep tokens; add-folder alerts at the window root. Reviews: cavecrew + design, ux + a11y — fixed. `mac-addsource.json` + dark pass, board ≤ 4 pt. Left: sheet sits centred (system), the board draws it at top 52; ↑↓ not scripted; macOS reads the Sources header as one element (+ is its named action) |
| 5 | MAC_SourceIndexing | FS-19 01/01b | done (3d884d98) — read banner (Pause/Resume/×, survives relaunch, Read All skips it, "was disconnected" state), ring on the row, foot bar (click → banner), offline banner (Locate… with wrong-folder check, Remove Source… with honest wording), one-line summary for several offline sources, offline glyph on tiles, "· N offline"; folder indexer reports progress (throttled) and SourcesModel reads the DB off-main on the read path. Reviews: cavecrew + design, ux + perf — fixed. `mac-sourceindexing.json` + dark pass; regression places/empty/addsource pass. Left: Hide Its Photos wording on the offline banner (Row lacks whenUnplugged); replug → online within 5 s (no mount observer); "64 read so far" in the day header |
| 6 | MAC_LibraryList | 02-library-viewer-cull | done (80ddad55) — NSTableView list (View › as Grid ⌘1 / as List ⌘2, toolbar picker, mode remembered): 12 columns, self-drawn cells, zebra, amber/grey selection with rounded run ends, header menu hides columns, autosaved widths/order. Date/ISO/Focal/Aperture/Shutter sort in the library (grid follows); Name/Camera/Lens/Rating/Source/Size sort in the table only, off-main, remembered. Camera/lens/rating/source from `LibraryTableQueries` (one read, cursor, debounced while indexing). Reviews: design + code (r1), ux + perf (r2) — fixed. `mac-list.json` + dark. Perf 45k -O: sorts 0 hangs; one 124 ms mode switch in 4 runs. Deferred to row 8: selection → inspector/actions, open (Return/Space/double-click), 0–5 rating keys — the grid has none of these yet either. Open nits: Reset Columns item; local sort no-op until details load |
| 7 | MAC_ContextMenu | 01b-menus-shortcuts-and-drag | done (dde9bfc7) — `MacPhotoMenu` (native NSMenu, grid + list, right-click on an unselected photo selects it alone): Quick Look (QL panel, Esc/Space close, first 50), Rating ▸ / Flag ▸ via `PhotoMarks` (now in MacDependencies; demo → pending table), Favorite/Unfavorite (Photos photos), Add to Album ▸ (Photos albums read off-main; New Album alert), Share ▸ (system services, files written only on pick, per-asset temp folders cleared once a launch), Show in Finder (connected file copies), Move to Trash (smart-album delete flow, plan read off-main, errors shown). Facts read only for ≤500 ids; larger selections resolve at action time. Failures → "Couldn’t Finish" alert, not a beep. Reviews: cavecrew + design (r1), ux + swift-concurrency (r2) — fixed. `mac-contextmenu.json` (every row clicked on demo), `mac-contextmenu-55k.json` (select-all right-click, 45k) — no ShotDex main-thread frame in the sample. Open/Edit/Get Info/Export wait for their screens; Reveal in Photos not possible; grid tiles show no star/flag/heart badge yet (Main board draws them — follow-up); selection → inspector is row 8 |
| 8 | MAC_LibrarySelected | 02 | done (fc059081) — selection model (grid keeps its ids by delta, never re-reads 55k paths; kept by id across rebuilds, deleted ids leave; carried across ⌘1/⌘2; cleared when nothing shows) + inspector `MacSelectionInspector`: stacked thumbs, "N Photos/Items" + dates · size, Add to Album ▾ + Share, Selection / Gear / Exposure Range / Keywords (shared vs partial chips) / Rating and Flags (5 stars, re-click clears; board-style segmented; mixed-state Favorite) from `SelectionSummaryQueries` (per-900-id reads, cancellable; tests incl. 901 ids). Subtitle "6 selected · 144 MB". Tile marks ⚑/✕ ♥ ★n (reject dimmed, spoken). Marks change patches only the touched photos' details. Reviews: cavecrew + design (r1), ux + perf (r2) — fixed. `mac-selected.json` (+dark, +55k select-all: no ShotDex main-thread frame), `mac-contextmenu.json` 3/3 after a hover-wait fix. Open: Edit/Compare/Sync/Export buttons wait for their screens; keyword editing = 8b; Favorite is Photos-only |
| 8b | MAC_LibrarySelected keywords: add to all / × remove from all / partial chip → all | 02 §2, §8 | done (4082c819) — `MacKeywordEditor`: per-photo, case-aware changes (add skips a photo with the word in another case; remove takes every spelling, as Photos removes exact-case); Photos via `CaptionKeywordService` (macOS 27, now composed on the Mac with the keyword mirror — window only, not the helper), file photos via `PhotoUserMarksStore.addKeyword/removeKeyword` (chunked) + sidecars; demo writes the mirror rows only. Chips one per caseKey named by the common spelling, "+N More", field disabled with a note where Photos can't be written, empty input ignored, failed text restored, outcome said per add/remove. Reviews: cavecrew (r1), ux+concurrency (r2) — fixed. `mac-keywords.json`, `PhotoUserMarksKeywordTests`, chip test in `SelectionSummaryQueriesTests`. Known gap: no Undo (iOS sheet has one) |
| 9 | MAC_GetInfoSingle | 02 §8 | done (this commit) — `MacInfoPanel` (420 utility NSPanel, Image › Get Info ⌘I + photo menu Get Info; non-key until a field is clicked; follows the asking window; only the active window answers ⌘I) + `MacInfoView`: header, Title (file photos; "Kept by Photos" otherwise), Caption (file row+sidecar, or Photos on macOS 27), Keywords (chips, add, × — `MacKeywordEditor`), Rating/Favorite/Flag, Date, Location, EXIF, On Server, save note + Saving…/Saved. Save as you type: per-field 600 ms debounce, writes chained in order, flushed on photo change, panel close and quit; same-second saves win (`setText` `<=`). `PhotoInfoQueries` (+tests). Driver: `window` field for x/y clicks and screenshots, missing window fails. Reviews: cavecrew+design (r1), ux+concurrency (r2) — fixed. `mac-getinfo.json` 3/4 green (one runner failure with no failed step). Rest → 9b. Note: `NSSharingService.sharingServices(forItems:)` is deprecated (row 7 share menu) — replace with the picker's standard share menu in row 12
| 9b | MAC_GetInfoSingle: Creator + Copyright (new user-data columns + XMP), Date Adjust…, Location Adjust…, Show All Raw Metadata, Metering/White Balance | 02 §8 | todo |
| 10 | MAC_GetInfo | 02 §8 | todo |
| 11 | MAC_Search | 02 §4 | todo |
| 12 | MAC_MenuBar | 01b | todo |
| 13 | MAC_OnThisDay | FS-06 07 | todo |
| 14 | MAC_Hidden | FS-19 04 | todo |
| 15 | MAC_DeleteCopies | FS-19 04 | todo |
| 16 | MAC_Collections | 04 §1 | todo |
| 17 | MAC_AlbumDetail | 04 §1 | todo |
| 18 | MAC_SmartAlbumEditor (nested groups) | FS-06 08 | todo |
| 19 | MAC_BackupOrganize (Custom… popover) | FS-22 01 | todo |
| 20 | MAC_Support | FS-13 | todo |
| 21 | MAC_Viewer | 02 §6 | todo |
| 22 | MAC_ViewerFullScreen | 02 §6 | todo |
| 23 | MAC_ViewerCloudDownload | 02 §6 | todo |
| 24 | MAC_Cull | 02 §7 | todo |
| 25 | MAC_ServerBrowser upload + MAC_ServerUpload | FS-15 02 | todo |
| 26 | MAC_Ingest | FS-20 | todo |
| 27 | MAC_IngestProgress | FS-20 | todo |
| 28 | MAC_Statistics | 04 §2, FS-07 | todo |
| 29 | MAC_StatisticsCamera | FS-07 | todo |
| 30 | MAC_ChartEditor (+ MAC_ChartStyle decision) | FS-07 01b | todo |
| 31 | MAC_Edit | 03 §1 | todo |
| 32 | MAC_EditCrop | 03 | todo |
| 33 | MAC_EditColor | 03 | todo |
| 34 | MAC_EditHeal | 03 | todo |
| 35 | MAC_EditMask | 03 | todo |
| 36 | MAC_EditMarkup | 03 | todo |
| 37 | MAC_EditPresets | 03 | todo |
| 38 | MAC_EditBatch | 03 | todo |
| 39 | MAC_Export | 03 | todo |
| 40 | MAC_EditPhotos | 03 | todo |
| 41 | MAC_SettingsEditing | FS-08 03 | todo |
| 42 | MAC_Compress | 04 §4 | todo |
| 43 | MAC_Merge | 04 §4, FS-14 | todo |
| 44 | MAC_Collage | 04 §4, FS-11 | todo |
| 45 | MAC_Creations | FS-06 01b | todo |
| 46 | MAC_Duplicates | 04 §1, FS-06 06 | todo |
| 47 | MAC_BurstFrames | FS-02 05 | todo |
| 48 | MAC_VideoProjects | 04 §5, FS-12 18 | todo |
| 49 | MAC_VideoStudio | FS-12 | todo |
| 50 | MAC_VideoClipSelected | FS-12 | todo |
| 51 | MAC_VideoText | FS-12 | todo |
| 52 | MAC_VideoExport | FS-12 16 | todo |
| 53 | MAC_VideoStudioCompact | FS-12 | todo |
| 54 | MAC_SettingsAI | FS-08 07 | todo |
| 55 | MAC_SettingsAIProvider | FS-08 07 | todo |

Already done before the loop (board ↔ code exist): FilterPopover, CameraDatabase, Backup, BackupNew,
CommonPhotos(+Run, Compare), Activity, ServerForm, SmartAlbum, Settings General/Sources/SourcesCache/Servers.
