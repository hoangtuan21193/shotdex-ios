# Kế hoạch — Chọn nhiều clip, nhịp nhạc, tự hạ nhạc (FS-12.11 · FS-12.12 · FS-12.13)

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-12.11](../02-functional-spec/FS-12-video-studio/11-multi-select-and-reorder.md) F1 (18 AC) · [FS-12.12](../02-functional-spec/FS-12-video-studio/12-beats.md) F2 (16 AC) · [FS-12.13](../02-functional-spec/FS-12-video-studio/13-audio-ducking.md) F3 (16 AC) — **50 AC** |
| Intent | [2026-10-03-video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — F1, F2, F3 (mảng cuối của thứ tự: chrome → chọn → Media → Video Settings/Export → Look → kích thước → **F1–F8**) |
| Design | board trong repo — `F*_P_*` ở [`docs/design/iphone/project/`](../design/iphone/project/) · `F1_IL_MultiSelect`, `F2_IL_BeatSnap`, `F3_IL_Ducking` ở [`docs/design/ipad/project/`](../design/ipad/project/) · `F*_DI_*`, `F*_DC_*` ở [`docs/design/duo/project/`](../design/duo/project/); board iPad vẽ lại kiểu Mac 2026-10-04 (commit `76df46d5`, xem khối M của [vs-wide-and-duo-layout](2026-10-03-vs-wide-and-duo-layout.md)). Hàng F1: `F1_P_MultiSelect` · `F1_IL_MultiSelect` · `F1_DI_Reorder` · `F1_DC_MultiSelect`; F2: `F2_P_BeatDetect` · `F2_P_BeatDuration` · `F2_IL_BeatSnap` · `F2_DI_CutToBeat` · `F2_DC_Beats`; F3: `F3_P_Ducking` · `F3_IL_Ducking` · `F3_DI_Ducking` · `F3_DC_Ducking`. Board F1–F3 có đủ trong repo; task 19, 34, 50 render thẳng board trong repo (`Tools/design-board render docs/design/<thiết bị>/project/<board>.dc.html`, shim `support.js` — [docs/design](../design/README.md)) |
| Phụ thuộc | plan **vs-tools-selection-phone** (FS-12.04 / 04b / 07) và các plan khác của Video Studio — §8 |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **6** của thứ tự xây. 51 task = 50 commit + 1 phép đo (task 33, chỉ commit nếu phải sửa code) |

> Dòng `Tiến độ` của intent và FS-12.11 AC-17, AC-19, AC-20 đã ghi trong commit duyệt 2026-10-03.

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 6** của thứ tự xây.
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
- **Quyết định của plan này:** Q-a (chuyển cảnh theo cặp id, tài liệu đúng) và màu chọn #57BFD1 duyệt. Q-b → FS-12.11
  AC-17 đã sửa thành "giữ clip 4 trong 0,35 s rồi kéo (> 10pt) tới ranh giới 0:03.0, thả". §2.5 → thêm FS-12.11
  **AC-19** (Fade nhóm: clip 2 video 6,2 s + clip 4 ảnh 3,0 s, Fade in 2,0 s → 2,0 / 1,5 s, một Undo) và **AC-20**
  (Motion nhóm: clip 1, 4 Zoom In, một Undo) — task 8 và task 9 chứng minh chúng. ❓ SoundAnalysis trên sim vẫn là
  phép đo đầu task 40.
- `MusicTrack` dùng bộ giải mã khoan dung của tools plan task 4 (§7 rủi ro JSON, §8 dòng FS-12.08): task 24 và 43
  chỉ thêm khoá.
- **Board canvas phải sửa** (board trong repo `docs/design/<thiết bị>/project/` — [docs/design](../design/README.md); sửa file rồi publish, trước task
  `design-parity` đầu tiên của board đó):
  - Không board nào phải sửa vì các quyết định duyệt của plan này. `F1_DI_Reorder`, `F2_DI_CutToBeat`,
    `F3_DI_Ducking` nhận cột badge 100 (Lock · Mute) của plan màn rộng trước task 19, 34, 50.

## 1. Hiểu đúng chưa

Ba tính năng cuối hàng canvas, đều đứng trên khung mới (thanh dưới 5 công cụ, phiên chọn ✕ · tên · ✓, hàng lệnh
64×56) mà plan vs-tools-selection-phone dựng:

- **F1 chọn nhiều:** trên thân clip có ba cử chỉ phân biệt bằng thời gian giữ (0,32 s / 0,5 s) và 10pt dịch chuyển —
  giữ-thả vào chế độ chọn, giữ-kéo dời (cả nhóm nếu clip thuộc nhóm), giữ ngắn rồi thả không làm gì. Nhóm có 7 lệnh
  (Speed · Volume · Look · Motion · Move · Duplicate · Delete), mỗi lệnh một bước undo, ✕ trả project về lúc vào chọn.
  Dời nhóm chỉ thả ở ranh giới clip; ranh giới còn kề giữ chuyển cảnh, ranh giới mới là cắt thẳng — **luật này áp cả
  cho dời và xoá một clip**.
- **F2 nhịp:** tìm BPM + vị trí nhịp trên máy (giải mã AVFoundation, DSP Accelerate), cache theo file trong Caches;
  vạch nhịp `timelineBeat` trên băng nhạc và dải tổng quan; Snap to beats (Every Beat/Every Bar, Offset ±250 ms) cho
  tay nắm mép, slider Duration ảnh/freeze, mép chữ/sticker; Cut to Beat có xem trước, một bước undo.
- **F3 ducking:** mỗi băng nhạc tự hạ Amount dB trong lúc clip có giọng (SoundAnalysis "speech") hoặc có tiếng bất kỳ
  (RMS > −40 dBFS), dốc trước Duck in, lên lại trong Recover, gộp khoảng lặng ngắn; chỉ là thêm dốc âm lượng vào
  **cùng một** audio mix của preview và export; phân tích theo giây nguồn, cache theo asset.

Dữ liệu mới chỉ là vài khoá trong `MusicTrack` (Snap/division/Offset; ducking on/Amount/Duck in/Recover/trigger),
đọc khoan dung. Tập đang chọn, BPM, vị trí nhịp, đoạn có giọng **không** vào recipe. Không migration (app chưa
release — CLAUDE.md), không đụng `photo_metadata`.

## 2. Đối chiếu AC ↔ code

Ký hiệu: ✅ code đã đạt · ⚠️ lệch · ❌ chưa có · ❓ chưa kết luận. Đường dẫn tương đối `ShotDex/`.

### 2.1 FS-12.11 — chọn nhiều, đổi thứ tự

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 giữ 0,5 s thả → chọn | ❌ | chọn là **một** đích: `selectedClipID` `Features/VideoStudio/VideoStudioModel.swift:99`, `inspectorTarget` `:263-268`; long-press 0,32 s chỉ để reorder `VideoTimelineScroller.swift:134-140`, thả không xê dịch → `commit` không làm gì `VideoTimelineView.swift:330-341`; không pill, không huy hiệu (`ClipBand` chỉ có viền 2,5 `VideoTimelineTracks.swift:277-282`) | task 4 |
| AC-2 chạm thêm/bớt, pill, phụ đề đếm loại | ❌ | `toggleClip` bật/tắt **một** clip `VideoStudioModel.swift:276-279` | task 5 |
| AC-3 Speed nhóm, một undo | ❌ | `setSpeed` một clip, không tự push undo `:867-878`; caller push `VideoStudioSheetHost.swift:216` | task 7 |
| AC-4 nhóm toàn ảnh → 5 ô | ❌ | không có danh sách lệnh nhóm | task 6 |
| AC-5 loa nhóm, một undo trả trạng thái lẫn | ❌ | `setMuted` một clip, không undo `VideoStudioModel.swift:1199-1204` | task 8 |
| AC-6 Duplicate nhóm | ❌ | clip không có Duplicate nào (chỉ overlay `:1776-1793`); Split đã có mẫu "hai clip dùng chung nguồn đã nạp" `:891-894` để tái dùng | task 10 |
| AC-7 Delete nhóm, ranh giới mới None | ⚠️ | `deleteClip` `:721-735` gọi `syncTransitionsWithClips` `Domain/Video/VideoProjectModels.swift:542-552` — chuyển cảnh **theo vị trí**, cắt đuôi mảng: xoá 2·3·4 thì Crossfade 1→2 còn ở ô 0 và thành 1→5 | §2.4 Q-a; task 11 |
| AC-8 chọn cả 5 → Delete mờ 0,28 | ❌ | `deleteClip` lặng lẽ không làm gì khi còn 1 clip `:722`; không trạng thái mờ | task 12 |
| AC-9 kéo nhóm, giữ/huỷ chuyển cảnh | ⚠️ | dời **một** clip có: long-press `VideoTimelineScroller.swift:340-366` → `dropIndex` `Domain/Video/VideoTimelineMath.swift:211-221` (test `VideoTimelineMathTests.dropIndexFollowsTileMidpoints`) → `moveClip` `VideoStudioModel.swift:661-671` — nhưng `moveClip` **không đụng** `transitions` (theo vị trí: Crossfade 1→2 ở lại ô 0 thành 1→3); không có nhóm, chồng, vạch thả; phép tính điểm thả nằm trong View `VideoTimelineView.swift:330-341` | §2.4 Q-a; task 13 |
| AC-10 nhóm không liền nhau tới cuối | ❌ | — | task 14 |
| AC-11 thả về chỗ cũ → không bước undo | ❌ (một clip đã đúng) | một clip: chỉ push undo khi `target != sourceIndex` `VideoTimelineView.swift:338-341`; nhóm chưa có; logic nằm trong View | task 15 |
| AC-12 Move không kéo | ❌ | — | task 16 |
| AC-13 ✕ trả project, gỡ undo | ❌ | không có ảnh chụp đầu phiên; undo chỉ là ngăn `undoStack` `:135`, `pushUndo` `:603-610` | task 17 — cần phiên chọn của vs-tools-selection-phone |
| AC-14 Duo ngoài 18 pt/s, cao 240, ✓ về 55 | ❌ | `pointsPerSecondRange = 20...160` `VideoStudioMetrics.swift:627` không xuống được 18; `pps` là `@State` riêng của `VideoTimelineView.swift:27` nên màn ngoài không đặt được | task 18 (quyết định kỹ thuật §6 D-6) |
| AC-15 bốn board ≤ 2pt | ❌ | board F1 chưa có bản local | task 19 |
| AC-16 giữ 0,4 s thả → không gì | ✅ (hôm nay) | long-press nổ ở 0,32 s, thả với dịch chuyển ≈ 0 → `dropIndex` = chỗ cũ → không đổi, không undo `VideoTimelineView.swift:337-341`; không có chế độ chọn nào để lọt vào | task 1: khoá bằng route trước khi thêm cử chỉ mới |
| AC-17 giữ 0,35 s kéo → chỉ clip đó dời | ✅ code · ⚠️ số trong AC | code: long-press 0,32 s rồi kéo dời một clip, một bước undo, không chọn (`VideoTimelineView.swift:339-340`). Số: clip 4 bắt đầu 14,2 s, ranh giới 3,0 s — tâm clip phải qua giữa clip 2 (6,1 s) tức dời ≥ 9,6 s = **192–1 536pt** ở 20–160 pt/s; "kéo 40pt" không tới được ở zoom nào | §2.4 Q-b; task 2 |
| AC-18 luật ba cử chỉ, test thuần | ❌ | ngưỡng chỉ nằm trong cấu hình recognizer UIKit `VideoTimelineScroller.swift:137` (+ `allowableMovement` mặc định 10pt), không có ở Domain | task 3 |

### 2.2 FS-12.12 — nhịp

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 click 96 BPM, phách 1 | ❌ | không có phát hiện nhịp nào trong repo (grep `beat`); `VideoWaveform` lấy mẫu thưa `step = count/1024` `Features/VideoStudio/VideoWaveform.swift:49` — không dùng được cho khởi âm; repo chưa ai `import Accelerate` ngoài kit (`ShotDexKit/Render/PhotoRenderService.swift:1`) | task 20 |
| AC-2 im lặng 0,37 s ở đầu | ❌ | — | task 21 |
| AC-3 ồn trắng → "No steady beat" | ❌ | — | task 23 |
| AC-4 tab Beats, thẻ, vạch 137,5/34,4pt | ❌ | băng nhạc chỉ vẽ waveform `VideoTimelineTracks.swift:615-720`; hàng lệnh nhạc chỉ Replace · Add Track `VideoStudioSheetHost.swift:684-690`; không token vàng trong `Features/Editing/EditorTheme.swift` | task 22 |
| AC-5 slider Duration dính 3.30s | ❌ | slider thường, giá trị 1 chữ số thập phân `VideoStudioSheetHost.swift:238-260` | task 24 |
| AC-6 giữ 0,5 s → kéo tự do | ❌ | — | task 25 |
| AC-7 tay nắm mép video dính beat 14, pill | ❌ | tay nắm mép clip là no-op `VideoTimelineView.swift:342-343` (việc của FS-12.05); điểm dính chỉ có mép clip, marker, playhead `VideoStudioModel.swift:1022-1034`; dính chỉ áp lúc thả, không lúc kéo | task 27 — cần plan FS-12.05 |
| AC-8 Every Bar | ❌ | — | task 28 |
| AC-9 Offset +50 ms, một undo | ❌ | — | task 26 |
| AC-10 xem trước Cut to Beat | ❌ | — | task 29 |
| AC-11 Apply, một undo | ❌ | — | task 30 |
| AC-12 cut không dời được | ❌ | — | task 31 |
| AC-13 rời xem trước = không đổi | ❌ | — | task 32 |
| AC-14 3:24, ≤ 5 s, ≤ 30 MB, máy bay | ❌ | — | task 33 (đo sim, máy thật sau) |
| AC-15 năm board ≤ 2pt | ❌ | — | task 34 |
| AC-16 màu nhịp | ❌ | không token | task 35 |

### 2.3 FS-12.13 — ducking

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 giọng tổng hợp 2,0–5,0 s | ❌ | không dùng SoundAnalysis ở đâu (framework có trong SDK sim 27.1, chưa đo chạy được không) | task 40 |
| AC-2 đường mức 0,8 → 0,201 | ❌ (một phần) | dốc fade nhạc có: `musicRamps` `Domain/Video/VideoTimelineMath.swift:138-176`, test `musicRampsCoverTheWholeBed`; chưa có ducking | task 36 |
| AC-3 gộp khoảng lặng < Duck in + Recover | ❌ | — | task 37 |
| AC-4 nhân với fade out | ❌ | builder chỉ đặt từng dốc fade riêng, còn nhân `masterVolume` `Data/Sources/VideoCompositionBuilder.swift:316, 348-364` (Master bị bỏ ở FS-12.04 AC-15 — plan vs-tools-selection-phone) | task 38 |
| AC-5 Voices vs Any Clip Sound | ❌ | `VideoAudioEnvelope` lấy đỉnh thưa `Features/VideoStudio/VideoAudioEnvelope.swift:88`, không ra RMS 50 ms | task 41 |
| AC-6 clip tắt tiếng không kích hoạt | ❌ | `isMuted` có `VideoProjectModels.swift:116`; lane V1 tắt = `videoVolume == 0` `VideoStudioModel.swift:349` | task 42 |
| AC-7 Speed 2×, trim → giây timeline | ❌ | — | task 39 |
| AC-8 đổi thứ tự không phân tích lại | ❌ | — | task 45 |
| AC-9 tắt → mix bằng mix chưa bật | ❌ | — | task 43 |
| AC-10 kéo Amount: một undo, không dựng khung | ❌ (cơ chế có) | tầng chỉ-âm-thanh có sẵn: `applyAudioTier` `VideoStudioModel.swift:1947-1950` → `VideoStudioService.applyAudioMix` `Data/Sources/VideoStudioService.swift:390-395` | task 44 |
| AC-11 export sin 440 Hz, −12 ±1 dB | ❌ (đường có) | export dùng **cùng** `audioMix` `VideoStudioService.swift:434` → `VideoExportWriter.swift:85` | task 48 |
| AC-12 clip iCloud không mạng | ❌ | trạng thái clip lỗi là FS-12 README AC-13 (plan khác) | task 46 |
| AC-13 đồ thị iPhone 370×78 | ❌ | — | task 49 |
| AC-14 đóng studio huỷ ≤ 1 s | ❌ (mẫu có) | `close()` huỷ task waveform `VideoStudioModel.swift:506-511` | task 47 |
| AC-15 bốn board ≤ 2pt | ❌ | — | task 50 |
| AC-16 màu giọng | ❌ | không token | task 51 |

### 2.4 Chỗ lệch cần quyết

| # | Lệch | Khuyến nghị |
|---|---|---|
| **Q-a** (AC-7, AC-9, và luật §6 "áp cả cho dời một clip") | chuyển cảnh lưu **theo vị trí** (`transitions[i]` giữa `clips[i]`, `clips[i+1]`); `moveClip` không đụng mảng, `deleteClip` cắt đuôi — chuyển cảnh trôi sang cặp shot khác | **Tài liệu đúng** — sửa code: chuyển cảnh đi theo cặp id hai bên, cặp mới sinh ra là None. Crossfade chọn cho hai shot cụ thể vô nghĩa giữa hai shot khác. (Split và chèn media cũng đang theo vị trí `VideoStudioModel.swift:895-896, 1144-1145` — ngoài phạm vi, ghi `REVIEW_QUEUE.md`) |
| **Q-b** (FS-12.11 AC-17) | "giữ 0,35 s rồi kéo **40pt** tới ranh giới 0:03.0" không tới được ở zoom nào (cần ≥ 192pt kể cả 20 pt/s) | **Sửa tài liệu:** "giữ clip 4 trong 0,35 s rồi kéo (> 10pt) tới ranh giới 0:03.0, thả". Code đã đúng ý AC |
| (cross-plan) màu chọn | `timelineSelection` = accent cam `Features/Editing/EditorTheme.swift:73`; DESIGN.md §3.3 và FS-12.04/11 nói `#57BFD1` | **Tài liệu đúng.** Thuộc vs-tools-selection-phone (mô hình chọn); nếu plan đó không sửa thì task 4 sửa, một dòng |

### 2.5 ❓ và lỗ hổng tài liệu

- **Không AC nào phủ Fade, Motion, Look của nhóm** (FS-12.11 §5). Task 8 (Fade, cùng section Volume) và task 9
  (Look + Motion) làm theo spec kèm test, nhưng task 9 không map AC nào. Đề xuất thêm khi duyệt: *AC-19* "clip 2, 3
  chọn, Fade in 1,0 s → mỗi clip fade 1,0 s, clip 3,0 s kẹp 1,5 s; một Undo"; *AC-20* "clip 1, 4 chọn, Motion Zoom In →
  cả hai Zoom In; một Undo". Look nhóm dùng ô **Selected** của FS-12.06c (plan 2026-10-02 task 14).
- **❓ SoundAnalysis trên simulator** (iOS 26.5 và 18.6): framework có trong SDK sim, chưa biết bộ phân loại
  `.version1` có chạy được trong sim không. Task 40 bắt đầu bằng phép đo; nếu không chạy, AC-1 của FS-12.13 chỉ chứng
  minh được trên máy thật và test Voices phải `.enabled(if:)` theo môi trường — báo lại, không đoán.
- Cut to Beat với cut nằm **ngoài** cửa sổ của băng có lưới nhịp: spec không nói. Quyết định kỹ thuật D-9 (§6).

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `UILongPressGestureRecognizer` + `TimelineDragZone` + `handleReorder` `VideoTimelineScroller.swift:132-140, 340-366` | cả ba cử chỉ thân clip — chỉ thêm báo pha "thả" kèm thời gian giữ và quãng dịch; **không** dùng gesture SwiftUI (chết trong UIScrollView) |
| `VideoTimelineMath.dropIndex` `:211-221`, `placements` `:62-71` | điểm thả theo ranh giới, Move theo playhead |
| mẫu Split "hai clip dùng chung nguồn đã nạp" `VideoStudioModel.swift:891-894` | Duplicate nhóm không giải mã thêm |
| `pushUndo` / `beginUndoGroup` / `endUndoGroup` `:603-620` | mỗi lệnh nhóm một bước; kéo slider một nhóm |
| ba tầng dựng lại (`applyAudioTier` / `applyVideoTier` / `schedulePreviewRebuild`) `:1947-1966` | ducking chỉ chạm tầng âm thanh; Speed nhóm là tầng cấu trúc |
| `VideoCompositionBuilder.audioMix` `Data/Sources/VideoCompositionBuilder.swift:312-370`, `VideoTimelineMath.musicRamps` | đường mức nhạc có ducking, một chỗ cho preview + export |
| đọc PCM qua `AVAssetReaderTrackOutput` của `VideoAudioEnvelope` / `VideoWaveform` | khuôn cho bộ đọc PCM mono đầy đủ (hai bộ kia lấy mẫu thưa nên không dùng thẳng) |
| huỷ task trong `close()` + `reloadWaveforms()` `:506-511, 1924-1940` | huỷ phân tích nhịp/giọng khi xoá băng, undo, đóng studio |
| `snappedTime` (8pt quy ra giây theo zoom) `:1022-1034`, `VideoTimelineView.swift:281` | thêm nhịp vào danh sách điểm dính — chuyển xuống Domain |
| `VideoTimelineOverview` `Features/VideoStudio/VideoViewerChrome.swift:302-366` | vạch nhịp, đích Cut to Beat trên dải tổng quan |
| `VideoScopeModel` (`@Observable` con, `Features/VideoStudio/VideoScopeModel.swift:17`) | khuôn cho hai model con `VideoBeatsModel`, `VideoDuckingModel` |
| `LossyArray` / `decodeLossyArrayIfPresent` `ShotDexKit/Models/LossyDecoding.swift` | khoá mới trong `MusicTrack` đọc khoan dung |
| `Tools/stats-fixtures` + `Tools/lib/stats-fixtures.swift` | khuôn cho `Tools/video-fixtures` (media mẫu tự sinh, không mặt người, không nhạc bản quyền) |
| từ plan vs-tools-selection-phone (chưa có trong code): phiên chọn ✕/✓, chân ✕ · tên · ✓, hàng lệnh 64×56 (mục/hành động, ẩn-không-mờ, mờ 0,28), panel không đổi cao, Volume từng clip + đĩa loa | nền cho mọi task UI ở đây — **không làm lại** |

## 4. File đổi và tầng

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `Domain/Video/TimelinePressClassifier.swift` | Domain | luật ba cử chỉ: (giữ, quãng, đã thả) → `.scroll / .nothing / .enterSelection / .move`; ngưỡng 0,32 s · 0,5 s · 10pt là hằng ở đây | mới |
| `Domain/Video/VideoClipGroupEditing.swift` | Domain | thuần trên `VideoProjectRecipe`: `remapTransitions(old:new:)` theo cặp id, `moveClips(_:toBoundary:)`, `duplicateClips(_:makeID:)`, `deleteClips(_:)` (từ chối khi là mọi clip), `setSpeed/setMuted/setVolume/setFade/setEffect(_:in:)`, `summary(_:)` (đếm loại, tổng giây), `commands(for:)`, `nearestBoundary(to:)`, `boundary(forFingerTime:)`, "Mixed" | mới |
| `Domain/Video/TimelineSnapping.swift` | Domain | `snappedTime` chuyển xuống thuần, nhận danh sách điểm (mép clip, marker, playhead, hai đầu, **nhịp**); trả cả nguồn điểm dính (để pill "Beat 14") | mới (nếu plan FS-12.05 đã chuyển thì chỉ thêm nhịp) |
| `Domain/Video/BeatDetector.swift` | Domain | DSP thuần trên `[Float]` mono 11 025 Hz: khởi âm (FFT vDSP, khung 256 / bước 128 ≈ 11,6 ms), tự tương quan 60–180 BPM, bám nhịp (lập trình động, trôi ±5%), phách 1 = pha mạnh nhất dải < 200 Hz, độ tin cậy | mới |
| `Domain/Video/BeatGrid.swift` | Domain | lưới trên timeline từ kết quả + vị trí/trim băng + Offset; đánh số từ 0; bar/beat; `nearest(_:division:tolerance:)`; vạch theo zoom (dưới 6pt chỉ vẽ bar) | mới |
| `Domain/Video/CutToBeatMath.swift` | Domain | xem trước (đích, độ dời, "can't move", tóm tắt) và áp dụng (ảnh co giãn, video dời cuối trim, kẹp 0,5 s / nguồn), cut có chuyển cảnh lấy giữa vùng chồng | mới |
| `Domain/Video/DuckingMath.swift` | Domain | đoạn kích hoạt (giây nguồn → timeline qua trim/speed/placement; loại clip ảnh/freeze/tắt tiếng/âm 0/V1 tắt), gộp khoảng lặng, mức nhạc = Volume × fade × duck, dốc cho `AVAudioMix` (chia nhỏ đoạn hai dốc chồng), mẫu đồ thị, độ sâu lõm 26pt/12 dB, tóm tắt "Voices in 3 clips · 8.6s" | mới |
| `Domain/Video/VideoProjectModels.swift` | Domain | `MusicBeatSnap` {isOn, division, offsetMs}, `MusicDucking` {isOn, amountDB, duckIn, recover, trigger}; `MusicTrack.init(from:)` khoan dung (khoá thiếu/hỏng → mặc định) | sửa |
| `Domain/Video/VideoTimelineMath.swift` | Domain | `musicRamps` giữ nguyên chữ ký; dùng lại trong `DuckingMath` | không đổi / đọc |
| `Data/Sources/AudioPCMReader.swift` | Data | AVAssetReader → Float32 mono ở tốc độ chỉ định, theo đoạn, có `timeRange`, kiểm `Task.isCancelled` mỗi buffer; từ URL hoặc `AVAssetTrack` | mới |
| `Data/Sources/MusicBeatAnalyzer.swift` | Data | URL → `BeatAnalysis` (PCMReader 11 025 Hz + `BeatDetector`), không mạng | mới |
| `Data/Sources/VoiceActivityAnalyzer.swift` | Data | `SNAudioStreamAnalyzer` + `SNClassifySoundRequest(.version1)` lớp "speech", cửa sổ 1 s chồng 0,5, bỏ đoạn < 0,3 s; RMS 50 ms cùng một lượt đọc (16 kHz); chỉ phần nguồn đang dùng | mới |
| `Data/Sources/AudioAnalysisCache.swift` | Data | JSON trong Caches: nhịp theo (tên + kích thước + ngày sửa), giọng theo (assetID + khoảng nguồn đã phân tích); ghi hỏng → giữ RAM cho phiên | mới |
| `Data/Sources/VideoCompositionBuilder.swift` | Data | `audioMix(recipe:layout:activity:)` — thêm dốc ducking từ `DuckingMath` | sửa |
| `Data/Sources/VideoStudioService.swift` | Data | truyền activity vào `makePreviewItem` / `applyAudioMix` / `export` | sửa |
| `Features/VideoStudio/VideoStudioModel.swift` | Features | tập chọn nhóm (`selectedClipIDs` có thứ tự, vào/ra/bật-tắt), lệnh nhóm gọi Domain + undo, trạng thái Move, `deleteClip`/`moveClip` qua `remapTransitions`; sở hữu hai model con; `close()` huỷ chúng; export chờ phân tích giọng | sửa |
| `Features/VideoStudio/VideoBeatsModel.swift` | Features | `@Observable @MainActor`: kết quả/trạng thái phân tích mỗi băng, task, Snap (một nguồn mỗi project), Offset, xem trước Cut to Beat | mới |
| `Features/VideoStudio/VideoDuckingModel.swift` | Features | `@Observable @MainActor`: activity mỗi clip, task, "Listening for voices…", "· 1 clip not checked", setter → tầng âm thanh | mới |
| `Features/VideoStudio/VideoTimelineScroller.swift` | Features | báo pha thả (giữ, quãng) cho classifier; tự cuộn khi ngón trong 44pt mép (CADisplayLink) lúc kéo nhóm | sửa |
| `Features/VideoStudio/VideoTimelineView.swift` | Features | `commit` gọi Domain (bỏ toán trong View); pill "3 selected · 14.2s"; pill nhịp lúc kéo; mức zoom 18 pt/s khi chọn trên Duo ngoài | sửa |
| `Features/VideoStudio/VideoTimelineTracks.swift` | Features | viền 2pt + huy hiệu 19pt; chỗ cũ tối 0,66 viền đứt; chồng 131×54 + huy hiệu đếm 22; vạch thả 3×82 + pill; vạch nhịp (một `Canvas`, không mỗi nhịp một View); đường mức nhạc + pill "−12 dB"; nhãn Voice trên V1 (iPad, Duo trong); mũi tên Cut to Beat | sửa |
| `Features/VideoStudio/VideoViewerChrome.swift` | Features | `VideoTimelineOverview`: vạch nhịp, đích Cut to Beat (Duo ngoài) | sửa |
| `Features/VideoStudio/VideoGroupPanel.swift` | Features | nội dung panel nhóm: Speed (chip, Mixed, chú thích ảnh), Volume + loa, FADE, LOOK (ô Selected của 06c), MOTION | mới |
| `Features/VideoStudio/VideoBeatsPanel.swift` | Features | thẻ nhịp (4 trạng thái), Snap, SNAP TO, Offset (nấc 0), Cut Clips to Beat + xem trước + Apply | mới |
| `Features/VideoStudio/VideoDuckingPanel.swift` | Features | đồ thị 370×78 / 354×78, UNDER VOICES, Amount, Duck in, Recover, chip, tóm tắt | mới |
| `Features/VideoStudio/VideoBeatSlider.swift` | Features | slider Duration có vạch nhịp, dính 8pt rãnh, giữ 0,5 s = tự do, núm/giá trị vàng, 2 chữ số | mới |
| `Features/VideoStudio/VideoStudioSheetHost.swift`, `VideoStudioCommandBand.swift` | Features | hàng lệnh nhạc thêm Beats · Ducking (ô kiểu *mục*) trên hàng lệnh của plan vs-tools-selection-phone; hàng lệnh nhóm 7 ô | sửa |
| `Features/Editing/EditorTheme.swift` | Features | `timelineBeat` #FFD60A, `timelineBeatInk` #1A1500, `timelineSpeech` #5E9CFF, `timelineSpeechInk` #06142E | sửa |
| `DESIGN.md` §3.3 | doc | **chỉ** thêm 4 token vào danh sách + một câu phạm vi (được phép, theo người dùng) | sửa |
| `Localizable.xcstrings` | Features | "%lld Clips", "%lld selected", "%lld videos + %lld photo(s)", "Move %lld clips here", BPM/Beat/dB/"Voices in…" — số nhiều qua catalog | sửa |
| `ShotDexUITests/UIDriverTests.swift` | test | bước kéo nhận `pressSeconds` (hôm nay cố định 0,1 s `:180`) | sửa |
| `Tools/video-fixtures` + `Tools/lib/video-fixtures.swift` | tool | sinh media mẫu: 2 ảnh phong cảnh tổng hợp, video 6,2/10 · 5,0/10 · 6,8 s, giọng `say` ở 4,2–7,4 / 10,8–13,0 / 18,7–21,9 s, "Morning Drive" click+bass 96 BPM, sin 440 Hz, bài 3:24 tổng hợp | mới |
| `ShotDexTests/Fixtures/voice-2s.caf` | test | giọng `say` 3 s (≈ 15 KB) cho AC-1 FS-12.13 | mới |
| `ShotDexUITests/scripts/video-*.json` | test | route từng AC UI (§7) | mới |
| `docs/…/11, 12, 13` | doc | cột "Chứng minh bằng" từng AC khi xong | sửa theo task |

Không đổi bảng GRDB; recipe vẫn là JSON trong `creations`. Không đụng ShotDexKit, không đụng extension.

## 5. Thứ tự task

Một AC = một task = một commit (`feat(FS-12.11): AC-n …`). Trong từng spec: ✅ khoá trước → ⚠️ → ❌, **trừ** chỗ một
⚠️ cần nền ❌ (AC-7, AC-9 cần chế độ chọn nhóm) — quyết định ⚠️ chốt lúc duyệt, code theo phụ thuộc. Ba khối theo thứ
tự F1 → F2 → F3 của intent. Mọi task UI kết thúc bằng `/build`, ảnh chụp 4 máy (iPhone 17 26.5 dọc, iPad 13" ngang,
Duo trong, Duo ngoài — Duo **chỉ** qua `Tools/ui-drive` + `Tools/sim-shot`), và nhánh iOS 18.6 trên iPhone SE.

### Khối F1 — FS-12.11 (task 1–19)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | `Tools/video-fixtures` + route khoá **trước** khi đổi cử chỉ: iPad, giữ clip 2 0,4 s thả → dump không có pill/"1 Clip", thứ tự giữ, nút Undo vẫn tắt | 11/AC-16 | route `video-press-release.json` (iPad 26.5; phone không liệt kê được phần tử Video Studio) |
| 2 | (số AC-17 đã sửa trong commit duyệt); `UIDriverTests` thêm `pressSeconds` cho bước kéo; route khoá: giữ clip 4 0,35 s, kéo tới ranh giới 3,0 s | 11/AC-17 | route `video-press-drag.json`: thứ tự 1·4·2·3·5, không pill, Undo bật đúng 1 bước |
| 3 | `TimelinePressClassifier` + scroller báo (giữ, quãng) lúc thả; route 1–2 chạy lại xanh | 11/AC-18 | `TimelinePressClassifierTests.fourCasesFromTheSpec` (0,2 s/15pt cuộn · 0,4/2 không gì · 0,6/2 vào chọn · 0,6/20 dời) + biên 0,32/0,5/10pt |
| 4 | vào chế độ chọn: `selectedClipIDs`, viền 2pt + huy hiệu 19pt, pill 190×22, chân ✕ · "1 Clip" · ✓, hàng 7 ô (component của vs-tools-selection-phone); `timelineSelection` → #57BFD1 nếu plan kia chưa sửa | 11/AC-1 | `VideoStudioMultiSelectTests.holdReleaseEntersWithOneClip` (model dựng từ `Creation.video` mẫu); route iPad dump; phone sim-shot |
| 5 | chạm bật/tắt, về 0 = ✓, chạm chữ/nhạc = ✓ rồi chọn, ⌘-click / Shift-click dải; pill + phụ đề đếm loại qua String Catalog | 11/AC-2 | `VideoClipGroupEditingTests.summaryCountsKinds` ("14.2s · 2 videos + 1 photo", một loại thì bỏ đếm); `VideoStudioMultiSelectTests.toggleDownToZeroExitsLikeDone` |
| 6 | lệnh theo loại: nhóm không video thì ẩn Speed, Volume | 11/AC-4 | `VideoClipGroupEditingTests.photoOnlyGroupHasFiveCommands` |
| 7 | Speed nhóm: chip 0.5×·1×·2×·4×, slider, "Mixed", chú thích "Applies to the 2 videos · the photo keeps its 3.0s", một bước undo | 11/AC-3 | `…GroupEditingTests.speedTouchesOnlyVideos` (3,1 · 2,5 · 3,0; tổng 18,4); `MultiSelectTests.oneUndoRestoresBothSpeeds` |
| 8 | Volume nhóm (slider + loa 26pt, lẫn → vẽ bật, chạm = tắt cả nhóm) + section FADE (kẹp nửa từng clip) | 11/AC-5, AC-19 | `…speakerMutesWholeMixedGroup`, `…oneUndoRestoresMixedMute`, `…groupFadeClampsPerClip` |
| 9 | LOOK (ô Selected của 06c) + MOTION cho nhóm | 11/AC-20 (Look nhóm không AC riêng) | `…groupMotionAppliesToAll`; Look: test của plan 06c task 14 với ≥ 2 clip |
| 10 | Duplicate nhóm: chèn sau clip cuối, giữ thứ tự tương đối, id mới, dùng chung nguồn, ranh giới mới None, bản sao thành nhóm chọn | 11/AC-6 | `…duplicateInsertsAfterLastKeepsOrder` (7 clip, tổng 35,2, ranh 3→bản sao None); `MultiSelectTests.duplicateIsOneUndo` |
| 11 | `remapTransitions` theo cặp id; `deleteClips` nhóm; `deleteClip` đơn dùng chung luật (Q-a); thoát chọn | 11/AC-7 | `…deleteMiddleThreeLeavesNoneBoundary` (1·5, None, 9,8 s); `MultiSelectTests.oneUndoRestoresClipsAndCrossfade` |
| 12 | Delete mờ 0,28 khi nhóm = mọi clip, chạm không xoá | 11/AC-8 | `…deletingEveryClipIsRefused`; dump `opacity`/`isEnabled` ô Delete |
| 13 | kéo nhóm: chồng 131×54 + huy hiệu, chỗ cũ tối 0,66 viền đứt, vạch 3×82 + pill "Move 2 clips here", điểm thả chỉ ở ranh giới, tự cuộn 44pt mép, pill trạng thái ẩn khi kéo; `moveClip` đơn qua `remapTransitions` (Q-a); toán điểm thả rời khỏi View | 11/AC-9 | `…moveGroupKeepsInnerTransitionDropsOthers` (1·3·4·2·5; 3→4 Crossfade; 1→3, 4→2, 2→5 None); `…fingerPastMidpointJumpsToNextBoundary`; `MultiSelectTests.oneUndoRestoresOrderAndCrossfade`; route kéo iPad |
| 14 | nhóm không liền nhau tới cuối | 11/AC-10 | `…nonContiguousGroupLandsInTimelineOrder` (2·3·5·1·4) |
| 15 | thả về chỗ cũ / ngoài lane / hệ thống huỷ → không đổi, không bước undo | 11/AC-11 | `…dropAtOriginIsNoOp`; `MultiSelectTests.cancelledDragAddsNoUndo` |
| 16 | Move không kéo: vạch ở ranh giới gần playhead, cuộn để dời vạch, chạm pill để thả; VoiceOver đọc được | 11/AC-12 | `…nearestBoundaryToPlayhead` (2,8 s → ranh 3,0 → 1·4·2·3·5); route VoiceOver-label dump iPad |
| 17 | ✕ trả recipe lúc vào chọn và gỡ các bước undo của phiên (phiên của vs-tools-selection-phone, "N Clips") | 11/AC-13 | `MultiSelectTests.discardRestoresEntrySnapshotAndUndoDepth` |
| 18 | Duo ngoài: vào chọn → timeline 240 cao, 18 pt/s; ✓ → mức cũ; hạ cận dưới `pointsPerSecondRange` xuống 18 (D-6); `pps` nhận lệnh từ màn hình | 11/AC-14 | `VideoStudioLayoutTests.duoCoverMultiSelectZoom` (6,2 s → 111,6pt); route Duo `video-duo-cover-multiselect.json` + `sim-shot cover` |
| 19 | export lại canvas → `design-parity` bốn board, sửa tới khi ≤ 2pt | 11/AC-15 | agent `design-parity`; `Tools/design-board compare` từng board |

### Khối F2 — FS-12.12 (task 20–35)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 20 | `BeatDetector` (Domain, Accelerate) | 12/AC-1 | `BeatDetectorTests.click96BarAccented` (96 ±0,5; ≤ 20 ms; 0,4,8… phách 1) + `click170NotHalved`, `click60NotDoubled` (rủi ro §10) — click tổng hợp trong test |
| 21 | khoảng im lặng đầu bài | 12/AC-2 | `…leadingSilenceShiftsFirstBeat` (0,37 ±0,02; 120 ±0,5) |
| 22 | `AudioPCMReader` + `MusicBeatAnalyzer` + `AudioAnalysisCache` + `VideoBeatsModel`; ô Beats trong hàng lệnh nhạc; thẻ nhịp; vạch trên băng + dải tổng quan; **4 token + DESIGN.md §3.3** | 12/AC-4 | `BeatGridTests.ticksAt55pps` (bar 137,5 · beat 34,375; "30 beats marked"); `MusicBeatAnalyzerTests.decodesWavAndCaches` (WAV viết trong test, lần 2 đọc cache, kết quả giống hệt); phone sim-shot |
| 23 | ồn trắng → "No steady beat"/"Snap needs music with a clear beat", Snap + Cut mờ 0,28, không vạch; "Can't read this track"; "Finding beats…" | 12/AC-3 | `BeatDetectorTests.whiteNoiseHasNoSteadyBeat`; `VideoBeatsModelTests.unreadableFileShowsCantRead` |
| 24 | `MusicBeatSnap` vào `MusicTrack` (đọc khoan dung), một nguồn mỗi project, `VideoBeatSlider` cho Duration ảnh/freeze: dính 8pt rãnh, rung 1 lần, vàng, 2 chữ số, dòng "Ends on beat 28 · 0:17.50 · hold to move freely" | 12/AC-5 | `BeatGridTests.durationSnapsToBeat28` (3,25 → 3,30); `VideoProjectDecodingTests.musicTrackWithoutBeatKeysDecodesDefaults` + `…garbageBeatKeysDecodeDefaults`; `VideoBeatsModelTests.snapOnA2TurnsA1Off` |
| 25 | giữ 0,5 s giữa lúc kéo → tự do tới khi nhấc | 12/AC-6 | `BeatSliderLogicTests.holdHalfSecondReleasesSnap` (logic ở Domain `BeatGrid`/`TimelineSnapping`, không trong View) |
| 26 | Offset −250…+250 ms bước 5, nấc 0, dời vạch + điểm dính + Cut to Beat, một kéo = một undo | 12/AC-9 | `BeatGridTests.offsetShiftsEveryBeat`; `VideoBeatsModelTests.offsetDragIsOneUndo` |
| 27 | nhịp vào `TimelineSnapping`: tay nắm mép clip (cần FS-12.05), mép chữ/sticker; pill vàng "Beat 14 · 0:08.75 · −0.45s", đường vàng hết lane, dòng phụ "5.75s · on beat 14"; tay nắm giữ yên (FS-12.17) không dính | 12/AC-7 | `TimelineSnappingTests.edgeSnapsToBeat14At70pps`; `…preciseTrimIgnoresBeats`; route iPad kéo tay nắm |
| 28 | Every Bar: chỉ phách 1 | 12/AC-8 | `TimelineSnappingTests.everyBarSkipsOffbeats` (8,75 không dính; 7,5 / 10,0 dính) |
| 29 | `CutToBeatMath` xem trước + panel/cột; mũi tên, vạch đứt 2×74, pill độ dời; chip Every Bar · 2 Bars · 4 Bars | 12/AC-10 | `CutToBeatMathTests.previewSampleProject` ("4 cuts move · largest +0.8s"; −0,5 · +0,8 · +0,8 · +0,3; recipe không đổi) |
| 30 | Apply to N Clips = một undo | 12/AC-11 | `…applyStretchesPhotosTrimsVideos` (2,5 · 7,5 trim 0–7,5 · 5,0 · 2,5 · clip 5 ở 17,5); `VideoBeatsModelTests.applyIsOneUndo` |
| 31 | cut không đạt được đứng yên, "· 1 can't move" | 12/AC-12 | `…shortSourceCutStays` (fixture: clip 3 nguồn 10 s để cut 14,2 → 15,0 hợp lệ) |
| 32 | rời xem trước (ô khác, ✕, đổi chọn) = không đổi | 12/AC-13 | `VideoBeatsModelTests.leavingPreviewChangesNothing` (recipe + độ sâu undo) |
| 33 | đo bài 3:24 m4a 44,1 kHz: thời gian, bộ nhớ đỉnh, không request mạng, huỷ ≤ 1 s — **sim 26.5 trước** (signpost + `vmmap`/Instruments Allocations), **máy thật iPhone 17 sau** | 12/AC-14 | `MusicBeatAnalyzerTests.cancelStopsWithinOneSecond` (sim); số đo ghi vào FS-12.12 §9; commit chỉ khi phải tối ưu |
| 34 | `design-parity` năm board | 12/AC-15 | agent `design-parity` |
| 35 | `design-reviewer` màu nhịp; sửa chỗ lệch | 12/AC-16 | agent `design-reviewer` + `grep` không `#EB9526`/`timelineSelection` trong code nhịp |

### Khối F3 — FS-12.13 (task 36–51)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 36 | `MusicDucking` (struct) + `DuckingMath.level`/`ramps`: hạ trước Duck in, đáy, lên trong Recover | 13/AC-2 | `DuckingMathTests.singleDipShape` (0,8 tới 3,9; 0,201 tại 4,2; giữ tới 7,4; 0,8 tại 8,2) — `musicRampsCoverTheWholeBed` vẫn xanh |
| 37 | gộp khoảng lặng < Duck in + Recover | 13/AC-3 | `…shortGapHoldsTheFloor` (3,9–7,3) |
| 38 | nhân với fade băng; chia nhỏ đoạn hai dốc chồng (D-11) | 13/AC-4 | `…fadeAndDuckMultiply` (0,100 ±0,005 tại 17,4) |
| 39 | giây nguồn → timeline qua trim, speed, placement | 13/AC-7 | `…speedTwoMapsSourceToTimeline` (5,0–6,0) |
| 40 | **đo trước:** SoundAnalysis `.version1` chạy được trên sim 26.5 / 18.6 không, mất bao lâu cho 10 s; rồi `VoiceActivityAnalyzer` (stream, cửa sổ 1 s chồng 0,5, bỏ < 0,3 s) + cache | 13/AC-1 | `VoiceActivityAnalyzerTests.syntheticVoiceOneSegment` (fixture `say`, nền −50 dBFS, mép ≤ 0,25 s) — trên cả 18.6 và 26.5 nếu sim chạy được (§2.5) |
| 41 | Any Clip Sound: RMS 50 ms > −40 dBFS sau mức clip | 13/AC-5 | `…windWithoutVoice` (Voices: không lõm; Any Clip Sound: lõm cả clip) |
| 42 | clip ảnh/freeze, tắt tiếng, âm 0, V1 tắt, Video sound 0 không kích hoạt; tóm tắt không đếm | 13/AC-6 | `DuckingMathTests.mutedClipNeverTriggers` + các biến thể |
| 43 | `MusicDucking` vào `MusicTrack` (đọc khoan dung), `audioMix(…activity:)` trong builder + service, công tắc UNDER VOICES, một undo | 13/AC-9 | `VideoAudioMixDuckingTests.offEqualsNeverOn` (so `getVolumeRamp` từng mốc của hai mix); `VideoProjectDecodingTests.musicTrackWithoutDuckingKeys`; `VideoDuckingModelTests.toggleIsOneUndo` |
| 44 | Amount/Duck in/Recover: kéo = một bước, chỉ tầng âm thanh | 13/AC-10 | `VideoDuckingModelTests.amountDragOneUndoNoRebuild` (đếm lần `rebuildPreview` = 0, `applyAudioMix` ≥ 1) |
| 45 | cache theo asset: đổi thứ tự/trim/speed không phân tích lại; trim rộng ra chỉ phân tích phần mới | 13/AC-8 | `VideoDuckingModelTests.reorderAnalysesZeroTimes` (analyzer giả đếm lần gọi) |
| 46 | clip không đọc được (iCloud không mạng, `.limited` thu hồi) → "· 1 clip not checked", không lõm, tự phân tích khi tải về | 13/AC-12 | `…unreadableClipIsNotChecked` (nguồn giả ném lỗi) |
| 47 | xoá băng / đóng studio huỷ ≤ 1 s, không file tạm; mở lại phân tích phần thiếu | 13/AC-14 | `…closeCancelsWithinOneSecond` |
| 48 | export chờ phân tích ("Listening for voices…" trong tiến độ export — chỗ hiện thuộc plan FS-12.10b); smoke âm thanh | 13/AC-11 | `VideoDuckingExportTests.sine440DipsTwelveDecibels`: dựng composition + **cùng** `audioMix` export dùng, đọc bằng `AVAssetReaderAudioMixOutput`, năng lượng 440 Hz 5–7 s thấp hơn 1–3 s 12 ±1 dB (D-12) |
| 49 | panel Ducking iPhone: đồ thị 370×78, chú giải, lõm "−12 dB", tóm tắt; dùng `timelineSpeech` | 13/AC-13 | `DuckingMathTests.graphGeometry` (băng 283,7pt, lõm 26pt); phone sim-shot |
| 50 | `design-parity` bốn board (nhãn Voice trên V1 ở iPad/Duo trong, pill "−12 dB" trên băng) | 13/AC-15 | agent `design-parity` |
| 51 | `design-reviewer` màu giọng | 13/AC-16 | agent `design-reviewer` |

## 6. Quyết định kỹ thuật (tự chốt, kèm lý do)

| # | Quyết định | Lý do |
|---|---|---|
| D-1 | Ngưỡng cử chỉ là hằng của `TimelinePressClassifier`; recognizer giữ `minimumPressDuration 0.32`, `allowableMovement 10` và hỏi classifier lúc thả | một nguồn số cho AC-18 và cho code; UIKit vẫn là đường duy nhất sống trong UIScrollView |
| D-2 | `selectedClipIDs` có thứ tự trong `VideoStudioModel`; `selectedClipID` cũ = nhóm 1 phần tử | `inspectorTarget`, `restore()` và phiên ✕/✓ đã xoay quanh model này; một model chọn, không hai |
| D-3 | Chuyển cảnh đi theo cặp id (`remapTransitions`) — áp cho dời, xoá, nhân đôi | Q-a; một luật thay vì vá từng lệnh |
| D-4 | Beats và ducking ở hai `@Observable` con (`VideoBeatsModel`, `VideoDuckingModel`) do `VideoStudioModel` sở hữu | model đã 2 036 dòng; vòng đời task phân tích gom một chỗ, `close()` huỷ cả hai; khuôn `VideoScopeModel` |
| D-5 | DSP nhịp ở Domain (Accelerate là toán thuần), giải mã ở Data | test được bằng mảng tổng hợp, không cần file |
| D-6 | `pointsPerSecondRange` hạ cận dưới 20 → 18 | board Duo ngoài cần 18; pinch xuống 18 vô hại; một kẹp thay vì hai |
| D-7 | Vạch nhịp vẽ bằng một `Canvas` theo cửa sổ đang thấy | bài 3 phút = 326 nhịp; mỗi nhịp một View làm host của scroller dựng lại cả cây mỗi lần cập nhật |
| D-8 | Khung khởi âm 256 mẫu, bước 128 (11,6 ms) | spec "khung ~23 ms" và AC-2 cần ±20 ms — bước 23 ms là sát biên |
| D-9 | Cut nằm ngoài cửa sổ của băng có lưới: không dời, không tính "can't move" | ở đó không có nhịp; ghi rõ để người dùng lật nếu muốn |
| D-10 | Fixture giọng sinh **một lần** bằng `say` trên Mac (≈ 15 KB, commit vào test) thay vì `AVSpeechSynthesizer.write` trong test | bộ đọc trong sim thiếu giọng và không ổn định; `say` là bộ đọc của hệ thống, đúng tinh thần spec |
| D-11 | Mức nhạc khi hai dốc chồng nhau (fade × duck) chia thành 4 đoạn tuyến tính | `setVolumeRamp` chỉ nội suy thẳng; tích hai dốc thẳng là bậc hai; 4 đoạn lệch < 1% |
| D-12 | Chứng minh AC-11 FS-12.13 bằng render âm thanh của chính `audioMix` export dùng (`AVAssetReaderAudioMixOutput`), thêm smoke export đầy đủ khi plan FS-12.10b có harness | cùng đối tượng mix tới `VideoExportWriter.swift:85`; nhanh và tất định |
| D-13 | Voice phân tích ở 16 kHz mono, RMS tính cùng lượt | một lần đọc cho cả hai chế độ; đổi chip không phân tích lại |
| D-14 | Export chờ phân tích giọng bằng trạng thái `ExportState.listening` | spec "hiện trong tiến độ export"; không xuất bản thiếu ducking |

## 7. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **JSON project:** `MusicTrack` dùng `Codable` tổng hợp — thêm khoá không có `init(from:)` thì project cũ (thiếu khoá) **không mở được** (`Creation.videoRecipe` là `try?` cả cục `Core/Models/Creation.swift:102-105`) | cao nếu quên | `init(from:)` khoan dung trong task 24 và 43, test thiếu khoá + khoá rác; không migration (CLAUDE.md). Nếu plan FS-12.08/04 thêm decoder khoan dung cho cả `VideoProjectRecipe` thì dùng chung |
| Giữ-để-chọn và giữ-để-kéo cùng ngón | vừa | ngưỡng ở Domain có test; đo cảm giác trên máy thật (agent `iphone-ux-review`) |
| Gesture SwiftUI chết trong UIScrollView | đã biết | chạm chọn dùng `onTapGesture` (chạm vẫn sống); kéo nhóm, tự cuộn đi qua UIKit |
| **Bộ nhớ:** Duplicate 10 clip 4K | thấp | bản sao trỏ cùng `VideoClipSource` (mẫu Split); filmstrip cache theo `assetID` |
| **Bộ nhớ:** phân tích | thấp | đọc theo buffer, chỉ giữ đường khởi âm (≈ 17 k Float cho 3:24) — PCM cả bài ở 11 025 Hz là 9 MB, không giữ; ngưỡng AC-14 ≤ 30 MB |
| **Concurrency:** task phân tích sống quá model; callback SoundAnalysis trên queue riêng | vừa | task do model con giữ, `close()` huỷ; observer gom kết quả dưới `OSAllocatedUnfairLock` (bài học `assumeIsolated`); kết quả là value `Sendable`, về `@MainActor` một lần |
| **Duo 669pt:** cột 264 chứa Speed + Volume + LOOK 46 + hàng lệnh; ducking 7 dòng | vừa | tổng ≈ 330pt < cột 385 (04b §6); `device-layout` + `duo-ux-review` |
| Duo ngoài: trạng thái chọn khi gập/mở máy | vừa | tập chọn là trạng thái màn hình; quy về ✓ khi scene đổi (hỏi `duo-ux-review`), mức zoom cũ khôi phục |
| **30 fps preview:** vạch nhịp, đường mức, pill vẽ lại khi playhead chạy | vừa | `Canvas` (D-7); lớp vạch không đọc `currentTime`; ducking không chạm tầng khung |
| `AVAudioMix` 50 đoạn dốc | thấp | đo ở task 44: thời gian dựng mix + gán mix lúc đang phát không vấp (spec §8 yêu cầu đo 50 đoạn) |
| Bộ phân loại "speech" đổi theo iOS | chấp nhận | spec §8; test chạy trên 18.6 và 26.5 |
| Tempo gấp đôi/nửa | vừa | khoá 60–180; test 60 và 170 BPM |
| XCUITest không liệt kê Video Studio trên phone | đã biết | phone: dump nút + `Tools/sim-shot`; route đo trên iPad/Duo |
| Hai agent một checkout | đã biết | `git commit -- <đường dẫn>`, không `add -A` |

## 8. Phụ thuộc giữa các plan Video Studio

| Plan / spec | Plan này cần gì | Task chặn |
|---|---|---|
| **vs-tools-selection-phone** (FS-12.04, 04b, 07) | phiên chọn ✕/✓ với ảnh chụp đầu phiên và gỡ undo; chân ✕ · tên · ✓; hàng lệnh 64×56 (mục/hành động, ẩn-không-mờ, mờ 0,28); panel không đổi cao; hàng lệnh nhạc có chỗ Beats · Ducking; Volume từng clip + đĩa loa; bỏ Master (FS-12.04 AC-15); `timelineSelection` = #57BFD1; LEVEL 370×8 (07 §6) | 4–19, 22, 24, 43–51 |
| plan của **FS-12.05** (tay nắm mép, dính lúc kéo + haptic) | tay nắm mép clip có thật; dính tính lúc `.changed`, không chỉ lúc thả | 27, 28 |
| **FS-12.06c** — [2026-10-02-video-photo-looks](2026-10-02-video-photo-looks.md) task 14 | đích **Selected** cho look nhóm | 9 |
| **FS-12.03 / 07b** (Duo trong cột 264, Duo ngoài dải 84, panel 382×344, dải tổng quan y 306) | khung đúng kích thước | 18, 19, 34, 50 |
| **FS-12.17** (giữ tay nắm → cắt từng khung) | chế độ không dính nhịp | 27 |
| **FS-12.17b** (bàn phím) | ⌘A chọn mọi clip, Esc thoát — đặt trên API của task 5 | — (plan này cung cấp) |
| **FS-12.14** (phụ đề) | dùng chung `timelineSpeech` — task 22 thêm cả hai token | — (plan này cung cấp) |
| **FS-12.10b** (Export) | chỗ hiện "Listening for voices…" trong tiến độ; harness smoke export nếu có | 48 |
| **FS-12 README AC-13** (clip lỗi `failed`) | trạng thái clip không tải được | 46 |
| **FS-12.08** (model) | nếu có decoder khoan dung cho cả recipe thì dùng chung | 24, 43 |

## 8b. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 9. Cách chứng minh là xong

- **Test (Swift Testing):** `TimelinePressClassifierTests`, `VideoClipGroupEditingTests`, `VideoStudioMultiSelectTests`,
  `BeatDetectorTests`, `BeatGridTests`, `TimelineSnappingTests`, `CutToBeatMathTests`, `MusicBeatAnalyzerTests`,
  `VideoBeatsModelTests`, `DuckingMathTests`, `VoiceActivityAnalyzerTests`, `VideoDuckingModelTests`,
  `VideoAudioMixDuckingTests`, `VideoDuckingExportTests`, `VideoProjectDecodingTests`; `VideoTimelineMathTests` cũ vẫn xanh.
  Mỗi task chạy test liên quan; **full suite một lần** khi xong cả ba spec, rồi `Tools/gate`.
- **Route `Tools/ui-drive`:** `video-press-release`, `video-press-drag`, `video-multiselect-ipad`,
  `video-group-drag-ipad`, `video-move-voiceover`, `video-duo-cover-multiselect`, `video-beats-ipad`,
  `video-beat-snap-ipad`, `video-cut-to-beat-duo`, `video-ducking-ipad`, `video-ducking-duo` — Duo **chỉ** bằng
  `ui-drive` + `Tools/sim-shot … inner|cover` (không dùng MCP sim tool).
- **Màn hình phải chụp** (tên `vs-<spec>-<state>-<device>.png`): F1 vào chọn 1 clip · 3 clip · nhóm toàn ảnh · đang kéo
  (chồng + vạch thả) · Move · Delete mờ · Duo ngoài 18 pt/s; F2 Finding beats · đã tìm · No steady beat · slider dính ·
  tay nắm dính + pill · xem trước Cut to Beat · sau Apply; F3 Listening · đồ thị · tắt · "1 clip not checked". Mỗi trạng
  thái trên iPhone 17 (26.5), iPad 13" ngang, Duo trong, Duo ngoài; nhánh iOS 18.6 trên iPhone SE cho trạng thái chính.
- **Design parity:** render board từ `docs/design/<thiết bị>/project/`; `design-parity` cho 13 board
  F1–F3 tới khi mọi board ≤ 2pt.
- **Phép đo (sim trước, máy thật sau):**
  - sim 26.5: nhịp bài 3:24 — thời gian, bộ nhớ đỉnh, huỷ ≤ 1 s (task 33);
  - sim 26.5 + 18.6: SoundAnalysis có chạy không, thời gian 10 s / 3 clip (task 40);
  - sim: dựng `AVAudioMix` 50 đoạn, gán lúc đang phát (task 44);
  - **máy thật iPhone 17**: FS-12.12 AC-14 (≤ 5 s, ≤ 30 MB, chế độ máy bay), thời gian phân tích giọng, cảm giác ngưỡng
    0,32 / 0,5 s / 10pt, 30 fps khi có vạch nhịp + đường mức.
- **Tài liệu cập nhật:** cột "Chứng minh bằng" của FS-12.11/12/13 theo từng task; FS-12.11 AC-17 (Q-b) lúc duyệt;
  DESIGN.md §3.3 bốn token (task 22); FS-12.12 §9 ghi số đo máy thật; `REVIEW_QUEUE.md` mục Split/chèn media giữ
  chuyển cảnh theo vị trí.

## 10. Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `swift-concurrency` | hai model con, task phân tích, callback SoundAnalysis, huỷ ≤ 1 s |
| `memory-leak` | cache phân tích, buffer PCM, nguồn dùng chung của Duplicate, task giữ `self` |
| `perf-profiler` | vạch nhịp trên timeline, 50 đoạn dốc, dựng lại host của scroller |
| `photokit-guard` | đọc âm thanh từ `AVAsset` của PHAsset; iCloud không mạng, `.limited` (FS-12.13 AC-12) |
| `data-migration` | khoá mới trong recipe JSON ở `creations`, decoder khoan dung |
| `design-parity` · `design-reviewer` | 13 board; màu `timelineBeat`/`timelineSpeech`/`timelineSelection` |
| `device-layout` · `duo-ux-review` · `iphone-ux-review` · `ipad-ux-review` | cột 264, dải 84, panel 340; cử chỉ giữ/kéo; trạng thái chọn qua gập máy |
| `ipad-multitasking` | ⌘-click, Shift-click, con trỏ trên clip |
| `a11y-voiceover` | Move không kéo, huy hiệu ✓, pill, thẻ nhịp, đồ thị ducking có nhãn |
| `localization` · `copy-consistency` | số nhiều "N Clips", "2 videos + 1 photo", BPM, dB |
| `ios26-parity` | cùng bộ action trên 26.5 và 18.6 |
| `test-coverage` | Domain mới (classifier, nhóm, nhịp, Cut to Beat, ducking) |
| `challenger` | điền §8b trước khi code |
