# FS-12.10b — Export

`FS-12.10b` · tier D · `Features/VideoStudio/VideoExportSheet.swift` · `Data/Sources/VideoExportWriter.swift`
· cập nhật 2026-10-03

**Một câu:** Export không còn hỏi chất lượng — nó tóm tắt thứ Video Settings đã chốt, xuất, cho huỷ, và nói thật
khi hỏng.

Nguồn intent: [2026-10-03-video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md).
Canvas: [Video Studio](https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ) v23 — `P7_Export` · `IL5_Export` · `DI6_Export`.
Nút Export ở chrome và mọi thông số xuất: [10](10-video-settings-and-export.md). Đường ghi file: [01 §9](01-render-and-export-pipeline.md).

## 1. Người dùng cần gì

Bấm xuất xong mới biết file 4K nặng 120 MB, hay xuất nhầm 16:9 cho Reels, là mất vài phút chờ. Trước khi xuất cần
thấy một dòng tóm tắt đúng thứ sẽ ra; trong lúc xuất cần huỷ được; hỏng thì cần biết làm gì tiếp.

## 2. Mở ở đâu

Bấm nút Export ở chrome → **Export Video** mở, **chưa xuất**. *Vì nút Export iPhone chỉ 36pt cạnh nút Video Settings;
chạm nhầm không được tốn vài phút encode.*

| | iPhone 402×874 | iPad 1376×1032 · 1032×1376 | Duo trong 951×669 | Duo ngoài 466×678 |
|---|---|---|---|---|
| Vùng | panel cao theo tỉ lệ project (16:9 340) | form sheet 540 giữa màn | cột phải 264 | panel từ y 334 |
| Tiêu đề | "Export Video" 17 đậm, ô icon 24 bên trái, ✕ tròn 30 bên phải (`P7` vẽ lúc đang xuất nên không có ✕) | "Export Video" 22 đậm + ✕ tròn 32 | "Export Video" 20 đậm + ✕ tròn 30 | như iPhone |
| Nút xuất | **Export** cam 362×50 ở (20, 705) | **Export** cam 492×50, icon + chữ | chạm lần hai vào **Export** 78×40 ở (829, 622) | chạm lần hai vào **Export** tròn 44 ở y 556 |

- Duo (cả hai màn): cột / panel ghi "The button stays where your thumb is — bottom right."
  *Vì nút đã nằm dưới ngón cái; thêm nút thứ hai trong cột là bắt tay rời chỗ.*
- iPhone: hàng công cụ mờ suốt lúc Export Video mở; Duo ngoài: năm ô công cụ mờ.

## 3. Nội dung

| Hàng | Chữ |
|---|---|
| LUT mất (chỉ khi có) | ⓘ "1 look is missing its LUT and exports without it." — chữ của [06c §6](06c-photo-looks.md), **ngay trên nút xuất** |
| Tóm tắt | 🕒 "0:24 · 16:9 · 30 fps · ~30 MB"; chạm → Video Settings mở, Export Video đóng. Duo trong tách "~30 MB" thành hàng riêng có icon tải |
| Đích | 🖼 "Saved to Photos as a new video" |

Số MB là ước tính của [10 §5](10-video-settings-and-export.md), cùng số với Output.

## 4. Trạng thái

| Trạng thái | Hiển thị |
|---|---|
| Sẵn sàng | §3 + nút xuất |
| Đang xuất | "Exporting… 62%" + thanh tiến độ 362 + **Cancel Export** chữ đỏ trên nền đỏ tối, cao 48, ở chỗ nút xuất; ✕ ẩn; Back · Undo · Redo, timeline, khung không nhận chạm |
| Đang lưu | "Saving to Photos…", không Cancel |
| Xong | Video Studio đóng, viewer hiện video mới ([01 §2](01-render-and-export-pipeline.md)) |
| Lỗi | chữ đỏ nói lỗi + nút xuất trở lại |

## 5. Đường hỏng

- **Cancel** dừng ≤ 1s, xoá file tạm, Photos không thêm gì, về Sẵn sàng.
- **Thiếu chỗ:** trống < 2 × ước tính (file tạm + bản trong Photos) → không bắt đầu:
  "Not enough space to export — about 60 MB needed. Free up space, then try again."
- **Rời app khi đang xuất** → huỷ như Cancel, quay lại thấy "Export stopped when you left ShotDex. Export again to finish."
  *Vì GPU không được vẽ ở nền; huỷ thật thà hơn một file hỏng.*
- **Không được ghi Photos** → "ShotDex can't save to Photos. Allow access in Settings." + Open Settings.
- **Bộ mã từ chối kích thước** (H.264 ở khung dọc 4K) → "This size can't be encoded as H.264 on this device. Switch Codec to HEVC."
- **Project ảnh server:** nút xuất thành "Export…", hàng Đích thành "Choose where it goes next"; file đi tiếp theo
  [FS-17.06](../FS-17-import-from-server/06-edit-and-export.md), không vào Photos.

## 6. Dữ liệu và ràng buộc

| | |
|---|---|
| Đọc | công thức project + cài đặt của [10](10-video-settings-and-export.md); không ghi gì vào project |
| Ghi | file tạm → Photos (asset video mới, index ngay); `photo_metadata` chỉ qua index như mọi asset (BD-02) |
| Bộ nhớ | xuất 4K không vượt trần app (NF-02) |
| iOS 26 vs trước | form sheet và panel giống nhau ở hai nhánh |
| Truy cập | thanh tiến độ đọc "Exporting, 62 percent"; Cancel Export là nút phá huỷ |

## 7. Tiêu chí nghiệm thu

Project mẫu: 5 clip 24,0s (2 ảnh, 3 video 1920×1080) · 16:9 · Fit · 1080p · 30 · H.264.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, project mẫu | bấm Export ở băng trên | panel "Export Video": "0:24 · 16:9 · 30 fps · ~30 MB", "Saved to Photos as a new video", nút Export 362×50; **không** có hàng Quality; chưa có tiến độ | ⚠️ chưa có |
| AC-2 | Export Video đang mở | chạm hàng tóm tắt | Export Video đóng, Video Settings mở | ⚠️ chưa có |
| AC-3 | project mẫu đổi sang 9:16 · 24 fps | xuất xong | file 1080×1920, 24 khung/giây, track H.264, thời lượng lệch < 1 khung so với 24,0s | ⚠️ chưa có |
| AC-4 | project mẫu đổi sang 60 fps · HEVC | xuất xong | file 1920×1080, 60 khung/giây, track HEVC, thời lượng lệch < 1 khung | ⚠️ chưa có |
| AC-5 | clip 2 dùng LUT "Kodak 2383" đã xoá | mở Export Video, bấm Export | dòng "1 look is missing its LUT and exports without it." ngay trên nút; xuất chạy tới 100% | một phần: `VideoLUTRendererTests.aMissingFileLeavesTheFrameAlone` |
| AC-6 | đang xuất 62% | bấm Cancel Export | dừng ≤ 1s; thư mục tạm không còn file; Photos không thêm asset; nút Export trở lại | ⚠️ chưa có |
| AC-7 | máy còn 40 MB trống, ước tính ~30 MB | bấm Export trong panel | không bắt đầu; hiện "Not enough space to export — about 60 MB needed…" | ⚠️ chưa có |
| AC-8 | đang xuất 30% | về màn Home rồi mở lại app | không có file dở; thấy "Export stopped when you left ShotDex. Export again to finish." | ⚠️ chưa có |
| AC-9 | quyền ghi Photos bị từ chối | xuất xong phần encode | "ShotDex can't save to Photos. Allow access in Settings." + Open Settings; file tạm bị xoá | ⚠️ chưa có |
| AC-10 | Duo trong 951×669 | chạm Export (829, 622), rồi chạm lại đúng chỗ đó | lần một mở cột Export Video, chưa xuất; lần hai bắt đầu xuất; nút không dời chỗ | ⚠️ chưa có |
| AC-11 | project từ ảnh server | bấm "Export…" | xuất xong mở sheet xuất của FS-17.06; Photos không thêm asset | ⚠️ chưa có |
| AC-12 | từng board `P7_Export` · `IL5_Export` · `DI6_Export` | `design-parity` | mọi phần tử đặt tên lệch ≤ 2pt (sau khi ba board bỏ hàng Quality, §8) | ⚠️ chưa có |

| AC-13 | iPad 1376×1032 và Duo trong 951×669, project mẫu | mở Export Video, dump | không phần tử nào tên "Quality", "1080p" hay "4K" ngoài hàng tóm tắt; chạm tóm tắt mở Video Settings | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 → AC-4, AC-6 → AC-13; AC-5 một phần.

## 8. Đã chốt (2026-10-03) và rủi ro

**Export không có hàng Quality 1080p / 4K.** Độ phân giải chỉ chỉnh ở RESOLUTION của Video Settings; hàng tóm tắt
(§3) chạm mở Video Settings. *Vì một giá trị chỉ có một chỗ chỉnh (DESIGN §1 mục 3).* Board `P7`, `IL5`, `DI6` vẽ lại
không có hàng Quality.

| Rủi ro | Xử lý |
|---|---|
| Không có board trạng thái Sẵn sàng trên iPhone (`P7` vẽ lúc đang xuất) và chưa có board Export cho iPad dọc, Duo ngoài | vẽ `P7_ExportReady`, `IP_Export`, `DC_Export` cùng lúc bỏ hàng Quality khỏi `P7`, `IL5`, `DI6` |
| Chạm hai lần trên Duo dễ thành xuất nhầm khi người dùng chỉ muốn xem | lần một chỉ mở cột; lần hai phải cách lần một ≥ 0,5s mới tính |
