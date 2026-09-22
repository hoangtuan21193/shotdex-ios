# NF-04 — Trạng thái rỗng và trạng thái lỗi

`NF-04` · cập nhật 2026-09-22

**Một câu:** danh mục empty/error state toàn app và luật viết chúng.

## 1. Luật

- Empty state ngắn, nói **việc đang xảy ra** và **hành động tiếp theo**, không nói thuật ngữ.
- Mọi lỗi phải kèm lối ra: nút, hoặc câu chỉ đúng chỗ cần mở.
- Không có trạng thái im lặng: thứ gì đang chạy lâu phải nhìn thấy được.

## 2. Danh mục

| Trạng thái | Nội dung |
|---|---|
| Chưa cấp quyền | giải thích + nút mở Settings |
| Limited Photos Access | giải thích + nút chọn thêm ảnh |
| Không có ảnh | câu ngắn, không hành động bắt buộc |
| Đang index | dòng tiến độ, không chặn thao tác khác |
| Không khớp filter | "No photos match these filters." + nút **Clear Filters** |
| Không có EXIF | hiện dữ kiện `PHAsset` thuần thay vì ô trống |
| Camera chưa xác định cảm biến | lối vào Unknown Cameras trong Settings |
| Index bị lỗi | nói lỗi + nút thử lại |
| Ảnh iCloud chưa tải về | trạng thái tải, và khi iCloud không phản hồi thì nói rõ ([BD-03.04](../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)) |
