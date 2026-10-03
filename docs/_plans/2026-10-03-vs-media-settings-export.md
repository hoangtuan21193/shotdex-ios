# Kế hoạch — Video Studio: Media trong panel, Video Settings, Export, pipeline xuất

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-12.09](../02-functional-spec/FS-12-video-studio/09-media-panel.md) (18 AC) · [FS-12.10](../02-functional-spec/FS-12-video-studio/10-video-settings-and-export.md) (12 AC) · [FS-12.10b](../02-functional-spec/FS-12-video-studio/10b-export.md) (13 AC) · [FS-12.01](../02-functional-spec/FS-12-video-studio/01-render-and-export-pipeline.md) §7b–§9 (không có bảng AC riêng; đi kèm [README](../02-functional-spec/FS-12-video-studio/README.md) AC-6/7/8) |
| Intent | [2026-10-03-video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — mảng 3 (Media) và 4 (Video Settings/Export) của thứ tự "thanh dưới → chọn item → **Media** → **Video Settings/Export** → Look → kích thước → F1–F8" |
| Canvas | [Video Studio](../design/README.md) — đọc lại 2026-10-03 (bản `1790981542-377a`, 112 file): đã có `MP_P_Drag916`, `P7_ExportReady`, `IP_Export`, `DC_Export`; `ES_*`/`P6` ghi "Video Settings", "~30 MB", không còn hàng Quality |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **3** của thứ tự xây. 46 task = 46 commit |
| Slug | `vs-media-settings-export` |

> Bản sao canvas ở `build/design/video/project/` **cũ** (22 file, chưa có board `MP_*`/`ES_*`/`P6`/`P7*`). Mỗi task có
> `design-parity` phải export lại `project/` của canvas vào đó trước khi chạy `Tools/design-board`.
> Dòng `Tiến độ` của intent ghi lúc duyệt 2026-10-03.

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 3** của thứ tự xây.
- **Thứ tự xây cả intent** (người dùng chốt 2026-10-03): 1 `vs-tools-selection-phone` khối 0, A–D (+ khối N lưu
  nháp) → 2 `vs-wide-and-duo-layout` task 4–15 → 3 `vs-media-settings-export` → 4
  [`2026-10-02-video-photo-looks`](2026-10-02-video-photo-looks.md) → 5 `vs-tools-selection-phone` khối E +
  `vs-wide-and-duo-layout` task 16–18 → 6 `vs-multiselect-beats-ducking` → 7 `vs-captions-compare-presets` → 8
  `vs-precise-trim-input` (task 1–2 của nó — bước driver, chỉ đụng `ShotDexUITests/` — được làm trước).
- **Task code đầu tiên của cả chuỗi là bộ giải mã khoan dung** cho `VideoProjectRecipe` (+ `VideoClip`, `MusicTrack`,
  `TimedOverlay`; mảng qua `LossyArray`) — **task 4 của `vs-tools-selection-phone` sở hữu**. Mọi plan thêm khoá vào
  recipe phụ thuộc nó và chỉ thêm khoá, không viết bộ giải mã thứ hai.
- **Lưu nháp (người dùng đổi 2026-10-03, thay câu trả lời "chỉ lưu khi Export"):** project video tự lưu thành nháp
  ~1 s sau mỗi thay đổi và ngay khi Back / xuống nền / đổi scene; Back không còn hỏi "Discard this video?"; Video
  Projects hiện nháp lẫn bản đã xuất — spec mới [FS-12.18](../02-functional-spec/FS-12-video-studio/18-drafts.md)
  (12 AC), làm ở **khối N** của `vs-tools-selection-phone`, ngay sau task 4. FS-12.14 AC-12 và FS-12.16 AC-8 giữ
  nghĩa "rời rồi mở lại".
- **Quyết định của plan này:** mọi ⚠️ "tài liệu đúng" duyệt. Q1 → **đếm = số hàng = số lần dùng**; FS-12.09 AC-1 thành
  "7 clip, 27,0 s; In Video · 8" và luật đếm ghi ở FS-12.09 §4. Q2 → AC mới đã viết vào spec: Albums = FS-12.09 **AC-19**
  (task M2); nền Blur / Image + ảnh nền mất = FS-12.10 **AC-13, AC-14** (task S6); tỉ lệ mặc định theo clip đầu =
  FS-12.10 **AC-15** (task S1); câu "can't be encoded as H.264" = FS-12.10b **AC-14** (task E8).
- **Export Video — trạng thái Sẵn sàng là của FS-12.16** (chốt duyệt; FS-12.10b §2–3, AC-1, AC-2, AC-12, AC-13 đã
  sửa): plan này dựng **khung panel** (vùng, tiêu đề, ✕, mở-không-xuất, chạm-hai-lần trên Duo) và các trạng thái
  **Đang xuất · Đang lưu · Lỗi · huỷ · thiếu chỗ**; nội dung Sẵn sàng tạm thời chỉ là một nút Export xuất theo Video
  Settings của project (= Custom) cho tới task 34 của `vs-captions-compare-presets` thay bằng danh sách preset. Task E1,
  E2, E10, E12 đã sửa phạm vi theo đó.
- **Bộ giải mã khoan dung (T-4):** do task 4 của tools plan viết (bước 1, trước plan này); S1 chỉ thêm khoá mới.
- Plan bắt đầu sau `vs-tools-selection-phone` khối 0, A–D (+ N) và `vs-wide-and-duo-layout` task 4–15 — đúng như §5 đã ghi.
- **Board canvas phải sửa** (canvas Video Studio [docs/design](../design/README.md), trước task
  `design-parity` đầu tiên của board đó):
  - `P7_ExportReady`: **bỏ** — Sẵn sàng iPhone là `F8_P_ExportPresets`.
  - `IL5_Export`, `DI6_Export`, `IP_Export`, `DC_Export`: vẽ lại thành trạng thái **Đang xuất** của máy đó (Sẵn sàng
    là `F8_IL` / `F8_DI` / `F8_IP` / `F8_DC`); `P7_Export` giữ (đã là Đang xuất).
  - `MP_*` có số In Video sau một lần chèn: số theo luật **đếm = số lần dùng** (vd. sau AC-1 là "In Video · 8").
  - Đã có sẵn trong spec, nhắc lại: `MP_P_MediaPicker` · `MP_P_Drag` · `MP_P_Limited` · `MP_P_InVideo` · `MP_IL_*` ·
    `MP_DI_Media` · `MP_DC_Media` đặt Select · 🔍 theo FS-12.09 §3; `MP_DI_Media`, `ES_DI_ExportSettings` nhận cột
    badge 100 của plan màn rộng.

## 0. Phụ thuộc với các plan Video Studio khác

| Plan | Cái plan này cần từ nó | Cái nó cần từ plan này |
|---|---|---|
| **`vs-tools-selection-phone`** (`docs/_plans/2026-10-03-vs-tools-selection-phone.md`, đang viết song song) | ô **Media** ở hàng đáy 5 ô; đáy ✕ · tên · ✓ và **mô hình phiên panel** (ảnh chụp recipe + độ sâu undo/redo lúc mở; ✕ trả về, ✓ giữ); `GlobalTool` mới (bỏ `.ratio`, `.background`, `.masterVolume`); băng trên iPhone có chỗ cho hai đĩa 36 ở x 312/356 (FS-12.07 §2) và **đường mở** Video Settings (plan này lo nội dung panel và chữ/biểu tượng của nút); bảng cao panel theo tỉ lệ (FS-12.07 §3: 340/320/300/278/360/340) | — |
| **`vs-wide-and-duo-layout`** ([2026-10-03-vs-wide-and-duo-layout](2026-10-03-vs-wide-and-duo-layout.md)) | **trước** plan này (mảng 1–2): task 4 `VideoStudioWindowClass`; task 6–10 chỗ chứa — pool 236, dock 324, cột Duo trong 264 (Media mở trong cột), dải 84 Duo ngoài với đĩa Video Settings @504 / Export @556, nút Settings trên băng iPad và hàng đáy Duo trong; task 7 header pool "Library" + 4 tab (**gỡ Effects**). **Sau** plan này (mảng 6): task 16–17 transport/header/meter, task 18 `design-parity` đủ board | nội dung tab Media trong pool 236 / cột 264 / panel Duo ngoài; số ô lưới trong pool (`mediaPoolColumnCount`, `mediaPoolCellWidth`); chữ của nút Settings ("16:9 · 1080p · 30 fps", hai dòng) và readout "0:24 · ~30 MB" |
| **06c look** ([2026-10-02-video-photo-looks](2026-10-02-video-photo-looks.md), đã duyệt, chờ khung) | task 12 (dòng "1 look is missing its LUT…" theo look) → FS-12.10 AC-8 và FS-12.10b AC-5 | khung nền **từng bên trước khi trộn** (task S7 ở đây) là nền cho task 1 của 06c ("grade từng bên trước `blend`, rồi mới ghép lên nền"); bộ giải mã khoan dung của recipe (task S1) nhận thêm trường `look` |
| F8 preset xuất (FS-12.16, sau) | — | bảng kích thước, cổng 4K, công thức ước tính ở Domain, **không** biết gì về preset (`VideoOutputSpec`) |

Chỗ chứa trên iPad và Duo đã có từ `vs-wide-and-duo-layout` task 4–10 khi plan này bắt đầu, nên AC đo vị trí trong
chỗ chứa (09 AC-13/17, 10 AC-9, 10b AC-10/13) làm và chứng minh ngay. Ba task `design-parity` cả board (M17, S13, E12)
chỉ xanh hết sau task 16–18 của plan đó (transport, header, meter cùng nằm trên board); phần tử của plan này phải đạt ≤ 2 pt ngay khi xong.

## 1. Hiểu đúng chưa

- **Media** thôi là trình chọn của hệ thống: một thư viện ngay trong panel (cột pool trên iPad ngang), đọc thẳng
  PhotoKit không trần, chạm = chèn ở playhead (tách clip nếu cần, playhead nhảy tới cuối clip mới), Select → Add (N),
  giữ 0,3 s rồi kéo thả vào **ranh giới clip** trên timeline (hoặc dải tổng quan khi không có lát timeline), có tab In
  Video, dấu ✓ / ×n cho thứ đang dùng, tìm bằng ngôn ngữ truy vấn của Library, hàng quyền giới hạn "Manage Access…",
  và là một phiên ✕/✓ ngoài iPad ngang. Ảnh/video chỉ có trên iCloud vào timeline ngay rồi tải bản gốc; hỏng thì gỡ kèm câu sẵn có.
- **Video Settings** gom tỉ lệ (6), Fit/Fill, nền khi Fit (Blur · Colour · Image), độ phân giải (720p/1080p/4K theo
  **cạnh ngắn**, trần 3840), fps (24/30/60), codec (H.264/HEVC) và dung lượng ước tính; mọi thay đổi áp ngay, mỗi chạm
  một bước undo; 4K khoá khi có clip dưới 4K.
- **Export** chỉ còn tóm tắt + nút xuất; huỷ ≤ 1 s, thiếu chỗ, rời app, không được ghi Photos, project ảnh server đều có đường hỏng rõ chữ.
- **Pipeline (FS-12.01)**: xuất theo kích thước/fps/codec của Video Settings, bitrate = w × h × fps × 0,16 (HEVC × 0,6);
  preview vẫn 1280 / 1/30; nền vẽ từng bên trước khi trộn; tỉ lệ, Fit/Fill, nền chỉ đổi bản dựng khung hình.

Không lệch với đặc tả, trừ một chỗ số học trong FS-12.09 AC-1 (❓ Q1 ở §7).

## 2. Đối chiếu AC ↔ code

Ký hiệu: ✅ code đã đạt (chỉ viết test khoá) · ⚠️ code làm khác (kèm đề nghị) · ❌ chưa có · ❓ chưa kết luận.
Đường dẫn rút gọn: `VS/` = `ShotDex/Features/VideoStudio/`, `DS/` = `ShotDex/Data/Sources/`, `DV/` = `ShotDex/Domain/Video/`.

### 2.1 FS-12.09 — Media

| AC | | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 chạm ô → tách Coast ở 8,4, ảnh vào giữa, ✓, In Video tăng, playhead 11,4 | ⚠️ | tách-rồi-chèn có ở `VS/VideoStudioModel.swift:1117-1147` nhưng chỉ khi `mediaInsertMode == .insertAtPlayhead`, mặc định `.appendAtEnd` (`:1099`, `:1119`); playhead không dời; không có dấu dùng, không có In Video | **tài liệu đúng**: bỏ `MediaInsertMode`, chạm luôn chèn ở playhead, playhead tới cuối clip mới. Số "6 clip" trong AC xem ❓ Q1 |
| AC-2 Select → Add (3) theo thứ tự chọn, 1 undo | ❌ | — | mới |
| AC-3 giữ 0,3 s, kéo tới ranh giới 14,2, thả không tách | ⚠️ | kéo hôm nay là kéo-thả hệ thống: ô `.onDrag` (`VS/VideoMediaPoolColumn.swift:747`, `:823`) thả lên `.onDrop` của timeline (`VS/VideoStudioScreen.swift:508-513`) và **nối cuối** (`:636-641`); kéo được cả ra app khác | **tài liệu đúng**: giữ-kéo bằng UIKit trên scroll view của lưới, thả vào ranh giới; `.onDrop` nhận từ app khác giữ nguyên (spec §2) |
| AC-4 thả lại lưới → không đổi, không có bước undo | ❌ | — | mới |
| AC-5 vuốt dọc 30 pt trong 0,2 s đầu → cuộn, không nhấc | ❌ | lưới hiện là `LazyVGrid` SwiftUI 400 ô | mới (cùng task lưới UIKit) |
| AC-6 ×2 → xoá clip 6 → ✓ → xoá clip 1 → hết dấu | ❌ | id nguồn đã có cho clip (`VideoClip.assetID`) và sticker (`PhotoOverlay.imageAssetIdentifier`, `ShotDexKit/Models/PhotoOverlayModels.swift:259-262`, ghi ở `VS/VideoStudioModel.swift:1796-1802`, `VS/VideoStudioScreen.swift:631`) — dữ liệu đủ, chưa có phép đếm | mới, Domain |
| AC-7 In Video 6 hàng, chạm Coast → playhead 3,0, chọn clip 2 | ❌ | — | mới |
| AC-8 ✕ → 5 clip, độ sâu undo như lúc mở | ❌ | undo là mảng ảnh chụp (`VS/VideoStudioModel.swift:135-136`, `:603-635`), chưa có phiên | mới, dùng mô hình phiên của `vs-tools-selection-phone` |
| AC-9 `.limited`: 12 ô + hàng khoá + Manage Access…; cấp thêm → 15, panel không đóng | ❌ | `presentLimitedLibraryPicker()` có (`DS/PhotoLibraryService.swift:196-203`); `libraryChangeToken` có (`:1170-1172`) | mới |
| AC-10 video chỉ iCloud, offline → vẫn 5 clip + câu "One clip couldn't be loaded…" | ✅ hành vi | `loadAndMerge` gỡ clip không nạp được và đặt đúng câu (`VS/VideoStudioModel.swift:1165-1190`) | khoá bằng test — **cần một seam** (nạp nguồn đi thẳng PhotoKit, `DS/VideoStudioService.swift:73-77`, `:133`, `:142`), nên làm ở task M8 cùng đường bản gốc iCloud; xem §3 |
| AC-11 55 000 mục, cuộn tới cuối, không "Browse All Photos…", +< 60 MB | ⚠️ | trần `capacity = 400` (`VS/VideoMediaPoolColumn.swift:51`, `:579-586`) + hàng "Browse All Photos…" mở picker hệ thống (`:499-500`, `VS/VideoStudioScreen.swift:412`, `:182-202`) | **tài liệu đúng** (spec §2 "cố ý không có") |
| AC-12 "85mm" → đúng 20 ô | ❌ | `SearchService` (`DS/SearchService.swift`) + `LibraryQueries.gridItems(query:)` có sẵn | mới, tái dùng |
| AC-13 iPad: pool 4 tab Media · Text · Stickers · Music; hàng tab vừa 236; tiêu đề Library · Select · 🔍 · Hide Media | ⚠️ | 5 tab theo thứ tự media·stickers·text·music·effects (`VS/VideoMediaPoolColumn.swift:593-594`); menu Append/Insert (`:223-248`) | **tài liệu đúng**; header "Library" + 4 tab (gỡ Effects) do `vs-wide-and-duo-layout` task 7 làm trước; plan này thêm Select, đệm tab 8, lưới 3 cột, bỏ menu Append/Insert và `.onDrag` |
| AC-14 VoiceOver "Video, 0:06, in this video" + Insert at Playhead, Select | ⚠️ | nhãn hiện "Video, <ngày>, <độ dài>" (`VS/VideoMediaPoolColumn.swift:864-874`), không action | **tài liệu đúng** |
| AC-15 `design-parity` 10 board `MP_*` | ❌ | — | phần tử Media ngay; cả board sau `vs-wide-and-duo-layout` task 16–18 |
| AC-16 iPhone hàng tab: Recents · Albums · In Video · 6 · Select · 🔍, x ≤ 390 | ❌ | — | mới |
| AC-17 Duo trong: hàng tab cuộn, mép mờ 24 | ❌ | — | mới; cột 264 có từ `vs-wide-and-duo-layout` task 9 |
| AC-18 Falls ở 2 clip + 1 sticker → "×3" | ❌ | (như AC-6) | cùng task AC-6 |

### 2.2 FS-12.10 — Video Settings

| AC | | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 iPhone, chạm 9:16 → khung 216×384, panel 278, Output "1080×1920 · 0:24 · ~30 MB", 1 undo | ❌ | tỉ lệ đổi qua `setAspect` (`VS/VideoStudioModel.swift:858-864`) từ `RatioStrip` (`VS/VideoInspectorControls.swift:280-300`); không có màn Video Settings | mới; cao panel theo tỉ lệ đến từ `vs-tools-selection-phone` |
| AC-2 Fill → mất BACKGROUND, nhãn "9:16 · Fill", không pixel nền | ❌ | chỉ có aspect-fit (`DV/VideoGeometry.swift:59-67`, `:71-86`) | mới |
| AC-3 9:16 · Fit · xám → hàng pixel trên = #808080 ± 2 | ✅ đường code | nền màu ghép dưới khung đã fit (`DS/VideoFrameCompositor.swift:368`, `:409`); canvas 9:16 1080p = 1080×1920 (`DV/VideoProjectModels.swift:47-61`); test hình học có (`VideoGeometryTests.portraitSourcePillarboxesOnALandscapeCanvas`) | test khoá ở mức file xuất. **Giá trị byte chưa đo**: `CIColor(red:0.5…)` qua không gian màu làm việc của context có thể không ra 128; nếu lệch thì sửa trong cùng task |
| AC-4 18 ô kích thước, mọi cạnh chẵn | ⚠️ | 4 tỉ lệ (`DV/VideoProjectModels.swift:21-23`), kích thước theo **cạnh dài** của preset 1920/3840 (`:47-61`, `:338-344`, `:507-512`) → 1:1 1080p ra 1920×1920, 4:5 ra 1536×1920 | **tài liệu đúng** (bảng cạnh ngắn + 4:3, 21:9) |
| AC-5 4K mờ + "4K needs 4K clips — 3 of your 5 clips are 1080p." | ❌ | cỡ nguồn có trong `VideoClipSource` (`DS/VideoCompositionBuilder.swift:7-19`) nhưng freeze mang cỡ khung đã thu nhỏ | mới, Domain |
| AC-6 đang 4K, thêm clip 1080 → 1080p, chung 1 undo với lần thêm | ❌ | — | mới |
| AC-7 HEVC: "~30 MB" → "~18 MB" | ⚠️ | ước tính 0,15 bit × 30 fps cố định (`VS/VideoStudioModel.swift:1886-1891`) → "~28 MB"; writer dùng công thức riêng 4,8 bit/pixel (`DS/VideoExportWriter.swift:96`); chỉ H.264 (`:100`) | **tài liệu đúng**: một hàm `VideoExportEstimate` cho cả Output lẫn writer |
| AC-8 dòng LUT mất | ❌ | — | chờ 06c task 12 (look theo clip) |
| AC-9 iPad popover 340, Duo trong cột 264 + ⌃, Duo ngoài panel y 334 | ❌ | — | mới; nút và chỗ chứa từ `vs-wide-and-duo-layout` task 6–10 |
| AC-10 `design-parity` 6 board | ❌ | — | phần tử Settings ngay; cả board sau `vs-wide-and-duo-layout` task 16–18 |
| AC-11 "Video Settings" mọi nơi, không còn "Export Settings" | ❌ | không có chữ nào trong code; công cụ cũ là "Ratio", "Background" (`VS/VideoStudioModel.swift:36-71`) | mới |
| AC-12 xuất 16:9 · 1080p · 30 · H.264: 10 Mbps ±15 %, 30 MB ±15 % | ✅ | 1920×1080×4,8 = 9,95 Mbps (`DS/VideoExportWriter.swift:95-105`) = 1920×1080×30×0,16 — trùng đúng ở 30 fps | test khoá (giữ xanh qua task S2 khi đổi sang công thức chung) |

### 2.3 FS-12.10b — Export

| AC | | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 panel "Export Video" tóm tắt, không Quality, nút 362×50 | ⚠️ | sheet có Picker "Quality" 1080p/4K (`VS/VideoExportSheet.swift:24-33`), sheet `.height(300)` (`VS/VideoStudioScreen.swift:150-158`) | **tài liệu đúng** |
| AC-2 chạm tóm tắt → Video Settings | ❌ | — | mới |
| AC-3 9:16 · 24 fps → 1080×1920, 24 fps, H.264, lệch < 1 khung | ⚠️ | kích thước đúng; fps cứng 1/30 cho cả preview lẫn export (`DS/VideoCompositionBuilder.swift:292`) | **tài liệu đúng** (01 §8: export đọc fps của Video Settings, preview giữ 1/30) |
| AC-4 60 fps · HEVC | ❌ | chỉ H.264 (`DS/VideoExportWriter.swift:100`) | mới |
| AC-5 dòng LUT mất ngay trên nút, xuất tới 100 % | ❌ (một phần: `VideoLUTRendererTests.aMissingFileLeavesTheFrameAlone`) | — | chờ 06c task 12 |
| AC-6 Cancel ≤ 1 s, không còn file tạm, Photos không thêm | ⚠️ | huỷ có (`DS/VideoExportWriter.swift:223-225`, `VS/VideoStudioModel.swift:1866-1868`) nhưng file `ShotDex-Video-*.mp4` ở lại tới khi đóng phiên (`DS/VideoStudioService.swift:436-448`, `:473-478`); ≤ 1 s chưa đo | **tài liệu đúng**: xoá file ở mọi nhánh throw |
| AC-7 trống < 2 × ước tính → không bắt đầu | ❌ | `DiskSpace` có (`ShotDex/Core/Utils/DiskSpace.swift`) | mới |
| AC-8 rời app khi xuất → huỷ + câu "Export stopped when you left ShotDex…" | ⚠️ | hôm nay **xuất tiếp** dưới background task, chỉ huỷ khi hết hạn (`VS/VideoStudioModel.swift:1819-1827`) | **tài liệu đúng** (chốt: GPU không được vẽ ở nền) |
| AC-9 Photos bị từ chối → câu + Open Settings, xoá file tạm | ❌ | lỗi thô `error.localizedDescription` (`VS/VideoStudioModel.swift:1860-1862`); `saveToPhotos` chỉ xoá file khi thành công (`DS/VideoStudioService.swift:453-459`) | mới |
| AC-10 Duo trong: chạm Export lần 1 mở cột, lần 2 (≥ 0,5 s) xuất, nút không dời | ❌ | — | mới; nút Export 78×40 ở hàng đáy Duo trong từ `vs-wide-and-duo-layout` task 9 |
| AC-11 project ảnh server → "Export…" → sheet FS-17.06, Photos không thêm | ⚠️ một phần | luồng + nhãn "Export…" có (`VS/VideoExportSheet.swift:68-82`, `:101-103`; `VS/VideoStudioModel.swift:1842-1851`), đã có test `ServerComposeToolTests.videoOfServerPhotosExportsToAFile`; hàng Đích "Choose where it goes next" chưa có | thêm hàng Đích; giữ test cũ |
| AC-12 `design-parity` `P7_Export` · `IL5_Export` · `DI6_Export` | ❌ | — | phần tử Export ngay; cả board sau `vs-wide-and-duo-layout` task 16–18 |
| AC-13 iPad + Duo trong: không "Quality"/"1080p"/"4K" ngoài tóm tắt | ❌ | (như AC-1) | mới |

### 2.4 FS-12.01 — yêu cầu pipeline (không có bảng AC riêng) và README

| Yêu cầu | | Bằng chứng | Việc |
|---|---|---|---|
| README AC-6 2 clip + transition + nhạc, 9:16 → file đọc được, tỉ lệ đúng, lệch < 1 khung | ✅ (chưa test) | đường đọc–ghi `DS/VideoExportWriter.swift:36-228` | test khoá (bộ khung test xuất ở §3) |
| README AC-7 project ảnh → không đoạn rỗng, không track âm rỗng | ✅ (chưa test) | xương sống đen `DS/VideoStudioService.swift:214-266`; lọc track âm rỗng `DS/VideoExportWriter.swift:66-70`, `DS/VideoStudioService.swift:356-362` | test khoá |
| README AC-8 Cancel ≤ 1 s, không file dở | ⚠️ | = 10b AC-6 | chung task E3 |
| §7 shake trên đồng hồ 1/30 bất kể fps | ✅ | `DV/VideoEffectMath.swift:77-94` lượng tử theo `time * 30` | test khoá ở 60 fps |
| §7b nền Blur / Image, vẽ **từng bên trước khi trộn** | ⚠️ | chỉ nền màu, ghép **một lần sau** `blend` (`DS/VideoFrameCompositor.swift:368`, `:385-410`, `:525-540`) | **tài liệu đúng**; ❓ Q2: chưa có AC |
| §8 tỉ lệ · Fit/Fill · nền = tầng bản dựng khung hình | ⚠️ | `setAspect` dựng lại toàn bộ (`VS/VideoStudioModel.swift:858-864`) vì phép fit nướng vào layout lúc `build` (`DS/VideoCompositionBuilder.swift:155`, `:162`, `:201-206`) | **tài liệu đúng** (xem lựa chọn kỹ thuật T-2 ở §3) |
| §8 preview cạnh dài 1280, luôn 1/30 | ✅ | `DS/VideoStudioService.swift:15`, `:482-489`; `DS/VideoCompositionBuilder.swift:292` | giữ; test trong task S4 rằng preview vẫn 1/30 khi project 60 fps |
| §9 bitrate w × h × fps × 0,16, HEVC × 0,6, AAC 128k | ⚠️ | như 10 AC-7 | chung task S2 |
| §9 kích thước = tỉ lệ × lớp cạnh ngắn của **đích xuất** | ⚠️ | như 10 AC-4 | chung task S1 |
| README AC-13 iCloud offline lúc mở → trạng thái `failed` có chữ | — | ngoài phạm vi plan này; task M8 đổi đường tải dùng chung nên test của M8 phủ luôn trường hợp mở project | — |

**Tổng:** 46 AC trong phạm vi (09: 18 · 10: 12 · 10b: 13 · README: 3). ✅ 5 (09 AC-10, 10 AC-3, 10 AC-12,
README AC-6, AC-7) · ⚠️ 13 · ❌ 28 · ❓ 0 trên AC (2 câu hỏi về tài liệu ở §7).

## 3. Tái dùng — và lựa chọn kỹ thuật

| Có sẵn | Dùng cho |
|---|---|
| `VideoStudioModel.insertMedia` — tách clip dưới playhead bằng `VideoSplitMath.split`, chèn vào vết cắt, chép `sources` sang hai nửa (`VS/VideoStudioModel.swift:1117-1147`) | lõi của chạm-chèn (AC-1), Add (N) (AC-2); chuyển phần tính chỗ chèn về Domain `MediaInsertMath` để test thuần |
| `loadAndMerge` + câu iCloud sẵn có (`:1165-1190`) | AC-10; giữ câu chữ y nguyên |
| `PhotoOverlay.imageAssetIdentifier` | dấu dùng cho sticker (AC-6/18), hàng "Photo · sticker" (AC-7) — **không** thêm trường mới |
| `PhotoLibraryService.requestThumbnail` / `startCachingThumbnails` (`PHCachingImageManager`, thang fast→exact→network), `fetchUserAlbums`, `presentLimitedLibraryPicker`, `authorizationState`, `libraryChangeToken` | lưới Media, Albums, hàng `.limited`, nạp lại tại chỗ |
| `SearchService` (parser → model → free text) + `LibraryQueries.gridItems(query:)` | Tìm (AC-12) — cùng ngôn ngữ truy vấn của Library, không viết parser thứ hai |
| `OriginalFetching` (`probe` mạng tắt, `fetch` có tiến độ/huỷ) + `FakeOriginalFetcher` (`-ShotDexFakeICloud cloud=…,fail=…`) + `StillFrameStore.setFiles` (đã đọc bản trên đĩa cho ảnh server) | **bản gốc iCloud của media** (AC-10): xem T-3 |
| `DiskSpace` (`volumeAvailableCapacityForImportantUsage`) | kiểm chỗ trống trước khi xuất (10b AC-7) |
| `ServerComposeToolTests.videoOfServerPhotosExportsToAFile` — xuất thật từ ảnh trên đĩa, không cần PhotoKit | khung cho mọi test xuất (size/fps/codec/bitrate/huỷ): ảnh server + nguồn video tổng hợp nạp thẳng vào `VideoStudioService.export(recipe:sources:)` |
| `PhotoDropImport` + `.onDrop` của timeline | giữ nguyên cho thả **từ app khác** |
| `VideoMediaPoolFormat` (tên, thời lượng, nhãn VO) | ô lưới + hàng In Video; sửa nhãn VO theo AC-14 |
| `UIDriverTests` bước `drag` (`ShotDexUITests/UIDriverTests.swift:175-180`, giữ 0,1 s) | thêm `pressSeconds` để giữ 0,35 s rồi kéo (AC-3/4/5) |

**Lựa chọn kỹ thuật (tự quyết, kèm lý do):**

- **T-1 Lưới Media là `UICollectionView` riêng nhỏ trên `PHFetchResult`, không phải `PhotoGridCollectionView`.** Lưới của
  Library (2 581 dòng) nhận mảng phẳng, có section ngày, pinch, swipe-chọn — Media cần kết quả truy vấn lười (55 000 mục
  không thành mảng), và một `UILongPressGestureRecognizer` (0,3 s, `allowableMovement` 10) gắn **trên chính collection
  view**, khi bắt đầu thì tắt-bật `panGestureRecognizer` để huỷ cuộn (spec §5). Thumbnail, cache và luật Optimize Storage đi
  qua đúng hàm của `PhotoLibraryService` nên không có cách tải ảnh thứ hai.
- **T-2 Hình học fit/fill rời `build` sang `videoComposition(recipe:layout:)`.** Layout giữ `naturalSize` +
  `preferredTransform` (track) hoặc cỡ ảnh (still); phép đặt khung tính từ recipe **tươi** như hiệu ứng và fade đang làm
  (`DS/VideoCompositionBuilder.swift:270-310`). Thế là tỉ lệ, Fit/Fill, nền chỉ thay `item.videoComposition` (đổi được
  `renderSize` trên player item) — không debounce 300 ms, khung đổi trong khung hình kế tiếp như §5 đòi.
- **T-3 Bản gốc iCloud của media dùng `OriginalFetching`, không dùng modal `OriginalPreparation`.** Spec 09 §5 muốn clip vào
  timeline ngay và gỡ khi hỏng — không có hỏi Continue/Retry. Nên: `probe` mạng tắt → `.inCloud` thì `fetch` về thư mục
  phiên (tối đa 4 cùng lúc, như `OriginalPreparation`), ảnh đi `StillFrameStore.setFiles` (bỏ được lần tải iCloud
  **đồng bộ trên hàng đợi compositor** ở `DS/VideoFrameCompositor.swift:213-229`), video mở `AVURLAsset` từ file. Phải
  mở rộng `PhotoKitOriginalFetcher.resource(for:)` chọn `.video`/`.fullSizeVideo` và phép kiểm đủ byte cho video (so
  `fileSize` của resource, không đo pixel). Có `FakeOriginalFetcher` là test và sim chạy được "offline".
- **T-4 Bộ giải mã khoan dung cho `VideoProjectRecipe`.** Hôm nay `Codable` tự sinh (`DV/VideoProjectModels.swift:460`):
  thêm **một** khoá là mọi project đã lưu giải mã ra `nil` (`ShotDex/Core/Models/Creation.swift:102-104`) và biến mất khỏi
  Video Projects. Task S1 viết `init(from:)` với `decodeIfPresent` cho mọi trường + `LossyArray` cho clip, overlay, nhạc,
  marker; giá trị lạ → mặc định §5. Nếu `vs-tools-selection-phone` (bỏ Master) vào trước thì nó viết bộ giải mã, S1 chỉ thêm khoá.
- **T-5 Ghi file xuất: một hàm `VideoEncodingSettings.make(spec:)`** (codec, profile, bitrate) dùng chung với ước tính —
  Output và file không thể lệch nhau.
- **T-6 Freeze trích ở cỡ canvas lúc nạp** (`VS/VideoStudioModel.swift:472`, `:1166`): đổi 1080p → 4K sau đó thì export phóng
  khung freeze. Export trích lại freeze ở cỡ đích (export đã dựng kho khung tĩnh riêng, `DS/VideoStudioService.swift:424-427`);
  cổng 4K đọc cỡ **video nguồn** của freeze, không đọc cỡ khung đã trích.

## 4. File đổi và tầng

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `DV/VideoProjectModels.swift` | Domain | `VideoAspect` + `r4x3`, `r21x9`; `VideoResolution` (720/1080/2160 cạnh ngắn), `VideoFrameRate` (24/30/60), `VideoCodec` (h264/hevc), `VideoFraming` (fit/fill), `VideoBackground` (kind blur/colour/image · colour · blurAmount · imageAssetID); bỏ `VideoRenderPreset`, `renderPreset`, `background: OverlayColor`; `canvasSize()` theo bảng §5; `init(from:)` khoan dung | sửa |
| `DV/VideoOutputSpec.swift` | Domain | kích thước khung (bảng 18 ô, trần 3840, chẵn), `VideoExportEstimate` (bitrate, MB/GB, chuỗi "~30 MB"), `VideoResolutionGate` (lý do "3 of your 5 clips are 1080p" / "smaller than 4K"), tỉ lệ mặc định theo clip đầu (log tỉ lệ, ngang → 16:9), `ExportSpaceCheck` (2 × ước tính) | mới |
| `DV/VideoGeometry.swift` | Domain | `placement(displayed:render:framing:)` cho fit/fill (track + still) | sửa |
| `DV/MediaInsertMath.swift` | Domain | chỗ chèn từ playhead (tách / mép / cuối), playhead mới; nhiều mục theo thứ tự chọn; ranh giới gần ngón nhất theo x, tốc độ tự cuộn theo độ sâu trong 40 pt | mới |
| `DV/MediaUsage.swift` | Domain | đếm lần dùng theo asset id (clip + sticker) → ✓ / ×n; hàng In Video theo thứ tự timeline (tên, "Photo · clip 1", khoảng giờ); hàng dưới playhead | mới |
| `DS/VideoCompositionBuilder.swift` | Data | layout giữ hình học thô; `videoComposition` nhận `frameDuration` và tính đặt khung từ recipe tươi | sửa |
| `DS/VideoFrameCompositor.swift` | Data | `VideoRenderRecipe` mang framing + nền; nền **từng bên trước `blend`** (Blur ở 1/8 cạnh dài rồi phóng, Image qua kho khung tĩnh có một ô ghim riêng ngoài LRU 4); ảnh nền mất → đen | sửa |
| `DS/VideoExportWriter.swift` | Data | `VideoEncodingSettings`; HEVC; xoá file ở mọi nhánh huỷ/lỗi | sửa |
| `DS/VideoStudioService.swift` | Data | export theo `VideoOutputSpec` (size, fps, codec); trích lại freeze ở cỡ đích; seam `VideoSourceLoading`; bản gốc iCloud qua `OriginalFetching` (T-3); `saveToPhotos` xoá file khi lỗi và phân loại lỗi quyền | sửa |
| `DS/OriginalFetcher.swift`, `DS/FakeOriginalFetcher.swift` | Data | resource video + kiểm đủ byte cho video; script fake áp cho video | sửa |
| `DS/VideoMediaLibrary.swift` | Data | `PHFetchResult` Recents / album / kết quả tìm (id từ index → fetch theo id), trạng thái quyền, nạp lại theo `libraryChangeToken` | mới |
| `VS/VideoStudioModel.swift` | Features | bỏ `MediaInsertMode`, `appendMedia` chỉ còn cho thả từ app khác; `insertMedia` theo `MediaInsertMath` + dời playhead; `addMedia(_:at boundary:)` cho thả; phiên Media; `setAspect/Framing/Background/Resolution/FrameRate/Codec` (mỗi chạm một bước, tầng video); tự hạ 4K chung bước undo với lần thêm; export: kiểm chỗ, huỷ khi vào nền (`didEnterBackground`), phân loại lỗi; bỏ `estimatedExportBytes` cũ | sửa |
| `VS/VideoMediaPanel.swift` | Features | panel Media (hàng tab, Select/Add, tìm, Albums, In Video, quyền, rỗng) cho iPhone / dock / cột / Duo ngoài | mới |
| `VS/VideoMediaGridView.swift` | Features | `UICollectionView` lưới (T-1) + nhận dạng giữ-kéo, báo vị trí ngón theo toạ độ màn | mới |
| `VS/VideoMediaDragOverlay.swift` | Features | bóng 70×70 nghiêng −3°, vạch trắng + viên nang "+ 0:14.2" trên lane video hoặc dải tổng quan; haptic | mới |
| `VS/VideoTimelineScroller.swift` | Features | tắt pan khi đang kéo media, tự cuộn theo `MediaInsertMath`; xuất khung lane video / ranh giới theo toạ độ màn | sửa |
| `VS/VideoMediaPoolColumn.swift` | Features | iPad ngang: thêm Select vào header (header + 4 tab là của `vs-wide-and-duo-layout` task 7), tab Media dùng `VideoMediaPanel` (lưới 3 cột), bỏ trần 400 / Browse All / menu Append-Insert / `.onDrag` | sửa |
| `VS/VideoMediaPicker.swift` | Features | **giữ** (Collage còn dùng, `ShotDex/Features/Creations/CreationsScreen.swift:81`); Video Studio thôi gọi | — |
| `VS/VideoSettingsPanel.swift` | Features | nội dung §4 theo thứ tự; Done ✓; dòng LUT mất (slot, nối ở 06c task 12) | mới |
| `VS/VideoExportPanel.swift` (thay `VideoExportSheet.swift`) | Features | tóm tắt (chạm → Video Settings), Đích, nút Export / Cancel Export, trạng thái lỗi; form sheet iPad 540 | mới / gỡ cũ |
| `VS/VideoStudioScreen.swift`, `VideoStudioToolbar.swift`, `VideoStudioCommandBand.swift`, `VideoViewerChrome.swift`, `VideoStudioSheetHost.swift`, `VideoInspectorControls.swift` | Features | nút Video Settings (đĩa tỉ lệ / "16:9 · 1080p · 30 fps ⌄" / hai dòng) + Export icon; nhãn khung "9:16 · Fill"; gỡ `RatioStrip`, `BackgroundStrip`, sheet `VideoMediaPicker`, sheet Export cũ | sửa |
| `ShotDexUITests/UIDriverTests.swift` | Test | bước `drag` có `pressSeconds` | sửa |
| `ShotDexTests/` | Test | `VideoOutputSpecTests`, `VideoProjectRecipeDecodingTests`, `MediaInsertMathTests`, `MediaUsageTests`, `VideoExportSmokeTests` (+ `VideoExportFixtures`: video nhiễu tổng hợp, ảnh trên đĩa), `VideoBackgroundRenderTests`, `VideoMediaOriginalsTests`, `VideoMediaLibraryTests`, `VideoStudioMediaSessionTests`, `VideoExportFlowTests`; sửa `VideoGeometryTests`, `VideoEffectMathTests`, `VideoStudioLayoutTests`, `CreationStoreTests` | mới / sửa |
| `ShotDexUITests/scripts/video-media-*.json`, `video-settings-*.json`, `video-export-*.json` | Test | route từng máy | mới |

Không bảng GRDB mới, không migration (dự án lưu JSON trong `creations.recipeJSON`); `photo_metadata` không đụng. Logic ở
Domain/Data; view chỉ đọc và gọi model.

## 5. Thứ tự task

Một AC = một task = một commit `feat(FS-12.xx): AC-n …` (các AC cùng một phép đo đi chung một task, ghi rõ); `/build` sau
mỗi commit; đụng UI thì `/screens` (iPhone 26.5 + 18.6, iPad, Duo trong/ngoài bằng `Tools/ui-drive` + `Tools/sim-shot`).
Thứ tự: ✅ khoá test → mảng **Media** (⚠️ rồi ❌) → mảng **Video Settings / pipeline** → mảng **Export**; task chờ plan khác
để cuối mảng. **Cả plan chỉ bắt đầu sau khi `vs-tools-selection-phone` (hàng đáy, ✕·tên·✓, phiên panel, đường mở Video Settings) và
`vs-wide-and-duo-layout` task 4–15 (lớp cửa sổ, chỗ chứa iPad/Duo) đã vào code.**

### Phase 0 — khoá cái đã đúng

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| L1 | Bộ khung test xuất: `VideoExportFixtures` (video nhiễu 1920×1080 tổng hợp bằng `AVAssetWriter`, ảnh JPEG trên đĩa như ảnh server, nhạc tổng hợp) gọi thẳng `VideoStudioService.export` | README AC-6, AC-7 | `VideoExportSmokeTests.nineBySixteenWithTransitionAndMusic` (`naturalSize` 1080×1920, lệch < 1/30 s), `.photoOnlyProjectHasRealVideoAndNoEmptyAudio` |
| L2 | Nền xám ở khung 9:16 | FS-12.10 AC-3 | `VideoExportSmokeTests.fitGreyBackgroundFillsTheBars` (hàng y 0 = #808080 ± 2). Đỏ do không gian màu → sửa trong task này |
| L3 | Bitrate 1080p30 H.264 | FS-12.10 AC-12 | `.bitrateIsTenMbpsAt1080p30` (nguồn nhiễu 4 s, `estimatedDataRate` 9,95 Mbps ± 15 %) |
| L4 | Shake 1/30 ở 60 fps | 01 §7 | `VideoEffectMathTests.shakeHoldsEachOffsetForTwoFramesAt60fps` |

### Phase M — Media (FS-12.09)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| M1 | Lưới Recents UIKit trên `PHFetchResult` không trần (T-1), thumbnail đúng cỡ ô × scale, cache có trần, nạp trước ≤ 2 màn; panel Media iPhone (4 cột 99, khe 2) mở từ ô Media; gỡ trần 400 + "Browse All Photos…" + sheet `VideoMediaPicker` khỏi Video Studio | AC-11 ⚠️ | `VideoMediaLibraryTests.recentsIsTheWholeFetchNoCap`, `.prefetchWindowIsTwoScreens`; **máy thật** cuộn 55 000 mục: Instruments Allocations < 60 MB so với lúc mở |
| M2 | Hàng tab Recents · Albums · In Video · n · Select · 🔍, vị trí §3; Albums (danh sách → lưới album, "‹ Albums") | AC-16, AC-19 | `ui-drive` `video-media-tabs.json` dump hàng tab (x ≤ 390); `VideoMediaLibraryTests.albumGridIsTheAlbumFetch` (FS-12.09 **AC-19**, thêm lúc duyệt) |
| M3 | `MediaUsage`: ✓ tròn 19 / viên nang ×n; đếm cả sticker | AC-6, AC-18 | `MediaUsageTests.twoUsesShowTimesTwo`, `.deletingBackToOneShowsCheck`, `.stickerCountsAsAUse` (×3) |
| M4 | Chạm = chèn ở playhead (`MediaInsertMath`), playhead tới cuối clip mới; bỏ `MediaInsertMode` | AC-1 ⚠️ | `MediaInsertMathTests.tapSplitsCoastAt8_4` (27,0 s, playhead 11,4), `.edgeInsertsWithoutSplit`, `.threeTapsKeepOrder`; số clip theo Q1 |
| M5 | Phiên Media ✕/✓ trên mô hình phiên của `vs-tools-selection-phone` | AC-8 | `VideoStudioMediaSessionTests.cancelRestoresAndLeavesUndoDepth` (2 lần chèn → ✕ → 5 clip, `undoStack.count` như lúc mở, redo rỗng) |
| M6 | Select → Add (N): số thứ tự đánh lại, Add (0) mờ, Add chèn theo thứ tự chọn một bước undo, ✓ Add luôn phần đang chọn | AC-2 | `VideoStudioMediaSessionTests.addThreeInSelectionOrderOneUndo`, `.confirmAddsPendingSelection` |
| M7 | In Video: hàng theo thứ tự timeline, khoảng giờ đơn cách, hàng dưới playhead sáng; chạm → playhead + chọn + Media đóng như ✓ | AC-7 | `MediaUsageTests.inVideoRowsInTimelineOrder` (6 hàng, "0:03–0:09"); model: chạm Coast → `currentTime == 3.0`, `selectedClipID == clip 2` |
| M8 | Bản gốc iCloud của media qua `OriginalFetching` (T-3); seam `VideoSourceLoading`; lần thêm hỏng không để lại bước undo rỗng | AC-10 ✅ | `VideoMediaOriginalsTests.offlineVideoIsLeftOutWithMessage` (fake `fail=1`: 5 clip, đúng câu), `.inCloudPhotoReadsFromTheDownloadedFile`, `.failedAddLeavesNoUndoStep`; sim `-ShotDexFakeICloud cloud=1,fail=1` + ảnh chụp |
| M9 | Quyền: hàng `.limited` (khoá · "ShotDex can see the 12 items you chose." · Manage Access…), nạp lại tại chỗ; bị từ chối (chữ NF-04 + Open Settings, In Video vẫn dùng); rỗng (2 câu) | AC-9 | `VideoMediaLibraryTests.limitedRowCountsGrantedItems`; sim 26.5: `simctl privacy reset` + chạm "Limit Access" (memory: `grant` không chạy trên 26.5), cấp thêm 3 → 15 ô, panel còn mở |
| M10 | Tìm: ô tìm thay hàng tab, `SearchService` → id → lưới | AC-12 | `VideoMediaLibraryTests.searchUsesTheLibraryQueryLanguage` (index trong bộ nhớ: 20 dòng 85 mm → 20 id); `ui-drive` gõ "85mm" |
| M11 | Giữ-kéo: `UILongPressGestureRecognizer` 0,3 s / 10 pt trên collection view, huỷ pan khi bắt đầu | AC-5 | `UIDriverTests` thêm `pressSeconds`; `video-media-drag.json`: vuốt 30 pt trong 0,2 s → lưới cuộn, không có `MediaDragGhost` trong dump |
| M12 | Bóng + đích thả: vạch trắng dính ranh giới gần nhất, viên nang "+ 0:14.2", tick haptic, tự cuộn ở mép 40 pt, pan timeline tắt; thả → chèn không tách, một bước undo; không lát timeline → đích là dải tổng quan | AC-3 ⚠️ | `MediaInsertMathTests.nearestBoundaryBetweenLakeAndNight` (14,2), `.autoscrollSpeedGrowsWithDepth`, `.dropDoesNotSplit` (38,0 s); `video-media-drag.json` thả trên 16:9 và 9:16 (`MP_P_Drag916`) |
| M13 | Thả lại lưới / khung / ngoài màn → bóng bay về 0,25 s, không đổi, không undo | AC-4 | `VideoStudioMediaSessionTests.cancelledDropChangesNothing` (`canUndo` không đổi) + route |
| M14 | VoiceOver ô: "Video, 0:06, in this video" + action Insert at Playhead / Select | AC-14 ⚠️ | `MediaUsageTests.accessibilityLabelSaysInThisVideo`; `a11y-voiceover` |
| M15 | iPad ngang: thêm **Select** vào header "Library" (header + 4 tab của `vs-wide-and-duo-layout` task 7), hàng Recents · Albums · In Video · 6 vừa 220 (đệm tab 8), lưới 3 cột 69 khe 6 lề 8 (`mediaPoolColumnCount/CellWidth`); bỏ menu Append/Insert, `.onDrag` | AC-13 ⚠️ | `VideoStudioDeskLayoutTests.poolMediaGridIsThreeColumnsOf69`; `ipad-vs-pool-media.json` dump (4 tab, header, hàng tab ≤ 236) |
| M16 | Duo trong: hàng tab cuộn ngang, Select · 🔍 cuối, mép mờ 24 | AC-17 | `Tools/ui-drive` `duo-video-media.json` + `Tools/sim-shot inner` |
| M17 | `design-parity` 10 board `MP_*` | AC-15 | agent `design-parity`; cả board sau `vs-wide-and-duo-layout` task 16–18 |

### Phase S — Video Settings + pipeline (FS-12.10, FS-12.01, FS-12.10b AC-3/4)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| S1 | Model mới (§4 hàng `VideoProjectModels`) + bảng 18 ô + khoá mới vào bộ giải mã khoan dung **của tools plan task 4** (T-4) + tỉ lệ mặc định theo clip đầu; trích lại freeze ở cỡ đích khi xuất (T-6) | 10 AC-4 ⚠️, AC-15 | `VideoOutputSpecTests.everyRatioAndResolution` (18 ô, cạnh chẵn, 21:9 4K = 3840×1646), `VideoProjectRecipeDecodingTests.oldRenderPresetKeyIsIgnored`, `.unknownCodecFallsBackToH264`, `.oneUnreadableClipKeepsTheProject`, `.defaultAspectIsNearestToFirstClip` (FS-12.10 **AC-15**), `CreationStoreTests` giữ xanh |
| S2 | `VideoExportEstimate` + `VideoEncodingSettings` (T-5): 0,16 × fps, HEVC × 0,6, + 128 kbps, "~1.2 GB" | 10 AC-7 ⚠️ | `VideoOutputSpecTests.hevcDropsThirtyToEighteen`, `.gigabyteFormatting`, `.writerAndEstimateShareOneBitrate`; L3 giữ xanh |
| S3 | fps xuất theo Video Settings, preview giữ 1/30 | 10b AC-3 ⚠️ | `VideoExportSmokeTests.nineBySixteenAt24fps` (1080×1920, `nominalFrameRate` 24, H.264, lệch < 1/24 s), `VideoCompositionTierTests.previewStaysAt30` |
| S4 | HEVC 60 fps | 10b AC-4 | `VideoExportSmokeTests.hevcAt60fps` (`kCMVideoCodecType_HEVC`, 60 fps) |
| S5 | Fill (T-2: hình học sang tầng video; tỉ lệ cũng sang tầng video) | 10 AC-2 | `VideoGeometryTests.fillCoversTheCanvas` (4 hướng xoay), `VideoExportSmokeTests.fillLeavesNoBackgroundPixel`, `VideoCompositionTierTests.aspectAndFramingKeepTheComposition` (cùng `AVComposition`, chỉ `videoComposition` đổi) |
| S6 | Nền Blur / Colour / Image **từng bên trước khi trộn**; Blur ở 1/8 cạnh dài; Image ghim ngoài LRU; mất ảnh → đen + "Image unavailable — choose another." | 01 §7b ⚠️, 10 AC-13, AC-14 | `VideoBackgroundRenderTests.blurPreviewMatchesExportScaledDown` (1280 vs 3840 thu về 320: ≤ 3/255), `.crossfadeBlendsEachSidesBackground`, `.missingImageIsBlack`; đo 30 fps preview Blur + crossfade trên **máy thật** |
| S7 | `VideoResolutionGate` + nút 4K mờ có khoá + câu lý do | 10 AC-5 | `VideoOutputSpecTests.threeOfFiveAre1080p`, `.mixedSizesSaySmallerThan4K`, `.freezeUsesSourceVideoSize`, `.allUHDUnlocks4K` |
| S8 | Tự hạ 4K → 1080p chung bước undo với lần thêm | 10 AC-6 | `VideoStudioSettingsTests.addingA1080ClipDropsTo1080pInOneUndo` (Undo một lần: clip mất, lại 4K) |
| S9 | Panel Video Settings iPhone (thứ tự §4, Done ✓, áp ngay, một chạm một bước, nhãn khung "9:16 · Fill", chạm công cụ hàng đáy thì đóng); nút Video Settings đĩa 36 ở (312, 11.5) mang hình tỉ lệ; Export đĩa cam 36; gỡ `RatioStrip`/`BackgroundStrip` (và hai lỗi undo `VS/VideoInspectorControls.swift:315`, `:325-333`) | 10 AC-1 | `VideoStudioSettingsTests.eachTapIsOneUndo`; `VideoStudioLayoutTests.phoneFrameAndPanelPer916` (402×226 → 216×384, 340 → 278 qua bảng của `vs-tools-selection-phone`); ảnh chụp 26.5 + 18.6 |
| S10 | "Video Settings" mọi nơi + nhãn VO "Video Settings, 16:9, 1080p, 30 fps", "4K, unavailable" | 10 AC-11 | dump 5 bố cục: không chuỗi "Export Settings"; `localization` |
| S11 | iPad popover 340 dưới nút ("16:9 · 1080p · 30 fps ⌄" / hai dòng), Duo trong cột 264 + ⌃, Duo ngoài panel từ y 334 | 10 AC-9 | `ipad-video-settings.json`, `duo-video-settings.json` + `sim-shot` |
| S12 | Dòng LUT mất ở đầu Video Settings | 10 AC-8 | sau 06c task 12: `exportLineCountsLooks` của 06c + ảnh chụp |
| S13 | `design-parity` `P6_RatioBackground` · `ES_*` · `DI5_RatioBackground` | 10 AC-10 | agent `design-parity`; cả board sau `vs-wide-and-duo-layout` task 16–18 |

### Phase E — Export (FS-12.10b)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| E1 | **Khung** panel Export Video (vùng theo FS-12.16 §5, tiêu đề + ✕, mở không xuất, hàng công cụ nhường chỗ); Sẵn sàng tạm = một nút Export xuất theo Video Settings (Custom) tới task 34 của plan captions-compare-presets; không Quality | 10b AC-1 ⚠️ | `VideoExportFlowTests.firstTapOpensNeverExports`; route dump: không "Quality", có ✕, chưa tiến độ |
| E2 | Đường Export → Video Settings: dòng **Custom** (iPhone) đóng Export, mở Video Settings — task 46 của plan captions giữ hành vi này | 10b AC-2 | `VideoExportFlowTests.customOpensVideoSettings` |
| E3 | Cancel ≤ 1 s, xoá file tạm ở mọi nhánh, Photos không thêm | 10b AC-6 ⚠️, README AC-8 | `VideoExportSmokeTests.cancelStopsWithinASecondAndLeavesNoFile` (nguồn nhiễu 20 s, huỷ ở 50 %, thư mục phiên không còn `.mp4`) |
| E4 | Kiểm chỗ trống 2 × ước tính trước khi bắt đầu | 10b AC-7 | `VideoOutputSpecTests.spaceCheckNeedsTwiceTheEstimate` (40 MB trống, ~30 → câu "about 60 MB needed") với `availableBytes` tiêm |
| E5 | Vào nền → huỷ như Cancel, lúc quay lại hiện "Export stopped when you left ShotDex. Export again to finish."; bỏ background task | 10b AC-8 ⚠️ | `VideoExportFlowTests.backgroundingCancelsAndExplains` (gửi `didEnterBackgroundNotification`); sim: Home giữa lúc xuất |
| E6 | Không được ghi Photos → câu + Open Settings, xoá file tạm | 10b AC-9 | `VideoExportFlowTests.photosDeniedSaysWhatToDo` (`importFile` tiêm ném `PHPhotosError.accessUserDenied`) |
| E7 | Project ảnh server: "Export…", Đích "Choose where it goes next" | 10b AC-11 ⚠️ | `ServerComposeToolTests.videoOfServerPhotosExportsToAFile` (giữ) + `VideoExportFlowTests.serverRunDestinationRow` |
| E8 | Bộ mã từ chối kích thước → "This size can't be encoded as H.264 on this device. Switch Codec to HEVC." | 10b AC-14 | **máy thật** iPhone 17 + iPad: xuất 2160×3840 và 2160×2700 H.264; bị từ chối thì map lỗi `canAdd`/`startWriting` + test với writer tiêm |
| E9 | Duo trong: chạm Export lần 1 mở cột, lần 2 (≥ 0,5 s, cùng chỗ) xuất; Duo ngoài như thế ở y 556 | 10b AC-10 | `VideoExportFlowTests.secondTapWithinHalfASecondIsIgnored`; `duo-video-export.json` |
| E10 | iPad, Duo trong: không Quality, không bộ chọn độ phân giải riêng trong Export Video | 10b AC-13 | dump iPad + Duo trong |
| E11 | Dòng LUT mất ngay trên nút xuất | 10b AC-5 | sau 06c task 12 |
| E12 | `design-parity` trạng thái **Đang xuất**: `P7_Export` · `IL5_Export` · `IP_Export` · `DI6_Export` · `DC_Export` (sau khi vẽ lại); Sẵn sàng đo ở task 49 của plan captions (`F8_*`) | 10b AC-12 | agent `design-parity`; cả board sau `vs-wide-and-duo-layout` task 16–18 |

**46 task** (4 khoá + 17 Media + 13 Settings + 12 Export). Chờ plan khác: S12, E11 (06c task 12); M17, S13, E12 chỉ xanh **cả board** sau `vs-wide-and-duo-layout` task 16–18.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **JSON project:** `Codable` tự sinh, thêm một khoá là project cũ giải mã `nil` và mất khỏi Video Projects | chắc chắn nếu không xử lý | S1 viết `init(from:)` khoan dung **trước** khi thêm khoá nào (T-4); không migration (app chưa phát hành) |
| **Bộ nhớ xuất 4K:** kho khung tĩnh 3840 × LRU 4 ≈ 132 MB + ảnh nền ghim ≈ 33 MB + Blur hai bên trong crossfade + bộ mã HEVC | trung bình | Blur tính ở 1/8; ghim đúng một ảnh nền; đo đỉnh bộ nhớ khi xuất 20 clip 4K 60 fps HEVC trên **iPhone 17** (Instruments); `memory-leak` |
| **Bộ nhớ lưới 55 000:** thumbnail không trần / prefetch quá xa | trung bình | cache có trần, prefetch ≤ 2 màn, đo < 60 MB trên máy thật (AC-11) |
| **H.264 phần cứng từ chối 2160×3840 / 2160×2700** | trung bình | đo máy thật (E8); bị từ chối thì câu Switch to HEVC, không tự đổi codec |
| **30 fps preview khi có nền Blur:** hai blur mỗi khung trong crossfade | trung bình | 1/8 cạnh dài; đo CADisplayLink trên iPhone 17 và iPad; quá tải thì hạ Blur preview xuống 1/16 (export giữ 1/8) — vẫn cùng ảnh sau thu nhỏ |
| **Concurrency:** tải bản gốc iCloud song song với `rebuildPreview`; huỷ khi đóng Media/Video Studio; export huỷ từ notification nền; `StillFrameStore` đọc file trên hàng đợi compositor | trung bình | tải ≤ 4, `Task` giữ trong model và huỷ ở `close()`; `setFiles` dưới khoá có sẵn; `swift-concurrency` |
| **Gesture:** giữ-kéo bắt đầu trong collection view, đi qua scroll view timeline (memory: gesture SwiftUI chết trong `UIScrollView`) | cao nếu làm bằng SwiftUI | UIKit recognizer trên lưới, vị trí theo toạ độ màn, timeline nhận qua model; pan timeline tắt suốt lúc kéo |
| **XCUITest không liệt kê Video Studio trên iPhone** (memory) — dump hàng tab, nút có thể rỗng | cao | phép đo iPhone lấy từ toán layout (`VideoStudioLayoutTests`) + `Tools/sim-shot` + `design-parity` bằng mắt; dump chỉ dùng cho nút đọc được |
| **Duo 669pt:** cột Video Settings 264×385 phải cuộn; Export dùng lại nút góc dưới | thấp | cuộn trong cột; E9 giữ nút đứng yên; đo bằng `Tools/ui-drive` (không dùng MCP sim tool trên Duo) |
| **PhotoKit `.limited`:** sim 26.5 không nhận `simctl privacy grant` | cao trên sim | `reset` + một lần chạm "Limit Access" (memory); `photokit-guard` |
| **Đổi phép kiểm đủ của `OriginalFetcher` cho video** có thể làm lệch đường ảnh của FS-02.06 | thấp | nhánh theo `mediaType`; test cũ của `OriginalPreparationTests`, `OriginalCompletenessTests` giữ xanh |
| `vs-wide-and-duo-layout` task 7 gỡ tab Effects trước khi Look (06c) vào → iPad ngang tạm không có lối vào filter cả video | chắc chắn | việc của plan đó (đã ghi ở task 7 của nó); plan này không đụng |
| Nền Blur có grade hay không khi 06c chuyển grade về từng bên | — | quyết định kỹ thuật: Blur lấy từ khung **sau** look của bên đó (là "chính khung đó"); Colour/Image không grade (khớp 06c "nền không grade"); ghi vào 06c task 1 lúc làm |

## 7. Câu hỏi còn treo (về tài liệu, không phải code)

- **Q1 — FS-12.09 AC-1 số học.** *(Duyệt 2026-10-03 theo đề nghị — spec đã sửa.)* Chạm một ảnh ở 8,4 tách Coast làm hai, nên timeline là **7** clip (5 + nửa Coast + ảnh mới),
  không phải 6; và "In Video · 7" chỉ đúng nếu đếm **mục thư viện khác nhau** (6 → 7), trong khi §4 vẽ mỗi hàng là một lần
  dùng ("Photo · clip 1"). **Đề nghị: sửa tài liệu** — đếm = số hàng = số lần dùng (clip + sticker), AC-1 thành
  "7 clip, 27,0 s; In Video · 8". Một luật, tab và danh sách luôn bằng nhau; AC-7 (6 hàng) và AC-16 ("In Video · 6") không đổi.
- **Q2 — Thiếu AC** *(Duyệt 2026-10-03 — FS-12.09 AC-19, FS-12.10 AC-13–15, FS-12.10b AC-14.)* cho những luật spec đã chốt mà plan phải làm: Albums (09 §4), nền Blur/Image và ảnh nền mất
  (10 §5, 01 §7b), tỉ lệ mặc định theo clip đầu (10 §5), câu bộ mã từ chối H.264 (10 §9, 10b §5). **Đề nghị: thêm AC qua
  `/spec`** — các task M2, S1, S6, E8 đã có test đặt sẵn tên để điền vào cột "Chứng minh bằng".

## 8. Cần đo

| Đo gì | Ở đâu | Task |
|---|---|---|
| Kích thước, fps, codec, thời lượng file xuất; huỷ ≤ 1 s; pixel nền | sim (unit test) | L1–L2, S3–S5, E3 |
| Bitrate 10 Mbps ± 15 % | sim (unit test) **và** máy thật — bộ mã của sim là VideoToolbox của Mac, điều khiển bitrate khác | L3 |
| Đỉnh bộ nhớ xuất 4K 60 fps HEVC, 20 clip | **máy thật** (iPhone 17) | S1/S4 |
| H.264 2160×3840, 2160×2700 có mã được không | **máy thật** iPhone 17 + iPad | E8 |
| 30 fps preview với nền Blur + crossfade | **máy thật** iPhone 17 + iPad | S6 |
| Cuộn 55 000 mục, bộ nhớ < 60 MB | **máy thật** (thư viện thật) | M1 |
| Video chỉ iCloud, offline | sim với `-ShotDexFakeICloud`; một lần máy thật chế độ máy bay lúc `/verify` | M8 |
| Haptic khi đổi ranh giới | **máy thật** | M12 |
| `.limited` 12 → 15 mục | sim 26.5 (reset + chạm) | M9 |
| Duo trong / ngoài | sim Duo, `Tools/ui-drive` + `Tools/sim-shot` | M16, S11, E9 |

## 9. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 10. Cách chứng minh là xong

- **Test:** mọi tên ở §5; `VideoExportSmokeTests` chạy trong `ShotDexTests` (không cần PhotoKit); full suite một lần khi xong cả intent (memory: per task chỉ test liên quan).
- **Màn hình phải chụp:** Media (Recents, Select 3, đang kéo 16:9 và 9:16, In Video, Albums, Tìm, `.limited`, bị từ chối, rỗng),
  Video Settings (Fit/Blur, Fit/Colour, Fit/Image, Fill, 4K khoá), Export (Sẵn sàng, Đang xuất, Lỗi, thiếu chỗ, rời app) — iPhone 26.5 + 18.6,
  iPad ngang + dọc, Duo trong + ngoài (`Tools/sim-shot`, khung có mask).
- **`design-parity`** từng board ở M17, S13, E12 tới khi lệch ≤ 2 pt.
- **Tài liệu cập nhật cùng commit:** cột "Chứng minh bằng" của FS-12.09/10/10b; FS-12.01 §7b–§9 nếu tên hàm đổi; FS-12.08 §2 (Video Settings trong model) nếu lệch; `DESIGN.md` không đổi (không token mới — tab trắng 20 %/6 %, `r-sm`, accent chỉ Export, đều có sẵn).
- **Agent giai đoạn Deploy:** `photokit-guard` (lưới, `.limited`, bản gốc iCloud, đổi `OriginalFetcher`) · `memory-leak` (lưới, kho khung tĩnh, xuất 4K) · `perf-profiler` (lưới 55 000, Blur mỗi khung) · `swift-concurrency` (tải bản gốc, huỷ xuất, hàng đợi compositor) · `data-migration` (bộ giải mã khoan dung của `recipeJSON`) · `device-layout` + `duo-ux-review` + `iphone-ux-review` (giữ-kéo, ngón cái) + `ipad-ux-review` · `ipad-multitasking` (thả từ app khác vẫn chạy, popover trong Split View) · `ios26-parity` · `a11y-voiceover` · `copy-consistency` + `localization` (câu mới, "Manage Access…", plural "3 of your 5 clips") · `design-parity`.
