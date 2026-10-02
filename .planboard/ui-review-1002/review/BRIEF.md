# ShotDex UI review — shared brief

ShotDex = native iOS photo-library app for photographers (browse library, filter by camera/lens/exposure EXIF, gear statistics,
collections/smart albums, compare, compress, collage, upload to file servers). Unreleased. Repo: /Users/hoangtuan/Project/shotdex-ios (READ ONLY — do not edit code, do not commit, do not build unless your own agent definition requires it; prefer reading the design boards).

## What to review
A Design canvas of every screen except the photo editor and Video Studio, drawn from the current code (iOS 26 path):
- Board PNGs (1x, light mode): /Users/hoangtuan/Project/shotdex-ios/build/design/app/render/<Board>.png  — LOOK at them (Read tool shows images).
- Board sources: /Users/hoangtuan/Project/shotdex-ios/build/design/app/project/<Board>.dc.html ; captions per board in project/canvas.json ("title").
- Prefixes: `Main` = iPhone Library; `PH_` iPhone 17 402×874; `IP_` iPad 13" landscape 1376×1032; `DI_` iPhone Duo inner 951×669 (short, 84pt tab rail on the right); `DC_` Duo cover 466×678 (app area 382 wide, system rail on right).
- Screens: Onboarding, Library, LibrarySelect, Search, AdvancedSearch, Viewer, Metadata, Compare, VideoTrim, Share, Collections, AlbumDetail, SmartAlbum, SmartAlbumEditor, OnThisDay, Places, Trips, Duplicates, Creations, Collage, CollageExport, Compress, Statistics, ChartEditor, DateRange, Settings, WidgetSettings, CompressionPresets, CameraDatabase, Support, SupportThread, ServerList, ServerForm, ServerBrowser, ServerUpload, UploadedToServer.
- The boards were drawn by agents from code, so where a board looks wrong, check the Swift source (ShotDex/Features/...) before blaming the app: say whether the issue is in the APP (code) or only in the BOARD (drawing error). Both are useful.
- Design rules: /Users/hoangtuan/Project/shotdex-ios/DESIGN.md (house rules; a proposal that breaks one must say so and argue why).
- Don't re-raise what docs/ already decided unless you argue against the decision explicitly.

## Output
Write your findings to /private/tmp/claude-501/-Users-hoangtuan-Project-shotdex-ios/e353bb24-e1ca-4dc4-a582-e5da3840c191/scratchpad/review/<your-slug>.md, Vietnamese prose (keep UI strings, code names in English), one entry per finding:

```
### <ID e.g. UX-03> <short title>
- Màn / thiết bị: Library · PH, IP
- Mức: blocker | nên sửa | gợi ý
- Ở đâu: APP (file:line) | BOARD (board name) | cả hai
- Vấn đề: what a user hits, concretely (numbers in pt where layout)
- Đề xuất: the change, concrete (pt, labels, placement), and what it costs (space, effort, rule broken)
- Bằng chứng: board PNG name(s), file:line, HIG/source URL, or user quote+source
```
Rank most important first. Max ~25 findings; quality over count. Then return to the caller ONLY: the file path + your top 8 findings as one line each (ID · title · màn · mức).
