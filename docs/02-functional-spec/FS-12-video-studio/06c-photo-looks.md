# FS-12.06c — Look ảnh cho video

`FS-12.06c` · tier D · `Domain/Video/VideoProjectModels.swift` · `Data/Sources/VideoFrameCompositor.swift`
· `Domain/Editing/LookPresetStore.swift` · `Domain/Editing/LookExchange/LookCubeBaker.swift`
· `Features/VideoStudio/VideoColorPanel.swift` · nguồn intent [user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md)
mục 8 · cập nhật 2026-10-02

**Một câu:** film look, My Looks (kể cả look nhập từ XMP Lightroom) và LUT của editor ảnh chọn được thẳng trong
Video Studio, cho cả video hoặc từng clip, không phải xuất `.cube` rồi nhập lại.

Tầng màu và node chain: [FS-12.06](06-color-layer.md). Đọc `.cube`: [FS-12.06b §3](06b-scopes-luts-and-tracking.md).
My Looks và nhập preset: [FS-03.02](../FS-03-photo-editor/02-film-simulation-and-presets.md), [FS-03.14](../FS-03-photo-editor/14-lightroom-preset-exchange.md).

## 1. Người dùng cần gì

Người chụp đã có tông riêng cho ảnh trong My Looks. Làm reel từ chính buổi chụp đó, video phải cùng tông. Hôm nay
phải xuất look ra `.cube`, nhập lại trong Color, và mất Clarity, Grain, Vignette dọc đường; clip nào cũng chung một LUT.

## 2. Phạm vi

**Có:** một ô look cho cả video và một ô look riêng cho từng clip; ba nguồn Presets · My Looks · LUTs; Amount;
Import Look… dùng chung kho với editor ảnh.

**Cố ý không có:**
- Node chain, de-log, Adjust riêng cho từng clip — Adjust và Color vẫn cho cả video; per-clip chỉ là look.
- Chồng hai look lên nhau — một ô look, chọn cái này là bỏ cái kia, cùng luật với editor ảnh (film look ↔ LUT).
- Sửa look ngay trong Video Studio — sửa ở editor ảnh rồi lấy lại (§6).

## 3. Màn hình (theo canvas Video Studio, hàng F5)

| Máy | Lối vào | Bố cục look |
|---|---|---|
| iPhone 402×874 | công cụ **Look** ở hàng đáy 5 ô (cả video); ô **Look** trong hàng lệnh clip (từng clip) | panel 340 tại y 450: tiêu đề "Look · Whole video" ✕ ✓; chip **Filter · Adjust · Color** 28; Filter → **Presets · My Looks · LUTs** 30; một hàng ô 70×70 cuộn ngang; Amount 40; **APPLY TO** All Clips · This Clip; dòng chú thích; **Import Look…** 42 |
| Duo ngoài 466×678 | ô Look trong rail 84 | panel 382×344 tại y 334: cùng thứ tự, ô 60, Amount 36 |
| Duo trong 951×669 | ô Look ở hàng đáy | cột phải 264: lưới 3×2 ô 66, Amount 34; cột cuộn xuống Apply To, chú thích, Import Look… |
| iPad 1376×1032 | Look ở hàng đáy (cả video); inspector clip (từng clip) | inspector 280: **LOOK FOR THIS CLIP**, lưới 3×2 ô 72, Amount, **This Clip · Selected · All Clips**; chân "Clip 2 · Coast / Look · Moody Coast" |

- Ô My Looks nhập từ preset mang nhãn **XMP** góc trên phải, như ở editor.
- Ô vẽ khung của clip dưới playhead qua từng look; chưa có ảnh thì vẽ gradient hai tông của look (luật của editor).
- Amount chỉ hiện khi có look (luật FS-03.02). Look mới bắt đầu ở 100; chạm lại ô đang chọn giữ nguyên Amount.
- Clip có look riêng mang **pill tên look** trên lane V1 (cao 19, như canvas); clip theo look cả video không có pill.
- Chọn LUT và nhập LUT chuyển hẳn vào Filter → LUTs và Import Look…; chip Color không còn mục LUT.
- **Look riêng trên iPhone và Duo:** hàng lệnh clip có ô **Look** ngay trước Delete (64×56, icon + chữ). Chạm thì
  phần dưới panel chuyển sang khối **LOOK FOR THIS CLIP**, như Trim chuyển sang hai chip; đích là các clip đang chọn.
  - Khối: tiêu đề 28 · Presets/My Looks/LUTs 30 · hàng ô 70 (Duo ngoài 60) · Amount 40 · This Clip · Selected ·
    All Clips 30 · chú thích. *Vì một chạm từ hàng lệnh, panel 340 không phải cuộn qua Duration/Speed/Fade/Motion.*
  - Nhờ vậy điện thoại có đủ "Selected" cho nhiều clip như iPad.
- **Trả một clip về look cả video:** nút chữ **Use Video Look** (12.5, accent) ở bên phải dòng tiêu đề
  LOOK FOR THIS CLIP, trên mọi máy; chỉ hiện khi clip có look riêng. Một chạm = một bước undo, pill trên lane mất.

## 4. Hành vi

- **Đích của lựa chọn.** Look (cả video) + All Clips → look cả video; This Clip → clip dưới playhead, và dòng phụ
  của tiêu đề đổi từ "Whole video" thành tên clip. Inspector clip: This Clip, Selected (khi chọn ≥ 2 clip), All Clips.
- **Clip thắng cả video.** Clip có look riêng (kể cả Original) dùng look đó **thay** look cả video, không chồng lên.
  *Vì hai film look chồng nhau nhân đôi contrast, chưa ai muốn thế.*
- **All Clips** đặt look cả video **và xoá mọi look riêng** của clip — đúng chữ "All Clips"; cả việc là một bước
  undo, Undo trả lại mọi look riêng.
- **Amount** 0…100 trộn **cả look** (tone, màu, film, LUT, hạt, vignette) với khung trước look. Khác editor, nơi Amount
  chỉ chỉnh phần film/LUT. *Vì trên video look là một khối kín, không có slider con để chỉnh phần còn lại.*
- **Thứ tự mỗi khung:** de-log → node chain → look của clip → hiệu ứng clip → chuyển cảnh → nền viền → overlay.
  - Cả chuỗi grade chạy **trên từng clip trước khi trộn**: dissolve giữa hai look là trộn hai khung đã grade riêng.
  - Viền letterbox không còn bị grade: màu nền ra đúng màu đã chọn. Scope đo khung của clip dưới playhead với look của nó.

## 5. Phần nào của look chạy được trên video

Ngân sách preview: **30 khung/giây = 33,3 ms/khung** ở cạnh dài 1280. Export đi cùng chuỗi, không cần thời gian thực.

| Phần của look | Trên video | Vì |
|---|---|---|
| Light, WB, presence, Brilliance, B&W, mixer, point colour, grading, calibration, curve, film look, LUT | **nướng** vào một bảng 33³ lúc chọn, mỗi khung một lượt tra | từng pixel độc lập; sai số trung bình ≤ 1/255 (đã đo cho Mono, FS-03.14) |
| Clarity, Texture, Sharpening, Dehaze | chạy **từng khung**; bán kính co giãn theo cạnh dài khung, chuẩn 1920 | cần điểm lân cận; giữ bán kính theo pixel thì preview 1280 và export 4K ra hai ảnh khác |
| Vignette | từng khung, theo khung hình của clip, không theo canvas có viền | — |
| Grain | từng khung, **mẫu hạt đổi mỗi khung** | hạt đứng yên trên video trông như bụi trên ống kính |
| Noise Reduction | **bỏ** | NR không gian từng khung làm nhấp nháy; video cần NR theo thời gian |
| Upright, Lens Correction, quang học | **bỏ** | hình học của một tấm ảnh khác |

- Không ghép look thành bảng lúc mở panel: nướng **khi chọn**, ngoài main thread; bảng giữ trong cache **24 bảng**
  (~14 MB), khoá theo nội dung look. Project mở lại thì nướng lại; bảng không ghi vào project.
- Dòng chú thích dưới Apply To nêu đúng phần bị bỏ của look đang chọn: "Skipped on video: Noise Reduction, Upright."
  Không bỏ gì thì "Everything in this look applies to video." Dòng luôn có, nên panel không nhảy.
- Clarity…Dehaze không giữ được 30 khung/giây ở phép đo §9 thì cả bốn chuyển sang **bỏ** ở cả preview lẫn export,
  và dòng chú thích nêu tên — không bao giờ preview một đằng, export một nẻo.

## 6. Dữ liệu và look sửa sau

| | |
|---|---|
| Project giữ | một ô look cả video + một ô look tuỳ chọn mỗi clip; mỗi ô: loại (preset · My Look · LUT), tên, Amount |
| My Look | **bản chép** phần look của công thức (~2–5 KB) + id look gốc + cờ "nhập từ preset" |
| Preset | chỉ tên preset; tên người dùng đặt lại lấy từ kho tên của editor |
| LUT | id + tên, bảng ở đĩa (luật FS-12.06b §3) |
| Lưu ở | công thức project trong bảng Video Projects ([FS-06.01b](../FS-06-collections/01b-album-management-and-creations.md)); không đụng `photo_metadata` (BD-02) |

- Ô filter + cường độ và ô LUT + strength cũ gộp thành một ô look. App chưa release: không migration.
- **Look sửa sau ở editor ảnh:** project giữ **bản chép** lúc chọn. Ô của look gốc có viền chọn; chạm lại = lấy
  bản mới (một bước undo). Look gốc bị xoá thì video vẫn render như cũ. *Vì áp look lên ảnh cũng là chép, và
  project không được đổi tông sau lưng người dùng.*
- **LUT mất file** (LUT chọn thẳng, hoặc LUT bên trong một My Look): phần đó render như không có, phần còn lại giữ.
  - Pill thành "Kodak 2383 · Missing"; chú thích: "Kodak 2383 is missing. Import it again, then pick it in LUTs."
  - Export không bị chặn; sheet Export thêm một dòng phụ trên nút Export: "1 look is missing its LUT and exports without it."
  - Nhập lại cùng file cấp id mới nên **không tự nối lại**; người dùng chọn lại một chạm.

## 7. Undo, huỷ, đường hỏng

- Chạm một ô = một bước undo; một lần kéo Amount = một bước; đổi đích kéo theo đổi look = một bước. Trần 40 bước.
- ✕ của panel trả look về đúng lúc mở panel và không để lại bước undo nào; ✓ giữ từng bước đã làm.
- Import Look… mở bộ chọn Files của editor (xmp, lrtemplate, dng, shotdexlook, cube) và hiện báo cáo nhập của
  FS-03.14a. Preset vào My Looks, `.cube` vào LUTs, look vừa nhập được chọn cho đích hiện tại. Huỷ picker: không đổi gì.
- Clip dưới playhead chỉ có trên iCloud, máy mất mạng: ô dùng gradient thay thế, **không** gọi tải ảnh chỉ để vẽ ô.
- Bộ nhớ: cache 24 bảng là trần; quá thì bảng ít dùng nhất bị thay. Tier D, không rẽ nhánh iOS 26/trước 26.
- VoiceOver: ô đọc "Look Moody Coast, imported from Lightroom, selected"; nhãn clip đọc thêm "Look Night Teal".

## 8. Tiêu chí nghiệm thu

Look mẫu **Moody Coast**: Exposure +0,3 · Contrast +20 · Velvia 100% · Grain 25 · Vignette −20.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | look tone + HSL + curve + Velvia, khung thử 64×64 | nướng bảng 33³ cho video | khung qua bảng lệch trung bình ≤ 1/255 so với chuỗi của editor ảnh | một phần: `LookExportCubeTests.bakesColourOnly` (chỉ Mono) |
| AC-2 | project 3 clip, không look | Look → My Looks → chạm Moody Coast, All Clips | cả 3 clip có look; khung ở 1,0 s mỗi clip khớp ảnh editor áp Moody Coast lên khung đó, lệch trung bình ≤ 2/255; undo +1 | ⚠️ chưa có |
| AC-3 | cả video Velvia; clip 2 có look riêng Night Teal | render khung giữa clip 1, 2, 3 | clip 1 và 3 là Velvia; clip 2 khớp Night Teal **một mình**, không Velvia; chỉ clip 2 có pill "Night Teal" | ⚠️ chưa có |
| AC-4 | clip 1 Velvia, clip 2 Night Teal, dissolve 1,0 s, tỉ lệ 9:16 trên canvas 16:9 | render khung ở giữa dissolve | khung = trộn 50/50 hai khung đã grade riêng (≤ 1/255); viền letterbox đúng màu nền đã chọn | ⚠️ chưa có |
| AC-5 | Moody Coast, Amount 100 | kéo Amount về 40 trong một lần kéo | khung = 40% look + 60% khung trước look (≤ 1/255); undo +1; ở 0 khung bằng không look | ⚠️ chưa có |
| AC-6 | My Look có Grain 25, Noise Reduction 50, Upright Auto, trên clip ảnh tĩnh | chọn look | chú thích "Skipped on video: Noise Reduction, Upright."; hai khung liền nhau có mẫu hạt khác nhau, cùng độ lệch chuẩn ±10% | ⚠️ chưa có |
| AC-7 | project dùng Moody Coast; ở editor đổi Contrast 20 → 60 và lưu đè | mở lại project, rồi chạm ô Moody Coast | trước khi chạm: render Contrast 20, ô có viền chọn; sau khi chạm: Contrast 60, undo +1 | ⚠️ chưa có |
| AC-8 | clip 2 dùng LUT "Kodak 2383", file đã xoá khỏi LUTs | mở project, rồi mở Export | clip 2 render như không look; pill "Kodak 2383 · Missing"; Export chạy được, sheet có dòng "1 look is missing its LUT…" | một phần: `VideoLUTRendererTests.aMissingFileLeavesTheFrameAlone` |
| AC-9 | project không look | mở Look, chạm Velvia, chạm Moody Coast, kéo Amount 70, bấm ✕ | project về không look; số bước undo bằng lúc trước khi mở panel | ⚠️ chưa có |
| AC-10 | như AC-9 nhưng bấm ✓ | Undo 3 lần, từng lần một | lần 1: Moody Coast 100; lần 2: Velvia; lần 3: không look | ⚠️ chưa có |
| AC-11 | playhead 7,0 s nằm trong clip 2; Look (cả video), This Clip | chạm Warm Fjord | chỉ clip 2 có look; dòng phụ tiêu đề là "Clip 2 · Coast"; look cả video không đổi | ⚠️ chưa có |
| AC-12 | clip 2 Night Teal; Look (cả video), All Clips | chạm Velvia | cả 3 clip Velvia, pill clip 2 biến mất; một Undo trả Night Teal cho clip 2 | ⚠️ chưa có |
| AC-13 | Look → Filter → My Looks | Import Look… chọn một `.xmp` hợp lệ; lần sau chọn một `.cube`; lần ba huỷ picker | xmp: đứng đầu My Looks, nhãn XMP, đã được chọn, editor ảnh cũng thấy; cube: vào LUTs và được chọn; huỷ: không đổi gì | ⚠️ chưa có |
| AC-14 | iPhone 402×874 · Duo ngoài 466×678 · Duo trong 951×669 · iPad 1376×1032 | mở Look (iPad: chọn clip) | khớp board F5_P/F5_DC/F5_DI/F5_IL lệch ≤ 2pt (ô 70/60/66/72); Apply To tới được; không control nào dưới góc bo hay rail 84 | ⚠️ chưa có — agent `design-parity` + `Tools/sim-shot` |
| AC-15 | clip HEVC 4K 30 fps, Moody Coast + Clarity 30 + Texture 20 + Dehaze 15, preview 1280; máy thật iPhone 17 và iPad | play 10 s, có một dissolve giữa hai look | ≤ 3 khung rơi trong 10 s, kể cả trong dissolve | ⚠️ chưa có — máy thật |

**Chưa chứng minh được:** AC-1 → AC-15. AC-1 và AC-8 có test một phần; AC-15 cần máy thật, Duo chỉ có simulator.

## 9. Rủi ro và phần phải đo trước `/plan`

| Rủi ro | Xử lý |
|---|---|
| Chuỗi grade chạy hai lần mỗi khung trong chuyển cảnh, cộng bốn lượt lân cận, vượt 33,3 ms | đo AC-15 trên máy thật trước `/plan`; không đạt thì bỏ Clarity…Dehaze trên video (§5) |
| Thời gian nướng một bảng 33³ qua chuỗi ảnh chưa đo; My Looks 50 look = 50 lần nướng cho ô | mục tiêu ≤ 50 ms/look trên iPhone 17; ô điền dần, gradient thay thế trong lúc chờ |
| Bảng 33³ cắt giá trị ngoài 0…1 (HLG chưa de-log) | đã đúng với film look hiện có; de-log đứng đầu chuỗi |
| Export `.cube` liệt Brilliance là "mất" dù pass của nó là từng pixel (bán kính 0) | xem lại ở `/plan`; video nướng Brilliance vào bảng |
