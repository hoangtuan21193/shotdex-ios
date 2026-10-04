# FS-12.10 — Video Settings

`FS-12.10` · tier D · `Features/VideoStudio/VideoExportSheet.swift` · `Domain/Video/VideoProjectModels.swift`
· `Data/Sources/VideoExportWriter.swift` · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** tỉ lệ, cách đặt khung, nền, độ phân giải, fps và codec chỉnh ở một chỗ, áp ngay lên khung hình, kèm
dung lượng ước tính — còn Export chỉ là nút xuất ([10b](10b-export.md)).

Nguồn intent: [2026-10-03-video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md).
Board: `P6_RatioBackground`, `ES_P_ExportSettings` ở [`docs/design/iphone/project/`](../../design/iphone/project/) ·
`ES_IL_ExportSettings` ở [`docs/design/ipad/project/`](../../design/ipad/project/) (kiểu Mac 2026-10-04) · `DI5_RatioBackground`,
`ES_DI_*`, `ES_DC_*` ở [`docs/design/duo/project/`](../../design/duo/project/).
Preset theo nơi đăng (F8) là [FS-12.16](16-export-presets.md): preset dùng **cùng** bảng kích thước, cổng 4K và công
thức ước tính ở đây, và **không ghi đè** các trường này — preset chỉ là đích của một lần xuất (chốt 2026-10-03).

## 1. Người dùng cần gì

"Phải có chỗ chỉnh ratio, độ phân giải video trước khi export." Người dựng clip cho Reels cần 9:16, cho YouTube cần
16:9 hoặc 4K, và cần biết file nặng bao nhiêu trước khi chờ xuất. Hôm nay Ratio lẫn trong thanh công cụ, Quality
nằm trong sheet xuất, fps và codec không chỉnh được.

## 2. Phạm vi

**Có:** Ratio 16:9 · 9:16 · 1:1 · 4:5 · 4:3 · 21:9 · Fit on Background (Blur / Colour / Image) / Fill (Crop) ·
720p / 1080p / 4K · 24 / 30 / 60 fps · H.264 / HEVC · Output + MB ước tính · hai nút ở chrome.

**Cố ý không có:** bitrate tay, HDR, chỉnh khung từng clip khi Fill — *vì đó là việc của NLE desktop*; 4K khi nguồn
nhỏ hơn 4K — *vì phóng to không thêm chi tiết mà file nặng gấp 4*.

## 3. Mở ở đâu

| | iPhone 402×874 | iPad ngang 1376×1032 | iPad dọc 1032×1376 | Duo trong 951×669 | Duo ngoài 466×678 |
|---|---|---|---|---|---|
| Nút Video Settings | tròn 36 ở (312, 11.5), nền trắng 10% → 20% khi mở | capsule kính 226×44 ở x 894 (nút 222×40): icon tỉ lệ · "16:9 · 1080p · 30 fps" · ⌃⌄; "0:24 · ~30 MB" là dòng phụ dưới tiêu đề toolbar | như ngang, một dòng, capsule ở x 550 | hai dòng 154×40 góc phải hàng đáy, x 666; ⌃ khi mở | tròn 44 trong dải 84 ở y 504 |
| Nút Export | tròn cam 36 ở (356, 11.5), chỉ icon | viên nang cam "Export" **124×44** bo `r-export` 19 ở x 1236 | viên nang cam 124×44 ở x 892 | viên nang cam "Export" 78×40 ở x 829 | tròn cam 44 ở y 556, chỉ icon |
| Video Settings mở ra | panel cao theo tỉ lệ (16:9 340 · 1:1 320 · 4:5 300 · 9:16 278 · 4:3 360 · 21:9 340) | popover **400×548** bo 16 (`sheet`) dưới nút, ở (807, 80) | popover 400 dưới nút | cột phải 264, cao 385, cuộn | panel từ y 334 tới đáy |

- **Tên là "Video Settings" ở mọi nơi** — nút, tiêu đề panel/popover/cột, VoiceOver (chốt 2026-10-03). *Vì tỉ lệ và
  nền đổi chính project, không chỉ file xuất.*
- Accent cam chỉ ở nút Export (ràng buộc của intent). Nút Video Settings mang **tỉ lệ đang dùng** làm icon.
- Duo ngoài: đang chọn một item thì ✕/✓ chiếm y 504/556 và cả hai nút này ẩn (board `DC3`).

## 4. Nội dung Video Settings

Đầu: tiêu đề + dòng phụ "1080×1920 · 0:24 · ~30 MB" (Duo: bỏ thời lượng), nút **Done** ✓ tròn 30 bên phải. Không có
✕ — *vì mọi thay đổi đã áp ngay và đã nằm trong undo.* Rồi theo thứ tự, lề 16 (Duo ngoài 14):

| Mục | Điều khiển (iPhone; cột hẹp chia cùng tỉ lệ) |
|---|---|
| dòng LUT mất (chỉ khi có) | icon ⓘ + chữ của [06c §6](06c-photo-looks.md): "1 look is missing its LUT and exports without it." |
| RATIO | 6 nút 118×30, 3 cột khe 8, mỗi nút có hình khung đúng tỉ lệ |
| Fit / Fill | "Fit on Background" · "Fill (Crop)" 181×28 |
| BACKGROUND (chỉ khi Fit) | Blur · Colour · Image 118×28; dưới đó: Blur → slider "Blur" 0–100; Colour → 4 chấm tròn 28 khe 12 (đen · xám #808080 · trắng · màu tự chọn); Image → thumbnail 28 + "Choose…" |
| RESOLUTION | 720p · 1080p · 4K 118×30; 4K không dùng được thì mờ 35% có ổ khoá + dòng lý do |
| FRAME RATE | 24 · 30 · 60 118×28 |
| CODEC | H.264 · HEVC 181×28 + "HEVC is about 40% smaller; some older devices can’t play it." |
| Output | "1080×1920 · 0:24 · ~30 MB" chữ đơn cách, rồi "Changes apply right away — Export uses them." |

Khung hình hiện nhãn "9:16 · Fill" (74×20, góc trái trên) khi Video Settings đang mở.

**iPad (kiểu Mac, 2026-10-04, board `ES_IL_ExportSettings`):** popover là **form hai cột** — nhãn bên trái (x +16:
Ratio · Framing · Background · Blur · Resolution · Frame Rate · Codec), điều khiển bên phải từ x +120, rộng 264:
**Ratio là nút pop-up** "▯ 9:16 ⌃⌄" 150×44 (mở menu 6 tỉ lệ; board chưa vẽ menu) thay 6 nút; Framing, Background,
Resolution, Frame Rate, Codec là segmented 264×36 (nút 32); Blur là slider 44. Đầu: "Video Settings" 20 semibold +
dòng phụ mono, nút chữ **Done** 72×44 bên phải. Dòng LUT mất, chú thích 4K và HEVC, Output giữ thứ tự bảng trên.

## 5. Luật

- **Áp ngay**: khung hình, panel và Output đổi trong cùng khung hình kế tiếp. Mỗi lần chạm là **một bước undo**, một
  lần kéo slider Blur là một bước (luật [08 §1](08-model-and-v1-limits.md)).
- **Đổi tỉ lệ trên iPhone** đổi cả khung lẫn chiều cao panel theo bảng §3, chuyển động 0,25s. Đây là lần duy nhất panel đổi cao.
- **Kích thước khung** = cạnh ngắn theo lớp (720 / 1080 / 2160), cạnh dài theo tỉ lệ, **trần 3840**, làm tròn số chẵn:

| | 16:9 | 9:16 | 1:1 | 4:5 | 4:3 | 21:9 |
|---|---|---|---|---|---|---|
| 720p | 1280×720 | 720×1280 | 720×720 | 720×900 | 960×720 | 1680×720 |
| 1080p | 1920×1080 | 1080×1920 | 1080×1080 | 1080×1350 | 1440×1080 | 2520×1080 |
| 4K | 3840×2160 | 2160×3840 | 2160×2160 | 2160×2700 | 2880×2160 | 3840×1646 |

- **Cổng 4K:** chỉ mở khi **mọi** clip có nguồn cạnh ngắn ≥ 2160 (ảnh tính theo pixel ảnh, freeze theo video nguồn).
  Lý do: "4K needs 4K clips — 3 of your 5 clips are 1080p." Các clip thiếu khác lớp nhau thì "… are smaller than 4K."
- Đang 4K mà thêm một clip dưới 4K → tự về 1080p, hiện dòng lý do; **chung bước undo** với lần thêm clip.
- **Ước tính** = (bitrate video + 128 kbps) × thời lượng ÷ 8, làm tròn MB, tiền tố "~"; ≥ 1000 MB ghi "~1.2 GB".
  Bitrate H.264 = rộng × cao × fps × 0,16 bit (≈ 10 Mbps ở 1080p30, mức hôm nay); HEVC × 0,6. Đổi bất kỳ trường
  nào hay thời lượng → số mới ngay. **Giữ ~10 Mbps ở 1080p30** (chốt 2026-10-03, §9); mọi số MB ở FS-12 theo mức này.
- **Mặc định project mới:** tỉ lệ gần nhất với clip đầu (so theo log tỉ lệ; ngang bằng → 16:9) · Fit · Colour đen
  · 1080p · 30 · H.264. *Vì clip dọc trong khung 16:9 là hai phần ba màu đen; H.264 mở được ở mọi nơi.*
- **Fill** phủ kín khung, cắt giữa, ẩn BACKGROUND. **Fit** đặt cả khung nguồn vào, phần thừa là nền.
- **Blur** = chính khung đó phủ kín rồi làm mờ; **Image** = một ảnh thư viện phủ kín, không mờ, chọn qua Media ở chế
  độ chọn một ảnh ([09](09-media-panel.md)). Ảnh nền mất quyền hoặc bị xoá → nền đen + "Image unavailable — choose another."
- Chạm một công cụ ở hàng đáy khi Video Settings đang mở → Settings đóng (đã áp), công cụ mở.

## 6. Dữ liệu

| | |
|---|---|
| Ghi vào | công thức project: tỉ lệ · Fit/Fill · loại nền + màu + độ mờ + id ảnh nền · độ phân giải · fps · codec |
| Thay | trường preset 1080p/4K và màu nền cũ; app chưa phát hành → không migration, đọc khoan dung (giá trị lạ → mặc định §5) |
| `photo_metadata` | không đụng (BD-02) |

Đường dựng đổi theo các trường này: [01 §7b–§9](01-render-and-export-pipeline.md).

## 7. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | đổi tỉ lệ / nền chỉ dựng lại bản dựng khung hình; độ phân giải, fps, codec không đụng preview |
| Bộ nhớ | xuất 4K không vượt trần app; nền Blur tính ở 1/8 cạnh dài khung |
| iOS 26 vs trước | popover iPad và panel giống nhau ở cả hai nhánh |
| Truy cập | nút Video Settings đọc "Video Settings, 16:9, 1080p, 30 fps"; nút 4K mờ đọc "4K, unavailable" + lý do |

## 8. Tiêu chí nghiệm thu

Project mẫu: 5 clip 24,0s — 2 ảnh 4032×3024, 3 video 1920×1080; 16:9 · Fit · Colour đen · 1080p · 30 · H.264.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, project mẫu, Video Settings mở | chạm 9:16 | khung 402×226 → 216×384 ở y 60; panel 340 → 278; Output "1080×1920 · 0:24 · ~30 MB"; một Undo về 16:9 | ⚠️ một phần — `VideoStudioSettingsTests.eachTapIsOneUndo` (9 chạm = 9 bước undo, kéo Blur = 1, Output "720×1280 · 0:06 · ~4 MB"); sim 26.5 (`vs3/out/s9`): chạm 9:16 → khung 9:16 ngay (tầng bản dựng khung hình), Output "1080×1920 · 0:09 · ~11 MB", nút Video Settings mang hình 9:16; **khung 216×384 ở y 60 và panel 340 → 278: chờ khối E plan tools** (bảng cao panel theo tỉ lệ chưa có — panel iPhone vẫn 264) |
| AC-2 | project mẫu đang 9:16 · Fit | chạm Fill (Crop) | mục BACKGROUND biến mất; nhãn "9:16 · Fill"; khung xuất của clip ngang 1920×1080 không còn pixel nền | `VideoExportSmokeTests.fillLeavesNoBackgroundPixel` (hàng trên/giữa/dưới của khung xuất là màu clip), `VideoGeometryTests.fillCoversTheCanvas`, `.aspectAndFramingKeepTheComposition`; sim 26.5: chạm Fill (Crop) → BACKGROUND ẩn, nhãn "9:16 · Fill" góc trái trên khung (`vs3/out/s9/05-scrolled.png`) |
| AC-3 | 9:16 · Fit · Colour xám | Export | hàng pixel trên cùng của khung xuất là #808080 ± 2 | `VideoExportSmokeTests.fitGreyBackgroundFillsTheBars` (clip 16:9 trong 9:16 · nền xám → hàng y 0 của file 1080×1920 = 128 ± 2 ở cả ba kênh, đọc giá trị mã qua ma trận YCbCr của track) + `VideoGeometryTests.portraitSourcePillarboxesOnALandscapeCanvas` |
| AC-4 | mọi tỉ lệ × mọi độ phân giải | tính kích thước khung | đúng 18 ô của bảng §5, mọi cạnh chẵn | `VideoOutputSpecTests.everyRatioAndResolution` (đúng 18 ô của bảng §5, 21:9 4K = 3840×1646, mọi cạnh chẵn); `VideoAspectTests` |
| AC-5 | project mẫu | mở RESOLUTION | 4K mờ + "4K needs 4K clips — 3 of your 5 clips are 1080p."; thay 3 video bằng bản 3840×2160 → 4K bấm được | ⚠️ một phần — `VideoOutputSpecTests.threeOfFiveAre1080p` ("4K needs 4K clips — 3 of your 5 clips are 1080p."), `.mixedSizesSaySmallerThan4K`, `.allUHDUnlocks4K` (thay 3 video bằng 3840×2160 → mở), `.freezeUsesSourceVideoSize` (freeze tính theo video nguồn 3840×2160, không theo khung đã trích 1920×1080); nút 4K mờ có khoá trong panel: task S9 |
| AC-6 | project toàn 4K, đang 4K | thêm 1 video 1920×1080 | độ phân giải thành 1080p, dòng lý do hiện; một Undo → clip mất và lại 4K | `VideoStudioSettingsTests.addingA1080ClipDropsTo1080pInOneUndo` (project ảnh 4K đang 4K, thêm ảnh 1920×1080 → 1080p, lý do "… 1 of your 3 clips is 1080p."; một Undo → clip mất và lại 4K); dòng lý do trong panel: task S9 |
| AC-7 | 9:16 · 1080p · 30 · H.264 · 24,0s | chạm HEVC | Output từ "~30 MB" thành "~18 MB" | `VideoOutputSpecTests.hevcDropsThirtyToEighteen` (9:16 · 1080p · 30 · 24,0 s: "~30 MB" → HEVC "~18 MB"), `.gigabyteFormatting` ("~1.2 GB" từ 1000 MB); dòng Output trong panel: task S9 |
| AC-8 | clip 2 dùng LUT "Kodak 2383" đã xoá | mở Video Settings | dòng đầu "1 look is missing its LUT and exports without it."; bỏ LUT khỏi clip 2 → dòng biến mất | ⚠️ chưa có |
| AC-9 | iPad, Duo trong, Duo ngoài | mở Video Settings | iPad: popover 400×548 dưới nút (Ratio là pop-up 150×44); Duo trong: cột 264 + ⌃; Duo ngoài: panel từ y 334, nút tỉ lệ sáng | ⚠️ chưa có |
| AC-10 | từng board `P6_RatioBackground` · `ES_P_ExportSettings` · `DI5_RatioBackground` · `ES_DI_ExportSettings` · `ES_IL_ExportSettings` · `ES_DC_ExportSettings` | `design-parity` | mọi phần tử đặt tên lệch ≤ 2pt (sau khi board sửa tên và số MB theo §9) | ⚠️ chưa có |
| AC-11 | iPhone, iPad ngang, iPad dọc, Duo trong, Duo ngoài | mở Video Settings, dump | tiêu đề và nút đều "Video Settings"; không phần tử nào chứa "Export Settings" | ⚠️ chưa có |
| AC-12 | project mẫu (16:9 · 1080p · 30 · H.264, 24,0s) | Export | bitrate video của file 10 Mbps ±15%; file 30 MB ±15%; Output trước đó ghi "~30 MB" | `VideoExportSmokeTests.bitrateIsTenMbpsAt1080p30` (nguồn hạt nhiễu 1920×1080 4 s → `estimatedDataRate` và cỡ file trong ±15 % của 1920×1080×30×0,16; sim); `VideoOutputSpecTests.writerAndEstimateShareOneBitrate` (writer xin đúng bitrate mà ước tính dùng, 9 953 280 bps ở 1080p30) và `.hevcDropsThirtyToEighteen` (24 s → "~30 MB"); **máy thật chưa đo** (bộ mã của sim là VideoToolbox của Mac) |
| AC-13 | project mẫu 9:16 · Fit · Blur 50; clip 1 ảnh ngang, crossfade 1,0 s sang clip 2 | đọc khung preview (cạnh dài 1280) và khung xuất (1080×1920 thu về cùng cỡ) ở 1,0 s và giữa crossfade | dải trên/dưới là chính khung đó phủ kín rồi làm mờ; preview và xuất lệch ≤ 3/255; giữa crossfade mỗi bên mang nền của chính nó trước khi trộn | `VideoBackgroundRenderTests.blurPreviewMatchesExportScaledDown` (Blur 50, khung 9:16 ở 1280 và 3840 thu về 180×320: dải trên/dưới lệch ≤ 3/255, dải là chính khung đó mờ), `.crossfadeBlendsEachSidesBackground` (xuất đỏ → xanh crossfade 1 s trên Blur: trước đỏ, sau xanh, giữa mang cả hai); **30 fps preview Blur + crossfade trên máy thật: chưa đo** |
| AC-14 | 9:16 · Fit · Image, ảnh nền đã chọn | xoá ảnh nền khỏi thư viện (hoặc thu quyền), mở lại Video Settings, Export | nền đen; BACKGROUND hiện "Image unavailable — choose another."; xuất vẫn chạy, dải là đen | ⚠️ một phần — `VideoBackgroundRenderTests.missingImageIsBlack` (nền Image không đọc được → đen); ảnh nền ghim ngoài LRU 4 của kho khung tĩnh; câu "Image unavailable — choose another." trong BACKGROUND: task S9 |
| AC-15 | New Video Project, clip đầu là video dọc 1080×1920 (lần khác: ảnh 4032×3024; ảnh vuông) | Video Studio mở | tỉ lệ mặc định 9:16 (lần khác: 4:3; 1:1); Fit · Colour đen · 1080p · 30 · H.264 | `VideoOutputSpecTests.defaultAspectIsNearestToFirstClip` (video dọc 1080×1920 → 9:16, ảnh 4032×3024 → 4:3, vuông → 1:1; so theo log tỉ lệ, hoà → 16:9; mặc định Fit · Colour đen · 1080p · 30 · H.264); model mới lấy tỉ lệ theo clip đầu (`VideoStudioModel.init`) |

**Chưa chứng minh được:** AC-1, AC-2, AC-4 → AC-11, AC-13 → AC-15; AC-12 một phần (dòng Output, máy thật).

## 9. Đã chốt (2026-10-03) và rủi ro

- **Tên:** "Video Settings" mọi nơi (§3). Board ghi "Export Settings" (`ES_*`, nút iPad) sửa chữ theo.
- **Board iPad kiểu Mac ghi "Color"** cho nền màu (`ES_IL_ExportSettings`), board iPhone `P6_RatioBackground` và spec ghi
  "Colour": một lựa chọn một tên — chưa chốt chữ nào; hỏi người dùng trước khi code chữ (ghi trong khối M của
  [plan wide-duo](../../_plans/2026-10-03-vs-wide-and-duo-layout.md)).
- **Bitrate:** giữ ~10 Mbps ở 1080p30 — 0,16 bit/pixel/khung (§5), ngang khuyến nghị tải lên 1080p30 của YouTube;
  Reels/TikTok đằng nào cũng nén lại. *Vì mức ~28 Mbps mà board ngụ ý làm file gấp ~3 lần, tốn chỗ máy và thời gian lưu.*
  Số MB trên board vẽ lại theo §5: 24 s 1080p30 H.264 = ~30 MB (`ES_*`, `F8_*`, `IL*`, `IP*`, `DI*`).

| Rủi ro | Xử lý |
|---|---|
| Bộ mã H.264 phần cứng có thể từ chối 2160×3840 / 2160×2700 | đo trên máy thật ở `/plan`; bị từ chối thì lỗi "This size can't be encoded as H.264 on this device. Switch Codec to HEVC." |
| Đổi tỉ lệ làm overlay lệch chỗ | toạ độ overlay giữ theo tỉ lệ khung, không theo pixel; kiểm ở `/plan` |
