# Smart Album giống Photos — các quyết định

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | All/Any khi 1 điều kiện | OK | Ẩn, ghi "Khớp điều kiện sau" (như Photos) |
| D2 | Chỗ thêm điều kiện mới | OK | Nút − + trên mỗi dòng, + chèn ngay dưới (như Photos Mac) — khác đề xuất |
| D3 | Số ảnh khớp | OK | Thanh đếm cố định ở đáy sheet |
| D4 | Sửa trong album đang mở | OK | Nút ⋯ + chạm thanh điều kiện |
| D5 | Nhân bản / Đổi tên / Xoá Mac | OK | Đủ cả ba, cả ở menu nhấn giữ ô album |
| D6 | Điều kiện ngày | OK | Đơn vị days/weeks/months/years + "is not in the last" |
| D7 | Loại "Photo is …" | OK | Làm luôn những loại PhotoKit cho đọc — khác đề xuất |
| D8 | Mac | OK | iPhone, iPad, Duo và Mac |
| A1–A6 | Phần Claude tự quyết | OK | Cập nhật sống, đếm không nhấp nháy, báo lỗi lưu, giữ giá trị khi đổi loại, quy trình, giữ mọi chức năng |

## D2 — Nút − + trên mỗi dòng
- **Chốt:** mỗi dòng có − (xoá) và + (chèn điều kiện mới ngay dưới), như Photos Mac; nút Add Condition cuối danh sách giữ lại.
- **Đã cân nhắc:** menu ⋯ (Claude đề xuất, tránh bấm nhầm trên 402pt) — người dùng chọn −/+. Hệ quả cần xử lý: hai nút phải đủ 44pt vùng chạm và cách nhau, − không xoá ngay khi dòng đã có giá trị? → không hỏi lại; Photos xoá ngay, ShotDex có Cancel của sheet làm đường lui.
- **Lịch sử:** vòng 1 — chọn khác đề xuất.

## D7 — Loại "Photo is …"
- **Chốt:** thêm điều kiện "Photo" với các giá trị PhotoKit đọc được: favorite, edited (`hasAdjustments`, iOS 15+), tagged with GPS, RAW, video, Live Photo, burst (`burstIdentifier`), panorama, HDR, portrait, screenshot, screen recording, slo-mo, time-lapse, Cinematic, Spatial, animated.
- **Không làm (không đọc được hoặc không áp dụng):** hidden (ShotDex không thấy ảnh ẩn), selfie (chỉ có dạng album hệ thống), long exposure, ProRes, referenced, unable to upload to iCloud.
- **Hệ quả:** hai cột mới (`hasAdjustments`, `burstIdentifier`) đọc ở lượt nhanh (thuộc tính PHAsset, không đọc file) + tăng `indexerVersion` để hàng cũ được điền dần; mediaSubtypes đã có sẵn nên phần lớn không cần index lại.
- **Lịch sử:** vòng 1 — chọn khác đề xuất (đề xuất là để sau).

## D1, D3–D6, D8
Chốt như đề xuất trong plan.json; lý do ở trường `why` của từng câu.
