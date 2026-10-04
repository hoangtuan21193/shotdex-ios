# FS-12.10b — Export

`FS-12.10b` · tier D · `Features/VideoStudio/VideoExportSheet.swift` · `Data/Sources/VideoExportWriter.swift`
· cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** Export không còn hỏi chất lượng — panel **Export Video** mở mà chưa xuất, trạng thái Sẵn sàng là danh
sách preset của [16](16-export-presets.md), còn tài liệu này giữ khung panel, lúc đang xuất, huỷ và đường hỏng.

Nguồn intent: [2026-10-03-video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md).
Board: `P7_Export` ([`docs/design/iphone/project/`](../../design/iphone/project/), đang xuất) · `IL5_Export`, `IP_Export`
([`docs/design/ipad/project/`](../../design/ipad/project/), kiểu Mac 2026-10-04) · `DI6_Export`, `DC_Export`
([`docs/design/duo/project/`](../../design/duo/project/)); trạng thái
Sẵn sàng là `F8_*` của [16](16-export-presets.md). Nút Export ở chrome và mọi thông số xuất:
[10](10-video-settings-and-export.md). Đường ghi file: [01 §9](01-render-and-export-pipeline.md).

> **Chốt 2026-10-03:** FS-12.16 đúng cho trạng thái Sẵn sàng. Bản trước của tài liệu này tả một Sẵn sàng khác
> (hàng tóm tắt + "Saved to Photos…" + nút 362×50; iPad form sheet 540) — đã bỏ, để không xây Sẵn sàng hai lần.

## 1. Người dùng cần gì

Bấm xuất xong mới biết file 4K nặng 120 MB, hay xuất nhầm 16:9 cho Reels, là mất vài phút chờ. Trước khi xuất cần
thấy đúng thứ sẽ ra; trong lúc xuất cần huỷ được; hỏng thì cần biết làm gì tiếp.

## 2. Khung panel

Bấm nút Export ở chrome → **Export Video** mở, **chưa xuất**. *Vì nút Export iPhone chỉ 36pt cạnh nút Video Settings;
chạm nhầm không được tốn vài phút encode.*

- Vùng, tiêu đề, cỡ nút xuất và vị trí từng máy: [16 §5](16-export-presets.md) (iPhone panel 340 + nút "Export for …"
  382×50 ở đáy; iPad sheet **700** (kiểu Mac 2026-10-04); Duo trong cột 264; Duo ngoài panel 382 từ y 334). Đóng: [16 §5](16-export-presets.md).
- Duo (cả hai màn): **không có nút xuất thứ hai** — chạm lần hai vào nút Export sẵn có (Duo trong 78×40 ở (829, 622),
  Duo ngoài tròn 44 ở y 556) là xuất. *Vì nút đã nằm dưới ngón cái.*
- iPhone: hàng công cụ nhường chỗ cho nút xuất suốt lúc Export Video mở; Duo ngoài: năm ô công cụ mờ.

## 3. Nội dung tài liệu này thêm vào trạng thái Sẵn sàng

| Hàng | Chữ |
|---|---|
| LUT mất (chỉ khi có) | ⓘ "1 look is missing its LUT and exports without it." — chữ của [06c §6](06c-photo-looks.md), **ngay trên nút xuất** |

- Danh sách preset, Fit/Fill, dung lượng từng dòng, Custom (mở Video Settings), dòng đích ("saved to Photos" / "then
  choose where it goes"): [16 §3–§5](16-export-presets.md). Số MB là ước tính của [10 §5](10-video-settings-and-export.md).

## 4. Trạng thái

| Trạng thái | Hiển thị |
|---|---|
| Sẵn sàng | danh sách preset của [16 §5](16-export-presets.md) + dòng LUT mất (§3) + nút xuất |
| Đang xuất | "Exporting… 62%" + thanh tiến độ theo bề rộng nút xuất + **Cancel Export** chữ đỏ trên nền đỏ tối, cao 48, ở chỗ nút xuất; ✕ ẩn; Back · Undo · Redo, timeline, khung không nhận chạm. **iPad** (`IL5_Export`, `IP_Export`): sheet 700×572, chân sheet chia đôi — trái "Exporting… 62%" + thanh 360×6, phải **Cancel Export** 180×44; pill Export ở toolbar về nền `fill` |
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

Project mẫu: 5 clip 24,0s (2 ảnh, 3 video 1920×1080) · 16:9 · Fit · 1080p · 30 · H.264. AC đo nội dung Sẵn sàng
(preset, dung lượng từng dòng) nằm ở [16 §8](16-export-presets.md).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, project mẫu | bấm Export ở băng trên | panel "Export Video" mở ở vùng panel, có ✕; **không** có hàng Quality; chưa có tiến độ, chưa export nào chạy; nội dung Sẵn sàng như [16](16-export-presets.md) AC-1 | ⚠️ một phần (khung) — `VideoExportFlowTests.firstTapOpensNeverExports` (Export mở Export Video, `exportState` vẫn idle, recipe không đổi); sim 26.5 (`vs3/out/e1`): panel "Export Video" có ✕, không hàng Quality, chưa có tiến độ; đang xuất "Exporting… 0%" + thanh + "Cancel Export" đỏ trên nền đỏ tối 48 cao, ✕ ẩn, băng trên mờ; **nội dung Sẵn sàng (danh sách preset của FS-12.16 AC-1) và nút "Export for …" 382×50: task 34 của plan captions-compare-presets** — hiện là dòng Custom + nút Export tạm |
| AC-2 | iPhone, Export Video đang mở | chạm dòng Custom | Export Video đóng, Video Settings mở (đường duy nhất từ Export sang Video Settings — không còn hàng tóm tắt) | `VideoExportFlowTests.customOpensVideoSettings` (Export Video mở → dòng Custom → Export Video đóng, Video Settings mở); dòng Custom là đường duy nhất từ Export sang Video Settings — task 46 của plan captions giữ hành vi này |
| AC-3 | project mẫu đổi sang 9:16 · 24 fps | xuất xong | file 1080×1920, 24 khung/giây, track H.264, thời lượng lệch < 1 khung so với 24,0s | `VideoExportSmokeTests.nineBySixteenAt24fps` (9:16 · 24 fps → file 1080×1920, `nominalFrameRate` 24, H.264, 3,0 s lệch < 1/24 s, 72 mẫu khung), `.previewStaysAt30` (project 60 fps: preview vẫn 1/30, bản dựng xuất 1/60) |
| AC-4 | project mẫu đổi sang 60 fps · HEVC | xuất xong | file 1920×1080, 60 khung/giây, track HEVC, thời lượng lệch < 1 khung | `VideoExportSmokeTests.hevcAt60fps` (60 fps · HEVC → file 1920×1080, `nominalFrameRate` 60, track `hvc1`, 3,0 s lệch < 1/60 s); **đỉnh bộ nhớ 4K 60 HEVC 20 clip trên máy thật: chưa đo** |
| AC-5 | clip 2 dùng LUT "Kodak 2383" đã xoá | mở Export Video, bấm Export | dòng "1 look is missing its LUT and exports without it." ngay trên nút; xuất chạy tới 100% | một phần: `VideoLUTRendererTests.aMissingFileLeavesTheFrameAlone` |
| AC-6 | đang xuất 62% | bấm Cancel Export | dừng ≤ 1s; thư mục tạm không còn file; Photos không thêm asset; nút Export trở lại | `VideoExportSmokeTests.cancelStopsWithinASecondAndLeavesNoFile` (nguồn hạt nhiễu 20 s, huỷ ở ≥ 50 %: ném `CancellationError` trong < 1 s, thư mục phiên không còn `ShotDex-Video-*.mp4`); writer xoá file ở mọi nhánh huỷ/lỗi; huỷ thì không gọi Photos; sim 26.5: Cancel Export → panel về Sẵn sàng (`vs3/out/e1/42-cancelled.png`) |
| AC-7 | máy còn 40 MB trống, ước tính ~30 MB | bấm Export trong panel | không bắt đầu; hiện "Not enough space to export — about 60 MB needed…" | ⚠️ chưa có |
| AC-8 | đang xuất 30% | về màn Home rồi mở lại app | không có file dở; thấy "Export stopped when you left ShotDex. Export again to finish." | ⚠️ chưa có |
| AC-9 | quyền ghi Photos bị từ chối | xuất xong phần encode | "ShotDex can't save to Photos. Allow access in Settings." + Open Settings; file tạm bị xoá | ⚠️ chưa có |
| AC-10 | Duo trong 951×669 | chạm Export (829, 622), rồi chạm lại đúng chỗ đó | lần một mở cột Export Video, chưa xuất; lần hai bắt đầu xuất; nút không dời chỗ | ⚠️ chưa có |
| AC-11 | project từ ảnh server | bấm "Export…" | xuất xong mở sheet xuất của FS-17.06; Photos không thêm asset | ⚠️ chưa có |
| AC-12 | trạng thái **Đang xuất**: board `P7_Export` và `IL5_Export` · `DI6_Export` · `IP_Export` · `DC_Export` sau khi vẽ lại thành Đang xuất (§8) | `design-parity` | mọi phần tử đặt tên lệch ≤ 2pt | ⚠️ chưa có |
| AC-13 | iPad 1376×1032 và Duo trong 951×669, project mẫu | mở Export Video, dump | không phần tử nào tên "Quality"; không có bộ chọn độ phân giải riêng — độ phân giải chỉ hiện trong dòng thông số preset ([16 §3](16-export-presets.md)); iPad: dòng Custom mở Video Settings | ⚠️ chưa có |
| AC-14 | bộ mã H.264 từ chối kích thước (writer tiêm trong test; máy thật: 9:16 · 4K · H.264 nếu bị từ chối) | Export | không file dở; "This size can't be encoded as H.264 on this device. Switch Codec to HEVC."; codec **không** tự đổi; nút xuất trở lại | ⚠️ chưa có — test writer tiêm + máy thật |

**Chưa chứng minh được:** AC-1 → AC-4, AC-6 → AC-14; AC-5 một phần.

## 8. Đã chốt (2026-10-03) và rủi ro

**Export không có hàng Quality 1080p / 4K.** Độ phân giải chỉ chỉnh ở RESOLUTION của Video Settings (Custom) hoặc
đi theo preset. *Vì một giá trị chỉ có một chỗ chỉnh (DESIGN §1 mục 3).*

**Sẵn sàng là của FS-12.16** (chốt 2026-10-03). Board: `P7_Export` giữ (đang xuất); `IL5_Export`, `DI6_Export`,
`IP_Export`, `DC_Export` vẽ lại thành trạng thái **Đang xuất** của máy đó (Sẵn sàng của chúng là `F8_IL` / `F8_DI` /
`F8_IP` / `F8_DC`); `P7_ExportReady` bỏ — Sẵn sàng iPhone là `F8_P_ExportPresets`.

| Rủi ro | Xử lý |
|---|---|
| Chạm hai lần trên Duo dễ thành xuất nhầm khi người dùng chỉ muốn xem | lần một chỉ mở cột; lần hai phải cách lần một ≥ 0,5s mới tính |
