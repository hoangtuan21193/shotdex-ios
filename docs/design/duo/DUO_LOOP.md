# Duo inner review loop

One screen per pass, on the Duo's inner display (951×669, open). Each pass:
screenshot with `Tools/sim-shot <udid> … inner` (driven by `Tools/ui-drive`),
look for defects, run `duo-ux-review` against the HIG pages it fetches, fix,
re-shoot, then update the matching board in `project/` and publish it to the
Duo canvas <https://claude.ai/artifact/N91F3p5AZWgSQiMWVtZYrL>. One commit per screen.

Status: `todo` · `doing` · `done` · `blocked` (needs a decision beyond a layout fix — reason in Findings).

| # | Screen | Board(s) | Status | Findings | Commit |
|---|--------|----------|--------|----------|--------|
| 1 | Library grid | `Main` | done (2026-10-24) | Fixed: tile captions cut mid-value (`ISO 400 · 35m…`) at the 96pt tiles of 9 columns — trailing fields now drop off whole until the line fits. Board: Settings/Filter/tabs/Search redrawn in the system's vertical rail (HIG *Designing for iPhone Duo*: toolbars and tab bars move to the side), tab labels gone, captions as the app draws them. Rejected: even column count (HIG "prefer an even number of columns") — the grid is 867pt beside an 84pt rail, so column edges miss the hinge at x≈475 either way. Open: `Select` stays in the horizontal row while every other bar item moves to the rail — needs an experiment on why (text item? principal slot?), see row 1a. Checked: Duo inner light, iPhone 16 iOS 18.6. | 04fc2485 |
| 1a | Library — `Select` placement in the rail | `Main` | done (2026-10-24) | Measured: the Duo's vertical toolbar takes icon items only — a text `Select` stayed alone in the horizontal row, a `Label` with `checkmark.circle` moves into the rail under Filter (y 240–288). On the Duo inner (`VideoStudioWindowClass == .duoInner`) `Select` is now that icon; iPhone and iPad keep the spelled-out word. A wide-but-short iPad Stage Manager window also resolves to `.duoInner` and gets the icon. Board: Select drawn in the rail. Checked: Duo inner, iPhone 16 iOS 18.6. Tap into selection not re-driven (same action, label `Select photos` kept). | |
| 2 | Library select | `DI_LibrarySelect` | todo | | |
| 3 | Search / Advanced search | `DI_Search`, `DI_AdvancedSearch` | todo | | |
| 4 | Date range | `DI_DateRange` | todo | | |
| 5 | Empty library / Onboarding | `DI_EmptyLibrary`, `DI_Onboarding` | todo | | |
| 6 | Viewer | `DI_Viewer`, `DI_ViewerCloudDownload` | todo | | |
| 7 | Metadata / Info keywords | `DI_Metadata`, `DI15_InfoKeywords` | todo | | |
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
