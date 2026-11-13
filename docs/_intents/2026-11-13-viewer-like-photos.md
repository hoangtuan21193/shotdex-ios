# Intent: Viewer và tải ảnh mượt như Photos

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-13 |
| Trạng thái | accepted (2026-11-13, planboard `.planboard/viewer-photos`, 1 vòng, đồng ý cả 6 mặc định) |
| Nguồn | "Understand how Library and image view, image load works in the Photos app, show me the evidence, and build a similar UI for shotdex… tap 1 lần vào ảnh sẽ ẩn hết các button… tìm hiểu các load ảnh và giao diện để cải thiện tốc độ" |
| Bằng chứng | [docs/_research/2026-11-13-photos-viewer-loading-re.md](../_research/2026-11-13-photos-viewer-loading-re.md) |
| Spec sinh ra từ đây | [FS-02 §8, AC-1…AC-16](../02-functional-spec/FS-02-photo-detail/README.md#8-đợt-giống-photos-2026-11-13) |

## Problem
- Chạm vào ảnh không làm gì; muốn chỉ nhìn ảnh phải phóng to. Video thì chạm = dừng — hai nghĩa cho một cử chỉ.
- Nền viewer luôn đen, board vẽ nền theo sáng/tối: design và code lệch.
- Mở ảnh trượt từ dưới lên; đóng xong lưới không về ảnh vừa xem (spec FS-02.01b §1 đã yêu cầu).
- Phóng to làm ảnh gốc ~190 MB rơi vào cache ảnh màn hình (giới hạn 160 MB) → đẩy hết ảnh khác ra, quay lại phải tải lại.
- Ảnh nét giải mã trên luồng chính lúc vẽ → giật khi vuốt; chỉ chuẩn bị ±1 ảnh; thiếu bộ nhớ không dọn cache.

## Outcome
Như Photos: chạm 1 lần ẩn hết chrome (trừ vòng tải iCloud), nền chuyển đen, trạng thái giữ khi vuốt; mở/đóng
phóng từ ô lưới; vuốt nhanh không mờ, không giật; bộ nhớ không phình.

## Constraints
- Không bỏ chức năng nào của viewer (danh sách: planboard A8).
- iOS 17 tối thiểu: chuyển cảnh zoom có nhánh dự phòng; iOS 26 / trước 26 đều chạy.
- Tier C (viewer), nút kính phải đọc được trên nền sáng lẫn tối.
- Không chạy full suite / gate (chỉ khi người dùng bảo).
