# FS-12.16 — Preset xuất theo nơi đăng

`FS-12.16` · tier D · `Features/VideoStudio/VideoExportSheet.swift` · `Domain/Video/VideoProjectModels.swift` (preset xuất, tỉ lệ)
· `Data/Sources/VideoExportWriter.swift` · nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) (canvas hàng F8) · cập nhật 2026-10-03

**Một câu:** chọn nơi sẽ đăng (Reels/TikTok, YouTube, Instagram…) là đủ tỉ lệ, độ phân giải, fps và codec cho
lần xuất đó, kèm dung lượng ước tính — không phải chỉnh từng thông số.

Video Settings (tỉ lệ, nền khi Fit, độ phân giải, fps, codec, kích thước ước tính) và luồng sau khi xuất:
[FS-12.10](10-video-settings-and-export.md) — tài liệu này **chỉ** nói preset. Đường render: [FS-12.01](01-render-and-export-pipeline.md).
Canvas: hàng F8 của <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ>.

## 1. Người dùng cần gì

Một buổi chụp ra một bản dựng 16:9 cho YouTube và một bản 9:16 cho Reels. Người chụp không nhớ Reels cần
1080×1920 hay 4K có tốn chỗ không; họ biết mình đăng ở đâu.

## 2. Phạm vi

**Có:** năm preset dựng sẵn + **Custom**; khung cắt hoặc khung Fit vẽ trên preview khi tỉ lệ preset khác project;
**Fit on Background · Fill (Crop)**; dung lượng ước tính từng dòng; project nhớ preset lần cuối.

**Cố ý không có:**
- Đổi tỉ lệ project khi chọn preset — preset chỉ là đích của lần xuất (§4).
- Preset do người dùng tự lưu — v1 không có; **Custom** (= Video Settings của project) là bộ thông số riêng (chốt 2026-10-03).
- Tự dời khung cắt theo chủ thể — Fill cắt giữa; muốn khung khác thì đổi tỉ lệ project trong Video Settings.
- Bitrate do người dùng chọn — ngoài phạm vi từ FS-12.01 §3.

## 3. Năm preset và Custom

| Preset | Tỉ lệ | Kích thước | fps | Codec | Ước tính (24 s) |
|---|---|---|---|---|---|
| **Reels / TikTok** | 9:16 | 1080×1920 | 30 | H.264 | ~30 MB |
| **YouTube 4K** | 16:9 | 3840×2160 | 30 | HEVC | ~72 MB |
| **YouTube** | 16:9 | 1920×1080 | 30 | H.264 | ~30 MB |
| **Instagram 4:5** | 4:5 | 1080×1350 | 30 | H.264 | ~21 MB |
| **Square** | 1:1 | 1080×1080 | 30 | H.264 | ~17 MB |
| **Custom** | thông số của Video Settings | | | | "Any ratio · 720p–4K · 24/30/60" |

- Preset là **hằng số của app** (tên, tỉ lệ, kích thước, fps, codec), không phải dữ liệu người dùng.
- Dòng thông số in mono: "1080×1920 · 30 fps", thêm "· HEVC" khi codec không phải H.264.
- **Dung lượng ước tính** dùng đúng công thức của FS-12.10 với thông số của preset — ~10 Mbps ở 1080p30 (chốt
  2026-10-03, [10 §9](10-video-settings-and-export.md)); board đang ghi số ~28 Mbps (~86 MB…) vẽ lại theo bảng trên.
  Không bao giờ xuống dòng: thiếu chỗ thì dòng thông số cắt bằng "…" (F8_DI và F8_IL đang gãy hai dòng — sửa board).
- **YouTube 4K** theo đúng luật 4K của Video Settings: không được thì dòng mờ 0,28, dòng thông số đổi thành lý do
  của FS-12.10 ("4K needs 4K clips…"), chạm không đổi gì.
- **Custom** mở Video Settings; quay lại thì Custom được chọn, dòng thông số là giá trị thật ("4:3 · 720p · 24 fps · H.264").
  Duo trong và Duo ngoài không có dòng Custom (board vẽ 5 dòng): nút Video Settings của chúng chính là Custom.
- **Không có preset tự lưu** ở v1 (chốt 2026-10-03): không hàng "Save as Preset…", không danh sách preset của người
  dùng. *Vì Custom đã là "một bộ thông số riêng", và nó nằm ngay trong project.*

## 4. Preset và tỉ lệ project

- **Preset là đích của lần xuất, không đổi project** (chốt 2026-10-03): tỉ lệ, nền, khung preview và Video Settings
  giữ nguyên. Khi panel xuất mở, nút cài đặt ghi thông số sẽ xuất ("9:16 · 1080p · 30 fps", như board); **dòng phụ
  tiêu đề giữ tỉ lệ project** ("5 clips · 16:9" — sửa F8_IL và F8_DI). *Vì bản dựng 16:9 xuất một lần cho Reels không
  được biến thành 9:16 cho lần xuất YouTube sau.*
- Tỉ lệ preset khác tỉ lệ project thì hiện tiêu đề **YOUR PROJECT IS 16:9** + **Fit on Background · Fill (Crop)**.
  Mặc định Fill (như board). Fit dùng nền của project (màu hoặc Blur, FS-12.10). Trùng tỉ lệ thì hàng ẩn.
- **Preview** trong lúc panel mở: Fill = vùng ngoài khung cắt tối 62%, viền trắng 1,5pt, pill trắng "9:16 · Fill"
  70×20 ở góc trên trái khung cắt; Fit = khung xuất thu nhỏ quanh khung project, dải nền hiện đúng màu. Đóng panel là mất.
- **Overlay vs phụ đề khi Fill:** overlay chữ, sticker là một phần của hình nên bị cắt như preview cho thấy; phụ đề
  ([FS-12.14 §5](14-captions.md)) đo theo khung xuất nên luôn trọn trong khung.
- **Project mới** chọn sẵn preset trùng tỉ lệ: 16:9 → YouTube, 9:16 → Reels / TikTok, 4:5 → Instagram 4:5, 1:1 →
  Square; tỉ lệ khác → Custom. *Vì* lần xuất đầu không nên cắt mất gì.

## 5. Màn hình (canvas hàng F8)

| Máy · board | Mở bằng | Bố cục |
|---|---|---|
| iPhone 402×874 · `F8_P_ExportPresets` | nút Export tròn 36 ở băng trên | panel 340 tại y 450: "Export Video" 14,5 semibold + "0:24" mono + ✕ 32; 6 dòng cao 54 (icon 34 vẽ hình tỉ lệ, tên 13,5, thông số mono 10,5, dung lượng mono 11,5, ✓); hàng Fit/Fill 181×30; đáy 84 tại y 790: **Export for Reels / TikTok ~30 MB** 382×50 `r-md` accent thay hàng 5 công cụ |
| iPad ngang 1376×1032 · `F8_IL_ExportPresets` | pill Export ở băng trên | sheet giữa màn rộng **660** (x 358): "Export Video" + Close 32; **WHERE IS IT GOING**; lưới 2 cột thẻ 300×78 cách 12; Fit/Fill 302×32; dòng "0:24 · H.264 · saved to Photos, then Share"; nút 612×50 |
| Duo trong 951×669 · `F8_DI_ExportPresets` | nút Export ở góc phải dưới | cột phải 264: "Export Video" + Close 28; 5 dòng cao 45; Fit/Fill 114×28; khung cắt 217×385 trên vùng khung 684×385; góc phải dưới giữ nút cài đặt 153,7×40 + **Export** 77,7×40 accent |
| Duo ngoài 466×678 · `F8_DC_ExportPresets` | Export tròn 44 trong dải 84 | panel 382 tại y 334: 5 dòng cao 43, Fit/Fill 173×28, chú thích "Export in the rail uses the chosen preset."; dải: Video Settings 44 tại y 504, Export 44 accent tại y 556 |

- **Dòng đang chọn:** viền trong 1,5pt trắng + nền trắng 8%, `r-md`, dấu ✓ trắng; chạm dòng khác là chọn nó.
- **Một accent:** khi panel mở, nút Export ở băng trên (iPhone, iPad) về nền trắng 10%; accent chuyển sang nút
  "Export for …". Duo trong và Duo ngoài không có nút lớn: nút Export sẵn có là nút xuất.
- **Mở và đóng:** chạm Export lần đầu mở panel, **không** xuất. Đóng bằng ✕/Close, chạm lại nút Export ở băng trên
  (iPhone, iPad), hoặc vuốt panel xuống. Duo ngoài: khi panel mở, chạm Export trong dải là xuất; chạm một công cụ
  trong dải là đóng panel và mở công cụ đó. *Vì* board DC không có ✕ và không có nút lớn.
- Nhãn nút xuất: "Export for <tên preset>"; Custom thì "Export". Duo trong vẽ chữ "Export" nhưng VoiceOver đọc đủ
  "Export for Reels / TikTok".
- iPad dọc chưa có board: sheet 660 như iPad ngang.
- Dòng thông tin dưới Fit/Fill (iPad): "<thời lượng> · <codec> · saved to Photos, then Share"; project ảnh server
  ([FS-17.06](../FS-17-import-from-server/06-edit-and-export.md)): "… · then choose where it goes".

## 6. Dữ liệu và undo

| | |
|---|---|
| Project giữ | đích xuất (id preset hoặc Custom) + lựa chọn Fit/Fill khi chênh tỉ lệ; thông số Custom chính là Video Settings (FS-12.10) |
| Lưu ở | công thức project, bảng Video Projects; không đụng `photo_metadata` |
| Đọc khoan dung | id preset lạ hoặc thiếu → preset trùng tỉ lệ project (luật §4), không báo lỗi. App chưa release: không migration; độ phân giải 1080p/4K cũ của project chuyển vào Video Settings (FS-12.10) |
| Undo | chọn preset, đổi Fit/Fill **không** là bước undo — chúng không đổi hình của project |

## 7. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Chỗ trống < 2 × dung lượng ước tính | trước khi xuất, chữ của [10b §5](10b-export.md): "Not enough space to export — about 60 MB needed. Free up space, then try again."; không bắt đầu, panel giữ nguyên |
| Huỷ giữa chừng, lỗi ghi, clip iCloud không tải được | đường chung của export — FS-12.10 và FS-12 AC-8, AC-13 |
| Không mạng, `.limited` | preset không đọc mạng hay thư viện; clip mất quyền theo luật chung của studio |

## 8. Tiêu chí nghiệm thu

Project mẫu 16:9, 24,0 s ([FS-12.14 §9](14-captions.md)), nền đen, clip 1080p trừ khi AC ghi khác.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, project mới 16:9 | chạm Export | panel "Export Video 0:24"; YouTube đã chọn; không hàng Fit/Fill; nút "Export for YouTube"; Export ở băng trên hết accent; chưa có export nào chạy | ⚠️ chưa có |
| AC-2 | như AC-1 | chạm Reels / TikTok | dòng có viền 1,5 + ✓; preview có khung cắt 127×226 tại x 137,5 ±1 với pill "9:16 · Fill"; hàng "YOUR PROJECT IS 16:9", Fill được chọn | ⚠️ chưa có |
| AC-3 | Reels / TikTok, Fill | Export | file 1080×1920, 30 fps, H.264, dài 24,0 s ±1 khung; khung 8,4 s khớp vùng cắt giữa của khung project ≤ 2/255 | ⚠️ chưa có — smoke test export |
| AC-4 | Reels / TikTok, Fit on Background | Export | file 1080×1920; hình 1080×608 ở giữa; hai dải trên/dưới đúng màu nền | ⚠️ chưa có |
| AC-5 | lần lượt Instagram 4:5 và Square | Export | file 1080×1350 rồi 1080×1080, cùng 30 fps H.264 | ⚠️ chưa có |
| AC-6 | 3/5 clip 1080p; rồi project toàn clip 4K | nhìn YouTube 4K; rồi Export nó | lần 1: dòng mờ 0,28, lý do của FS-12.10, chạm không chọn; lần 2: file 3840×2160 HEVC | ⚠️ chưa có |
| AC-7 | Custom, Video Settings đổi sang 4:3 · 720p · 24 fps | quay lại panel, Export | Custom được chọn, dòng "4:3 · 720p · 24 fps · H.264"; file đúng tỉ lệ 4:3 ở 720p theo FS-12.10, 24 fps | ⚠️ chưa có |
| AC-8 | chọn Reels / TikTok, Fill | đóng panel; rời studio; mở lại project, chạm Export | khi đóng: khung 402×226, Video Settings vẫn 16:9, số bước undo không đổi; khi mở lại: Reels + Fill đã chọn | ⚠️ chưa có |
| AC-9 | phụ đề Bottom và một chữ tại x 0,1 trong project; Reels, Fill | Export | phụ đề trọn trong khung 1080×1920; chữ tại x 0,1 bị cắt, đúng như khung cắt trên preview | ⚠️ chưa có |
| AC-10 | Duo ngoài, panel đóng | chạm Export trong dải, rồi chạm lần nữa | lần 1: panel 5 dòng mở, không xuất; lần 2: xuất với preset đang chọn | ⚠️ chưa có — `Tools/ui-drive` + `Tools/sim-shot` |
| AC-11 | máy còn 40 MB, Reels ước tính ~30 MB | bấm Export for … | thông báo "Not enough space to export — about 60 MB needed…"; không file tạm, trạng thái xuất vẫn rảnh | ⚠️ chưa có |
| AC-12 | project lưu với id preset "vimeo" (không tồn tại) | mở project, chạm Export | YouTube được chọn (trùng 16:9), không thông báo lỗi | ⚠️ chưa có |
| AC-13 | VoiceOver bật, Reels đang chọn | focus dòng Reels | đọc "Reels / TikTok, 1080 by 1920, 30 frames per second, about 30 megabytes, selected" | ⚠️ chưa có |
| AC-14 | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 | mở panel, chọn Reels | khớp `F8_P_ExportPresets`, `F8_IL_ExportPresets`, `F8_DI_ExportPresets`, `F8_DC_ExportPresets` lệch ≤ 2pt; dung lượng một dòng; không control dưới góc bo hay dải 84 | ⚠️ chưa có — agent `design-parity` |

| AC-15 | iPad ngang, project 16:9, panel xuất mở | chọn Reels / TikTok | nút cài đặt "9:16 · 1080p · 30 fps"; dòng phụ tiêu đề vẫn "5 clips · 16:9 · 0:24"; đóng panel → nút cài đặt về "16:9 · 1080p · 30 fps", Video Settings không đổi | ⚠️ chưa có |
| AC-16 | iPhone, panel xuất mở | đọc dung lượng năm dòng preset | ~30 · ~72 · ~30 · ~21 · ~17 MB đúng thứ tự §3, khớp công thức [10 §5](10-video-settings-and-export.md) | ⚠️ chưa có |
| AC-17 | mọi bố cục, Video Settings và panel xuất | dump | không phần tử "Save as Preset…"; danh sách chỉ có năm preset dựng sẵn (+ Custom trên iPhone, iPad) | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 tới AC-17.

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| FS-12.10 viết song song; công thức dung lượng, luật 4K, nền Fit nằm ở đó | preset chỉ tham chiếu; `/plan` đối chiếu hai tài liệu trước khi code |
| Writer hôm nay chỉ H.264 và 30 fps cố định | HEVC và fps khác là việc của FS-12.10; preset chỉ truyền thông số |
| iPad dọc chưa có board F8 | vẽ `F8_IP_ExportPresets` (sheet 660) trước khi code |
