# Pending spec edits — slug `server` (FS-15 / FS-17 server items)

Áp khi file không còn thay đổi chưa commit của phiên khác. Mỗi mục: file · section · thay đổi · ID.

## DESIGN.md

1. **§11, bullet "Xác nhận phá hủy" (dòng ~365)** — thay cả bullet (Q6):
   > - **Xác nhận phá hủy:** `.alert` 2 nút — nút phá hủy `role: .destructive` ghi rõ hành động ("Delete", "Remove"),
   >   nút `Cancel` `role: .cancel`; câu message nói hậu quả. **Không** dùng `confirmationDialog` (§10.5: iOS 26 vẽ nó
   >   thành popover và ẩn nút Cancel). `confirmationDialog` chỉ còn cho lựa chọn **không** phá huỷ nhiều nhánh.
2. **§8 bảng icon, sau hàng "Đã lên server (glyph trên ô lưới)"** — thêm một hàng sau khi chốt ⚠️ CẦN QUYẾT glyph
   In Library ở FS-17.01 §2b (H4). Theo đề xuất a:
   > | Đã có trong thư viện (ô trên màn duyệt server) | `photo.badge.checkmark` trắng trên đĩa tối mờ, 14pt — không dùng `checkmark.circle.fill` (dấu đã chọn) |

## docs/02-functional-spec/FS-17-import-from-server/05-cloud-folders.md

3. **Mục danh sách Cloud Folders (dòng ~35–36, "nhấn giữ/vuốt → **Rename** / **Remove**…")** — thêm ngay sau câu đó (Q6):
   > Remove hỏi bằng **alert hai nút** **Remove** đỏ + **Cancel**, câu "ShotDex stops using this folder. Nothing in the
   > cloud or in your library is deleted." — không dùng hộp kiểu action sheet (iOS 26 ẩn Cancel của nó). AC-89 ở FS-17.03.

## docs/02-functional-spec/FS-17-import-from-server/README.md

4. **Bảng các phần, hàng 03** — thay cột cuối (H4, Q6):
   > AC-1…30, AC-41…44, AC-71 (AC-18 từ lỗi 2026-09-27), AC-85…89 (review UI 2026-10-02: Select ở toolbar, glyph In Library, hộp xoá)

## docs/01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md

5. **§5 Chạy nền, sau bullet "Tác vụ nền được đăng ký lúc app khởi động…"** — thêm bullet (H3):
   > - Cấu hình app khai thêm một tác vụ chạy tiếp do người dùng bắt đầu: upload lên server trên iOS 26
   >   ([FS-15.02b](../../02-functional-spec/FS-15-server-upload/02b-background-upload.md)). Nó không xếp hàng và không
   >   chạy khi app chưa mở — khác tác vụ index nền.
