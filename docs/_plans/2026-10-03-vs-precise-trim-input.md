# Kế hoạch — Cắt từng khung, scrub chính xác, Pencil, bàn phím và skim (FS-12.17 · FS-12.17b)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-12.17`](../02-functional-spec/FS-12-video-studio/17-precise-trim-and-input.md) (17 AC) · [`FS-12.17b`](../02-functional-spec/FS-12-video-studio/17b-keyboard-and-pointer.md) (18 AC) — **35 AC**, cả hai là F6 |
| Intent | [video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — F6, thứ tự theo mảng: chrome → chọn item → Media → Video Settings → Look → kích thước → F1–F8 |
| Design | canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ> (Version 26), hàng F6: `F6_P_PreciseTrim` · `F6_P_FineScrub` · `F6_DI_TouchTrim` · `F6_IP_PencilTrim` · `F6_DC_PreciseTrim` · `F6_P_Keyboard` · `F6_DI_Keyboard` · `F6_DC_Keyboard` · `F6_IL_HoverScrub` · `F6_IL_Shortcuts` — **đủ 10 board trên canvas** (đã liệt kê file 2026-10-03, kể cả hai board `F6_DC_*` spec §11 yêu cầu vẽ thêm). Bản cục bộ `build/design/video/project/` **chưa có board F6 nào** → mỗi task UI xuất lại `project/` trước khi chạy `design-parity` |
| Phụ thuộc | xem §7 — chặn nhất là plan **chrome / chọn item / hàng lệnh / tay nắm mép** (FS-12.04 · 04b · 05 §3) |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **8** (cuối) của thứ tự xây. 38 task = 38 commit. Task 1–2 (driver) làm được ngay, trước cả bước 1; task 3 trở đi chờ các plan ở §7 |

> Dòng `Tiến độ` của intent và các chỗ sửa spec ở §5 đã ghi trong commit duyệt 2026-10-03.

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 8** của thứ tự xây.
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
- **Quyết định của plan này:** ⚠️-1 … ⚠️-4 "tài liệu đúng" duyệt. ⚠️-5 → câu "(đã thế)" ở FS-12.17 §13 đã sửa thành
  việc phải làm (task 13 dựng filmstrip theo vùng nhìn). ❓-1 → tiền đề FS-12.17 AC-13 đã sửa: "project mở khi có
  mạng, Clip 2 là luồng iCloud, rồi mất mạng". ❓-2 → **iPad: hai công tắc PRECISION nằm cạnh khối PENCIL** (FS-12.17
  §7 đã sửa; board `F6_IP_PencilTrim` vẽ thêm) — task 18 làm khối này, không còn "giá trị mặc định". ❓-3 → ngoại lệ
  Duo trong của ô Trim (không chip Start/End) đã vào FS-12.04b §4. ❓-4 kỹ thuật: phần bàn phím (task 22–34) chạy sau
  F1 và F7 — đúng thứ tự xây (bước 8 sau bước 6, 7).
- **Quyết định kỹ thuật 7 đổi theo FS-12.18:** In–Out vẫn ngoài undo và `restore()` giữ nó, nhưng **tự lưu cùng nháp**
  như mọi trường; Back không còn hỏi Discard nên không còn chuyện "bật `hasEdits`". Test task 27 đổi
  `inOutDoesNotDirtyProject` → `inOutIsSavedWithTheDraft`.
- `inPoint`/`outPoint` chỉ thêm khoá vào bộ giải mã khoan dung của tools plan task 4.
- **Board canvas phải sửa** (canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ>, trước task
  `design-parity` đầu tiên của board đó):
  - `F6_IP_PencilTrim`: thêm hai công tắc PRECISION cạnh khối PENCIL (❓-2); chân "Trim · Clip 2" / "0:09.07 · −4
    frames"; bỏ dòng Duration của clip video (FS-12.17 §11).
  - `F6_DI_TouchTrim`: bỏ dòng Duration; cột badge 100 (Lock · Mute) của plan màn rộng. `F6_DI_Keyboard`: cột badge 100.
  - `F6_P_FineScrub`: "pinch out to return" → "pinch in to return" (FS-12.17 §11).

## 1. Hiểu đúng chưa

**FS-12.17.** Giữ yên tay nắm mép clip 0,5 s (tay nắm do FS-12.05 vẽ) mở **chế độ Trim từng khung**: một phiên lồng
trong phiên chọn, recipe **không đổi** cho tới ✓; mép "ảo" dời theo lưới khung của project (fps của Video Settings),
viewer tự giải mã khung ở mép, kính lúp 10 khung khi ngón/Pencil đang giữ, pill ±1 Frame, ✓ = một bước undo, ✕ = như
chưa vào. Frame zoom nâng trần pinch lên 12pt/khung, khi đó scrub đi đúng từng khung (haptic, huy hiệu, seek chính xác).
Duo trong/iPad vào bằng ô Trim; iPad thêm Pencil (vào thẳng, đứng yên 0,3 s → 12pt/khung, hover, chạm đúp
trim↔scrub). Bốn công tắc theo máy.

**FS-12.17b.** 28 phím từ **một** danh mục sinh cả phím lẫn danh sách; iPad dùng danh sách ⌘ của hệ thống (3 nhóm),
iPhone/Duo vẽ thẻ riêng (12 dòng) tự hiện một lần, giữ ⌘ 0,6 s mở lại. J/K/L shuttle, In–Out chỉ để xem (Loop + Home/End),
⌘±zoom, ⌫ chỉ xoá thứ đang chọn, phím trần im khi gõ chữ, mọi phím im khi có sheet. iPad: rê con trỏ qua ô video của
thư viện Media là skim nguồn, không đụng playhead.

Không đụng `photo_metadata`; project thêm đúng hai trường tuỳ chọn (In, Out). Không migration (app chưa release).

## 2. Đối chiếu AC ↔ code

### FS-12.17 — cắt từng khung

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 giữ mép cuối 0,5 s → pill (77,728), đáy "Trim · Clip 2", 5 công cụ ẩn, "Last frame · 0:09.20", kính Ø124 | ❌ | Tay nắm mép clip **không tồn tại**: kind `clipLeadingHandle/clipTrailingHandle` có (`VideoTimelineScroller.swift:19-20`) nhưng không row nào phát zone, và commit là no-op "clips trim via the inspector Duration slider" (`VideoTimelineView.swift:342-343`). Long-press duy nhất là đổi thứ tự 0,32 s trên thân clip (`VideoTimelineScroller.swift:134-140`), chỉ khi clip chọn và `mode == .multiClip` (`VideoTimelineTracks.swift:418-429`). Không có trạng thái chế độ nào trong model | task 6 (sau khi plan chrome/chọn item vẽ tay nắm) |
| AC-2 −1 Frame ×4 → "0:09.07 · −4 frames", Clip 3 vẫn 9,20, recipe chưa đổi | ❌ | không có lưới khung: bước khung cố định `1/30` ở ba chỗ (`VideoStudioScreen.swift:670-673`, `VideoViewerChrome.swift:133`, `:432`); không có định dạng `m:ss.cc` | `VideoFrameGrid` + `FrameTrimSession` (Domain), task 7 |
| AC-3 ✓ → Clip 2 = 6,067 s, Clip 3 bắt đầu 9,067; +1 undo; Undo → 6,2 | ❌ | ghi được bằng `setTrim` (`VideoStudioModel.swift:684-698`) sau `pushUndo` (`:603-610`); chưa có phiên | task 8 |
| AC-4 ✕ → recipe như trước, undo không đổi | ❌ | như AC-3 | task 9 |
| AC-5 2× → mép timeline −1/30 s, cửa sổ nguồn −2/30 s | ❌ | phép quy đổi tốc độ đã có trong `trimToPlayhead` (`VideoStudioModel.swift:933-935`: `trimStart + localTime × speed`) và `effectiveDuration` (`VideoProjectModels.swift:141-150`) — **tái dùng công thức, không viết lần hai** | task 10 |
| AC-6 ảnh 0,5 s, −1 Frame → giữ 0,5; nút mờ 35%, không nhận chạm | ❌ | giới hạn có sẵn `photoDurationRange 0.5...10`, `minimumClipDuration 0.1` (`VideoProjectModels.swift:172-174`), `clampedTrim` (`VideoTimelineMath.swift:179-199`) | task 11 |
| AC-7 pinch ra hết → 360 pt/s, pill "Frame zoom · 1 frame = 12 pt", nhãn thước cách 72pt | ❌ | trần cứng `20...160` (`VideoStudioMetrics.swift:627`), kẹp trong View (`VideoTimelineView.swift:236-248`, `:250-260`); thước chỉ vạch 0,5 s nhãn "Ns" (`VideoTimelineTracks.swift:101-152`); `pps` là `@State` của View (`VideoTimelineView.swift:27-28`) nên phím ⌘± không với tới | task 13 |
| AC-8 ở Frame zoom kéo 36pt → lùi đúng 3 khung, 3 haptic, huy hiệu "−3 f · 0:08.80", khung viewer đúng | ❌ | haptic mỗi **giây** (`VideoTimelineView.swift:227-234`); scrub seek dung sai ±30/600 s (`VideoStudioModel.swift:577-580`) — rộng hơn một khung, đúng như spec §6 nói | task 14 |
| AC-9 "Frame zoom on pinch" tắt → dừng 160, không pill | ✅ (hành vi) | hôm nay mọi pinch dừng ở 160 và không có pill (`VideoStudioMetrics.swift:627`, `VideoTimelineView.swift:241-244`) — chính là trạng thái "tắt" | task 3 khoá bằng test; công tắc thật vào ở task 13, test chạy lại với công tắc tắt |
| AC-10 Duo trong: 4 ô đầu −1·+1·Frame Zoom·Trim(bật), không Split, 5 công cụ đáy không nhận chạm | ❌ | hàng lệnh hôm nay là `Split · Mute · Animate · Replace · Freeze` ô 52×54 (`VideoStudioSheetHost.swift:609-635`) — hàng mới là việc của plan chrome (04b) | task 15, sau plan chrome |
| AC-11 iPad Pencil: đứng yên 0,3 s rồi 24pt → −2 khung; ngón tay cùng lúc cuộn | ❌ | không có `UITouch.type`, `allowedTouchTypes`, `UIPencilInteraction` ở đâu trong `Features/VideoStudio/` (grep rỗng) | task 18 — **chỉ máy thật** |
| AC-12 chạm đúp Pencil → scrub, cửa sổ cắt không đổi | ❌ | như AC-11 | task 19 — **chỉ máy thật** |
| AC-13 Clip 2 chỉ iCloud, tắt mạng: kính xám "Offline", không request mạng, ✓ vẫn ghi | ❓ | Tiền đề **không dựng được như ghi**: `load()` bỏ mọi clip không có nguồn (`VideoStudioModel.swift:486-493`), và nguồn video đi qua `requestAVAsset` **cho phép mạng** (`PhotoLibraryService.swift:236-248`) → tắt mạng thì Clip 2 bị loại trước khi vào chế độ. Clip 2 chỉ còn trong project nếu project mở khi **có** mạng (PhotoKit trả `AVURLAsset` luồng) rồi mất mạng — chưa đo PhotoKit trả gì | xem ❓-1 ở §5; task 20 |
| AC-14 VoiceOver: tay nắm đọc "Clip 2 end, 0:09.20", vuốt xuống → −1 khung, đọc "0:09.17" | ❌ | `ClipBand` là một phần tử nút (`VideoTimelineTracks.swift:292-294`), không có phần tử tay nắm, không `accessibilityAdjustableAction` | task 12 |
| AC-15 design-parity 5 board | ❌ | không có UI nào của chế độ | task 21 (và mỗi task UI tự chạy board của nó) |
| AC-16 Duo ngoài: panel ẩn, timeline 334–644, pill (67,582), ✕ y 504, ✓ y 556, Export ẩn | ❌ | bố cục Duo ngoài 07b là việc của plan kích thước | task 17, sau plan kích thước |
| AC-17 iPad dọc + Duo trong: chân "Trim · Clip 2" / "0:09.07 · −4 frames" (Duo trong "−4 f"), không dòng Duration | ❌ | chân ✕ · tên · ✓ chưa có (plan chrome); dòng Duration video vẫn còn trong inspector hôm nay | task 16 |

### FS-12.17b — bàn phím, danh sách, In–Out, skim

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 24 fps, 2,000 s, ⇧→ → 2,0417 s | ⚠️ → **tài liệu đúng, sửa code** | ⇧←/→ bước cố định `1.0/30` (`VideoStudioScreen.swift:670-673`), hai transport cũng vậy (`VideoViewerChrome.swift:133`, `:432`); spec đã ghi "có, sửa bước theo fps project" — không phải quyết định mới | task 5 (cần trường fps của plan Video Settings) |
| AC-2 L, L → rate 2, nhãn "2×"; K → 0 | ❌ | chỉ có `togglePlayback` bật/tắt `play()` (`VideoStudioModel.swift:526-542`), không đặt `rate` | task 23 |
| AC-3 I 5,0 · O 12,0 · Loop · Space → quay về 5,0; cờ I/O; ⌥X xoá | ❌ | Loop có, nhưng về **0** ở cuối project (`VideoStudioModel.swift:2013-2027`); không có In/Out trong recipe (`VideoProjectModels.swift:460-512`) | task 27 |
| AC-4 7,0 s trong Clip 2, ⌥[ → nguồn bắt đầu 4,0, dài 2,2, +1 undo | ✅ (lệnh) · ❌ (phím) | phép tính đúng: `trimToPlayhead(.start)` (`VideoStudioModel.swift:915-950`) — `localTime = 4,0`, `sourceTime = 0 + 4×1`, `pushUndo` một lần; nút ở transport (`VideoViewerChrome.swift:151-162`, menu ⋯ `:503-516`). Chưa có phím ⌥[ / ⌥] | task 4 khoá phép tính; task 24 gắn phím |
| AC-5 đang gõ "jim k" → ô có chữ, playhead đứng, không In | ❌ | lớp phím ẩn không biết ô nhập đang focus (`VideoStudioScreen.swift:661-697`); `OverlayTextField` giữ `@FocusState` riêng (`VideoInspectorControls.swift:37-50`) | task 30 |
| AC-6 không chọn gì, ⌫ → recipe không đổi | ❌ | không có phím ⌫ | task 25 |
| AC-7 ⌘+ ×2: 55 → 220; ⌘− ×2 → 55 | ❌ | không có phím zoom; `pps` nằm trong `@State` của View (`VideoTimelineView.swift:27`) | task 26 (sau task 13) |
| AC-8 iPhone, lần đầu cắm phím, Space → danh sách trong vùng panel, 12 dòng | ❌ | không có thẻ | task 32 |
| AC-9 Duo trong, giữ ⌘ 0,6 s → thẻ 640×300, thả → mất; không tự hiện lại | ❌ | không đọc phím bổ trợ thô ở đâu | task 33 |
| AC-10 iPad giữ ⌘ → danh sách hệ thống 28 lệnh, 3 nhóm, tên đúng board | ⚠️ → **tài liệu đúng, sửa code** | 13 nút ẩn hôm nay (`VideoStudioScreen.swift:664-693`), tên lệch board: "Start", "End", "Split", "Export" (board: Go to Start, Go to End, Split at Playhead, Export…); không có nhóm; Esc chỉ bỏ chọn khi có sheet (`:691-693`) | task 22 |
| AC-11 Trim từng khung, −4, Esc → như ✕ | ❌ | Esc = `clearSelection` (`VideoStudioScreen.swift:691-693`) | task 31 |
| AC-12 skim 46% ô Lake → header "Skimming · Lake · 0:02.3 / 0:05", viewer khung 2,3 s, transport "0:08.4" | ❌ | ô pool chỉ có tap + `onDrag` (`VideoMediaPoolColumn.swift:705-779`); header viewer chỉ ghi clip dưới playhead (`VideoViewerChrome.swift:77-94`); viewer chỉ có `AVPlayerLayer` (`VideoStudioScreen.swift:793-797`) | task 35 (sau plan Media) |
| AC-13 con trỏ rời ô → header + viewer về playhead | ❌ | như AC-12 | task 36 |
| AC-14 video iCloud, tắt mạng → không request, thumbnail, "· Not downloaded" | ❌ | chưa có đường skim; `requestAVAsset` hiện **luôn** cho mạng (`PhotoLibraryService.swift:239`) — skim cần biến thể không mạng | task 37 |
| AC-15 design-parity 4 board | ❌ | — | task 38 |
| AC-16 In 5 · Out 12 · playhead 8,4: Home → 5, End → 12; ⌥X rồi Home → 0 | ⚠️ → **tài liệu đúng, sửa code** | Home/End và nút Go to Start/End nhảy cứng 0 / `totalDuration` (`VideoStudioScreen.swift:674-677`, `VideoViewerChrome.swift:174-199`, `:437-448`) — đúng hôm nay vì chưa có In–Out | task 28 |
| AC-17 In 5 · Out 12 → Export đủ 24,0 s, recipe clip không đổi | ✅ khi trường mới không chạm builder | builder/export không đọc trường nào ngoài clip/transition/music/overlay; In/Out mới chỉ đọc ở transport | task 29: test khoá sau khi trường tồn tại |
| AC-18 Duo ngoài, lần đầu cắm phím, Space → danh sách vùng 334–644, khung 382×215 không đổi | ❌ | — | task 34 |

**Không có ✅ đầy đủ** ngoài hành vi của AC-9 (17) và phép tính của AC-4 (17b). Những phím đang chạy đúng và giữ
nguyên (Space, ←/→, ⌘B, ⌘Z/⇧⌘Z, ⌘E mở sheet — `VideoStudioScreen.swift:664-690`) vào test danh mục ở task 22.

**Spec có, AC không có** (làm kèm test ở task gần nhất, `/verify` sẽ báo "có test, không AC"): Back trong chế độ = ✓
(§3, task 8); lane khoá không có chế độ (§3, task 6); gạch chéo/viền phần cắt-nới (§3, task 7); kéo mép khi đang giữ:
lưới khung + haptic (§5, task 6); clip 24 fps nguồn 30 (§10, task 10); cử chỉ bị huỷ giữ chế độ (§10, task 6); cảnh báo
bộ nhớ xả cache (§10, task 6); hover Pencil (§8, task 18); J lùi không được → tìm khung 15/s (17b §7, task 23); rút bàn
phím đóng danh sách (17b §7, task 32); mũi tên hai chiều trên tay nắm (17b §6, task 35); skim khi đang phát = không (task 35).

## 3. Tái dùng — không viết lần hai

| Có sẵn | Dùng cho |
|---|---|
| `TimelineDragZone` + nhận dạng UIKit trên `TimelineScrollView` (`VideoTimelineScroller.swift:17-44`, `:116-140`, `:368-395`) | long-press 0,5 s trên tay nắm, nhận dạng Pencil, hover, `UIPointerInteraction` — **mọi** cử chỉ mới đi qua scroller (gesture SwiftUI chết trong UIScrollView) |
| `trimToPlayhead` quy đổi tốc độ (`VideoStudioModel.swift:915-950`) | rút thành `VideoTrimToPlayheadMath` (task 4) — dùng chung cho ⌥[ / ⌥], chip Start/End to Playhead của plan chrome và phép dời mép của `FrameTrimSession`. Nếu plan chrome đã rút rồi thì task 4 chỉ thêm test |
| `clampedTrim`, `photoDurationRange`, `minimumClipDuration` | biên của ±1 Frame — **cùng hàm** với kéo tay nắm thường của FS-12.05, để hai lối cắt cùng một giới hạn |
| `VideoStudioService.extractFrame` (zero tolerance, `maximumSize`) (`VideoStudioService.swift:173-190`) | lõi giải mã của `VideoEdgeFrameSource` (kính + viewer ở mép) và skim |
| `VideoTransportMath` (`Domain/Presentation/VideoTransportMath.swift`) | kẹp seek của shuttle và Home/End |
| `fitToWindowToken` (`VideoStudioModel.swift:120`, `:422-424`) | mẫu "yêu cầu zoom qua token" cho ⌘± và ô Frame Zoom, thay vì kéo `pps` lên model |
| `VideoStudioLayoutTests` / `VideoStudioDeskLayoutTests` | khoá toạ độ pill, kính, thẻ phím, chân — số của board thành test thuần |
| `OverlayTextField` `@FocusState` | nguồn duy nhất của "đang gõ chữ" cho cổng phím trần |
| `VideoMediaPoolFormat.name` / `.duration` | tên "Lake" và "0:05" trong header skim |

## 4. Chỗ nào trong code

| File | Đụng gì | Tầng | Mới / sửa |
|---|---|---|---|
| `Domain/Video/VideoFrameGrid.swift` | lưới khung theo fps: snap, bước ±n (từ mép lệch lưới thì tới vạch kế), đếm khung, `m:ss.cc` ("0:09.07"), "−4 frames"/"−4 f" | Domain | mới |
| `Domain/Video/FrameTrimSession.swift` | phiên lồng: clip, mép, ảnh chụp clip lúc vào, số khung dời, `canStep(±)`, mép ảo, dải gạch/nới, `applied(to: recipe)` cho ✓ | Domain | mới |
| `Domain/Video/TimelineZoomMath.swift` | kẹp pinch theo trần (160 hoặc 12pt/khung), ⌘± ×2/÷2, nhận Frame zoom, scrub 12pt/khung (số khung vượt = số haptic), huy hiệu, vạch thước (nhãn mỗi 6 khung) | Domain | mới |
| `Domain/Video/PencilFrameStepper.swift` | đứng yên ≤ 2pt / 0,3 s → 12pt/khung cho phần còn lại của nét; chế độ trim/scrub | Domain | mới |
| `Domain/Video/VideoShortcut.swift` | danh mục 28: tên (như board), nhóm, phím + bổ trợ (kiểu riêng, không SwiftUI), 12 dòng gộp của thẻ; `VideoKeyboardRouter`: cổng (gõ chữ / sheet / phiên trim), chuỗi Esc, Return, ⇧←/→ trong trim | Domain | mới |
| `Domain/Video/VideoShuttle.swift` | J/K/L: rate, nhãn "2×"/"4×", tắt tiếng ở 4× và phát lùi | Domain | mới |
| `Domain/Video/VideoInOutRange.swift` | đặt In/Out (O trước In → In = 0; In sau Out → xoá Out), đích Go to Start/End, đích Loop | Domain | mới |
| `Domain/Video/VideoSkimMath.swift` | tỉ lệ ngang → giờ nguồn, chữ header, nhịp ≤ 30/s, "mới thay cũ" | Domain | mới |
| `Domain/Video/VideoTrimToPlayheadMath.swift` | rút từ `trimToPlayhead` | Domain | mới (task 4) |
| `Domain/Video/VideoProjectModels.swift` | `inPoint: Double?`, `outPoint: Double?` (Optional — xem §6 Rủi ro) | Domain | sửa |
| `Data/Sources/VideoEdgeFrameSource.swift` | actor: khung quanh mép ở cỡ ≤ 2× kính, zero tolerance, ≤ 30 khung/mép, xả khi cảnh báo bộ nhớ, **chỉ file cục bộ** (luồng iCloud → Offline) | Data | mới |
| `Data/Sources/VideoSkimFrameSource.swift` | actor: `AVAsset` thư viện **không mạng**, một yêu cầu đang chạy, mới thay cũ, ≤ 30/s, cạnh dài ≤ 1280 | Data | mới |
| `Data/Sources/PhotoLibraryService.swift` | `requestAVAsset(for:allowsNetwork:)` (mặc định giữ `true`) | Data | sửa |
| `Data/Sources/VideoInputPreferences.swift` | 4 công tắc + cờ "đã tự hiện danh sách phím" (UserDefaults, theo máy) | Data | mới |
| `Features/VideoStudio/VideoStudioModel+FrameTrim.swift` | vào/ra phiên, ±1, ✓/✕, Back = ✓, VoiceOver ±1 | Features (model) | mới — model đã 2036 dòng |
| `Features/VideoStudio/VideoStudioModel+Keyboard.swift` | shuttle, In/Out, zoom request, ⌫, Esc/Return | Features (model) | mới |
| `Features/VideoStudio/VideoFrameTrimChrome.swift` | pill, kính lúp, nhãn viewer, chân "Trim · Clip 2" | Features (view) | mới |
| `Features/VideoStudio/VideoKeyboardShortcuts.swift` | lớp nút ẩn (iPhone/Duo) + `CommandMenu` 3 nhóm (iPad) sinh từ `VideoShortcut.allCases`; thẻ iPhone/Duo ngoài, thẻ Duo trong | Features (view) | mới; thay `keyboardShortcuts` ở `VideoStudioScreen.swift:661-697` |
| `App/ShotDexApp.swift` | `.commands { VideoStudioCommands() }` + `@FocusedValue` — chỉ iPad (task 22) | App | sửa |
| `Features/VideoStudio/VideoTimelineScroller.swift` | long-press 0,5 s trên zone tay nắm (`allowableMovement` 4), cổng giữa zone pan và long-press, scrub lượng tử 12pt ở Frame zoom, nhận dạng Pencil (`allowedTouchTypes`), hover Pencil, `UIPointerInteraction` mũi tên hai chiều | Features | sửa |
| `Features/VideoStudio/VideoTimelineView.swift` | trần zoom từ `TimelineZoomMath`, pill Frame zoom + gợi ý, huy hiệu, nhận zoom request | Features | sửa |
| `Features/VideoStudio/VideoTimelineTracks.swift` | thước khung "8:12f"; gạch chéo / viền nới; **filmstrip chỉ vẽ ô trong vùng nhìn** (⚠️-5); phần tử VoiceOver tay nắm; cờ I/O + vùng sáng trên thước | Features | sửa |
| `Features/VideoStudio/VideoViewerChrome.swift` | header "Skimming · …"; nhãn "2×" trên Play; Go to Start/End theo In–Out; mục **Precision** trong ⋯ | Features | sửa |
| `Features/VideoStudio/VideoStudioScreen.swift` | lớp ảnh trên `AVPlayerLayer` (khung mép / khung skim), bố cục khi trong chế độ | Features | sửa |
| `Features/VideoStudio/VideoStudioMetrics.swift` | số của pill, kính (Ø124/140/208, khoảng hở 2/25/8), thẻ phím, theo máy | Features | sửa |
| Ô thư viện Media (FS-12.09, file do plan Media đặt) | `onContinuousHover` → skim; vạch 1pt, nhãn 76×20, dòng "Click adds · drag to place" | Features | sửa |
| `ShotDexUITests/UIDriver.swift`, `UIDriverTests.swift` | bước driver mới (task 1–2) | test | sửa |
| `.claude/skills/ui-drive/SKILL.md`, `CLAUDE.md` (danh sách bước) | ghi bước mới → chạy `Tools/evals` | agent config | sửa |

Logic **không** vào View: View chỉ đọc `FrameTrimSession`, `TimelineZoomMath`, `VideoShortcut` và gọi model.

## 5. Chỗ lệch và câu hỏi

| # | Loại | Chỗ | Khuyến nghị |
|---|---|---|---|
| ⚠️-1 | 17b AC-1 | bước khung 1/30 cố định (`VideoStudioScreen.swift:670-673`, `VideoViewerChrome.swift:133`, `:432`) | **Tài liệu đúng** — spec đã chốt "sửa bước theo fps project"; ba chỗ đọc chung `VideoFrameGrid` |
| ⚠️-2 | 17b AC-10 | tên nút ẩn "Start"/"End"/"Split"/"Export" lệch board | **Tài liệu đúng** — danh sách hệ thống in đúng tên nút, nên tên phải là tên board |
| ⚠️-3 | 17b §3 / FS-12.04 §5 | Esc hôm nay = bỏ chọn, chỉ khi có sheet (`VideoStudioScreen.swift:691-693`) | **Tài liệu đúng** — plan chrome đổi Esc thành ✓; plan này chèn hai bậc trước nó (✕ trim → đóng danh sách) |
| ⚠️-4 | 17b AC-16 | Home/End cứng 0 / cuối (`VideoStudioScreen.swift:674-677`) | **Tài liệu đúng** — hôm nay đúng chỉ vì chưa có In–Out |
| ⚠️-5 | 17 §13 | spec ghi thumbnail "vẽ theo ô trong vùng nhìn (**đã thế**)" — **sai**: `ClipFilmstrip` dựng `width/height` ô trong một `HStack` không lazy (`VideoTimelineTracks.swift:443-454`). Ở 720 pt/s (60 fps) một clip 60 s là ~650 view, cả project 10 phút là nội dung rộng 432 000pt | **Code sửa** (filmstrip chỉ dựng ô giao vùng nhìn — `TimelineTracksContent` đã nhận `visibleLeftTime`), và **sửa câu "(đã thế)"** trong spec 17 §13 thành việc phải làm. Làm trong task 13 |
| ❓-1 | 17 AC-13 | tiền đề "chỉ iCloud, tắt mạng" không mở được project có Clip 2 (`VideoStudioModel.swift:486-493`) | **Sửa tài liệu**: tiền đề thành "project mở khi có mạng, Clip 2 là luồng iCloud (không phải file trên máy), rồi tắt mạng". Code: kính coi **mọi** nguồn không phải file cục bộ là Offline — kể cả khi có mạng — vì §5 cấm "gọi tải chỉ để vẽ kính". Cần đo trên máy thật PhotoKit trả `AVURLAsset` luồng hay nil (D7) |
| ❓-2 | 17 §7 ↔ 03b §2 | Precision "trong menu ⋯ của transport" cho iPad, nhưng transport bàn dựng iPad **không có ⋯** (`VideoViewerChrome.swift:129-260`; 03b §2) | **Sửa tài liệu + board**: iPad đặt 2 công tắc PRECISION cạnh khối PENCIL của chế độ Trim (`F6_IP_PencilTrim`), như Duo trong đặt khối PRECISION trong cột phải. Không AC nào chạm — không chặn task nào; nếu chưa quyết, task 18 để iPad dùng giá trị mặc định |
| ❓-3 | 17 §3–4 ↔ 04b §57 | Duo trong: ô Trim bật là vào chế độ, cột phải **không** có hai chip Start/End to Playhead (board `F6_DI_TouchTrim`), trong khi 04b nói ô Trim luôn bật khối hai chip | **Tài liệu 17 đúng** cho Duo trong (transport bàn dựng đã có Trim Start/End, 669pt không dư một hàng); thêm một dòng ngoại lệ vào 04b §57. Không chặn AC-10 |
| ❓-4 | 17b AC-10 · AC-15 | danh mục có **⌘A Select All** (FS-12.11, F1) và **\\ Before and After** (FS-12.15, F7). "Danh sách không bao giờ ghi một phím không chạy" | Kỹ thuật: làm phần 17b **sau** plan F1 và F7; nếu phải làm trước, hai mục đó vắng mặt và AC-10 chỉ chứng minh được khi chúng vào (test đếm 28 sẽ đỏ tới lúc đó — đúng ý) |

## 6. Quyết định kỹ thuật (tự quyết, kèm lý do)

1. **Phiên Trim từng khung không đổi recipe** tới ✓; ✓ = `pushUndo` + một lần ghi (`setTrim`/`setPhotoDuration`);
   ✕ chỉ bỏ trạng thái. *Vì spec §3 muốn ±1 không chờ dựng lại composition, và ✕ không để bước undo nào là miễn phí.*
   Phiên lồng **trong** phiên chọn của plan chrome: ✕ của phiên chọn về sau vẫn gỡ bước ✓ này.
2. **Mép ảo**: thời điểm mép = mép gốc + khung × 1/fps, cả cho mép đầu (trên lane không khoảng trống, mép đầu "thật"
   chỉ dời sau ✓). Viewer chiếu khung nguồn = `trim ± khung × speed / fps`.
3. **Mép lệch lưới**: ±1 tới vạch lưới kế theo hướng đó; kéo luôn rơi đúng vạch. Số "−4 frames" đếm từ mép lúc vào.
4. **Long-press 0,5 s** là nhận dạng UIKit riêng trên zone tay nắm (`allowableMovement` 4). Zone pan của kéo thường
   chỉ bắt đầu khi long-press còn `.possible`/`.failed`; long-press thắng thì phần còn lại của ngón là kéo lượng tử
   theo khung. Vùng tay nắm được hit-test **trước** thân clip, nên giữ 0,5 s trên thân (FS-12.11) không đụng nhau.
5. **Zoom vẫn là `@State` của timeline**; phím ⌘± và ô Frame Zoom gửi **yêu cầu qua token** như `fitToWindowToken`.
   *Vì pinch ghi `pps` 60 lần/giây — đưa nó lên `@Observable` model là làm mọi view đọc model tính lại theo ngón.*
   `pps` hiện ra cho test qua `accessibilityValue` của timeline.
6. **Frame zoom scrub**: ở trần, `scrollViewWillEndDragging` kéo `targetContentOffset` về bội 12pt; `scrub` dùng
   dung sai 0 khi ở Frame zoom. Haptic = số vạch vượt (tính trong Domain), bộ phát gọi đúng số đó.
7. **In/Out** là `Double?` trong recipe, **không** `pushUndo`, tự lưu cùng nháp như mọi trường (FS-12.18 — Back không
   hỏi gì nữa), và `restore()` khi Undo/Redo **giữ** In/Out hiện tại. *Vì undo là ảnh chụp cả recipe (`VideoStudioModel.swift:637-659`) — không giữ thì Undo một lần cắt sẽ xoá luôn In vừa đặt.*
8. **Loop trong In–Out**: `addBoundaryTimeObserver` tại Out (đăng ký lại khi Out đổi); Play khi Loop bật mà playhead
   ngoài vùng thì bắt đầu từ In.
9. **J/K/L**: `player.rate`; item preview đặt `audioTimePitchAlgorithm = .timeDomain` (giữ cao độ ở 2×); `isMuted`
   ở 4× và rate < 0. Item không `canPlayReverse` → bộ tìm khung 15/s, tắt tiếng (17b §7).
10. **Đăng ký phím**: một danh mục `VideoShortcut` (Domain) → iPhone/Duo: lớp nút ẩn (cách hôm nay, đã chứng minh
    bằng bước `key` của driver); iPad: `CommandMenu` Playback/Edit/View ở `WindowGroup` với `@FocusedValue` của Video
    Studio (rỗng khi Video Studio không mở — danh sách ⌘ của app khác không bị dính), **không** gắn lớp nút ẩn để
    danh sách hệ thống không in hai lần. Trên iPadOS 26 các menu này còn hiện ở thanh menu — đúng HIG. Task 22 bắt đầu
    bằng phép đo M3; nếu `@FocusedValue` không đi qua `fullScreenCover`, dùng `focusedSceneValue`.
11. **Giữ ⌘ 0,6 s** (iPhone/Duo): `onModifierKeysChanged(mask: .command)` (iOS 17) + hẹn giờ 0,6 s. Đo M2 không ra
    sự kiện → mục **Keyboard Shortcuts** trong ⋯ (17b §9 đã chốt lối lùi này).
12. **"Keyboard connected"** và rút bàn phím: `GCKeyboard` (GameController — framework hệ thống, không phải dependency
    bên thứ ba).
13. **Con trỏ trên tay nắm**: `UIPointerInteraction` trên `TimelineScrollView` theo zone tay nắm, kiểu mũi tên trái/phải
    bằng `UIPointerAccessory.arrow` (iOS 15) — không dùng `pointerStyle` của SwiftUI (iOS 18) để khỏi nhánh `#available`.
14. **Pencil**: nhận dạng pan riêng `allowedTouchTypes = [.pencil]`; khi ô Trim bật, pan cuộn chỉ nhận `[.direct]`;
    chạm có `majorRadius` lớn (lòng bàn tay) bị bỏ. Chạm đúp: `pencilInteraction(_:didReceiveTap:)` iOS 17.5+, nhánh
    `pencilInteractionDidTap` cho 17.0–17.4 — cả hai gọi một hàm. Công tắc hover chỉ hiện khi máy đã báo một sự kiện
    hover Pencil (`UIHoverGestureRecognizer`, `zOffset`) — không đoán theo đời máy.
15. **Skim**: lớp ảnh trên `AVPlayerLayer`; `AVAsset` thư viện xin **không mạng**, nil → phóng thumbnail của ô +
    "· Not downloaded". Dung sai giải mã ±½ khung (nhanh hơn zero, sai lệch dưới một khung).
16. **Nhãn số khung** đi qua String Catalog có biến thể số nhiều ("−1 frame" / "−4 frames") — không ghép chuỗi.

## 7. Phụ thuộc vào các plan Video Studio khác

| Plan (spec) | Cần gì từ nó | Chặn task |
|---|---|---|
| **chrome / chọn item / hàng lệnh / tay nắm mép** (FS-12.04 · 04b · 05 §3) | tay nắm mép 12pt + zone 44pt trên lane video, kéo thường đã ghi; phiên chọn ✕/✓ (ảnh chụp lúc bắt đầu); chân ✕ · tên · ✓; hàng lệnh 64×56 với ô Trim; Esc/Return = ✓; Lock lane | 6–17, 22, 31 |
| **Video Settings / Export** (FS-12.10 · 10b) | trường fps của project (24/30/60, mặc định 30); export smoke test (README AC-6) | 5, 7–14, 29 |
| **Kích thước** (FS-12.03 · 03b · 07 · 07b) | bố cục iPhone theo tỉ lệ (panel 340, timeline 464), transport mới và menu ⋯, Duo ngoài: dải 84, vùng 334–644 | 6, 13, 15–17, 32–34 |
| **Media** (FS-12.09) | ô thư viện Recents/Albums/In Video trong panel/pool, click chèn / kéo đặt | 35–37 |
| **F1 chọn nhiều** (FS-12.11) | ⌘A vào chế độ chọn nhiều; giữ 0,5 s trên thân clip | 22 (⌘A); task 6 phải chạy lại test cử chỉ của F1 |
| **F7 trước/sau** (FS-12.15) | lệnh Before and After cho phím \\ | 22 |
| **Look** (FS-12.06c, đã duyệt) | không phụ thuộc trực tiếp; viewer skim "chưa áp look" là đúng theo 17b §6 | — |

**Ngược lại — plan khác cần driver của plan này:** bước **giữ-rồi-kéo** (task 1) là chứng minh duy nhất được cho
F1 FS-12.11 (giữ rồi kéo để dời nhóm clip), Media FS-12.09 (giữ kéo ảnh vào timeline) và kéo tay nắm sau khi giữ ở đây;
bước `pinch` cho mọi AC zoom; `holdKeys`/`key` mở rộng cho mọi AC bàn phím. Vì vậy **task 1–2 nên làm ngay khi duyệt**,
trước cả khung — chúng chỉ đụng `ShotDexUITests/` và tài liệu của driver.

## 8. Thứ tự task

Mỗi task một commit. Cột "Chứng minh" là cái task phải để lại; mỗi task UI còn chạy `design-parity` trên board của nó
(xuất `project/` của canvas về `build/design/video/project/` trước) và chụp: iPhone 17 (26.5) + iPhone 18.6 khi task
đụng view chung, iPad bằng `Tools/sim-shot`, Duo bằng `Tools/ui-drive` + `Tools/sim-shot` (**không** dùng MCP sim tool trên Duo).

### Giai đoạn 0 — công cụ (làm ngay)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 1 | **Driver: giữ-rồi-kéo và pinch.** `drag` thêm `hold` (giây đứng yên trước khi đi, mặc định 0,1 như hôm nay — `UIDriverTests.swift:175-180` đang cứng 0,1) và `velocity` (`slow`/`default`/`fast`); bước mới `pinch` (`label` hoặc `identifier`, `scale`, `velocity`) qua `XCUIElement.pinch(withScale:velocity:)` — API chỉ có trên phần tử, nên timeline nhận `accessibilityIdentifier("VideoTimeline")` ở task 13. Ghi vào doc comment `UIDriver.swift:8-50`, `.claude/skills/ui-drive/SKILL.md`, danh sách bước trong `CLAUDE.md` → chạy `Tools/evals` | hạ tầng (F6, F1, Media) | script `driver-hold-drag-probe.json` trên lưới Library: giữ 0,6 s rồi kéo, `report.json` không lỗi; **đo M4**: `pinch` theo id trong Video Studio iPhone có trả về không (cây phone không liệt kê được — truy vấn theo loại `scrollViews` + id) |
| 2 | **Driver: phím, giữ phím bổ trợ, hover.** `key` thêm tên `home` `end` `delete` `return` `space` `tab` `up` `down` và bổ trợ `ctrl` (hôm nay chỉ `left/right/escape` — `UIDriverTests.swift:154-174`); bước `holdKeys` (`direction` = bổ trợ, `seconds`, `name` tuỳ chọn → chụp + dump nút **trong lúc giữ**) qua `XCUIElement.perform(withKeyModifiers:block:)` (iOS 15); bước `hover` (`x`/`y`, `seconds`) qua `XCUICoordinate.hover()` (iOS 15). Tài liệu + `Tools/evals` như task 1 | hạ tầng (17b) | script `driver-keys-probe.json`: **đo M2** (giữ ⌘ trên iPhone/Duo có ra `onModifierKeysChanged` không — đo bằng một màn hiện có ghi log) và **M1** (hover trên iPad sim có tới `onContinuousHover` không) |

### Giai đoạn 1 — khoá cái đã đúng (✅)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 3 | Rút kẹp zoom khỏi View vào `TimelineZoomMath.clampedPPS(_:ceiling:)`, trần hôm nay 160; hai chỗ gọi `VideoTimelineView.swift:241-244`, `:255-258` | 17 AC-9 | `TimelineZoomMathTests.pinchStopsAt160WhenFrameZoomOff`, `noFrameZoomStateBelowCeiling` |
| 4 | Rút phép tính `trimToPlayhead` vào `VideoTrimToPlayheadMath` (Domain), model gọi nó | 17b AC-4 (lệnh) | `VideoTrimToPlayheadTests.startAtSevenSecondsInClipTwo` (nguồn 4,0, dài 2,2), `speedTwoHalvesTheLocalDelta`, `edgeOrBelowMinimumDoesNothing`; test model đếm undo +1 (dựng model như `ServerComposeToolTests.swift:168`) |

### Giai đoạn 2 — sửa cái lệch (⚠️)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 5 | `VideoFrameGrid` (Domain); ⇧←/→ và Back/Forward a Frame ở cả hai transport bước theo fps project | 17b AC-1 | `VideoFrameGridTests.stepAt24fps` (2,000 → 2,0417 ±1 ms), `stepAt60fps`, `offGridStepsToNextLine`, `formatsHundredths` ("0:09.07", "0:09.20", "0:08.87"); ui-drive `vs-keys-frame-step.json` (`key right` + `shift`, dump nút timecode) |

### Giai đoạn 3 — FS-12.17 trên iPhone

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 6 | **Vào chế độ.** Long-press 0,5 s trên zone tay nắm (quyết định 4); `FrameTrimSession` trong model; bố cục iPhone "trong chế độ" (panel ẩn, timeline 464, đáy ✕ · "Trim · Clip 2" · ✓, 5 công cụ ẩn); pill 248×48 tại (77,728); nhãn viewer "Last frame · 0:09.20" (cao 22); kính Ø124 khi đang giữ với `VideoEdgeFrameSource` (10 khung, dải 13 bước 14, đường cắt 3pt `timelineSelection`, trượt vào trong cách mép 8); lane khoá không vào; cử chỉ bị huỷ giữ chế độ; kéo khi đang giữ = lượng tử khung | AC-1 | `FrameTrimSessionTests.entersAtTrailingEdge` (mép 9,20, nhãn); `VideoStudioLayoutTests.frameTrimPillAt77x728`, `loupeClearsClipBy2pt`; ui-drive `vs-f6-trim-enter.json` (`longPress` 0,6 s theo điểm mép, `dump type=button`) + `Tools/sim-shot` khi giữ (kính chỉ hiện lúc giữ → `drag hold 0.6` + `seconds` dài, burst từ host); design-parity `F6_P_PreciseTrim` |
| 7 | **−1 / +1 Frame.** Nút pill, nhãn "0:09.07 · −4 frames", playhead theo mép, Clip 3 không dời, gạch chéo / viền nới, recipe không đổi | AC-2 | `FrameTrimSessionTests.fourFramesEarlier` (mép 9,0667, Clip 3 còn 9,20, recipe `==` lúc vào); ui-drive bấm 4 lần, dump nhãn |
| 8 | **✓.** Một `pushUndo` + ghi; Back = ✓ rồi rời | AC-3 | `VideoStudioFrameTrimTests.commitAddsOneUndo` (6,0667 ±1 ms, Clip 3 tại 9,0667, Undo → 6,2), `backCommitsFirst` |
| 9 | **✕.** Bỏ phiên | AC-4 | `VideoStudioFrameTrimTests.cancelRestoresAndKeepsUndoDepth` |
| 10 | **Tốc độ.** Mép −1/30 s, cửa sổ nguồn −2/30 s; project 24 fps nguồn 30 rơi theo lưới project | AC-5 | `FrameTrimSessionTests.speedTwoMovesSourceTwice`, `projectGridWinsOverSourceRate` |
| 11 | **Biên.** Ảnh 0,5/10 s, video đầu/cuối nguồn và 0,1 s: nút mờ 35%, không nhận chạm; kéo tới biên → một haptic va chạm | AC-6 | `FrameTrimSessionTests.photoAtMinimumCannotShorten`, `videoAtSourceEndCannotLengthen`; dump nút `enabled=false` |
| 12 | **VoiceOver.** Phần tử tay nắm "Clip 2 end", giá trị "0:09.20", điều chỉnh xuống = −1 khung (một bước undo, ghi ngay) | AC-14 | `VideoStudioFrameTrimTests.adjustableDecrementStepsOneFrame` (giá trị "0:09.17"); dump phần tử (nhãn + value); **đo D6** VoiceOver trên máy (hoặc Accessibility Inspector → Decrement trên sim) |
| 13 | **Frame zoom.** Trần = 12pt × fps khi công tắc bật (mặc định), 160 khi tắt; `VideoInputPreferences` + mục **Precision** trong ⋯ (iPhone, Duo ngoài); pill 270×26 cách đỉnh timeline 276 + "pinch in to return"; thước "giây:khung f" mỗi 6 khung; pinch vào là ra; filmstrip chỉ vẽ ô trong vùng nhìn (⚠️-5); `accessibilityIdentifier("VideoTimeline")` + value = pps | AC-7 (và chạy lại AC-9 với công tắc tắt) | `TimelineZoomMathTests.ceilingIs360At30`, `288At24`, `720At60`, `rulerLabelsEvery72pt`, `pinchStopsAt160WhenFrameZoomOff` (task 3, nay với công tắc); ui-drive `vs-f6-frame-zoom.json` (`pinch` theo id); design-parity `F6_P_FineScrub`; **đo M6 + D2** (bộ nhớ và 60 fps cuộn ở 720 pt/s, project 10 phút) |
| 14 | **Scrub từng khung.** 12pt = 1 khung, thả về khung gần nhất, haptic mỗi khung (công tắc "Frame steps with haptics"), huy hiệu 92×18 "−3 f · 0:08.80", seek dung sai 0 ở Frame zoom | AC-8 | `TimelineZoomMathTests.drag36ptIsThreeFrames` (8,90 → 8,80, 3 vạch vượt, chữ huy hiệu); ui-drive `drag` 36pt chậm + dump; **đo D5** đếm haptic trên máy |

### Giai đoạn 4 — các máy khác

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 15 | **Duo trong.** Ô Trim vào chế độ (mép gần playhead); hàng lệnh đầu −1 · +1 · Frame Zoom · Trim (trắng 14%), Split ẩn; Speed · Volume, khối PRECISION, chú thích; 5 công cụ đáy mờ, không nhận chạm; kính Ø140 cách clip 25 | AC-10 | `FrameTrimSessionTests.trimCellPicksEdgeNearerPlayhead`; `VideoStudioDeskLayoutTests.duoInnerTrimRowOrder`; ui-drive `vs-f6-trim-duo-inner.json` + sim-shot; design-parity `F6_DI_TouchTrim` |
| 16 | **Chân iPad dọc + Duo trong.** "Trim · Clip 2" / "0:09.07 · −4 frames" (Duo trong "−4 f"); bỏ dòng Duration video; iPad dọc: ba cột Speed · Volume │ PENCIL │ TRIM; iPad ngang: xếp dọc trong inspector 280 | AC-17 | `VideoFrameGridTests.compactFrameLabel`; ui-drive dump chân trên iPad dọc + Duo trong; design-parity `F6_IP_PencilTrim`; iPad ngang: sim-shot (không có board) |
| 17 | **Duo ngoài.** Panel ẩn, timeline 334–644, tên ở dòng đầu vùng timeline, pill (67,582), kính Ø124, dải 84: ✕ y 504, ✓ y 556, Export ẩn, không control ở y < 72 hay > 600 | AC-16 | `VideoStudioLayoutTests.duoCoverFrameTrim`; ui-drive `vs-f6-trim-duo-cover.json` + sim-shot (mask); design-parity `F6_DC_PreciseTrim` |

### Giai đoạn 5 — Pencil (máy thật)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 18 | **Pencil trim.** Ô Trim bật: Pencil chạm mép vào ngay; `PencilFrameStepper` (≤ 2pt / 0,3 s → 12pt/khung); ngón tay cuộn; lòng bàn tay bỏ; hover vạch 1pt + nhãn; khối PENCIL 2 công tắc (hover ẩn khi máy chưa từng báo hover) | AC-11 | `PencilFrameStepperTests.stillThenTwentyFourPointsIsTwoFrames`, `driftOverTwoPointsResetsStillness`; **đo D4** trên iPad + Pencil (XCUITest không giả được Pencil), quay màn hình làm bằng chứng |
| 19 | **Chạm đúp Pencil** trim ↔ scrub (nhánh 17.5 / 17.0); chú thích khối TRIM | AC-12 | `PencilFrameStepperTests.scrubModeMovesPlayheadOnly`; **D4** trên máy |

### Giai đoạn 6 — đường hỏng và đối chiếu board

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 20 | **Offline.** Nguồn không phải file cục bộ → kính 10 dải xám + "Offline", viewer giữ khung cuối, ±1 và ✓ vẫn chạy, không request mạng | AC-13 (tiền đề theo ❓-1) | `VideoEdgeFrameSourceTests.streamingAssetIsOfflineWithoutDecoding` (asset URL không phải file → không gọi generator); **đo D7** trên máy (Optimize Storage, Charles/nettop không thấy request) |
| 21 | **design-parity** 5 board F6 trim/scrub, sửa tới khi mọi phần tử ≤ 2pt | AC-15 | báo cáo `design-parity` từng board |

### Giai đoạn 7 — bàn phím (sau F1 và F7, ❓-4)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 22 | **Danh mục 28.** `VideoShortcut` + đăng ký theo quyết định 10 (bắt đầu bằng **đo M3** trên iPad sim có bàn phím: danh sách ⌘ của hệ thống có nhóm theo `CommandMenu` không, `@FocusedValue` qua `fullScreenCover` không); đổi tên theo board (⚠️-2) | 17b AC-10 | `VideoShortcutCatalogTests.twentyEightInThreeGroups` (11/10/7), `namesMatchBoard` (danh sách tên chép từ `F6_IL_Shortcuts`), `noTwoShareAKey`, `compactListHasTwelveRowsInBoardOrder`; ui-drive `holdKeys cmd` 12 s + sim-shot iPad |
| 23 | **J/K/L** + nhãn "2×"/"4×" + tiếng; lùi không được → 15/s (**đo M5** `canPlayReverse` của item preview) | AC-2 | `VideoShuttleTests.lTwiceIsTwoX`, `kStops`, `fourXAndReverseAreMuted`; ui-drive `key l` ×2 + dump nhãn nút Play |
| 24 | **⌥[ / ⌥]** gọi `VideoTrimToPlayheadMath`; lane khoá → không làm gì | AC-4 (phím) | `VideoKeyboardRouterTests.optionBracketTrimsClipUnderPlayhead`; ui-drive `key [` + `option` |
| 25 | **⌫** xoá thứ đang chọn, không chọn → không gì | AC-6 | `VideoKeyboardRouterTests.deleteWithoutSelectionDoesNothing` |
| 26 | **⌘+ / ⌘−** ×2/÷2 quanh playhead, 20 … trần (token, quyết định 5) | AC-7 | `TimelineZoomMathTests.commandPlusTwiceFrom55Is220`, `minusBack`, `ceilingWithFrameZoomOff`; ui-drive đọc value của `VideoTimeline` |
| 27 | **In–Out + Loop.** Trường `inPoint/outPoint` (quyết định 7); I, O, ⌥X; cờ 18×18 + vùng sáng trên thước; Loop trong vùng (quyết định 8) | AC-3 | `VideoInOutRangeTests.outBeforeInResetsIn`, `inAfterOutClearsOut`, `loopTargetIsIn`; `VideoStudioInOutTests.undoKeepsInOut`, `inOutIsSavedWithTheDraft`; test giải mã JSON không có hai khoá |
| 28 | **Home / End** và nút Go to Start/End theo In–Out | AC-16 | `VideoInOutRangeTests.homeGoesToInEndToOut`, `onlyInMeansEndIsProjectEnd`, `clearedHomeIsZero` |
| 29 | **Export bỏ qua In–Out** | AC-17 | `VideoInOutRangeTests.placementsIgnoreInOut` + smoke export của plan Export (README AC-6) chạy với In/Out đặt: 24,0 s |
| 30 | **Cổng phím.** Phím trần im khi ô nhập focus; mọi phím im khi có sheet | AC-5 | `VideoKeyboardRouterTests.bareKeysSilentWhileTyping`, `everythingSilentUnderSheet`; ui-drive trên iPad/Duo trong (cây phone không liệt kê được): `typeText "jim k"` vào ô chữ, dump value + timecode |
| 31 | **Esc / Return / ⇧←→ trong chế độ Trim** (chuỗi Esc ⚠️-3) | AC-11 | `VideoKeyboardRouterTests.escapeOrder` (trim ✕ → đóng danh sách → ✓), `returnCommitsTrim`, `shiftArrowsStepEdgeNotPlayhead`; ui-drive giữ mép, `key left shift` ×4, `key escape`, dump |
| 32 | **Thẻ iPhone.** Tự hiện một lần ở phím cứng đầu tiên (cờ trong `VideoInputPreferences`); vùng panel, đầu 46, dòng "Keyboard connected", 12 dòng 32 cuộn; ✕ "Close"; dòng đọc "Split at Playhead, Command B"; rút bàn phím đóng | AC-8 | `VideoStudioLayoutTests.keyboardCardTakesPanelSlot`; ui-drive `key space` + dump nút; sim-shot; design-parity `F6_P_Keyboard` |
| 33 | **Thẻ Duo trong.** Giữ ⌘ 0,6 s (quyết định 11) → thẻ 640×300 tại (155,150), thả → mất; tự hiện lần đầu: chạm ra ngoài / Esc | AC-9 | `VideoKeyboardRouterTests.holdOpensAfter600ms`; ui-drive `holdKeys cmd` 12 s + sim-shot burst; mở lại app không tự hiện; design-parity `F6_DI_Keyboard` |
| 34 | **Thẻ Duo ngoài.** Dạng iPhone trong vùng 334–644; khung 382×215 không đổi | AC-18 | ui-drive + sim-shot; design-parity `F6_DC_Keyboard` |

### Giai đoạn 8 — skim (sau Media)

| # | Task | AC | Chứng minh |
|---|---|---|---|
| 35 | **Skim.** `onContinuousHover` trên ô video → `VideoSkimMath` → `VideoSkimFrameSource`; lớp ảnh viewer; header "Skimming · Lake · 0:02.3 / 0:05"; vạch 1pt + nhãn 76×20; dòng "Click adds · drag to place"; ô ảnh: chỉ ảnh + tên; đang phát → không; mũi tên hai chiều trên tay nắm (quyết định 13) | AC-12 | `VideoSkimMathTests.fortySixPercentOfFiveSeconds` (2,3 s, chữ header), `throttlesToThirtyPerSecond`, `newestReplaces`; ui-drive `hover` (nếu M1 đạt) + sim-shot iPad; nếu M1 không đạt: Simulator "Capture Pointer" bằng tay + sim-shot |
| 36 | **Rời ô** → header + viewer về playhead ngay khung kế | AC-13 | `VideoSkimMathTests.leavingRestoresPlayheadTitle`; như task 35 |
| 37 | **iCloud** không mạng: `requestAVAsset(allowsNetwork: false)`, nil → thumbnail + "· Not downloaded" | AC-14 | `VideoSkimFrameSourceTests.nilAssetFallsBackToThumbnail`; **D7** trên máy |
| 38 | **design-parity** `F6_P_Keyboard`, `F6_DI_Keyboard`, `F6_DC_Keyboard`, `F6_IL_HoverScrub`; so tên/nhóm với `F6_IL_Shortcuts` | AC-15 | báo cáo `design-parity` |

## 9. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **JSON project**: Codable tổng hợp **không** dùng giá trị mặc định khi thiếu khoá — trường không-Optional mới làm `Creation.videoRecipe` (`Creation.swift:102-105`, `try?` cả recipe) trả nil, project cũ không mở lại được | cao nếu làm sai | `inPoint`/`outPoint` là `Double?` (tổng hợp dùng `decodeIfPresent`); test giải mã JSON không có hai khoá (task 27). Không migration (app chưa release). Phiên trim, công tắc, cờ thẻ phím **không** vào project |
| **Bộ nhớ**: kính 10 khung × 2 mép, khung viewer ở mép, skim | trung bình | giải mã ở ≤ 2× kính, ≤ 30 khung/mép, xả khi `didReceiveMemoryWarning`; khung viewer/skim cạnh dài ≤ 1280, giữ 1 khung; `memory-leak` soát actor và nhận dạng |
| **Timeline 360–720 pt/s**: nội dung 432 000pt, filmstrip không lazy (⚠️-5) | cao | windowing filmstrip trong task 13; đo M6/D2; `perf-profiler` |
| **Độ trễ ±1 Frame** HEVC 4K > 100 ms (spec §13) | trung bình | mỗi bước chỉ giải mã 1 khung mới, khung cũ trong cache; viewer chiếu khung từ cache trước; đo D1 trên iPhone 17 + iPad trước khi đóng task 7 |
| **Concurrency**: hai actor giải mã, `AVAssetImageGenerator` async, mới-thay-cũ, boundary observer của Loop | trung bình | huỷ Task cũ + `cancelAllCGImageGeneration`; callback về `@MainActor` bằng `Task { @MainActor in }` (không `assumeIsolated` trong closure không chắc ở main — bài học `mainactor-assumeisolated-sync-callback`); gỡ boundary observer trong `detachObservers`; `swift-concurrency` |
| **Cử chỉ chồng nhau**: giữ 0,5 s tay nắm · giữ 0,32 s đổi thứ tự (hôm nay) · giữ 0,5 s thân clip (F1) · kéo tay nắm ngay | cao | zone tay nắm hit-test trước thân; long-press tay nắm có `allowableMovement` 4 và cổng với zone pan (quyết định 4); task 6 chạy lại script cử chỉ của F1 bằng bước giữ-rồi-kéo |
| **Duo 669pt / ngoài 466×678** | trung bình | Duo trong không dùng pill (lệnh nằm ở hàng lệnh), kính Ø140 cách clip 25; Duo ngoài theo 07b; `duo-ux-review` |
| **Preview 30 fps** khi giải mã kính/skim song song | thấp–trung bình | trong chế độ trim player đang dừng; skim chỉ khi không phát; generator riêng, không chạm `AVPlayerItem` |
| **Danh sách ⌘ của iPad** không nhóm được từ view, hoặc in hai lần | trung bình | quyết định 10 + đo M3 ở đầu task 22 |
| **Giữ ⌘ trên iPhone** không ra sự kiện | trung bình | lối lùi mục ⋯ (spec 17b §9) |
| **Phát lùi với compositor riêng** | trung bình | đo M5; lối lùi tìm khung 15/s |
| **Pencil / VoiceOver / haptic không tự động hoá được** | chắc chắn | test Domain thuần cho mọi phép tính; phần cảm giác đo trên máy (D4–D6), ghi rõ trong `/verify` là chứng minh tay |

## 10. Đo đạc cần có

| Mã | Đo gì | Ở đâu | Task |
|---|---|---|---|
| M1 | `XCUICoordinate.hover()` có tới `onContinuousHover` trên iPad sim không | sim iPad | 2 |
| M2 | `perform(withKeyModifiers: .command)` có ra `onModifierKeysChanged` trên iPhone/Duo sim không | sim | 2 |
| M3 | danh sách ⌘ của iPadOS: nhóm theo `CommandMenu`, `@FocusedValue` qua `fullScreenCover`, không in đôi | sim iPad + bàn phím | 22 |
| M4 | `pinch` theo id trên Video Studio iPhone có trả về (cây phone không liệt kê) | sim iPhone | 1 |
| M5 | `canPlayReverse` của item preview có compositor riêng | sim | 23 |
| M6 | bộ nhớ + dựng nội dung 432 000pt (720 pt/s, 10 phút) | sim (Instruments) | 13 |
| D1 | độ trễ ±1 Frame HEVC 4K ≤ 100 ms | iPhone 17 + iPad thật | 7 |
| D2 | 60 fps cuộn ở 360 pt/s, project 10 phút (NF-01) | máy thật | 13 |
| D3 | nhiệt khi skim 30/s HEVC 4K; hạ 15/s khi `thermalState` cao | iPad thật | 35 |
| D4 | Pencil: đứng yên 0,3 s/2pt, lòng bàn tay, hover (máy có hover), chạm đúp (17.5 và trước) | iPad + Pencil | 18, 19 |
| D5 | số haptic khớp số khung | iPhone thật | 14 |
| D6 | VoiceOver đọc và điều chỉnh tay nắm | máy thật (sim: Accessibility Inspector) | 12 |
| D7 | PhotoKit trả gì cho video chỉ-iCloud khi có / không mạng; không request khi vẽ kính và khi skim | máy thật, Optimize Storage bật | 20, 37 |

## 11. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| _chưa chạy — chạy `challenger` trên plan này khi duyệt_ | |

## 12. Cách chứng minh là xong

- **Test (Swift Testing, Domain/Data thuần + model không player):** `VideoFrameGridTests`, `FrameTrimSessionTests`,
  `TimelineZoomMathTests`, `PencilFrameStepperTests`, `VideoShortcutCatalogTests`, `VideoKeyboardRouterTests`,
  `VideoShuttleTests`, `VideoInOutRangeTests`, `VideoSkimMathTests`, `VideoTrimToPlayheadTests`,
  `VideoEdgeFrameSourceTests`, `VideoSkimFrameSourceTests`, `VideoStudioFrameTrimTests`, `VideoStudioInOutTests`; thêm
  ca vào `VideoStudioLayoutTests` / `VideoStudioDeskLayoutTests`. Chạy theo task (`/test <Class>`); cả bộ một lần khi
  xong intent.
- **Script `Tools/ui-drive`:** `driver-hold-drag-probe`, `driver-keys-probe`, `vs-keys-frame-step`, `vs-f6-trim-enter`,
  `vs-f6-frame-zoom`, `vs-f6-trim-duo-inner`, `vs-f6-trim-duo-cover`, cùng các script phím của task 22–34. Trên phone
  chỉ dump theo loại (`type=button`); Duo/iPad chụp bằng `Tools/sim-shot`.
- **Màn hình phải chụp:** chế độ Trim (giữ có kính / nhấc tay), Frame zoom, thẻ phím — trên iPhone 17 (iOS 26.5) và
  iPhone iOS 18.6 (cùng tập action, `ios26-parity`), iPad dọc + ngang, Duo trong, Duo ngoài. Mọi board F6 qua
  `design-parity` ≤ 2pt.
- **Tài liệu phải cập nhật:** cột "Chứng minh bằng" của 35 AC trong FS-12.17/17b (tên test thật); câu "(đã thế)" ở
  17 §13 (⚠️-5); tiền đề AC-13 (❓-1); 17 §7 + board `F6_IP_PencilTrim` (❓-2); ngoại lệ Duo trong ở 04b §57 (❓-3);
  danh sách bước của driver trong `CLAUDE.md` + skill `ui-drive` (task 1–2, kèm `Tools/evals`); NF-03 nếu thêm khoá
  UserDefaults mới vào bảng required-reason.
- **Agent giai đoạn Deploy:** `swift-concurrency` (actor giải mã, observer, throttle) · `memory-leak` (cache khung,
  nhận dạng, observer GameController) · `perf-profiler` (720 pt/s, filmstrip, skim) · `device-layout` + `duo-ux-review`
  + `iphone-ux-review` + `ipad-ux-review` (pill, kính, thẻ, cử chỉ chồng) · `ipad-multitasking` (danh sách ⌘, con trỏ,
  Pencil) · `a11y-voiceover` (tay nắm điều chỉnh được, thẻ phím) · `ios26-parity` (18.6, nhánh Pencil 17.5) ·
  `design-parity` · `hig-components` (menu phím, tên lệnh) · `copy-consistency` + `localization` (28 tên, số nhiều
  "frames") · `photokit-guard` (`requestAVAsset` không mạng, iCloud) · `privacy-manifest` (UserDefaults) · `challenger`.
