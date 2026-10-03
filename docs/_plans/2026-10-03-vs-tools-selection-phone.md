# Kế hoạch — Video Studio: thanh công cụ, phiên chọn ✕ · tên · ✓, hàng lệnh, cắt mép, bố cục iPhone

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-12.04](../02-functional-spec/FS-12-video-studio/04-tools-and-inspector.md) (15 AC) · [FS-12.04b](../02-functional-spec/FS-12-video-studio/04b-command-rows.md) (11) · [FS-12.05 §3](../02-functional-spec/FS-12-video-studio/05-cutting-markers-and-fades.md) (13) · [FS-12.07](../02-functional-spec/FS-12-video-studio/07-phone-layout.md) (13) · [FS-12.06](../02-functional-spec/FS-12-video-studio/06-color-layer.md) "Đường vào" (không có AC riêng) — **52 AC** |
| Intent | [2026-10-03-video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — mảng **đầu tiên** của thứ tự xây |
| Design | canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ> (Version 26). Board của plan này: `Main`, `P2_ClipSelected`, `P3_TextOverlay`, `P4_MusicChooser`, `P5_MusicTrack`, `P8_Main916`, `P9_ClipSelected916`, `P9_Collapsed`, `P10_TextOverlay916`, `P11_Ratio43(_Selected)`, `P12_Ratio219(_Selected)`; hàng lệnh còn đo trên `IL2–IL4`, `IP2`, `IP3`, `DI2`, `DI3`, `DC2`, `DC3` (bố cục của chúng thuộc plan màn rộng). `build/design/video/project/` hiện chỉ có board F4/F7 + `canvas.json` — **export lại `project/` của Version 26** trước task đầu tiên có `design-parity` |
| Plan liên quan | **vs-wide-and-duo-layout** (FS-12.03/03b/07b — iPad, Duo trong, Duo ngoài) · [2026-10-02-video-photo-looks](2026-10-02-video-photo-looks.md) (FS-12.06c, đã duyệt, chờ khung) · plan Media (FS-12.09) · plan Video Settings/Export (FS-12.10/10b) · plan F1 chọn nhiều (FS-12.11), F2 nhịp (12), F3 ducking (13), F6 cắt từng khung (17/17b) |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **1** (khối 0, A–D, N) và bước **5** (khối E) của thứ tự xây. 63 task = 63 commit, chia 7 khối (§3). Khối E chạy **sau** plan Media, plan Video Settings và plan look |

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 1 (khối 0, A–D, N) và 5 (khối E)** của thứ tự xây.
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
- **Quyết định của plan này:** Q-1 … Q-11 duyệt đúng đề nghị. Đã sửa spec cùng commit duyệt: Q-7 → dòng âm lượng
  clip × Video sound ở FS-12.08 §2; Q-8 → tên clip giữ "Clip 2" (FS-12.03 AC-2, FS-12.03b §1, FS-12.04 §5); Q-9 →
  Rotate chỉ ở chế độ một video (FS-12.04b §3); thêm ngoại lệ Duo trong của ô Trim (FS-12.04b §4, theo plan
  precise-trim ❓-3). Q-10 (`DESIGN.md` tầng D) vẫn sửa ở task 43 — commit duyệt không đụng `DESIGN.md`.
- **Thứ tự trong plan:** task 1–2 (chỉ test) → **task 4** (bộ giải mã khoan dung + bỏ Master — task code đầu tiên) →
  **khối N** (N1–N12, lưu nháp) → task 3 → 5 → … → 41 (khối A–D). Khối E (42–51) là bước 5 của thứ tự xây.
- **Lớp cửa sổ — một kiểu, không hai:** task 6 ở đây tạo bộ phân loại theo **đặc tả của task 4 plan
  `vs-wide-and-duo-layout`** (tên `VideoStudioWindowClass`, 5 lớp, đọc cửa sổ + inset phải, `isShortWindow` < 720,
  bảng test của task 4 đó); `VideoStudioLayoutMode` không ra đời. Task 4 của plan màn rộng khi tới lượt chỉ còn nối
  màn hình đọc kích thước cửa sổ + inset và ghi `REVIEW_QUEUE` ngưỡng 60/84.
- **Số task:** 51 + 12 (khối N) = **63 task = 63 commit**.
- **Board canvas phải sửa** (canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ>, trước task
  `design-parity` đầu tiên của board đó):
  - `P3_TextOverlay`: thêm ô **Duplicate** (Q-11).
  - `IL2_ClipSelected`, `IP2_ClipSelected`: thêm ô **Look** vào hàng lệnh clip (FS-12.04b §8).
  - Mọi board có tên item "Clip 2 · Coast" (chân ✕ · tên · ✓, viewer header) → **"Clip 2"**: đã thấy ở `IL1`, `IL2`,
    `IP1`, `DI2`, `F4_IL`, `F4_IP`, `F7_IL`, `F8_IL`, `F8_IP` — grep lại sau khi export đủ `project/`.
  - Mọi board Video Studio còn vẽ alert **"Discard this video?"** → bỏ (FS-12.18).
  - Canvas **App Screens** <https://claude.ai/artifact/53VivNtnC7jPrMQZx41ra8>, màn **Video Projects** (hàng iPhone
    `PH_*`, iPad `IP_*`, Duo `DI_*`/`DC_*`): thêm dòng nháp (bìa clip đầu · nhãn **Draft** · "Edited 5 min ago") và
    hộp xác nhận **Delete Draft** (khối N, task N9–N10).

## 1. Hiểu đúng chưa

Thanh dưới hôm nay trộn hai loại việc: 4 nút thêm + 6 công cụ cả video (Ratio, Filter, Adjust, Color, Volume,
Background), cuộn ngang, và Back/Export nằm ở một băng riêng bên dưới. Chọn một item thì panel 264 trượt đè lên hai
băng đó, xoá là thùng rác trên dòng tiêu đề, không có cách nào **bỏ** những gì vừa sửa ngoài Undo từng bước.

Spec muốn: đáy chỉ còn **Media · Text · Sticker · Music · Look** (thêm vào timeline); việc cả video có đúng hai chỗ
(Look, Video Settings ở băng trên); chọn một item là mở một **phiên**: đáy thành **✕ · tên · ✓**, ✕ trả project về
đúng lúc chọn và gỡ luôn các bước undo của phiên, ✓ giữ từng bước. Lệnh của item là **hàng đầu panel**, ô 64×56 theo
tần suất, Delete đỏ cuối. Video bỏ slider Duration — cắt chỉ bằng **tay nắm mép** hoặc **Trim → Start/End to
Playhead**. iPhone: khung **cố định theo tỉ lệ** ở y 60, panel cao theo tỉ lệ (340/320/300/278/360/340), thu còn 78.

Plan này **sở hữu mô hình phiên + lịch sử undo** mà mọi plan Video Studio khác dùng lại (Look, Media, Video Settings,
F1 chọn nhiều), và **nguồn danh sách** công cụ/lệnh mà plan màn rộng đặt lên iPad và Duo.

## 2. Đối chiếu AC ↔ code

Đọc thật: `VideoStudioModel.swift` (toàn bộ), `VideoStudioSheetHost.swift`, `VideoStudioToolbar.swift`,
`VideoStudioCommandBand.swift`, `VideoStudioScreen.swift`, `VideoStudioMetrics.swift`, `VideoTimelineView.swift`,
`VideoTimelineScroller.swift`, `VideoTimelineTracks.swift` (ClipBand), `VideoViewerChrome.swift` (header, transport
gọn), `VideoStudioService.loadSources`, `VideoProjectModels.swift`, `Creation.swift`, `EditorToolBar.swift` (phiên
của editor ảnh), `project.pbxproj` (hướng xoay), các test `VideoStudio{Layout,DeskLayout}Tests`,
`VideoTimelineMathTests`, `ServerComposeToolTests` (cách dựng model trong test).

### FS-12.04 — Thanh công cụ và mô hình chọn

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 hàng đáy đúng 5 nút, không Ratio/Filter/… | ❌ | Hàng dựng từ `commandKinds` = Add·Text·Sticker·Music + `GlobalTool.allCases` (6) (`VideoStudioToolbar.swift:45-58`, `VideoStudioModel.swift:36-37`), cuộn ngang (`VideoStudioToolbar.swift:11-17`) | enum `VideoAddTool` 5 ca; hàng 5 ô 72×52 không cuộn; Ratio+Background → Video Settings (tạm), Filter/Adjust/Color → vỏ panel Look; Volume chung bỏ (task 5) |
| AC-2 mọi bố cục đủ 5 công cụ, kiểm bằng lặp | ❌ | Không có khái niệm "bố cục" chung: phone dùng toolbar, iPad dùng pool + menu Project Tools (`VideoStudioCommandBand.swift:111-138`); test hiện chỉ kiểm `GlobalTool` (`VideoStudioDeskLayoutTests.swift:220-260`) | `VideoStudioLayoutMode` (5 ca) + hàm thuần `addTools(for:)`; test lặp `allCases` (task 6) |
| AC-3 ✕ trả clip 2 về 1×/100, độ sâu undo như trước, Redo tắt | ❌ | Không có ✕; undo là mảng ảnh chụp không mốc (`VideoStudioModel.swift:597-657`); slider Volume của clip ghi `recipe.videoVolume` **cả project** (`VideoStudioSheetHost.swift:218-223`) | `VideoEditHistory` + `VideoEditSession` (Domain); ⚠️ Q-7 (Volume của clip) |
| AC-4 ✓ rồi Undo ×2: Volume trước, Speed sau | ❌ | Bước undo từng thao tác **đã đúng** (InspectorSlider gom một lần kéo: `VideoInspectorControls.swift:26-28`), nhưng không có ✓ | ✓ = kết thúc phiên, không đụng ngăn undo; test khoá thứ tự |
| AC-5 Text rồi ✕: không khối mới, ngăn undo như cũ | ⚠️ | Text thêm caption **rỗng** rồi mở trình sửa chữ toàn màn (`VideoStudioScreen.swift:241-252`), huỷ thì xoá (`:256-267`); `addTextOverlay` **không** đẩy undo (`VideoStudioModel.swift:1687-1696`) | Q-4 |
| AC-6 đổi sang băng chữ: clip giữ 2×, đáy ✕ · GOLDEN HOUR · ✓, panel cùng cao | ❌ | Chọn item khác chỉ đổi id (`VideoStudioModel.swift:271-309`); tiêu đề panel là "Video"/"Photo" + giây (`VideoStudioSheetHost.swift:130-157`); panel đã cố định 264 (`VideoStudioMetrics.swift:311`) | chọn item khác = ✓ rồi mở phiên mới; `VideoItemTitle` (Domain) |
| AC-7 Delete: 2 clip liền nhau, đáy về 5 công cụ, một Undo trả lại | ⚠️ | Liền nhau đã đúng (placement nối đuôi, `VideoStudioModel.swift:429-436`); `deleteClip` **không** đẩy undo (`:721-734`) — nút thùng rác tự `pushUndo` (`VideoStudioSheetHost.swift:165`), menu ⋯ thì không (`VideoViewerChrome.swift:589-591`) → xoá từ ⋯ không undo được | Q-3: undo vào trong lệnh model; Delete thành ô cuối hàng lệnh |
| AC-8 Duo trong: chạm Media khi đang chọn → không gì; 5 ô trắng 30% | ❌ | Duo trong hôm nay không có hàng đáy (rail/pool, `VideoStudioScreen.swift:403-421`) | luật thuần `toolsAreInert(mode:isSelecting:)` ở plan này; **chứng minh sau** khi plan màn rộng đặt hàng đáy Duo trong |
| AC-9 Music: Video sound 100→40, ✕ tiêu đề → 100, không bước undo | ❌ | Music là **sheet hệ thống** chọn bài (`VideoStudioScreen.swift:160-170`, `:922-1105`), không có dòng Video sound, không ✕ | panel Music trong khung (task 8) + phiên công cụ (task 14) |
| AC-10 chạm lại ô Music: đóng, giữ 40, một Undo về 100 | ❌ | như AC-9 | task 15 |
| AC-11 clip iCloud, không mạng: chọn được, Freeze mờ "Waiting for iCloud" | ⚠️ | Clip không tải được bị **gỡ khỏi project** lúc mở (`VideoStudioModel.swift:488-499`) và lúc thêm (`:1177-1186`), chỉ báo lỗi chữ | Q-5 |
| AC-12 lane V1 Lock: chạm clip 2 không chọn | ✅ | `toggleClip` chặn khi lane khoá (`VideoStudioModel.swift:276-279`); khoá lane đang chứa item chọn thì bỏ chọn (`:324-340`) | chỉ viết test khoá (task 1) |
| AC-13 26.5 vs 18.6 cùng tập nút | ❌ | ✕/✓ và hàng lệnh mới chưa có. Thư mục `Features/VideoStudio/` **không có** nhánh `#available` nào → tương đương do dựng chung | agent `ios26-parity` sau khối B (task 17) |
| AC-14 Quick Adjust: Speed · Video sound, không Master; panel Music: Video sound là dòng âm duy nhất | ❌ | Quick Adjust có Master (`VideoViewerToolStrip.swift:95-99`); công cụ Volume có Master + Clips (`VideoStudioSheetHost.swift:544-562`) | task 8 |
| AC-15 JSON còn Master 0,5: mở bình thường, mức clip trong file xuất không nhân 0,5 | ⚠️ | `masterVolume` vẫn trong recipe (`VideoProjectModels.swift:503`) và **nhân vào mix** (`VideoCompositionBuilder.swift:316`), meter đọc nó (`VideoAudioMeterColumn.swift:97`, nút mute master `:246-255`) | Q-2 |

### FS-12.04b — Hàng lệnh

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 clip video: 9 ô đúng thứ tự, Delete cuối `#FF6B5E` | ❌ | Hàng hiện Split · Mute · Animate · Replace · Freeze (+Rotate khi một video) (`VideoStudioSheetHost.swift:609-634`), ô 52×54 (`VideoStudioMetrics.swift:645-646`) | `VideoItemCommand` + `commands(for:)` thuần; ô 64×56 |
| AC-2 clip ảnh: Split · Trim · Replace · Duplicate · Look · Delete | ❌ | ảnh chỉ có Split · Replace (`:611-627`) | task 20 |
| AC-3 cùng danh sách ở 5 bố cục | ❌ | Một nguồn **đã** có (`commands` dùng chung `.band`/`.column`, `:600-607`) nhưng cột iPad **gập thành lưới** (`:76-78`, `VideoStudioCommandBand.swift:242-259`) — spec cấm | bỏ `wraps`; test lặp `VideoStudioLayoutMode.allCases` |
| AC-4 Trim sáng, hai chip đầu nội dung, panel giữ cao | ❌ | không có lệnh Trim trong panel; Trim to Playhead chỉ ở menu ⋯ (`VideoViewerChrome.swift:501-518`) | lệnh kiểu *mục* |
| AC-5 chạm Trim lần nữa: chip biến mất, nội dung bắt đầu bằng Speed | ❌ | như AC-4 | task 23 |
| AC-6 loa: lần 1 im, slider vẫn 80 mờ; lần 2 về 80; hai bước undo | ❌ | Mute là **ô lệnh** (`VideoStudioSheetHost.swift:614-619`); `isMuted` tách khỏi mức âm (`VideoProjectModels.swift:116`) → giữ số đã đúng về dữ liệu | đĩa loa 26 ở đầu dòng Volume (clip + nhạc) |
| AC-7 Split rồi ✕: còn 2 clip, không chọn gì | ❌ | Split chọn nửa phải (`VideoStudioModel.swift:881-900`); chưa có phiên | Split = ✓ + cắt + phiên mới |
| AC-8 Duplicate chữ rồi ✕: còn 1 khối | ❌ | `duplicateSelectedOverlay` có (`:1776-1792`, nhãn "Copy" `VideoStudioSheetHost.swift:653,664`); clip và nhạc **không** có Duplicate | Duplicate cho cả ba loại, phiên bắt đầu trước lúc thêm |
| AC-9 Duo trong: hàng lệnh cuộn trong cột 264 | ❌ | cột hiện 320 + lưới | luật một hàng (task 21); chứng minh sau plan màn rộng |
| AC-10 board ↔ dump ≤ 2pt | ❌ | — | `design-parity` |
| AC-11 ảnh có Duration 0,5–10; video **không** có "Duration", dòng phụ "6.2s · video" | ⚠️ | video vẫn có slider Duration (`VideoStudioSheetHost.swift:211`, `:238-263`); dòng phụ chỉ "6.2s" (`:150`) | Q-6 |

### FS-12.05 §3 — Cắt hai đầu clip

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 kéo tay nắm trái vào 2,0 s: trim 2–10, clip sau sớm 2 s, một bước undo | ❌ | Vùng `clipLeadingHandle/TrailingHandle` **có trong enum** (`VideoTimelineScroller.swift:19-20`) nhưng ClipBand không phát vùng đó (chỉ fade + reorder, `VideoTimelineTracks.swift:344-428`) và commit là `break` (`VideoTimelineView.swift:342-343`) | `VideoEdgeTrimMath` (Domain) + tab 12pt + vùng 44 |
| AC-2 2×, tay nắm phải vào 1 s: nguồn ra 10→8, dài 4 s | ❌ | như AC-1 | quy đổi qua tốc độ |
| AC-3 kéo ra quá nguồn: dừng ở 10 s, một haptic | ✅ một phần | phép kẹp có test `VideoTimelineMathTests.trimClampsIntoTheSourceWithAMinimumLength` (`VideoTimelineMathTests.swift:201`); cử chỉ + haptic chưa có | phần cử chỉ (task 35) |
| AC-4 ảnh 3 s, kéo vào 2,8 s: dừng ở 0,5 s | ❌ | — | task 36 |
| AC-5 Trim → Start to Playhead: nguồn 4–10, một Undo về 0–10 | ✅ một phần | Phép tính có (`VideoStudioModel.swift:915-949`), một bước undo; nhưng nằm trong model, tác động **clip dưới playhead**, không phải clip đang chọn | dời phép tính về Domain; chip tác động clip đang chọn, ⋯ giữ "clip dưới playhead" (spec §3 nói cả hai) |
| AC-6 2×, playhead cách đầu 1,5 s → điểm vào 3,0 s | ✅ | `sourceTime = trimStart + localTime × speed` (`VideoStudioModel.swift:934`) | test khoá sau khi dời về Domain (task 25) |
| AC-7 playhead trong clip 3: chip mờ 28%, "Move the playhead into this clip." | ❌ | — | task 26 |
| AC-8 nam châm 8pt về marker, một haptic | ❌ | `snappedTime` có sẵn (`VideoStudioModel.swift:1022-1034`), ngưỡng 8pt/pps đã dùng cho nhạc/chữ (`VideoTimelineView.swift:281`) | dùng lại; bỏ chính mép đang kéo khỏi ứng viên |
| AC-9 ✕ sau kéo tay nắm: trim về 0–10, Redo tắt | ❌ | cần phiên | task 38 |
| AC-10 hệ thống huỷ cử chỉ: không đổi, số bước undo không đổi | ✅ cơ chế | Scroller báo `.cancelled` (`VideoTimelineScroller.swift:330-331`), view chỉ commit ở `.ended` (`VideoTimelineView.swift:264-274`) | test ở tầng model sau khi commit dời vào model (task 39) |
| AC-11 clip iCloud chưa biết thời lượng nguồn: chỉ kéo vào | ❌ | phụ thuộc AC-11 của 04 (clip hôm nay bị gỡ) | sau task 30 |
| AC-12 IL2, IP2: tab 12pt cao bằng clip ≤ 2pt | ❌ | — | sau plan màn rộng |
| AC-13 video không Duration trên 4 máy; ảnh thì có | ⚠️ | như 04b AC-11 | gộp task 18 |

### FS-12.07 — Bố cục iPhone

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 xoay ngang: vẫn dọc | ✅ | iPhone chỉ khai báo dọc **cho cả app** (`project.pbxproj:895`, `:928` `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`) — rủi ro §9 "khoá cả app làm khoá Library" đã là trạng thái hiện nay, đúng ý | test khoá + sửa route; phần "khung 402×226 ở y 60" chứng minh lại ở task 43 |
| AC-2 16:9 không chọn: khung 402×226 y 60 … 5 ô 72×52 y 795 | ❌ | khung co giãn theo `stackLayout` (`VideoStudioMetrics.swift:351-447`); toolbar 62 + bottom bar 50 (`:27`, `:288`) | task 43 |
| AC-3 6 tỉ lệ: khung không đổi khi chọn, panel theo tỉ lệ, đáy 790 | ❌ | panel 264 trượt đè và nâng stack (`VideoStudioMetrics.swift:311-325`); `VideoAspect` chỉ 4 ca (`VideoProjectModels.swift:21-22`) | task 44; thêm `r4x3`, `r21x9` |
| AC-4 luật thuần cao khung → lát/panel | ❌ | — | `VideoPhoneLayout` (task 42) |
| AC-5 chọn nhạc lane 4: cửa sổ 62 hiện đúng lane | ❌ | scroller chỉ **báo** offset dọc (`VideoTimelineScroller.swift:76`), không nhận lệnh cuộn | task 45 |
| AC-6 băng trên: Back, Undo, Redo, Video Settings, Export; không Show original; x 138–264 trống | ❌ | băng trên phone: Undo · Redo · before/after · timecode (`VideoStudioCommandBand.swift:69-81`, `:186-209`); Back/Export ở băng dưới (`VideoStudioToolbar.swift:93-141`) | task 7 |
| AC-7 iPhone 375: timecode không cắt, đủ 6 nút | ⚠️ | test có (`VideoStudioDeskLayoutTests.swift:288`); thứ tự hiện 4 nút trái rồi timecode (`VideoViewerChrome.swift:436-468`), spec 2 · timecode · 2 · ⋯; timecode `hh:mm:ss:ff` chỉ giờ hiện tại, spec `0:08.4 / 0:24.0` | Q-1 |
| AC-8 pinch trên lát: zoom đổi, panel và khung đứng yên | ❌ | lát chưa có; pinch đã chỉ đổi `pps` cục bộ (`VideoTimelineView.swift:236-248`) | task 46 |
| AC-9 board Main, P2–P5, P8–P12, P9_Collapsed ≤ 2pt | ❌ | — | `design-parity` |
| AC-10 26.5 vs 18.6 Main, P2 | ❌ | không có `#available` trong thư mục | `ios26-parity` |
| AC-11 9:16, vuốt grabber xuống: panel 78 ở 712–790 … | ❌ | grabber hiện **bỏ chọn** khi vuốt > 40 (`VideoStudioScreen.swift:754-757`) | task 47 |
| AC-12 kéo tay nắm khi thu, vuốt lên: một bước undo, về 278 | ❌ | — | task 48 |
| AC-13 ✓ rồi chọn lại: panel mở đủ | ❌ | — | task 49 |

### FS-12.06 — Đường vào Filter · Adjust · Color

Không có AC riêng ("Xem README"). Hôm nay là ba công cụ ở hàng đáy (`VideoStudioModel.swift:37`), nội dung ở
`VideoStudioSheetHost.swift:542-543`, `:568-595`. Plan này làm **vỏ** công cụ Look (ô thứ 5, panel, chip
Filter · Adjust · Color bọc nội dung cũ, ✕ ✓ ở tiêu đề qua phiên chung); **ruột** Look (lưới look, My Looks, LUT,
Amount, Apply To) là task 6 của plan look. Gắn vào task 5 (AC-1 của 04, vì Look là một trong năm ô).

### Phát hiện ngoài bảng AC (ảnh hưởng mọi plan Video Studio)

- **Recipe video giải mã cứng.** `VideoProjectRecipe`, `VideoClip`, `MusicTrack`, `TimedOverlay` dùng `Codable` tự
  sinh — không có `init(from:)` nào trong `Domain/Video/` (đã grep), không `LossyArray`. Thiếu **một** khoá là cả
  project `nil` (`Creation.swift:102-105` nuốt lỗi bằng `try?`), và model **lặng lẽ dựng project mới** từ ảnh
  (`VideoStudioModel.swift:218-229`). Các chú thích "Optional in the decoder" (`VideoProjectModels.swift:471-478`) là
  sai. Mọi plan sắp thêm trường (look, Video Settings, nhạc nhịp…) sẽ làm mọi project đang lưu mở ra trắng. CLAUDE.md
  bắt decode khoan dung → **làm ở task 4**, trước mọi trường mới.
- **Undo nằm ở view.** ~40 lời gọi `model.pushUndo()` rải trong `VideoStudioSheetHost`, `VideoColorPanel`,
  `VideoTimelineView`, `VideoInspectorControls`, `VideoTransitionSheet`… Plan này chỉ dời undo vào model cho lệnh nó
  đụng (Delete, Duplicate, Text, Trim, cắt mép, Mute); phần còn lại → `REVIEW_QUEUE.md`.
- **Replace + ✕ làm mất nguồn.** `replaceSelectedClip` xoá nguồn của clip cũ ngay (`VideoStudioModel.swift:1156`);
  ✕ trả clip cũ về recipe mà không còn nguồn → builder bỏ qua, clip biến khỏi preview. Phải giữ nguồn tới lúc phiên
  kết thúc (task 12).

## 3. Thứ tự task

Luật xếp: theo mảng của intent (khung/thanh đáy → chọn item → … → kích thước); trong mỗi khối ✅ (test khoá) trước,
rồi ⚠️ theo quyết định, rồi ❌ — trừ khi ⚠️ cần một nền ❌ (ghi rõ). Một AC = một task = một commit
`feat(FS-12.0x): AC-n …`, `/build` sau mỗi commit, `/screens` khi đụng UI, chỉ chạy test liên quan; full suite một
lần cuối intent.

### Khối 0 — test khoá (không đổi code)

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 1 | Test khoá: lane V1 khoá thì `toggleClip` không chọn, `inspectorTarget == .none`; khoá lane đang chọn thì bỏ chọn | 04 AC-12 | `VideoSelectionSessionTests.aLockedLaneRefusesSelection` (model dựng từ `Creation.video` như `ServerComposeToolTests.swift:166-178`) |
| 2 | Test khoá hướng xoay iPhone; sửa `video-studio-orientation.json` không mở đầu bằng bước `orientation` (memory ui-drive) | 07 AC-1 | `VideoStudioOrientationTests.anIPhoneRunsPortraitOnly` (đọc `UISupportedInterfaceOrientations~iphone` của `Bundle.main` = `[portrait]`); route + `Tools/sim-shot` trước/sau xoay |

### Khối A — khung và thanh đáy

Thứ tự chạy: **4 → khối N → 3 → 5 → 6 → 7 → 8** (task 4 là task code đầu tiên của cả intent).

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 3 | Transport gọn: Go to Start · Back a Frame · timecode `m:ss.t / m:ss.t` · Forward a Frame · Go to End · ⋯ (nút 40 ở x 6/46/276/316/356); formatter `m:ss.t` của băng trên dời vào `VideoStudioMetrics` | 07 AC-7 ⚠️ | cập nhật `VideoStudioDeskLayoutTests.theCompactTransportFitsTheNarrowestPhone` (375pt, 6 nút); `compactTimecodeShowsPlayheadAndLength` |
| 4 | Bỏ Master: xoá `masterVolume` khỏi recipe, builder, meter (nút mute master → mute Video sound), Quick Adjust. **Decode khoan dung** cho `VideoProjectRecipe`/`VideoClip`/`MusicTrack`/`TimedOverlay` (`decodeIfPresent` + mặc định, mảng qua `LossyArray`) | 04 AC-15 ⚠️ | `VideoRecipeDecodingTests.aMasterKeyIsIgnored` (JSON có `masterVolume: 0.5` mở ra, mức clip = Video sound), `aProjectMissingNewerKeysStillOpens`, `oneBrokenClipKeepsTheRest`; `VideoAudioMixTests.clipGainIsVideoSoundOnly` (tham số audio mix tại 1 s); smoke export dùng chung test của plan Export |
| 5 | Năm công cụ thêm: `VideoAddTool` (media · text · sticker · music · look) thay `GlobalTool`; hàng 5 ô 72×52 cách 78 từ x 9, không cuộn, ô đang mở nền trắng 14% (không accent), chạm lại = đóng + giữ. **Tạm thời** cho tới plan sau: Media mở picker hệ thống như hôm nay (plan Media thay); Look mở **vỏ panel Look** (chip Filter · Adjust · Color bọc `FilterStrip`/sliders/`VideoColorPanel`, giữ-để-so-sánh chuyển từ băng trên vào tiêu đề này); Ratio + Background vào panel **Video Settings** tạm (chỉ Done ✓) mở từ băng trên (plan Video Settings thay ruột). iPad: menu Project Tools còn Look + Video Settings | 04 AC-1 (+ FS-12.06 đường vào) | `VideoStudioToolsTests.theBottomRowIsTheFiveAddToolsInOrder`; route `video-studio-chrome.json` (dump `{"type":"button"}` — điện thoại không liệt kê cây đầy đủ) + `Tools/sim-shot` |
| 6 | `VideoStudioLayoutMode` {phone, duoCover, duoInner, iPadLandscape, iPadPortrait} + phân loại theo cỡ cửa sổ (plan này viết luật `phone`: rộng ≤ 440; plan màn rộng tinh chỉnh bốn ca kia) + `addTools(for:)` (iPad: 4 tab/nút + Look mặc định) | 04 AC-2 | `everyLayoutOffersTheFiveAddTools` lặp `allCases`, so phần tử không đếm |
| 7 | Băng trên phone: Back · Undo · Redo (đĩa 36 trắng 10%, x 10/50/90) · Video Settings (đĩa 36, glyph theo tỉ lệ, x 312) · Export (đĩa 36 accent, glyph tối, x 356); x 138–264 trống; bỏ băng dưới Back/readout/Export | 07 AC-6 | `phoneTopBandLeavesTheIslandClear` (khung từ hàm vị trí thuần); route dump; sim-shot có mask |
| 8 | Panel Music trong khung (thay `VideoMusicChooserSheet` cho Add): tiêu đề 46 (icon 24 · "Add Music" 14,5 · ✕ 32), dòng **Video sound** 0–100 + "Original clip audio, whole project", "Add Music from Files…", MY MUSIC (dùng lại hàng nghe thử/waveform/xoá). Nội dung là view riêng để pool iPad (03b AC-7) dùng lại. Quick Adjust: Speed · Video sound | 04 AC-14 | route dump nút; sim-shot `P4_MusicChooser`; Replace nhạc vẫn dùng sheet tới plan Media |

### Khối N — lưu nháp ([FS-12.18](../02-functional-spec/FS-12-video-studio/18-drafts.md), thêm lúc duyệt 2026-10-03; chạy ngay sau task 4)

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| N1 | Dữ liệu: `Creation` thêm "ngày xuất" (rỗng = nháp) + bước đổi bảng GRDB đặt "ngày xuất = ngày sửa" cho mọi dòng có sẵn (đều sinh ra từ một lần xuất); `CreationStore` lưu/đọc nháp; mở nháp đi qua bộ giải mã khoan dung của task 4 | 18 AC-10 | `VideoDraftStoreTests.oldDraftMissingNewKeysOpens`, `oneBrokenClipKeepsTheDraft`, `existingRowsBecomeExported` (`AppDatabase.makeEmpty()`); agent `data-migration` |
| N2 | Hẹn ghi ~1 s sau thay đổi cuối (đồng hồ tiêm được), dồn thay đổi, ghi ở nền, bản mới nhất thắng; mọi thay đổi recipe (kể cả trường ngoài undo) hẹn ghi | 18 AC-1 | `VideoDraftAutosaveTests.savesOneSecondAfterTheLastChange`, `threeQuickChangesWriteOnce` |
| N3 | Project mới không sửa gì vẫn thành nháp (ghi ở Back) | 18 AC-11 | `aNewProjectWithNoEditsIsKept` (3 ảnh → một dòng 3 clip) |
| N4 | Back = ✓ phiên đang mở → ghi ngay → đóng; **gỡ alert "Discard this video?"** (`VideoStudioScreen.swift:124-125`, `:780`); project ảnh server (FS-17.06) không có nháp, giữ câu hỏi của FS-17.06 | 18 AC-2 | `backSavesWithoutAsking`, `serverProjectHasNoDraft`; route `video-studio-draft-back.json` (dump không alert) |
| N5 | Xuống nền → ghi ngay | 18 AC-3 | `backgroundingSavesImmediately` (gửi notification nền); sim: Home trong 0,3 s, `simctl terminate`, mở lại, sim-shot |
| N6 | Đổi scene (gập/mở Duo, đóng cửa sổ) → ghi ngay | 18 AC-4 | `sceneChangeSavesImmediately`; **đo tay** gập Duo trong Simulator.app |
| N7 | Mở lại: playhead lưu cùng nháp (khoá tuỳ chọn, ngoài undo — `restore()` giữ giá trị hiện tại); không chọn, không panel; undo rỗng | 18 AC-5 | `reopenRestoresPlayheadOnly` (8,4 s; `inspectorTarget == .none`; `canUndo == false`) |
| N8 | Export đánh dấu "ngày xuất" trên **đúng** dòng nháp; sửa sau xuất tự lưu cùng dòng; Export lại cập nhật dòng ấy | 18 AC-12 | `exportMarksTheDraftRowExported`, `editAfterExportKeepsOneRow` |
| N9 | Video Projects: một danh sách nháp + đã xuất theo ngày sửa; dòng nháp: bìa clip đầu, nhãn Draft, "Edited 5 min ago" (định dạng tương đối của hệ thống); số ở hàng Utilities đếm cả nháp | 18 AC-6 | `CreationStoreTests.videoProjectsListsDraftsAndExportsNewestFirst`; sim-shot Video Projects (canvas App Screens) |
| N10 | Giữ dòng nháp → Delete Draft + xác nhận ("The photos and videos stay in your library."); chỉ xoá dòng `creations` | 18 AC-7 | `deleteDraftRemovesOnlyTheRow` (không gọi PhotoKit); route xác nhận + Cancel |
| N11 | Ghi hỏng → banner "Couldn't save your video draft" + Try Again; project trong bộ nhớ giữ nguyên | 18 AC-8 | `failedSaveShowsBannerAndKeepsEditing` (store tiêm ném lỗi hết chỗ), `tryAgainClearsTheBanner` |
| N12 | Back khi lần ghi ngay hỏng: không đóng; alert Try Again · Leave Without Saving | 18 AC-9 | `backWithAFailedSaveStaysOpen`; sim-shot alert |

### Khối B — phiên chọn (nền chung của mọi plan Video Studio)

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 9 | **Nền:** `Domain/Video/VideoEditHistory.swift` (ngăn undo/redo ảnh chụp có **số thứ tự**, trần 40, nhóm kéo, `checkpoint()`/`rollback(to:)`), `Domain/Video/VideoEditSession.swift` (đích: item hoặc công cụ, recipe lúc bắt đầu, checkpoint, `isCollapsed`). Model: `select*` = ✓ phiên cũ rồi mở phiên mới; `clearSelection` = ✓ (chạm timeline trống, chạm khung khi dừng, grabber, Esc, **Return**, Back); Undo qua mốc đầu phiên = kết thúc phiên + bỏ chọn. Chân **✕ · tên · ✓** trên phone thay 5 ô (✕ đĩa tối `rgba(24,24,26,.82)` viền trong 1pt trắng 14%; ✓ đĩa trắng glyph đen) | 04 AC-4 | `VideoEditHistoryTests` (trần 40, nhóm, checkpoint qua trần), `VideoSelectionSessionTests.commitKeepsEachStep` (Speed 2× rồi Volume 60, ✓, Undo → Volume về, Speed 2×; Undo → 1×), `undoPastTheSessionStartDeselects` |
| 10 | Delete: undo vào trong `deleteClip`/`deleteSelectedOverlay`/`removeMusicTrack`; Delete kết thúc phiên như ✓; menu ⋯ dùng cùng lệnh | 04 AC-7 ⚠️ | `deleteKeepsClipsContiguousAndUndoesOnce`, `deleteFromTheTransportMenuIsUndoable` |
| 11 | Text: phiên mở **trước** khi thêm; khối "Text" từ playhead tới hết video, chọn, lệnh **Edit** sáng (cuộn ô nhập lên đầu + bàn phím); trình sửa toàn màn còn ở nút mở rộng của ô; Sticker và Music thêm cũng mở phiên trước | 04 AC-5 ⚠️ | `textThenCancelLeavesNoBlockAndNoUndo`, `stickerThenCancelRemovesIt`, `musicThenCancelRemovesTheTrack` |
| 12 | ✕: `rollback` về recipe đầu phiên, gỡ bước undo của phiên, xoá Redo; nguồn của clip bị Replace giữ tới hết phiên; thời lượng nguồn đã biết được gieo lại sau khi khôi phục; huỷ lần dựng preview đang chạy | 04 AC-3 | `cancelRestoresTheClipAndTheUndoDepth`, `cancelAfterReplaceKeepsTheOldSource`, `cancelWithNoChangeOnlyDeselects` |
| 13 | Đổi item = ✓ + phiên mới; `Domain/Video/VideoItemTitle.swift`: dòng 1 "Clip 2"/"Photo 2"/"Freeze 2" (cùng luật header viewer, `VideoViewerChrome.swift:78-94` gọi lại), nội dung chữ, tên bài; dòng 2 mono "6.2s · video", "Text · 1.0 → 5.0s", "Music · 0.0 → 18.4s"; chiều cao panel không phụ thuộc item | 04 AC-6 | `switchingItemsKeepsTheFirstItemsEdits`, `VideoItemTitleTests`; dump chân (sim-shot) |
| 14 | Phiên công cụ: mở Music/Look/Media/Video Settings cũng là phiên (đích = công cụ); ✕ ở tiêu đề panel Music bỏ mọi thay đổi từ lúc mở | 04 AC-9 | `toolCancelRestoresVideoSoundAndLeavesNoUndo` |
| 15 | Đóng bằng cách khác (chạm lại ô, grabber, chạm timeline trống, mở công cụ khác) = giữ | 04 AC-10 | `reopeningTheCellKeepsAndUndoesOnce` |
| 16 | Luật năm ô khi đang chọn: phone thay hẳn; Duo trong/ngoài mờ 30% không nhận chạm; iPad ngang chèn từ pool = ✓ trước; iPad dọc nhường chỗ — hàm thuần theo `VideoStudioLayoutMode` | 04 AC-8 | `toolsAreInertWhileSelectingOnTheDuo`; dump Duo trong bằng `Tools/ui-drive` **sau** task đặt hàng đáy của plan màn rộng |
| 17 | Chạy `ios26-parity` trên Main + P2 + P3 + P5 (26.5 vs 18.6) | 04 AC-13 | báo cáo agent; sửa nếu lệch |

### Khối C — hàng lệnh

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 18 | Video bỏ dòng Duration; nội dung mặc định clip video: Speed (chip 0.5× 1× 2× 4×) · Volume · FADE (in/out) · MOTION (chip, `ClipEffectRow` dùng lại); ảnh/freeze: Duration 0,5–10 · FADE · MOTION; dòng phụ "6.2s · video" — hàm thuần `VideoClipPanelSections.sections(for:)` | 04b AC-11 + 05 AC-13 ⚠️ | `videoClipHasNoDurationSection`, `photoClipKeepsDuration`; dump 4 máy (phone ở đây, Duo/iPad sau plan màn rộng) |
| 19 | `VideoItemCommand` + `commands(for: VideoItemKind)` thuần (6 loại item, Beats/Ducking **ẩn** tới F2/F3, Delete cuối); ô 64×56 bo `r-cell` 10, nhãn 10pt/500, khoảng icon–nhãn 5, hàng đệm 10, khe 4, dải mờ phải 32, kẻ 1pt trắng 7%; hàng là đầu panel; bỏ thùng rác tiêu đề | 04b AC-1 | `VideoItemCommandsTests.videoClipRowIsTheSpecOrder`; dump P2 |
| 20 | Hàng clip ảnh | 04b AC-2 | `photoRowHasNoSpeedVolumeFreeze` |
| 21 | Một hàng cuộn ở mọi bề rộng (bỏ `wraps`/lưới), mọi bố cục đọc cùng `commands(for:)` | 04b AC-3 | `everyLayoutGetsTheSameCommands` lặp `VideoStudioLayoutMode.allCases` × 6 loại item |
| 22 | Lệnh kiểu *mục*: Trim sáng (nền trắng 14%), khối hai chip Start/End to Playhead (cao 30 bo 8) + "Or drag the clip's edges on the timeline." | 04b AC-4 | `trimTogglesItsBlock` (trạng thái mục ở model); sim-shot panel giữ cao |
| 23 | Chạm lại mục = tắt, nội dung về Speed | 04b AC-5 | `tappingTrimAgainReturnsToSpeed` |
| 24 | `Domain/Video/VideoTrimMath+Playhead` (tên thật lúc làm: `VideoClipTrimMath`): Start/End to Playhead dời từ model; chip tác động **clip đang chọn**, ⋯ giữ clip dưới playhead | 05 AC-5 | `startToPlayheadKeepsTheTail` (0–10, playhead 4 → 4–10, 6,0 s), model: một Undo về 0–10 |
| 25 | Test khoá quy đổi tốc độ | 05 AC-6 | `startToPlayheadConvertsThroughSpeed` (2×, cách đầu 1,5 s → 3,0 s) |
| 26 | Chip mờ 28% + "Move the playhead into this clip." khi playhead ngoài clip hoặc trùng mép; dưới tối thiểu = không làm gì + haptic lỗi | 05 AC-7 | `chipsAreUnavailableOutsideTheClip` (hàm thuần trả lý do) |
| 27 | Đĩa loa 26 ở đầu dòng Volume (clip video + nhạc), nhãn "Mute"/"Unmute", slider mờ 30% giữ số, mỗi chạm một bước undo; bỏ ô Mute | 04b AC-6 | `muteKeepsTheLevelAndUndoesStepwise` |
| 28 | Split = ✓ cho clip đang chọn, cắt tại playhead, phiên mới trên nửa phải; ✕ không gỡ vết cắt | 04b AC-7 | `splitThenCancelKeepsTheCut` |
| 29 | Duplicate cho chữ, sticker, clip, nhạc: ✓ cho gốc, chèn ngay sau, chọn bản sao, phiên bắt đầu trước khi chèn (✕ gỡ bản sao) | 04b AC-8 | `duplicateThenCancelLeavesOneBlock`, `duplicateClipInsertsAfterAndSharesTheSource` |
| 30 | Clip không tải được **ở lại** project: `unavailableClipIDs` (trạng thái màn, không lưu), thời lượng từ `PHAsset.duration` (siêu dữ liệu cục bộ), builder dựng đoạn trống hợp lệ (memory: blank clip phải well-formed); chọn được, Freeze/Split video mờ + "Waiting for iCloud"; banner thay vì gỡ clip | 04 AC-11 ⚠️ | `anUnavailableClipStaysAndBlocksFreeze`, `VideoCompositionBuilderTests.unavailableClipIsAWellFormedGap`; **máy thật** offline cho phần iCloud |
| 31 | Hàng lệnh Duo trong cuộn trong cột 264 | 04b AC-9 | `Tools/ui-drive` swipe theo điểm + dump, **sau** cột 264 của plan màn rộng |
| 32 | `design-parity` hàng lệnh: P2, P3, P5, P9, P10 (phone, plan này); IL2–IL4, IP2, IP3, DI2, DI3, DC2, DC3 sau plan màn rộng | 04b AC-10 | `Tools/design-board compare` ≤ 2pt |

### Khối D — tay nắm mép

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 33 | `Domain/Video/VideoEdgeTrimMath.swift`: kéo mép trái/phải theo giây timeline → trim nguồn (video, quy đổi tốc độ) hoặc thời lượng (ảnh/freeze), kẹp, cờ "chạm giới hạn". ClipBand: hai tab 12pt `#57BFD1` ngoài mép, cao bằng clip, vùng chạm 44 (16 ra ngoài); núm fade giữ góc trên (vùng fade thắng trong 20pt trên cùng). Commit qua model (`edgeTrim(_:phase:)`): `.changed` cho khung preview tới mép + nhãn thời lượng, `.ended` một bước undo trong phiên, khung về playhead cũ | 05 AC-1 | `VideoEdgeTrimMathTests.leadingDragMovesTheSourceInPoint`; model: clip 3 sớm 2,0 s, một bước undo |
| 34 | Tốc độ 2×, tay nắm phải | 05 AC-2 | `trailingDragConvertsThroughSpeed` |
| 35 | Giới hạn nguồn + haptic nhẹ một lần | 05 AC-3 | `dragPastTheSourceStopsAndReportsTheLimit` |
| 36 | Ảnh 0,5–10 | 05 AC-4 | `photoEdgeClampsAtHalfASecond` |
| 37 | Nam châm 8pt (playhead, marker, mép clip khác, không tính chính mép đang kéo) + haptic | 05 AC-8 | `edgeSnapsToAMarkerWithinEightPoints` |
| 38 | ✕ sau cắt mép | 05 AC-9 | `cancelUndoesAnEdgeTrim` |
| 39 | Cử chỉ bị huỷ | 05 AC-10 | `cancelledDragChangesNothing` (model nhận `.cancelled`) |
| 40 | Clip chưa biết thời lượng nguồn: chỉ kéo vào | 05 AC-11 | `unknownSourceOnlyTrimsInwards` (sau task 30) |
| 41 | `design-parity` tay nắm trên IL2, IP2 | 05 AC-12 | sau plan màn rộng |

### Khối E — kích thước iPhone (chạy **sau** plan Media, plan Video Settings và task 6 plan look)

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| 42 | `VideoPhoneLayout` thuần: khung theo tỉ lệ (bảng §3 × bề rộng/402), transport, timeline, lát (= 662 − cao khung − 340 nếu ≥ 96), panel, tổng quan 28, thu 78; `VideoAspect` thêm `r4x3`, `r21x9` (plan Video Settings dùng lại; bảng 18 ô là AC của họ) | 07 AC-4 | `VideoPhoneLayoutTests.sliceAndPanelFollowTheFrame` (226/342/362/384/302/172 → lát 96/0/0/0/0/150, panel 340/320/300/278/360/340) |
| 43 | Phone stack mới: khung cố định y 60, transport, timeline tới 790, hàng đáy 790–852; bậc lane `phone` 40/80/46, thước 33, ô thumbnail 60, ô chuyển cảnh 26 (Duo trong giữ `compact`); `stackLayout` chỉ còn cho bố cục khác. Cập nhật đoạn "panel trượt đè" của `DESIGN.md` tầng D (Q-10) | 07 AC-2 | `phoneSixteenNineMatchesTheBoard`; dump nút + sim-shot `Main` |
| 44 | Panel theo tỉ lệ, đáy 790, khung ±0 khi chọn; dải tổng quan 378×22 (dùng lại `VideoTimelineOverview`) | 07 AC-3 | `selectingNeverMovesTheFrame` (6 tỉ lệ); sim-shot P2, P9, P11/P12 _Selected |
| 45 | Lát timeline cuộn dọc tới lane của item chọn (scroller nhận offset dọc theo token) | 07 AC-5 | `sliceScrollsToTheSelectedLane` (hàm thuần lane → offset); sim-shot |
| 46 | Pinch trên lát | 07 AC-8 | sim-shot trước/sau pinch (`touch2_path` trên iPhone, không trên Duo) |
| 47 | Thu panel 78 (grabber xuống), tổng quan ẩn, timeline tới 712, tay nắm chạm được; panel công cụ: vuốt xuống = đóng + giữ | 07 AC-11 | `collapsedPanelGivesTheTimelineBack` (9:16: 484–712); `P9_Collapsed` |
| 48 | Kéo tay nắm khi thu, vuốt lên về 278; lệnh *mục* bung panel, lệnh *hành động* chạy tại chỗ | 07 AC-12 | `trimWhileCollapsedIsOneStep` |
| 49 | Thu là trạng thái phiên | 07 AC-13 | `collapseResetsWithTheSession` |
| 50 | `design-parity` Main, P2–P5, P8–P10, P11/P12 (+_Selected), P9_Collapsed | 07 AC-9 | ≤ 2pt mọi phần tử chrome |
| 51 | `ios26-parity` Main, P2 | 07 AC-10 | báo cáo agent |

**Tái dùng, không viết lại:** `VideoTimelineMath.clampedTrim`/`placements`/`clipIndex`, `VideoSplitMath.split`,
`snappedTime`, `TimelineDragZone` + vùng UIKit của scroller (memory: cử chỉ SwiftUI chết trong UIScrollView),
`InspectorSlider` (một lần kéo = một bước), `ClipEffectRow`, `RatioStrip`/`BackgroundStrip` (tạm trong Video
Settings), `VideoColorPanel`, `FilterStrip` (tạm trong Look), hàng nghe thử/waveform của `VideoMusicChooserSheet`,
`ImportedMusicStore`, `VideoTimelineOverview`, `VideoLevelMeterBar` (thanh LEVEL panel nhạc), hình chân phiên của
editor ảnh `EditorToolBar.sessionBar` (`EditorToolBar.swift:115-145`) làm mẫu bố trí — hình ✓ khác (đĩa trắng theo
spec, editor ảnh là chữ nhật bo 12), ghi cho `component-consistency`.

### Tầng nhận logic

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `Domain/Video/VideoEditHistory.swift` | Domain | ngăn undo/redo có số thứ tự, trần 40, nhóm, checkpoint/rollback | mới |
| `Core/Models/Creation.swift`, `Data/Database/AppDatabase.swift` (bước đổi bảng), `Data/Database/CreationStore.swift` | Core / Data | "ngày xuất" (nháp), lưu/đọc/xoá nháp (khối N) | sửa |
| `Features/VideoStudio/VideoStudioModel.swift` (+ `VideoStudioModel+Draft.swift`), `Features/Creations/CreationsScreen.swift` | Features | hẹn ghi, ghi ngay ở Back/nền/scene, banner, dòng Draft + Delete Draft (khối N) | sửa / mới |
| `Domain/Video/VideoEditSession.swift` | Domain | phiên: đích, recipe đầu phiên, checkpoint, `isCollapsed`, mục đang bật | mới |
| `Domain/Video/VideoItemTitle.swift` | Domain | tên + dòng phụ (header viewer, chân phiên, Look "Clip 2") | mới |
| `Domain/Video/VideoEdgeTrimMath.swift`, `VideoClipTrimMath.swift` | Domain | cắt mép, Start/End to Playhead | mới (dời phép tính từ model `:915-949`) |
| `Domain/Video/VideoProjectModels.swift` | Domain | bỏ `masterVolume`; decode khoan dung 4 kiểu; `VideoAspect` +2 ca; (Q-7) `VideoClip.volume` | sửa |
| `Data/Sources/VideoCompositionBuilder.swift` | Data | bỏ nhân master (`:316`); đoạn trống cho clip chưa tải (task 30) | sửa |
| `Data/Sources/VideoStudioService.swift` | Data | trả clip không tải được thay vì bỏ im (task 30) | sửa |
| `Features/VideoStudio/VideoStudioModel.swift` | Features | lịch sử + phiên thay `undoStack`; lệnh Delete/Duplicate/Text/Trim/cắt mép mang undo bên trong; `VideoAddTool` thay `GlobalTool` | sửa |
| `Features/VideoStudio/VideoStudioTools.swift` | Features (thuần) | `VideoAddTool`, `VideoItemCommand`, `commands(for:)`, `addTools(for:)`, `toolsAreInert` | mới |
| `Features/VideoStudio/VideoStudioMetrics.swift` (+ `VideoStudioMetrics+Phone.swift`) | Features (thuần) | `VideoStudioLayoutMode`, hằng chung (§3 hợp đồng), `VideoPhoneLayout`, bậc lane `phone` | sửa / mới |
| `VideoStudioToolbar.swift`, `VideoStudioCommandBand.swift`, `VideoStudioSheetHost.swift`, `VideoStudioScreen.swift`, `VideoTimelineTracks.swift`, `VideoTimelineView.swift`, `VideoTimelineScroller.swift`, `VideoViewerChrome.swift`, `VideoViewerToolStrip.swift`, `VideoAudioMeterColumn.swift` | Features | chân phiên, hàng 5 ô, băng trên, hàng lệnh 64×56, panel Music/Look/Video Settings tạm, tab mép, cuộn dọc theo lệnh, transport | sửa |
| `Features/VideoStudio/VideoMusicPanel.swift`, `VideoSessionFooter.swift` | Features | panel Music trong khung; chân ✕ · tên · ✓ (vị trí do bố cục truyền vào) | mới |
| `ShotDexTests/Video{EditHistory,SelectionSession,ItemCommands,ItemTitle,EdgeTrimMath,ClipTrimMath,RecipeDecoding,AudioMix,PhoneLayout}Tests.swift`, `VideoStudioOrientationTests`, `VideoStudioToolsTests` | Test | | mới; `VideoStudioDeskLayoutTests` sửa (bỏ test `GlobalTool`) |
| `ShotDexUITests/scripts/video-studio-{chrome,session,commands,trim,phone-ratios}.json`, `video-studio-orientation.json` | Route | | mới / sửa |

### Hợp đồng chung với plan màn rộng (vs-wide-and-duo-layout)

Plan này làm trước nên **tạo** các mối nối; plan màn rộng chỉ đọc và điền phần của mình:

| Thứ | Ai sở hữu | Ghi chú |
|---|---|---|
| `VideoEditHistory`, `VideoEditSession`, luật ✕/✓, `VideoItemTitle` | plan này | màn rộng chỉ đặt chân ✕ · tên · ✓ (Duo trong x 620–907, Duo ngoài chân rail, iPad chân inspector/dock) |
| `VideoAddTool`, `VideoItemCommand`, `commands(for:)`, `addTools(for:)`, `toolsAreInert` | plan này | màn rộng không viết danh sách tay (memory "phone has every iPad feature") |
| `VideoStudioLayoutMode` + phân loại | plan này tạo (`phone`: rộng ≤ 440, cả Slide Over iPad); màn rộng định nghĩa 4 ca còn lại | một hàm `mode(for size:)`, test ở hai plan |
| Ô lệnh 64×56, `r-cell` 10, nhãn 10/500, hàng đệm 10 khe 4, dải mờ 32, kẻ 1pt trắng 7%, đĩa ✕/✓, mờ 30% khi trơ, nền ô bật trắng 14%, panel: dải mờ đáy 30 + thanh cuộn 3×70, grabber 36×4 | plan này (`VideoStudioMetrics.swift`) | màn rộng **không** tạo bản thứ hai |
| Ô công cụ 72×52 phone; chiều cao panel phone theo tỉ lệ; thu 78 | plan này | Duo ngoài dùng chung luật thu 78 |
| Ô công cụ Duo ngoài 64×56 trong rail 84, hàng đáy Duo trong 56, cột 264, inspector iPad 540/280, dock 324, chiều cao panel Duo/iPad, bậc lane `compact`/`regular`, viewer header/meter/pool | plan màn rộng | `panelHeight(mode:aspect:)` là **một** hàm; plan này viết ca `phone`, họ viết ca còn lại |

**Đề nghị cho plan look** (không sửa plan đó, chỉ ghi để người duyệt quyết): `VideoLookSession` (task 9/10 của họ)
trùng `VideoEditSession` → thành phiên công cụ đích `look`, task 9/10 của họ còn là test; task 6 của họ thay ruột vỏ
panel Look của task 5 ở đây; `VideoViewerChrome.clipTitle` → `VideoItemTitle` làm ở task 13 ở đây.

## 4. Câu hỏi ⚠️ — mỗi chỗ một câu, kèm đề nghị

| Q | Chỗ lệch | Đề nghị |
|---|---|---|
| Q-1 | 07 AC-7: transport gọn 4 nút trái + timecode `hh:mm:ss:ff` chỉ giờ hiện tại; spec 2 · timecode `m:ss.t / tổng` · 2 · ⋯ | **Tài liệu đúng** — board P2/Main vẽ vậy, và hai nút bước khung kẹp hai bên timecode dễ bấm lặp hơn. |
| Q-2 | 04 AC-15: Master còn trong recipe và nhân vào mix | **Tài liệu đúng** — xoá trường; JSON cũ có khoá thừa vẫn mở (decode khoan dung, task 4). |
| Q-3 | 04 AC-7: xoá từ menu ⋯ không có bước undo; xoá chữ đẩy undo ở view | **Tài liệu đúng** — lỗi, không phải lựa chọn: undo vào trong lệnh model. |
| Q-4 | 04 AC-5: Text thêm caption rỗng + trình sửa toàn màn; spec thêm khối "Text" + lệnh Edit trong panel | **Tài liệu đúng** — board P3 vẽ Edit; trình sửa toàn màn giữ sau nút mở rộng của ô nhập, không mất gì. |
| Q-5 | 04 AC-11 (+05 AC-11): clip không tải được bị gỡ khỏi project | **Tài liệu đúng** — giữ clip với thời lượng `PHAsset.duration`, đoạn trống hợp lệ, "Waiting for iCloud"; clip biến mất là thứ người dùng không sửa được. |
| Q-6 | 04b AC-11 / 05 AC-13: video còn slider Duration, dòng phụ thiếu "· video" | **Tài liệu đúng** — đã chốt 2026-10-03; slider thời lượng là lối cắt thứ ba. |
| Q-7 | Dòng **Volume** của clip video ghi `videoVolume` của **cả project**; FS-12.08 §2 không có mức âm riêng của clip, nhưng 04 AC-3 / 04b AC-6 nói "clip 2 Volume" | **Tài liệu đúng, thêm một dòng vào FS-12.08 §2**: `VideoClip.volume` (mặc định 1, decode khoan dung) nhân với Video sound — một slider trong panel của *một* clip mà đổi *mọi* clip là control nói sai phạm vi của nó. |
| Q-8 | Tên "Clip 2 · Coast" (04 §5, 03 AC-2): app không có tên địa điểm | **Code đúng** — "Clip 2" như plan look đã chốt (Q4 của họ); sửa chữ ở 04 §5 và 03 AC-2. |
| Q-9 | Chế độ một video (Photo Detail → Edit) có Rotate (FS-12.01 bảng lối vào "Một video": "thêm Rotate", `VideoStudioSheetHost.swift:629-631`); 04b §3 không có | **Code đúng** — giữ Rotate trước Delete chỉ ở chế độ một video; thêm một dòng vào 04b §3. |
| Q-10 | `DESIGN.md` tầng D: "panel trượt **đè lên** hàng công cụ + bottom bar" — FS-12.07 mới: khung cố định, đáy thành ✕ · tên · ✓, panel lấy chỗ timeline | **Spec đúng** — sửa đoạn đó của `DESIGN.md` trong task 43 (và câu về chân phiên ở task 9). |
| Q-11 | Board P3 (chữ) không có ô Duplicate; 04b §3 có | **Spec đúng** (luật "một danh sách") — sửa board P3 trên canvas. |

**❓ chưa kết luận:** không AC nào. Ba chỗ chỉ **máy thật** chứng minh được (xem §6): 04 AC-11 / 05 AC-11 (clip
chỉ có trên iCloud, máy không mạng), 05 AC-10 (cuộc gọi huỷ cử chỉ — sim chỉ chứng minh đường `.cancelled` ở tầng
model), cảm giác haptic của 05 AC-3/AC-8.

## 5. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Project JSON:** recipe giải mã cứng — mọi trường mới (của mọi plan) làm project đã lưu mở ra trắng, model dựng lại từ ảnh | cao (đã xảy ra theo cấu trúc) | task 4 làm decode khoan dung **trước** mọi trường mới; test thiếu khoá + một clip hỏng. Không migration (app chưa phát hành) |
| Trần undo 40 cắt đầu ngăn khi phiên dài → ✕ không biết gỡ tới đâu | trung bình | mỗi mục có số thứ tự; phiên giữ **recipe đầu phiên** riêng, `rollback` gỡ mọi mục ≥ checkpoint, không dựa vào chỉ số mảng; test qua trần |
| **Concurrency:** `loadAndMerge` / `resolveMusicDuration` ghi `sourceDuration` vào recipe sau khi đã chụp ảnh undo (`VideoStudioModel.swift:838-847`, `:1165-1189`) → khôi phục ảnh cũ mất thời lượng nguồn, `setTrim` im lặng | trung bình | thời lượng nguồn đã biết giữ ở model theo id, gieo lại sau mỗi `restore`/`rollback`; `swift-concurrency` soát |
| Replace rồi ✕ mất nguồn clip cũ | chắc chắn nếu không sửa | không `removeValue` nguồn tới khi phiên kết thúc; dọn ở ✓/đóng màn |
| ✕ trong lúc preview đang dựng lại trên bản cũ | thấp | `schedulePreviewRebuild` đã huỷ task trước (`:1959-1966`); ✕ đi đường dựng lại đầy đủ |
| **Bộ nhớ:** giữ nguồn tới hết phiên; khung preview tới mép khi kéo | thấp | nguồn là tham chiếu asset, không phải pixel; seek qua cổng scrub sẵn có (`:566-589`); không decode thêm thumbnail. Xuất 4K không đổi đường đi (chỉ bỏ nhân master) |
| Vùng chạm tay nắm mép (44) chồng núm fade (22) ở góc trên | trung bình | 20pt trên cùng thuộc fade, phần còn lại thuộc mép; test thứ tự vùng |
| Hàng đáy 790–852 nằm trong dải home indicator 34pt của iPhone 17 | trung bình | theo board; `iphone-ux-review` soát cử chỉ vuốt home với ô ở y 795–847 |
| Tay nắm trái của clip đầu ở sát mép trái màn (vuốt back hệ thống) | thấp | Video Studio là fullScreenCover, không có vuốt back; vẫn soát |
| **Duo 669pt:** luật trơ 30%, hàng lệnh trong 264 | — | thuộc chứng minh của plan màn rộng; plan này giao hàm thuần + test |
| **Hiệu năng 30 fps:** chụp recipe mỗi bước (struct giá trị, vài KB) | thấp | không đụng compositor; đo một lần trên máy thật khi phát với panel mở |
| Đổi `GlobalTool` làm gãy iPad giữa hai plan | trung bình | task 5 giữ menu Project Tools trỏ Look + Video Settings tới khi plan màn rộng thay; tab Effects của pool còn sống tới task 6 plan look |
| `XCUITest` không liệt kê Video Studio trên điện thoại | cao | dump `{"type":"button"}` + `Tools/sim-shot`; giá trị (Speed, Volume) chứng minh ở test model |
| Bậc lane `phone` 40/80/46 làm 9:16 (timeline 306) chỉ thấy 3 lane | đã biết (spec §9) | cuộn dọc + lát tự cuộn tới lane chọn |

## 6. Cách chứng minh là xong

- **Test (unit, chỉ chạy lớp liên quan mỗi task):** `VideoEditHistoryTests`, `VideoSelectionSessionTests` (04 AC-3–7,
  9, 10, 12; 04b AC-6–8; 05 AC-9), `VideoItemCommandsTests` (04b AC-1–3), `VideoItemTitleTests`,
  `VideoClipPanelSections` (04b AC-11, 05 AC-13), `VideoClipTrimMathTests` (05 AC-5–7), `VideoEdgeTrimMathTests`
  (05 AC-1–4, 8, 10, 11), `VideoRecipeDecodingTests` + `VideoAudioMixTests` (04 AC-15), `VideoPhoneLayoutTests`
  (07 AC-2–5, 11–13), `VideoStudioToolsTests` (04 AC-1, 2, 8), `VideoStudioOrientationTests` (07 AC-1),
  `VideoStudioDeskLayoutTests.theCompactTransportFitsTheNarrowestPhone` (07 AC-7). Full suite + `Tools/gate` một lần
  cuối intent.
- **Màn phải chụp** (iPhone 17 iOS 26.5 **và** 18.6; `Tools/sim-shot` có mask): Main, P2, P3, P4, P5, P8, P9,
  P9_Collapsed, P10, P11/P12 (+_Selected), panel Look tạm, panel Video Settings tạm; iPhone 375pt (transport);
  xoay ngang. Duo trong/ngoài và iPad: chỉ những gì plan này đổi trên đó (menu Project Tools tạm, hàng lệnh một
  hàng, không Duration) — bố cục của chúng do plan màn rộng chụp. Duo chỉ qua `Tools/ui-drive`, không MCP sim tool.
- **Design parity:** `design-parity` theo từng board (task 32, 41, 50) sau khi export `project/` Version 26 vào
  `build/design/video/project/`.
- **Đo:** sim — mọi hình học, route, ảnh; **máy thật** — 04 AC-11/05 AC-11 (iCloud offline), 05 AC-10 (cuộc gọi
  thật), haptic 05 AC-3/AC-8, 30 fps khi phát với panel mở và khi kéo tay nắm.
- **Tài liệu cập nhật cùng commit task:** cột "Chứng minh bằng" của từng AC trong FS-12.04/04b/05/07; FS-12.08 §2
  (bỏ Master khỏi model, thêm `VideoClip.volume` nếu Q-7 duyệt); FS-12.04 §5 + FS-12.03 AC-2 (Q-8); 04b §3 (Q-9);
  `DESIGN.md` tầng D (Q-10); chú thích sai "Optional in the decoder" trong `VideoProjectModels.swift` (task 4).
  Ngoài bảng AC → `REVIEW_QUEUE.md`: dời ~40 `pushUndo` còn lại từ view vào model.

### Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `swift-concurrency` | phiên/rollback chạy cùng `loadAndMerge`, `resolveMusicDuration`, `rebuildTask`; ghi nháp ở nền |
| `data-migration` | khối N: cột "ngày xuất", dòng có sẵn thành đã xuất, nháp đọc khoan dung |
| `memory-leak` | nguồn giữ tới hết phiên, closure của chân phiên/scroller |
| `design-parity` | Main, P2–P12, P9_Collapsed; hàng lệnh mọi board |
| `ios26-parity` | 04 AC-13, 07 AC-10 |
| `device-layout` | phone 375/402/440; xác nhận iPad/Duo không gãy giữa hai plan |
| `iphone-ux-review` | ✕/✓ dưới ngón cái, hàng đáy trong dải home indicator, tay nắm 44 vs scrub, thu 78 |
| `a11y-voiceover` | nhãn ✕/✓ ("Cancel"/"Done"), "Mute"/"Unmute", ô lệnh, tay nắm mép có hành động điều chỉnh |
| `component-consistency` | ✓ đĩa trắng (video) vs chữ nhật trắng (editor ảnh); ô lệnh một cỡ mọi nơi |
| `copy-consistency` · `localization` | "Waiting for iCloud", "Move the playhead into this clip.", "Original clip audio, whole project", "A video needs at least one clip.", "Copy" → "Duplicate" |
| `photokit-guard` | task 30 (clip iCloud ở lại, `PHAsset.duration` offline) |
| `challenger` | chạy một lần trên §3 trước khi duyệt — điền §7 |

## 7. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |
