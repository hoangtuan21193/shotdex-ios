# Kế hoạch — Video Studio: iPad ngang/dọc, Duo trong, Duo ngoài (FS-12.03 · 03b · 07b)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-12.03`](../02-functional-spec/FS-12-video-studio/03-timeline-and-desk-layout.md) (11 AC) · [`FS-12.03b`](../02-functional-spec/FS-12-video-studio/03b-desk-bands-and-lanes.md) (9 AC) · [`FS-12.07b`](../02-functional-spec/FS-12-video-studio/07b-duo-cover-layout.md) (12 AC) — **32 AC** |
| Intent | [2026-10-03-video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — thứ tự theo mảng, mọi thiết bị cùng lúc: thanh dưới → chọn item → Media → Video Settings/Export → Look → kích thước → F1–F8 |
| Design | canvas Video Studio [docs/design](../design/README.md) (Version 26). Board của plan này: `IL1`–`IL5`, `IP1`–`IP3`, `DI1`–`DI6`, `DC1`–`DC4`, `DC2_Collapsed`. Đã export `IL1`, `IL2`, `IP1`, `DI1`, `DI2`, `DC1` + `canvas.json` vào `build/design/video/project/`; export đủ bộ trước task 18 |
| Plan anh em | **`vs-tools-selection-phone`** (FS-12.04 · 04b · 07: 5 công cụ, mô hình chọn ✕ · tên · ✓, iPhone) · plan Media (FS-12.09) · plan Video Settings + Export (FS-12.10 · 10b) · [Look ảnh cho video](2026-10-02-video-photo-looks.md) (FS-12.06c, **đã duyệt**, chờ khung) · plan F1–F8 |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **2** (task 4–15) và bước **5** (task 16–18) của thứ tự xây. 18 task = 18 commit |

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 2 (task 4–15) và 5 (task 16–18)** của thứ tự xây.
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
- **Quyết định của plan này:** mọi ⚠️ "tài liệu đúng, sửa code" duyệt; tên item "Clip 2" (code đúng — FS-12.03 AC-2,
  FS-12.03b §1, FS-12.04 §5 đã sửa). Ba câu ❓:
  1. **Không có tên project** — bỏ tên ở giữa băng trên iPad (FS-12.03 §2–§3 đã sửa); recipe không thêm trường nào.
     Task 6 và 8 bỏ phần "tên"; dòng phụ "5 clips · 16:9 · 0:24" giữ.
  2. **Lock/Mute trên Duo trong:** cột badge rộng ra **100** (lề 6 · badge 26 · khe 4 · Lock 28 · khe 4 · Mute 28 ·
     lề 4; lane chữ chỉ Lock) — FS-12.03 §4, FS-12.03b §4 và AC-8 đã sửa; không menu giữ. Task 5 làm theo số này.
  3. Gập/mở Duo giữ cây view hay không: vẫn đo tay ở task 15 như plan ghi. Thêm: đổi scene là lúc **ghi nháp ngay**
     (FS-12.18 AC-4, khối N của tools plan).
- **Lớp cửa sổ:** task 6 của tools plan (bước 1) tạo `VideoStudioWindowClass` theo đặc tả task 4 ở đây; task 4 ở đây
  chỉ còn nối màn hình đọc kích thước cửa sổ + inset phải và ghi `REVIEW_QUEUE` ngưỡng 60/84. Task 1–3 (test khoá)
  chạy được bất cứ lúc nào; test Esc của task 2 viết theo luật Esc = ✓ của tools plan.
- **Phạm vi bước:** task 4–15 là bước 2; task 16–18 là bước 5 (cùng khối E của tools plan).
- **Board canvas phải sửa** (canvas Video Studio [docs/design](../design/README.md), trước task
  `design-parity` đầu tiên của board đó):
  - **Bỏ tên project** "Iceland Road Trip" ở giữa băng trên mọi board iPad: `IL1`–`IL5`, `IP1`–`IP3`, `IP_Export`,
    `F4_IL`/`F4_IP_Captions`, `F7_IL`/`F7_IP_BeforeAfter`, `F8_IL`/`F8_IP_ExportPresets` (và mọi board `IL*`/`IP*`/`F*_IL`/`F*_IP`
    khác có băng trên); giữ "5 clips · 16:9 · 0:24".
  - **Cột badge Duo trong 64 → 100 với Lock · Mute**: `DI1`–`DI6` và mọi board Duo trong có timeline — `F1_DI_Reorder`,
    `F2_DI_CutToBeat`, `F3_DI_Ducking`, `F4_DI_Captions`, `F5_DI_Looks`, `F5_DI_ClipLook`, `F6_DI_TouchTrim`,
    `F6_DI_Keyboard`, `F7_DI_BeforeAfter`, `F8_DI_ExportPresets`, `MP_DI_Media`, `ES_DI_ExportSettings`; lane hẹp đi 36pt.
  - "Clip 2 · Coast" → "Clip 2" ở `IL1`, `IL2`, `IP1`, `DI2` (cùng danh sách với tools plan).

## 1. Hiểu đúng chưa

Bốn cửa sổ không phải iPhone mỗi cái một hình, chọn theo **cửa sổ** chứ không theo tên máy: iPad ngang là bàn dựng
ba cột (pool 236 · khung · inspector 280) với transport, dải tổng quan và timeline **chạy hết bề ngang** bên dưới;
iPad dọc dồn điều khiển xuống **dock 324** dưới timeline; Duo trong (cửa sổ rộng nhưng **thấp < 720**) đặt **cột 264**
cạnh khung 684×385, transport 40, timeline 188, hàng đáy 56 — cộng đúng 669; Duo ngoài (compact, inset phải ≥ 84)
dời 5 công cụ, Video Settings/Export (hoặc ✕/✓ khi chọn) vào **dải 84 bên phải**, trả 382pt cho khung 382×215,
transport 40 và timeline 344. Khi không chọn gì, cột/dock hiện Look cả video; chọn item thì cột/dock thành lệnh +
thông số với chân ✕ · tên · ✓. Đổi cỡ cửa sổ (xoay, Stage Manager, gập/mở) giữ nguyên phiên chọn.

Code hôm nay là một ngăn xếp co giãn chung (`stackLayout`, `VideoStudioMetrics.swift:351-447`) với các vị từ rời
(`usesDeskChrome` 600, `usesToolRail` 700, `usesInspectorColumn`, `Lanes.for` 750): inspector 320 chỉ hiện khi đang
chọn, pool 300/236, rail 92 (đã chết), Duo trong được bàn dựng iPad thu nhỏ (header, meter, track header 104), Duo
ngoài không có bố cục riêng (chỉ có luật "timeline đứng xuống", `:411-429`). Plan này thay các vị từ bằng **một lớp
cửa sổ** và **một hàm hình học thuần cho mỗi lớp**, rồi dựng bốn khung theo board.

Không có migration (app chưa release — CLAUDE.md); plan **không thêm trường nào vào `VideoProjectRecipe`** (trừ khi ❓1
chốt thêm tên project). Lock, Mute-nhớ-mức, Loop, cột mở/đóng là trạng thái phiên.

## 2. Đối chiếu AC ↔ code

### FS-12.03 — bố cục cửa sổ rộng

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 iPad ngang không chọn: pool 236, inspector 280 ở x 1096 "Look · Whole video", khung 810×456 ở (236,122), timeline y 678 cao 354 | ⚠️ | pool 300 khi ≥ 900 (`VideoStudioMetrics.swift:163`, `:180-182`); inspector 320 (`:33`) và **chỉ vẽ khi `presentsSheet`** (`VideoStudioScreen.swift:325-326`); pool/inspector cao hết màn, transport + timeline nằm **trong** cột giữa (`VideoStudioScreen.swift:386-543`); timeline cao theo lane (`stackLayout`) | **tài liệu đúng, sửa code** — board và §1 chốt "khi không chọn, cột hiện Look"; cột luôn có nghĩa là khung không nhảy khi chọn. Task 6 |
| AC-2 chọn clip 2: chân inspector y 546 ✕ · "Clip 2 · Coast" · ✓; khung ±0; Export vẫn hiện | ❌ | không có chân ✕ · tên · ✓ (`VideoStudioSheetHost.swift:89-128` chỉ có dòng tiêu đề + thùng rác); cột mở ra khi chọn nên khung **co** | task 12, dùng chân + tên của `vs-tools-selection-phone`. Tên: **code đúng** — "Clip 2" theo Q4 của plan Look (không có tên địa điểm nào để ra "· Coast", `VideoViewerChrome.swift:78-94`); chữ "· Coast" trong AC là chữ mẫu của board |
| AC-3 iPad dọc không chọn: dock y 1052 cao 324, tiêu đề có Media · Text · Sticker · Music; pool đóng | ❌ | iPad dọc (1032 ≥ 600) có bàn dựng nên **không có** hàng công cụ nào (hàng + thanh đáy chỉ vẽ khi `!usesDeskChrome`, `VideoStudioScreen.swift:526-529`) — chỉ menu Project Tools ở băng trên (`VideoStudioCommandBand.swift:105-131`); dock chỉ tồn tại khi đang chọn và khung dư ≥ 264 + inset (`VideoStudioMetrics.swift:437-441`) | task 8 |
| AC-4 iPad dọc chọn clip 2: hàng lệnh trong dock; chân y 1316; timeline 722–1052 không bị phủ | ⚠️ | dock có (`dockedPanel`, `VideoStudioScreen.swift:522-525`) nhưng cao 264 + inset, đặt **trên** chỗ lẽ ra là hàng công cụ, không chân | **tài liệu đúng, sửa code** — dock cố định 324 luôn có mặt. Task 12 |
| AC-5 Duo mở 951×669 không chọn: khung 684×385 y 0; cột 264 x 687; transport y 385; timeline 188; hàng đáy y 613 có 5 công cụ từ x 40 và Export | ❌ | Duo trong nhận bàn dựng: băng trên + header + meter 50 + transport 44 + overview (`VideoStudioScreen.swift:423-495`), không hàng đáy, không cột khi idle | task 9; viết lại `duo-video-studio-desk.json` |
| AC-6 Duo chọn clip 2: ✕ · Clip 2 · ✓ ở x 620–907; Export ẩn; 5 công cụ trắng 30% | ❌ | không có | task 13 |
| AC-7 Stage Manager 1000×800, clip 2 chọn → kéo cao 700: bố cục Duo trong; clip 2 vẫn chọn; ✕ trả đúng lúc chọn | ❌ | không có lớp "cửa sổ thấp" (chỉ `Lanes.minimumHeightForRegularLanes` 750, `VideoStudioMetrics.swift:552`); giữ chọn thì **tự nhiên đúng** vì phiên chọn nằm trong model (`VideoStudioModel.swift:99-101`), không gắn bố cục | task 4 (lớp cửa sổ) + task 15 (chứng minh); bản chụp ✕ thuộc `vs-tools-selection-phone` |
| AC-8 iPad ngang, Inspector tắt, chọn clip 2 → cột mở, chân có ✕ · ✓ | ⚠️ | cột tắt thì panel **trượt lên từ đáy** đè timeline (`VideoStudioScreen.swift:547-556`); không có đường tự mở `isInspectorOpen` (`:71`, `:448`) | **tài liệu đúng, sửa code** — ✕/✓ ở chân cột; panel trượt trên iPad là đường thứ hai cho cùng việc. Task 11 |
| AC-9 iPad mở ngang → xoay dọc: bố cục dọc, không khoá hướng, item giữ nguyên | ✅ (phần cốt lõi) | iPad bốn hướng (`ShotDex.xcodeproj/project.pbxproj:894`), iPhone chỉ dọc (`:895`); bố cục tính lại từ `GeometryReader` mỗi lần (`VideoStudioScreen.swift:280`), chọn nằm trong model | khoá bằng route xoay (task 3) ngay bây giờ; chạy lại khi bố cục dọc mới vào (task 18) |
| AC-10 IL1–IL4, IP1–IP3, DI1–DI4 `design-board compare` ≤ 2pt | ❌ | chưa có bố cục nào khớp | task 18, agent `design-parity` |
| AC-11 Duo trong DI1/DI2, `sim-shot` có mask: Back và ✓ không bị góc bo cắt | ❌ | chưa có bố cục | task 9 + 13, đo ở task 18 — **rủi ro**: Back ở (16,12) nằm trong vùng góc bo ~66pt (§7) |

### FS-12.03b — băng bàn dựng và lane

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 meter đọc 0 · 0,5 · 1 · 0,5 theo fade | ✅ đã chứng minh | `VideoStudioDeskLayoutTests.theMeterReadsTheSameFadeEnvelopeTheExportWrites` (`VideoStudioDeskLayoutTests.swift:190-200`) | không việc |
| AC-2 thang meter tuyến tính dB | ✅ đã chứng minh | `VideoStudioDeskLayoutTests.theMeterScaleIsLinearInDecibels` (`:175-184`) | không việc |
| AC-3 iPad ngang: 15 nút theo 4 nhóm trong một hàng 44, không nút ngoài mép | ⚠️ | đủ 15 nút đúng nhóm (`VideoViewerChrome.swift:141-251`), nhưng với pool 300 + inspector 320 sân khấu còn 756 < 780 nên rơi về hàng hẹp (`VideoStudioScreen.swift:473-477`, test `aStageSqueezedByBothColumnsGetsTheNarrowTransportRow`). Lệch thêm: **Delete Clip xoá item đang chọn** (`:163-170`), spec: clip dưới playhead; **Play nền accent** (`:180-187`), spec: trắng 12%; timecode `hh:mm:ss:ff` (`:237`), spec `0:08.4 / 0:24.0`; nút 44×30 (`:273`), spec 40 (iPad) / 36 (Duo) | **tài liệu đúng, sửa code** cả bốn: transport chạy hết bề ngang nên luôn ≥ 780 trên 13"; nhóm "sửa tại playhead" tác động clip dưới playhead (§7 rủi ro của spec đã chốt); accent chỉ cho Export (ràng buộc của intent); một dạng timecode với điện thoại và board. Task 6 (vị trí) + task 16 (nội dung) |
| AC-4 V1 Volume 60 → Mute → bấm lại → 60 | ✅ | `toggleVideoTrackMuted` nhớ `videoVolumeBeforeMute` (`VideoStudioModel.swift:347-358`) | test khoá, task 1 |
| AC-5 2 track trong A1 → Mute A1 → Undo một lần → cả hai về mức cũ | ✅ | `toggleMusicLaneMuted` bọc `beginUndoGroup`/`endUndoGroup` (`VideoStudioModel.swift:373-388`, `:612-620`) | test khoá, task 1 |
| AC-6 clip 2 chọn, Speed 2×, Esc rồi ⌘Z → bỏ chọn, vẫn 2×; rồi 1× | ✅ | Esc = `clearSelection()` (`VideoStudioScreen.swift:690-692`, `VideoStudioModel.swift:394-399`) không đụng recipe; ⌘Z = `undo()` | test khoá ở tầng model, task 2. Khi `vs-tools-selection-phone` đưa ✓/✕ vào, **plan đó** trỏ Esc sang ✓ và sửa test này cùng commit |
| AC-7 pool tab Music: "Video sound" ở đầu, "Add Music from Files…" | ⚠️ | tab Music của pool có danh sách riêng, nút "Import from Files…" (`VideoMediaPoolColumn.swift:398`), không có dòng Video sound | **tài liệu đúng, sửa code** — một hành động một tên (§7 của spec); tab Music nhúng **đúng** nội dung panel Music của `vs-tools-selection-phone`. Task 7 |
| AC-8 Duo trong: cột badge 64 không Lock/Mute; lane 34/66/40 | ⚠️ | lane đúng 34/66/40 (`Lanes.compact`, `VideoStudioMetrics.swift:507`, `Lanes.for` → compact ở 669, test `aShortRegularWindowKeepsThePhonesLanes`), nhưng Duo trong được `withTrackHeaders(true)` → header 104 có Lock/Mute (`VideoStudioScreen.swift:340-342`, `VideoTimelineGutter.swift:20-36`); thước 26 (spec 33) | **tài liệu đúng, sửa code** — 40pt bề ngang trả về cho lane trên màn 951. Kéo theo ❓2 (Lock/Mute đi đâu trên Duo trong). Task 5 |
| AC-9 IL1, IP1, DI1 transport, overview, track header ≤ 2pt | ❌ | chưa đo; header viewer lệch (nút 44×26 bo 5, có timecode tổng — `VideoViewerChrome.swift:48-50`, `:102-112`; spec 36×28 bo 7, không timecode), meter theo **cửa sổ** ≥ 820 (`VideoStudioMetrics.swift:219-222`; spec theo **sân khấu**, Duo trong không meter), header track/gutter như trên | task 17 + 18 |

### FS-12.07b — Duo màn ngoài

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 466×678 không chọn: khung 382×215 y 45; transport y 260; timeline 300–644; 5 ô 64×56 x 392 y 80–360; Video Settings y 504; Export y 556 | ❌ | màn ngoài chạy bố cục điện thoại trong 382×644 (`stackLayout`), không đọc inset phải; rail 92 cũ là cho iPad và đã chết (`VideoStudioToolbar.swift:155-200`, không ai gọi) | task 10. Tái dùng `EditorWindowInsetsReader` (`EditorToolBar.swift:233-270`) |
| AC-2 chạm ô Music (424,276) → panel Music 300–644; ô nền trắng 14% | ❌ | không có | task 10 (panel do `vs-tools-selection-phone`) |
| AC-3 không phần tử nhận chạm ở x 382–466 × y 0–72 và y > 600 | ❌ | không có dải | task 10, test hình học + dump |
| AC-4 chọn clip 2: ✕ y 504, ✓ y 556, tên y 440; Video Settings/Export biến mất; 5 ô trắng 30% | ❌ | không có | task 14 |
| AC-5 clip 2 chọn, chạm ô Media → không mở gì | ❌ | không có | task 14 |
| AC-6 clip 2 chọn: overview y 306; panel từ y 334; khung vẫn 382×215 y 45 | ❌ | panel trượt + "timeline đứng xuống" (`VideoStudioMetrics.swift:411-429`) | task 14 |
| AC-7 project 9:16 → khung 121×215 giữa x 0–382 | ❌ | toán fit đã đúng và tái dùng được (`VideoGeometry.stillFitRect`, `VideoStudioScreen.swift:802-805`; `AVPlayerLayer.resizeAspect`, `:1193`), chỉ thiếu vùng 382×215 | task 10 |
| AC-8 clip 2 chọn, Speed 2× → mở máy: màn trong có ✕ · Clip 2 · ✓; ✕ trả 1× | ❌ / ❓ | chưa có hai bố cục; **chưa biết** gập/mở có giữ cây view (và `@State model`, `VideoStudioScreen.swift:40`) hay dựng lại scene — xem ❓3 | task 15; đo bằng tay trong Simulator.app |
| AC-9 DC1, DC2 `sim-shot … cover`: Back và ✓ không bị góc bo cắt | ❌ | chưa có bố cục | task 10 + 14, đo task 18 |
| AC-10 DC1–DC4, DC2_Collapsed ≤ 2pt | ❌ | — | task 18 |
| AC-11 hàng trên y 6–42 đúng 3 đĩa Back · Undo · Redo | ⚠️ | băng compact hôm nay: Undo · Redo · Show original · timecode, Back ở thanh đáy (`VideoStudioCommandBand.swift:57-81`, `VideoStudioScreen.swift:526-529`) | **tài liệu đúng, sửa code** — so sánh nằm ở header Look (FS-12.15), Settings/Export ở dải 84. Task 10 |
| AC-12 clip 2 chọn, vuốt grabber xuống → panel 78 ở 566–644; tay nắm mép clip 2 ở timeline 300–566; ✕/✓ còn; khung không đổi | ❌ | không có trạng thái thu | task 14; cử chỉ + cờ thu của `vs-tools-selection-phone`, plan này cấp số 566–644 |

**Tổng: 6 ✅ (2 đã có test, 4 cần test khoá), 7 ⚠️ (03 AC-1, AC-4, AC-8 · 03b AC-3, AC-7, AC-8 · 07b AC-11),
19 ❌; 1 AC kèm ❓ (07b AC-8). Mọi ⚠️ đề nghị "tài liệu đúng, sửa code"; riêng tên "Clip 2 · Coast" (03 AC-2) đề nghị
"code đúng" theo Q4 của plan Look.**

## 3. Ai giữ hằng số nào (phối hợp với `vs-tools-selection-phone`)

Hai plan cùng sửa `VideoStudioMetrics.swift` và `VideoStudioScreen.swift`. Luật: **mỗi hằng số một chủ**; plan kia chỉ đọc.
Số của plan này chuyển sang Domain (`VideoStudioDeskGeometry`, mới) — `VideoStudioMetrics` còn lại là token của điện thoại
và token dùng chung.

| Hằng số / kiểu | Chủ | Ghi chú cho plan kia |
|---|---|---|
| `VideoStudioWindowClass` + `resolve(window:trailingInset:)` (mới, Domain) | **wide-duo**, task 4 — **land trước mọi task bố cục của cả hai plan** | phone plan rẽ nhánh bằng `.phone`, không tự viết vị từ |
| `VideoStudioMetrics.Lanes` (kiểu + 3 bậc `.phone` 40/80/46 · thumb 60 · thước 33 · gutter 30; `.duo` 34/66/40 · 54 · 33 · gutter 30 glyph (ngoài) / 100 badge + Lock · Mute (trong); `.desk` 44/104/52 · 88 · 39 · 104 header) + `Lanes.for(_ windowClass:)` | **wide-duo**, task 5 (đặt sớm vì là kiểu dùng chung) | phone plan đọc `.phone`; số của `.phone` lấy từ FS-12.07 §4, phone plan sửa số nếu FS-12.07 đổi |
| pool 236, inspector 280, cột Duo 264, dock 324, dải 84, băng trên iPad 64, header 32, transport 44/40 (nút 40/36), overview 22 (+8), timeline iPad ngang sàn 354, Duo trong 385/40/188/56, Duo ngoài 45/215/40/344, ô công cụ Duo trong 72×50 và Duo ngoài 64×56, meter 50/32, `transportBarFullWidth` 780, Quick Adjust 44, mặc định pt/giây theo lớp (70 · 60 · 55 · 55), `timelineExtraRange` 0…400 | **wide-duo** (`VideoStudioDeskGeometry`) | — |
| `mediaPoolWideWidth`, `mediaPoolNarrowWidth`, `mediaPoolWidth(size:)`, `inspectorColumnWidth`, `railWidth`, `railCellHeight`, `VideoStudioToolRail`, `usesToolRail`, `usesInspectorColumn`, `minimumStageWidth`, `usesResizableTimeline`, `usesDeskChrome`, `deskChromeMinimumWidth`, `deskChromeHeight`, `canShowMediaPool`, `audioMeterWidth(size:)` | **wide-duo xoá** trong task bỏ caller cuối (6–10) | phone plan không gọi mới |
| số ô/lưới **bên trong** pool (`mediaPoolColumnCount`, `mediaPoolCellWidth`) | plan Media (FS-12.09) | wide-duo chỉ cấp bề rộng 236 |
| `sheetHeight` 264, `sheetLift`, `toolbarHeight` 62, `bottomBarHeight` 50, `previewMinimumHeight`, `timelineMinimumHeight`, `compactTransportHeight` 40 + `VideoCompactTransportBar`, ô lệnh 64×56 (`commandCellWidth/Height`), ô công cụ điện thoại 72×52, `topBandHeight` nhánh điện thoại | **phone plan** | Duo ngoài **dùng nguyên** `VideoCompactTransportBar` và ô lệnh 64×56 |
| `stackLayout` / `StackLayout` / `shortWindowHeight` 660 | cả hai thôi gọi; **plan nào bỏ caller cuối thì xoá** (grep `stackLayout(` = 0) cùng các test trong `VideoStudioLayoutTests` | — |
| dạng timecode transport `0:08.4 / 0:24.0` (hàm mới) | **phone plan** tạo | wide-duo đổi hàng desk sang dùng nó ở task 16 |
| tên item ("Clip 2"), chân ✕ · tên · ✓ (view), phiên chọn (bản chụp ✕, ✓, Esc), cờ thu panel 78 + cử chỉ, danh sách 5 công cụ, đường mở Video Settings, nội dung panel Music, bỏ `masterVolume` (kể cả chip "Master" của Quick Adjust, `VideoViewerToolStrip.swift:93`) | **phone plan** | wide-duo chỉ **đặt chỗ** cho chúng |
| `EditorLayoutMetrics.duoCoverRailMinimum` 60 (editor ảnh) | editor ảnh, không đụng | Video dùng 84 của spec; lệch hai ngưỡng → `REVIEW_QUEUE.md` (task 4) |

## 4. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `EditorWindowInsetsReader` (`EditorToolBar.swift:233-270`) | đọc inset phải 84 của màn ngoài (Video Studio tràn safe area trên/dưới nên `GeometryReader` không thấy) |
| `VideoGeometry.stillFitRect` | khung trong 382×215, 684×385, 810×456, 982×552 |
| `VideoTransportBar` (15 nút, đúng nhóm) | hàng transport iPad + Duo trong, thêm tham số cỡ nút 40/36 |
| `VideoCompactTransportBar` (của phone plan) | transport Duo ngoài |
| `VideoTimelineOverview`, `VideoAudioMeterColumn`, `VideoTrackHeader`, `VideoViewerHeader`, `VideoViewerToolStrip` | giữ, chỉ sửa số |
| `VideoStudioSheetHost(layout: .column)` | nội dung cột 280/264 và dock |
| `Tools/ui-drive`, `Tools/sim-shot`, `Tools/design-board` | bằng chứng; route cũ `ipad-video-studio*.json`, `duo-video-studio*.json` viết lại |
| `AppDependencies.preview()` + ảnh server tạm (`ServerComposeToolTests.swift:165-178`) | dựng `VideoStudioModel` trong unit test không cần PhotoKit (task 1, 2, 15) |

## 5. Chỗ nào trong code

| File | Đụng gì | Tầng | Mới / sửa |
|---|---|---|---|
| `ShotDex/Domain/Video/VideoStudioWindowClass.swift` | 5 lớp, `resolve`, `isShortWindow(height:)` (< 720, NF-05 §4) | Domain | mới |
| `ShotDex/Domain/Video/VideoStudioDeskGeometry.swift` | số §3 + một hàm thuần mỗi lớp ra `Frames` (rect từng băng: band, pool, header, stage, frame, meter, inspector, chân, transport, overview, timeline, dock, hàng đáy, ô rail, đĩa rail, panel chọn/công cụ/thu) | Domain | mới |
| `ShotDex/Features/VideoStudio/VideoDeskColumns.swift` | trạng thái phiên thuần: pool/inspector mở, Quick Adjust, divider; luật "chọn → cột tự mở" | Features (struct thuần) | mới |
| `VideoStudioMetrics.swift` | `Lanes` 3 bậc; xoá các vị từ ở §3 | Features | sửa |
| `VideoStudioScreen.swift` | `content` tách theo lớp: `deskLandscape`, `deskPortrait`, `duoInner`, `duoCover`, (phone giữ cho phone plan) | Features | sửa |
| `VideoStudioDuoCoverRail.swift` | dải 84 | Features | mới |
| `VideoStudioDuoBottomRow.swift` | hàng đáy 56 của Duo trong | Features | mới |
| `VideoStudioDock.swift` | dock 324 iPad dọc | Features | mới |
| `VideoStudioCommandBand.swift` | băng trên iPad (64) và hàng 3 đĩa Duo ngoài; đĩa nổi trên khung Duo trong | Features | sửa |
| `VideoViewerChrome.swift` | header 36×28 bo 7, bỏ timecode tổng; transport cỡ nút, Play trắng 12%, Delete theo playhead | Features | sửa |
| `VideoMediaPoolColumn.swift` | header "Library", 4 tab, tab Text, tab Music nhúng panel Music | Features | sửa |
| `VideoTimelineGutter.swift` | cột badge 64 không nút | Features | sửa |
| `VideoAudioMeterColumn.swift` | bề rộng theo sân khấu | Features | sửa |
| `VideoStudioToolbar.swift` | xoá `VideoStudioToolRail` | Features | sửa |
| `VideoStudioModel.swift` | `trimToPlayhead`-giống cho Delete: `deleteClipUnderPlayhead()` | Features (model) | sửa |
| `ShotDexTests/VideoStudioWindowClassTests.swift`, `VideoStudioDeskGeometryTests.swift` | AC số học | Test | mới |
| `ShotDexTests/VideoStudioDeskLayoutTests.swift`, `VideoStudioLayoutTests.swift` | sửa test vị từ cũ, thêm test khoá | Test | sửa |
| `ShotDexUITests/scripts/ipad-vs-*.json`, `duo-vs-inner-*.json`, `duo-vs-cover-*.json` | route dump | Test | mới (thay `ipad-video-studio*.json`, `duo-video-studio*.json`) |
| `DESIGN.md` §10.1b | ngoại lệ có tên: dải 84 của Video Studio trên Duo ngoài (status bar ẩn) | Docs | sửa ở task 10 |

Logic bố cục nằm ở Domain (`VideoStudioWindowClass`, `VideoStudioDeskGeometry`) và struct thuần (`VideoDeskColumns`);
view chỉ đặt `frame`/`position` theo `Frames`.

## 6. Thứ tự task

Một task = một commit `feat(FS-12.03…): AC-n …`, `/build` sau mỗi commit, `/screens` + `design-parity` khi đụng UI.
✅ (test khoá) trước; sau đó theo **mảng của intent**, trong mỗi mảng ⚠️ trước ❌ trừ khi phụ thuộc buộc khác.
Mảng 3–5 (Media, Video Settings, Look) **không có task riêng** ở plan này: khung đã chừa chỗ (pool 236, cột 280/264,
dock, nút Settings) và các plan đó đổ nội dung vào.

| # | Mảng | Task | AC | Test kèm theo | Phụ thuộc |
|---|---|---|---|---|---|
| 1 | ✅ | Test khoá mute lane | 03b AC-4, AC-5 | `VideoStudioDeskLayoutTests.mutingTheVideoLaneRestoresItsLevel` (0,6 → 0 → 0,6), `mutingAMusicLaneUndoesInOneStep` (2 track A1, 1 Undo) | — |
| 2 | ✅ | Test khoá Esc giữ thay đổi, ⌘Z lùi | 03b AC-6 | `VideoStudioDeskLayoutTests.escapeKeepsTheChangeAndUndoRevertsIt` (gọi đúng hành động của nút "Deselect") | phone plan đổi Esc → ✓ thì sửa test này cùng commit |
| 3 | ✅ | Route xoay iPad giữ chọn (bố cục hiện tại) | 03 AC-9 | `ipad-vs-rotate.json`: mở dọc, chọn clip 2, `orientation` landscape, chờ 12 s + `sim-shot` (memory: không mở đầu bằng orientation, khung driver bị letterbox), dump: clip 2 còn `selected` | — |
| 4 | 1 · chrome | `VideoStudioWindowClass` + `isShortWindow`; screen đọc kích thước **cửa sổ** (proxy + inset) và inset phải; `REVIEW_QUEUE` ngưỡng 60 vs 84 | 03 §1 · AC-7 (phần lớp) · 07b §1 | `VideoStudioWindowClassTests`: 402×874→phone · 466×678/84→duoCover · 466×678/0→phone · 951×669→duoInner · 1376×1032→iPadLandscape · 1032×1376→iPadPortrait · 639×1376→iPadPortrait · 507×1032→phone · 1000×800→iPadLandscape · 1000×700→duoInner; `isShortWindow` 669/678/719,5 → có, 720/812/874/1032 → không | — (land trước task bố cục của phone plan) |
| 5 | 1 · chrome | `Lanes` 3 bậc + `Lanes.for(windowClass)`; Duo trong cột badge **100** (T1 · V1 · A1 + Lock · Mute 28, vùng chạm 32 × cao lane; T1 chỉ Lock) | 03b AC-8 (sửa lúc duyệt) | sửa `aShortRegularWindowKeepsThePhonesLanes` → `eachWindowClassGetsItsLaneTier`; `duoInnerGutterIsA100ptBadgeColumnWithLockAndMute`; `trackHeadersLeaveTheLaneHeightsAlone` giữ | 4 |
| 6 | 1 · chrome | **iPad ngang**: băng 64 (Back · Undo · Redo · Show original đĩa 40 cách 10 từ x 20; dòng phụ "5 clips · 16:9 · 0:24" (không tên project); readout · nút Settings 32 bo 8 · Export 40), hàng [pool 236 \| header + sân khấu + meter \| inspector 280 luôn có, idle = Look] y 64–604, transport hết bề ngang 604–648, overview x 104–1360, timeline 678–1032 (sàn 354), 70pt/giây; xoá rail chết + vị từ cũ | 03 AC-1 ⚠️, 03b AC-3 (vị trí) | `VideoStudioDeskGeometryTests.iPadLandscapeIdle` (pool 236, inspector x 1096, khung 810×456 @ (236,122), transport 604, timeline 678/354), `theTransportAlwaysGetsTheFullRowOnA13InchIPad`; route `ipad-vs-landscape.json` dump | 4, 5; Look tạm của phone plan cho cột idle |
| 7 | 1 · chrome | Pool: header "Library" (Search Library · Hide Media), 4 tab **Media · Text · Stickers · Music** (bỏ Effects — báo plan Look là task 6 của nó đã xong phần này), tab Text (Add Text 44 bo 12, FONTS YOU USED hàng 50, dòng trống), tab Music = panel Music dùng chung | 03b AC-7 ⚠️ | `VideoStudioDeskLayoutTests.thePoolHasFourTabsInOrder`; route `ipad-vs-pool-music.json`: dump "Video sound" đầu, "Add Music from Files…", không "Import from Files…" | 6; panel Music + công cụ Look của phone plan |
| 8 | 1 · chrome | **iPad dọc**: băng như ngang (dòng phụ ở x 356, nút Settings 2 dòng cao 40 bo 10), header hết ngang, khung + meter 96–648, transport 648–692, overview 696–718, timeline 722–1052 (phần dư), **dock 324** (tiêu đề 46 "Look · Whole video" + 4 nút Media · Text · Sticker · Music cao 32 bo 8, 3 cột 344), pool đóng mặc định, 60pt/giây | 03 AC-3 | `iPadPortraitIdle` (dock 1052/324, timeline 722/330, khung 982×552); `aNarrowPortraitDockSplitsItsWidthInThree` (639 → 3 cột bằng nhau); route `ipad-vs-portrait.json` | 6 |
| 9 | 1 · chrome | **Duo trong**: khung 684×385 y 0 + cột 264 x 687 (idle Look, Media mở trong cột), 4 đĩa nổi 36 nền đen 55% ở (16,12) cách 8, transport 15 nút 36 y 385–425, timeline 425–613 (badge 64, bậc duo, 55pt/giây), hàng đáy 613–669 (5 ô 72×50 từ x 40 cách 4; phải tới x 907: nút Settings 2 dòng 40 · Export 40); không pool/header/meter | 03 AC-5 | `duoInnerBandsSumToTheWindow` (385+40+188+56 = 669, khung 684×385, cột 687/264); `duoInnerHasNoPoolMeterOrHeader`; route `duo-vs-inner.json` (viết lại `duo-video-studio-desk.json`) + `sim-shot inner` | 4, 5; 5 công cụ của phone plan |
| 10 | 1 · chrome | **Duo ngoài**: nội dung x 0–382 (hàng 3 đĩa 34 trắng 10% cách 6 từ x 10 · khung 382×215 y 45 · transport compact y 260 · timeline 300–644, cột glyph 30 không nhận chạm, bậc duo); dải 84 (nắp 0–72 sọc chéo, 5 ô 64×56 ở x 392 y 80–360 nhãn 9,5, ô đang mở nền trắng 14%, đĩa 44 Video Settings @504, Export @556); panel công cụ 300–644 phủ timeline, grabber 36×5; dải tràn `.ignoresSafeArea(edges: .trailing)` **chỉ lớp dải**; DESIGN.md §10.1b thêm ngoại lệ | 07b AC-1, AC-2, AC-3, AC-7, AC-11 ⚠️ | `duoCoverIdle` (khung, transport, timeline, 5 ô, 2 đĩa), `nothingTappableInTheCapOrBelow600`, `aPortraitProjectFitsCentred` (9:16 → 121×215 @ x 130,5); route `duo-vs-cover.json` (`ui-drive`, **không** MCP sim tool) + `sim-shot cover` | 4, 5; compact transport, 5 công cụ, panel công cụ của phone plan |
| 11 | 2 · chọn | `VideoDeskColumns`: chọn item khi cột tắt → cột mở; bỏ chọn không đóng; xoá đường panel trượt trên iPad | 03 AC-8 ⚠️ | `VideoDeskColumnsTests.selectingOpensAClosedInspector`, `deselectingLeavesItOpen`; route `ipad-vs-inspector-closed.json` | 6; phiên chọn của phone plan |
| 12 | 2 · chọn | iPad chọn: chân 58 ở y 546 (ngang) / chân 60 ở y 1316, hàng lệnh dock + 6, 3 cột thông số 344×190 ở dock + 72 (dọc); Export + Settings vẫn hiện; khung ±0 | 03 AC-2, AC-4 ⚠️ | `iPadLandscapeSelectedKeepsTheFrame` (rect khung idle == chọn), `iPadPortraitSelectedFooterAt1316`; route `ipad-vs-select.json` hai hướng | 6, 8; chân + tên + hàng lệnh của phone plan |
| 13 | 2 · chọn | Duo trong chọn: 5 ô trắng 30% không nhận chạm; nhóm phải → ✕ 40 · tên 14 + dòng phụ 11 · ✓ 40 ở x 620–907; Export ẩn; hàng lệnh là hàng đầu cột, cách góc bo 40 | 03 AC-6 | `duoInnerSelectedFooterSpans620To907`; route `duo-vs-inner-select.json` + `sim-shot inner` | 9; như 12 |
| 14 | 2 · chọn | Duo ngoài chọn: 5 ô 30%; tên 76×56 @ (386,440); ✕ @504, ✓ @556 (trắng, glyph đen); Settings/Export ẩn; overview 306–328 (x 12, rộng 358); panel 334–644 bo 16; chạm Media không mở gì; thu → 78 ở 566–644, timeline 300–566 | 07b AC-4, AC-5, AC-6, AC-12 | `duoCoverSelected`, `duoCoverCollapsedPanelIs78At566`; route `duo-vs-cover-select.json` (swipe theo **điểm** cho grabber) + `sim-shot cover` | 10; cờ thu + cử chỉ của phone plan |
| 15 | 2 · chọn | Đổi lớp cửa sổ giữ phiên: không reset `@State` nào khi lớp đổi; panel công cụ đang mở giữ qua gập/mở; cột dùng chung một `VideoStudioSheetHost` | 03 AC-7, 07b AC-8 | `VideoStudioWindowClassTests.shrinkingAStageManagerWindowChangesClassOnly` + `VideoDeskColumnsTests.classChangeKeepsColumns`; model: chọn clip 2, Speed 2×, đổi lớp (không dựng lại model), ✕ → 1× (sau khi phone plan có ✕); **đo tay**: gập/mở Duo trong Simulator.app, kéo cửa sổ Stage Manager | 9, 10, 13, 14 |
| 16 | 6 · kích thước | Hàng transport: nút 40 (iPad) / 36 (Duo trong), Play nền trắng 12%, nhóm sửa tác động **clip dưới playhead** (`deleteClipUnderPlayhead`), timecode `0:08.4 / 0:24.0` | 03b AC-3 ⚠️ | `VideoStudioDeskLayoutTests.deleteInTheTransportRemovesTheClipUnderThePlayhead` (chọn clip 1, playhead ở clip 2 → clip 2 mất), `theTransportRowHasFifteenControlsInFourGroups`; route dump 15 nút trong hàng 44, không frame `inf` | 6, 9; hàm timecode của phone plan |
| 17 | 6 · kích thước | Băng bàn dựng: header 32 (nút 36×28 bo 7, tên dưới playhead, bỏ timecode tổng, Media Pool chỉ iPad), meter 50/32 theo **sân khấu** < 820, Duo trong không meter, overview 22, track header thẻ 92 (badge + tên + Lock + Mute), thước 39/33, grabber chia 36×4 + trợ năng bước 40, Quick Adjust 44 mặc định tắt | 03b AC-9 | `theMeterNarrowsBelowAn820Stage`, `theDividerStepsBy40WithinItsRange`; `design-board compare` IL1/IP1/DI1 phần transport, overview, track header | 6, 8, 9 |
| 18 | 6 · kích thước | Vòng `design-parity` đủ board + góc bo: export đủ `project/` vào `build/design/video/project/`; IL1–IL4, IP1–IP3, DI1–DI4, DC1–DC4, DC2_Collapsed; `sim-shot` mask DI1/DI2/DC1/DC2; chạy lại route xoay task 3 trên bố cục mới | 03 AC-10, AC-11; 07b AC-9, AC-10; 03 AC-9 (chạy lại) | `Tools/design-board compare` từng board ≤ 2pt; ảnh mask | mọi task trên + nội dung của các plan Media/Settings/Look để board khớp cả khối |

## 7. Quyết định kỹ thuật (tự chốt)

- **Đo cửa sổ, không size class**: kích thước cửa sổ = `proxy.size` + bốn inset (Video Studio tràn trên/dưới); compact =
  rộng < 600 (giữ ngưỡng `deskChromeMinimumWidth` cũ: Split View 1/2 báo `.regular` ở ~500). Inset phải đọc bằng
  `EditorWindowInsetsReader`; trước báo cáo đầu tiên **chưa dựng** bố cục compact (tránh một khung điện thoại chớp lên
  màn ngoài rồi nhảy sang dải 84).
- **Mỗi lớp đúng một vùng co giãn**: iPad ngang → sân khấu (timeline = max(354, nhu cầu lane) + phần kéo divider);
  iPad dọc → timeline (khung theo bề ngang, dock 324 cố định); Duo trong → khung (40 + 188 + 56 cố định); Duo ngoài →
  timeline (644 − 300). Vì thế mỗi hình học là một hàm thuần có test số cụ thể, thay cho `stackLayout` đa năng.
- **Divider** (0…400) lấy chiều cao từ sân khấu (ngang) hoặc từ khung (dọc); không có trên Duo.
- **Pool chỉ trên iPad** (cả hai hướng); mở dọc thì pool đứng cạnh hàng khung y 64–648. Mặc định mở khi rộng ≥ 1100,
  chỉ mở được khi khung còn ≥ 330.
- **Dock ở bề ngang khác 1032** (Split View dọc 639): 3 cột chia đều; dưới 3 × 200 thì 2 cột + cuộn ngang.
- **Một hàng transport desk** có tham số cỡ nút (40/36), không viết hàng thứ ba cho Duo trong.
- **Dải 84 là lớp riêng** tràn `.trailing`; nội dung vẫn tôn trọng safe area (DESIGN §10.1b) — ngoại lệ có tên.
- Hằng số của plan này ở Domain (`VideoStudioDeskGeometry`), như `EditorLayoutMetrics` của editor.

## 8. Câu hỏi còn treo (❓)

1. **Tên project ở giữa băng trên iPad** ("Iceland Road Trip" trên IL1/IP1): không có trường nào giữ tên —
   `VideoProjectRecipe` (`VideoProjectModels.swift:460-512`) và `Creation` (`Creation.swift:24-33`) đều không.
   Đề nghị rẻ nhất: thêm `name: String?` vào recipe (không migration, decode khoan dung), mặc định = ngày clip đầu
   ("Oct 3, 2026"), chưa có chỗ sửa trong v1. Cần người dùng chốt vì là chuyện sản phẩm.
2. **Lock/Mute trên Duo trong**: cột badge 64 không nút (03b AC-8) và hàng transport đủ 15 nút không có ⋯ → Lock/Mute
   **không tới được** trên Duo trong, trái luật "đủ mọi chức năng". Đề nghị: menu ngữ cảnh (giữ) trên badge với Lock ·
   Mute — board không đổi. Cần chốt.
3. **Gập/mở Duo có giữ cây view không** (07b §5, AC-8): `simctl` không có lệnh gập (memory `iphone-duo-ios27`); phải gập
   bằng tay trong Simulator.app một lần để biết scene giữ hay dựng lại. Nếu dựng lại, phiên chọn phải lưu ra ngoài view
   (vd. `SceneStorage`/model giữ ở scene) — thêm việc vào task 15.

## 9. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Duo 669 không còn khe hở**: 385 + 40 + 188 + 56 = 669, một băng dày thêm 1pt là tràn | cao | test `duoInnerBandsSumToTheWindow` khoá tổng; cột 264 là `ScrollView` (Apply To của Look phải cuộn tới — plan Look đã ghi) |
| Góc bo Duo ~66pt: Back ở (16,12) và ✓ ở x 907 sát góc | trung bình | `sim-shot` mask ở task 9/13 trước task 18; nếu board tự vẽ vào vùng cắt thì báo người dùng sửa board, không tự dời |
| Status bar hiện lại (alert hệ thống) làm dải 84 hết nhận chạm | trung bình | giữ `.statusBarHidden()` (`VideoStudioScreen.swift:101`); route mở một alert rồi chạm lại dải; rủi ro ghi trong spec |
| **Hai plan một checkout, cùng file** (`VideoStudioScreen`, `VideoStudioMetrics`) | cao | §3 chia chủ; task 4–5 land trước phone plan đụng bố cục; commit `git commit -- <paths>`, không `add -A` (memory) |
| Hiệu năng 30 fps: timeline iPad 1272pt (≈ 18 s ở 70pt/giây, ô 88pt) nhiều ô hơn; timecode cập nhật 30 lần/giây kéo cả body | trung bình | `Frames` tính một lần mỗi lần layout (thuần, rẻ); readout tách view con đọc `currentTime`; meter chỉ refresh ở lớp có meter (Duo trong bỏ); `perf-profiler` |
| Bộ nhớ: thumbnail theo cao ô × scale (88pt × 3 = 264px, sàn 240) cho timeline rộng + lưới pool | thấp | cache có sẵn; `memory-leak` |
| Concurrency: `EditorWindowInsetsReader` báo qua `DispatchQueue.main.async` | thấp | chỉ ghi `@State`; `swift-concurrency` |
| Project JSON: plan không thêm trường (trừ ❓1) | thấp | decode khoan dung giữ nguyên (`LossyArray`) |
| Stage Manager (03 AC-7) không lái được bằng `ui-drive` | cao | chứng minh bằng test thuần + một lần kéo tay trên sim iPad |
| Màn ngoài và editor ảnh đặt công cụ khác nhau (trong dải 84 / cột 56 cạnh dải) | chấp nhận | spec đã chốt; `component-consistency` ghi nhận, không sửa ở đây |

## 10. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 11. Cách chứng minh là xong

- **Test** (`/test`): `VideoStudioWindowClassTests`, `VideoStudioDeskGeometryTests` (AC số học của 03 AC-1/3/5,
  07b AC-1/3/6/7/12), `VideoDeskColumnsTests` (03 AC-8, AC-7), `VideoStudioDeskLayoutTests` (03b AC-1…6, 8),
  `VideoStudioLayoutTests` (xoá phần `stackLayout` khi hết caller). Full suite một lần cuối intent (`Tools/gate`).
- **Route** (`Tools/ui-drive`, một lượt một lúc, foreground): `ipad-vs-rotate`, `ipad-vs-landscape`, `ipad-vs-portrait`,
  `ipad-vs-pool-music`, `ipad-vs-inspector-closed`, `ipad-vs-select`, `duo-vs-inner`, `duo-vs-inner-select`,
  `duo-vs-cover`, `duo-vs-cover-select`. Duo **chỉ** bằng `ui-drive`; ảnh bằng `Tools/sim-shot <udid> … inner|cover`.
- **Màn hình** (`/screens video-studio-wide`), iOS 26.5 + 18.6 (tier D không rẽ nhánh, vẫn chụp cả hai cho
  `ios26-parity`): iPad 13" ngang 1376×1032 và dọc 1032×1376 (idle, chọn clip, inspector tắt + chọn, pool Music),
  Duo trong 951×669 (DI1–DI4), Duo ngoài 466×678 (DC1–DC4, DC2_Collapsed), Split View dọc 639.
- **design-parity**: board §6 task 18 ≤ 2pt.
- **Đo**: sim — mọi thứ trên; **bằng tay** — gập/mở Duo (❓3, 07b AC-8), kéo Stage Manager (03 AC-7); **máy thật** —
  iPad: cuộn timeline 1272pt + meter ở 30 fps. Không có Duo thật: chạm dải 84 chỉ đo được trên sim.
- **Tài liệu** cùng commit task: cột "Chứng minh bằng" của 03/03b/07b từng AC; DESIGN.md §10.1b (task 10);
  `REVIEW_QUEUE.md`: ngưỡng Duo ngoài 60 (editor) vs 84 (video) (task 4); Mute lane Video không có bước undo trong khi
  Mute lane nhạc có (`VideoStudioModel.swift:351-358` vs `:373-388`) (task 1). Chữ "· Coast" trong 03 AC-2 và FS-12.04
  (dòng "Tên ở giữa") — người dùng sửa spec theo Q4 của plan Look.

## 12. Phụ thuộc giữa các plan

| Plan | Plan này cần gì | Plan đó cần gì từ plan này |
|---|---|---|
| `vs-tools-selection-phone` | 5 công cụ (một nguồn), panel công cụ (Music/Look tạm/Text/Sticker), phiên chọn + ✕/✓ + Esc, view chân ✕ · tên · ✓, tên item, ô lệnh 64×56, cờ thu + cử chỉ, compact transport + hàm timecode, bỏ `masterVolume` (cả chip Quick Adjust), đường mở Video Settings | `VideoStudioWindowClass` (task 4), `Lanes` 3 bậc (task 5) — **phải land trước** task bố cục điện thoại |
| Media (FS-12.09) | nội dung tab Media trong pool 236, trong cột 264 (Duo trong), trong panel công cụ (Duo ngoài) | bề rộng 236/264/382 và chỗ đặt |
| Video Settings + Export (FS-12.10 · 10b) | chữ của nút Settings ("16:9 · 1080p · 30 fps", hai dòng ở dọc/Duo), readout "0:24 · ~30 MB" | chỗ nút trên băng iPad, hàng đáy Duo trong, đĩa @504 Duo ngoài; luật "Export ẩn khi đang chọn" trên Duo |
| Look (FS-12.06c, đã duyệt) | panel Look cả video cho cột idle và dock | cột 280/264 + dock 324 (task 15 của plan Look đo trên đó); **tab Effects đã bỏ ở task 7** — task 6 của plan Look bỏ phần đó |
| F1 · F4 · F6/F7 · F8 | — | F4 thêm lane C1 vào `Lanes` (bậc theo lớp); F6/17b dùng luật Esc = ✓ (03b §5); F7 dùng nút Show original ở băng iPad/Duo trong (Duo ngoài không có) |

## 13. Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `design-parity` | 16 board, lặp tới khi qua (03 AC-10, 07b AC-10, 03b AC-9) |
| `device-layout` | bốn lớp cửa sổ trên ba máy, góc bo |
| `duo-ux-review` | 669pt, dải 84, ✕/✓ dưới ngón cái, gập/mở giữ phiên |
| `ipad-ux-review` · `ipad-multitasking` | dock dọc, cột tự mở, Split View 639, Stage Manager xuống < 720 (AC-7), phím Esc |
| `ios26-parity` | tập action trên 26.5 vs 18.6 |
| `a11y-voiceover` | nhãn ô dải 84, đĩa ✕/✓, cột badge, divider bước 40 |
| `swift-concurrency` | đọc inset bất đồng bộ, refresh meter |
| `perf-profiler` | timeline rộng, timecode 30 Hz |
| `component-consistency` | công cụ màn ngoài (dải 84) vs editor ảnh (cột 56); hàng transport một bản hai cỡ |
