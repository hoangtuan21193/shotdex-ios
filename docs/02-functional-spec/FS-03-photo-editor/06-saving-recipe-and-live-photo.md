# FS-03.06 — Lưu, recipe và Live Photo

`FS-03.06` · `Data/Sources/PhotoEditingService.swift` · `ShotDexKit` (model recipe) · cập nhật 2026-09-22

**Một câu:** một công thức sửa gắn vào chính tấm ảnh, nên mở lại là thấy đúng slider cũ — kể cả trong app
Photos.

## 1. Quy tắc

- Recipe (nguồn, mọi slider, look, crop, toàn bộ mask) gắn vào **adjustment data của ảnh** dưới định danh
  và phiên bản của ShotDex.
- Mỗi ảnh chỉ có **một** adjustment data — của lần sửa gần nhất, do hệ thống giữ.
- Mở ảnh đã có recipe của mình → **editor tự khởi tạo từ recipe đó**, không mở identity rồi bắt bấm Recall.
- App khác đã sửa ảnh sau đó → **không recall recipe cũ**, và nguồn lấy từ bản render mới nhất chứ không
  âm thầm quay về file gốc.
- **Save Changes không xoá bản gốc** — Photos vẫn Revert được.

## 2. Save Copy và Save Changes

| | Save Copy | Save Changes |
|---|---|---|
| Kết quả | asset **mới**, ảnh tĩnh, full resolution, chất lượng tối đa | ghi đè bản render của chính asset đó, giữ nguyên id |
| Tên file | basename gốc + `_SHOTDEX_EDITED_N` (N tăng riêng theo từng ảnh nguồn) | — |
| Recipe | copy mới **cũng mang recipe** nên mở lại sửa tiếp được | nằm trong adjustment data |
| Album | mở từ album cho phép thêm thì copy được thêm lại album đó | — |
| Live Photo | **chỉ ra ảnh tĩnh** | giữ chuyển động |

Save Copy còn lưu id của ảnh nguồn, nên một bản JPEG/HEIC vẫn dựng lại được từ RAW/JPEG gốc bất biến và
tái hiện đúng các slider RAW; nguồn không còn trên máy thì rơi về chính file của bản copy. **Id và recipe
này không có cơ chế đồng bộ riêng qua iCloud.**

## 3. Live Photo

Áp **cùng một chuỗi xử lý** lên ảnh tĩnh và đoạn chuyển động, giữ nguyên chuyển động.

Mask subject và sky **giải một lần trên ảnh tĩnh** rồi scale qua các frame — không chạy model cho từng frame.

## 4. Định dạng và metadata

- Sheet Save mặc định **JPEG** (format luôn dùng được); đổi sang HEIC nếu muốn.
- Máy không nhận HEIC → UI **báo trước** là sẽ dùng JPEG, lưu ở chất lượng tối đa, và **báo lại sau khi
  xong**.
- **Include Metadata** bật (mặc định) giữ EXIF, ngày, GPS, orientation. Tắt thì bản render không mang EXIF
  và ngày/vị trí ở mức asset cũng bị bỏ.

## 5. Sau khi lưu

- Asset mới được **index ngay** khi hệ thống trả id, nên nó có metadata trong ShotDex trước khi flow đóng.
- Save Copy còn phát tín hiệu thay đổi cấu trúc ngay để Library/album/smart album reload **trước khi
  editor đóng**, không phải chờ hệ thống debounce hay chờ một lượt index toàn thư viện đang chạy. Thông
  báo của hệ thống vẫn chạy như lưới an toàn.
- **Viewer hiện ngay ảnh vừa lưu** (cả hai đường lưu):
  - Chờ **cover đóng hẳn** rồi mới tìm — trang nằm dưới một cover đang đóng chỉ thấy nháy.
  - Save Changes trúng ngay lần đầu (cùng id), nhưng vẫn dựng lại trang để bản render mới thay ảnh cache.
  - Save Copy phải đợi index + tín hiệu cấu trúc đưa asset mới vào danh sách, nên **poll tối đa 20 lần ×
    250ms** thay vì bỏ cuộc ở lần trượt đầu.
- Nguồn không decode/render/encode được → **giữ phiên và báo lỗi**, không tạo asset rỗng.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
