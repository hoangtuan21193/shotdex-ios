# Intent: Video Studio theo canvas — khung mới trên mọi thiết bị

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-10-03 |
| Trạng thái | accepted — người dùng 2026-10-03: "Accepted, sang /spec" |
| Tiến độ | **đang làm** (2026-10-08) — task 221/265, 184/280 AC xanh; board Duo ngoài vẽ tay nắm 17 của panel, cột thông số dock iPad dọc ở y 1129 như board (người dùng chốt 2026-10-08); plan [vs-tools-selection-phone](../_plans/2026-10-03-vs-tools-selection-phone.md) tới task 17, plan [vs-wide-and-duo-layout](../_plans/2026-10-03-vs-wide-and-duo-layout.md) tới task 18 (xong), plan [vs-media-settings-export](../_plans/2026-10-03-vs-media-settings-export.md) tới task singlepick, plan [vs-multiselect-beats-ducking](../_plans/2026-10-03-vs-multiselect-beats-ducking.md) tới task 51, plan [vs-captions-compare-presets](../_plans/2026-10-03-vs-captions-compare-presets.md) tới task 48, plan [vs-precise-trim-input](../_plans/2026-10-03-vs-precise-trim-input.md) tới task 1 (thứ tự: công cụ/chọn + lưu nháp → bố cục rộng/Duo → Media/Settings/Export → Look → kích thước → F1–F8) · **2026-10-04: iPad chuyển sang canvas kiểu Mac** (`docs/design/ipad/`, commit `76df46d5`) — số iPad của FS-12 viết lại; 7 AC iPad đã xanh mở lại (03 AC-1·2·3·4·8·9, 09 AC-13; chưa trừ khỏi số trên) + 03b AC-3 (một phần); plan wide-duo thêm [khối M](../_plans/2026-10-03-vs-wide-and-duo-layout.md) (12 task) trước task 16–18; iPhone, Duo không đổi |
| Nguồn | phản hồi người dùng — các comment trên canvas Video Studio 29/9–30/9, và quyết định 2026-10-03 "làm khung mới trước" (trước plan look ảnh cho video, [FS-12.06c](../02-functional-spec/FS-12-video-studio/06c-photo-looks.md)) |
| Spec sinh ra từ đây | [FS-12](../02-functional-spec/FS-12-video-studio/README.md) .03 (11 AC) · .03b (9) · .04 (15) · .04b (11) · .05 (13) · .07 (13) · .07b (12) · .09 (19) · .10 (15) · .10b (14) · .11 F1 (20) · .12 F2 (16) · .13 F3 (16) · .14 F4 (17) · .15 F7 (15) · .16 F8 (17) · .17 F6 (17) · .17b F6 (18) · .18 lưu nháp (12) — **280 AC** (261 + 18 thêm lúc duyệt plan 2026-10-03); F5 là FS-12.06c (intent khác, không tính); sửa kèm FS-12.01, .02, .06, .08, NF-03 |

## Problem — vấn đề

Canvas Video Studio ([docs/design](../design/README.md), Version 23, 82 board) đã vẽ lại khung
theo các comment của người dùng. Code vẫn là khung cũ. Luật chung của người dùng: design và code phải khớp nhau,
nên hôm nay hai bên lệch nhau ở gần như mọi màn.

Người dùng đang gặp các chỗ sau trong app:

- **Thanh dưới lẫn hai loại việc.**
  - Hiện có 6 công cụ cho cả video ở thanh dưới: Ratio, Filter, Adjust, Color, Volume, Background
    (`Features/VideoStudio/VideoStudioModel.swift:36-37`). Chúng nằm chung với các công cụ thêm vào timeline.
  - Ratio bị trùng với nút ở băng trên.
  - Người dùng hỏi "ấn Add nó hiện ra gì", "các tool ở bottom có ý nghĩa khác nhau, không ổn".
- **Chọn một clip thì thanh dưới thành một hàng lệnh dài.**
  - Không có ✕ và ✓ như editor ảnh.
  - Nút Delete nằm trên hàng tiêu đề.
  - Người dùng: "ở dưới chỉ nên là chỗ hiện dấu x hay tick như bên edit ảnh".
- **Add mở trình chọn ảnh của hệ thống** (`VideoMediaPicker.swift`, `PHPickerViewController`).
  - Không kéo được ảnh thẳng vào timeline.
  - Không biết ảnh hay video nào đang được dùng trong video. Người dùng: "mở library thế này không có ý nghĩa".
- **Kích thước khung lệch canvas.**
  - Cột inspector 320pt (`VideoStudioMetrics.swift:33`), canvas vẽ 264pt cho Duo trong.
  - Dải công cụ 92pt (`:281`), canvas vẽ 84pt vào safe area của Duo màn ngoài.
  - Ô lệnh 52×54, canvas vẽ 64×56.
- **Không có màn Video Settings.**
  - Tỉ lệ, độ phân giải, fps, codec, nền khi Fit chưa có chỗ chỉnh trước lúc xuất như canvas vẽ.
  - Người dùng: "phải có chỗ chỉnh ratio, độ phân giải video trước khi export".
- **iPhone thường chỉ dùng dọc.** Đã chốt 2026-09-29; code cần khoá hướng xoay cho iPhone thường.

Ảnh hưởng: mọi người dùng Video Studio, trên mọi thiết bị. Canvas còn vẽ 8 tính năng chưa có trong code (F1–F8, xem Open questions).

## Proposed outcome — kết quả mong muốn

Video Studio trên iPhone, iPad (ngang và dọc), Duo mở ra và Duo màn ngoài trông và cư xử như các board của canvas.
`design-parity` chấm mọi board đạt (lệch không quá 2pt). Cụ thể:

- **Thanh dưới chỉ để thêm vào timeline:** Media · Text · Sticker · Music · Look. Chỉnh cả video thì vào Look
  hoặc Video Settings.
- **Chọn một item** (clip, chữ, nhạc):
  - đáy chỉ còn ✕ · tên · ✓;
  - lệnh của item là hàng đầu tiên của panel, cuộn ngang;
  - panel giữ nguyên chiều cao, khung video không nhảy.
- **Media là thư viện ngay trong panel:**
  - kéo thả ảnh hoặc video vào timeline;
  - chạm một lần để chèn ở playhead;
  - tab In Video, và dấu ✓ cho những gì đang dùng.
- **Video Settings mở từ nút tỉ lệ:** ratio, Background khi Fit, độ phân giải, fps, codec, kích thước ước tính.
  Export chỉ còn là icon.
- **Look gộp Filter · Adjust · Color** cho cả video. Volume chung chuyển thành dòng "Video sound" trong Music.
- **Kích thước theo canvas:**
  - iPhone: khung video cố định theo tỉ lệ project, panel cao theo tỉ lệ.
  - Duo trong: cột 264pt.
  - Duo ngoài: công cụ trong dải 84pt bên phải.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình:** Video Studio (`Features/VideoStudio/`: Screen, Toolbar, CommandBand, MediaPoolColumn, ViewerChrome,
  Metrics, SheetHost, Inspector), export sheet, trình chọn media.
- **Thiết bị:** iPhone (chỉ dọc), iPad ngang và dọc, Duo trong, Duo ngoài.
- **Tầng code:** chủ yếu Features. Domain và Data chỉ đổi nếu project model cần thêm trường (Video Settings:
  resolution, fps, codec, nền).
- **Dữ liệu đã lưu:** project video lưu dạng JSON. App chưa phát hành nên không cần migration
  ([quyết định 2026-09-23](../../CLAUDE.md)). Đọc dữ liệu vẫn phải khoan dung (`LossyArray`).
- **Tài liệu:** FS-12.03, 04, 07, 08 viết theo khung cũ nên phải viết lại. FS-12.06c (look ảnh) chờ intent này.

## Constraints — ràng buộc

- **Không thêm dependency.** Không dùng trình chọn của bên thứ ba.
- **Kéo thả từ lưới media trong UIScrollView phải đi qua UIKit pan.** Gesture SwiftUI chết trong UIScrollView,
  đã gặp ở timeline.
- **Nhánh iOS 26 và dưới 26 đều phải chạy.**
- **Giữ những gì đang chạy đúng:**
  - export qua AVAssetReader → AVAssetWriter với compositor riêng;
  - overlay chữ và sticker sống trên canvas;
  - nhạc nhập từ Files (`ImportedMusicStore`);
  - mọi thao tác timeline đã có (cắt, tốc độ, freeze, chuyển cảnh, beat).
- **Accent #EB9526 chỉ dùng cho nút chính (Export).** Màu #57BFD1 chỉ dùng cho timeline.
- **Quyền `.limited`:** thư viện Media chỉ hiện ảnh đã được phép, và có nút "Manage Access…".
- **iPhone thường không có giao diện ngang** cho Video Studio.

## Open questions — câu hỏi còn treo

### Đã chốt (người dùng 2026-10-03)

1. **Phạm vi:** làm cả khung **lẫn** 8 tính năng mới vẽ ở cuối các hàng canvas: F1 chọn nhiều clip, F2 beat, F3 âm
   thanh, F4 chữ động, F5 look (đã có spec riêng [FS-12.06c](../02-functional-spec/FS-12-video-studio/06c-photo-looks.md)),
   F6 cắt từng khung, F7 keyboard, F8 preset xuất. Một intent, chia thành nhiều spec FS-12.x khi sang Design.
2. **Cắt clip:** theo canvas, bỏ lối cắt bằng ngón tay cũ (FS-12.07). Chỉ còn hai cách: kéo tay nắm ở mép clip, và
   lệnh Trim (Start/End to Playhead) trong panel.
3. **Thứ tự:** theo mảng, mọi thiết bị cùng lúc: thanh dưới → chọn item → Media → Video Settings → Look → kích thước
   → từng tính năng F1–F8.
4. **Lưu nháp** (2026-10-03, lúc duyệt plan): project video tự lưu thành nháp như CapCut/iMovie — ~1 s sau mỗi thay
   đổi, ngay khi Back / xuống nền / đổi scene; Back không hỏi Discard; Video Projects hiện nháp lẫn bản đã xuất
   ([FS-12.18](../02-functional-spec/FS-12-video-studio/18-drafts.md)). *Vì sửa video mất thời gian, không được mất.*

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
