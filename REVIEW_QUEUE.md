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
- [ ] `CollageMetrics.swift:17` — the 216pt panel under a ~900pt canvas on iPad → **moved to Needs a decision** (scale it, or make it a side inspector like the editor's) _(device-layout)_
- [x] `CollageMetrics.swift:76` — 28pt aspect chips with no extended hit area, where Video Studio's equivalent band already extends its 28pt chips to 44 _(device-layout)_
- [x] `CollageMetrics.swift:81` — 52pt template cells under a canvas seventeen times their area _(device-layout)_

## Nits

- [ ] `VideoStudioMetrics.swift:139` — 20pt lane glyphs in the timeline gutter, decorative but hard to read at iPad distance _(device-layout)_
- [ ] `CollageMetrics.swift:70,72` — the counter (32pt) and Export pill (38pt) are legible but phone-scaled _(device-layout)_
- [x] `PhotoDetailScreen.swift:733` — the Flag or Rate submenu did not mark the state already in effect _(hig-components)_

## Needs a decision

- **Collage's panel on iPad.** `device-layout` says the 216pt bottom panel reads as a phone sheet under a big canvas and proposes either scaling it or restructuring it into a side inspector like the editor's. The second is the better answer and is a day of work on `CollageScreen`; the first is an hour. Which?
- **Video Studio's toolbar distribution.** Spreading nine cells across 1032pt is one line; making the toolbar a left rail on regular width (Final Cut / CapCut on iPad both do this) is a rework. The rail is right, the spread is cheap.

## Closed by spec.md

- Photo editor on iPad — `device-layout` found no layout problem: the sidebar (`EditorLayoutMetrics.sidebarMinCanvasWidth` 700, width clamped 280…420) is the model the other two tools should follow. spec §10.3 already documents it.
- 40pt icons in the viewer's action bar — DESIGN §6 records the exception.
