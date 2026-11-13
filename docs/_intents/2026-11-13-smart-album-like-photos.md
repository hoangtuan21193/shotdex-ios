# Intent: Smart Album dùng mượt như app Photos

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-13 |
| Trạng thái | accepted (2026-11-13, planboard `.planboard/smart-album-photos`, 1 vòng) |
| Nguồn | yêu cầu người dùng: "Understand how Smart Album works in the Photos app, show me the evidence, and build a similar UI for shotdex. Không được bỏ chức năng nào của shotdex, chỉ update giao diện và logic bên trong để shotdex hoạt động mượt hơn giống Photos" |
| Bằng chứng | [docs/_research/2026-11-13-photos-smart-album-re.md](../_research/2026-11-13-photos-smart-album-re.md) (Photos 12, macOS 27.2.1, REA) |
| Quyết định | `.planboard/smart-album-photos/DECISIONS.md` (D1–D8, A1–A6) |
| Spec sinh ra từ đây | [FS-06.08 §3c, AC-20…AC-37](../02-functional-spec/FS-06-collections/08-smart-albums.md) |

## Problem — vấn đề

Smart Album của ShotDex đã gần Photos (tên, All/Any, điều kiện, đếm khớp), nhưng dùng còn khựng:

- Muốn sửa điều kiện phải thoát album ra tab Collections, nhấn giữ ô, chọn Edit; lưu xong phải vào lại album mới
  thấy lưới mới (màn chi tiết giữ bản điều kiện lúc mở).
- Không nhân bản được smart album; đổi tên chỉ qua màn sửa; Mac không xoá được smart album.
- Sheet sửa: All/Any hiện cả khi chỉ một điều kiện; điều kiện mới luôn rơi xuống cuối; số ảnh khớp nằm dưới danh
  sách, cuộn mới thấy, biến mất khi chưa có điều kiện hợp lệ; lưu lỗi thì sheet im lặng.
- Ngày chỉ có "in last N days" — không có tuần/tháng/năm, không có "không trong … qua".
- Photos có điều kiện "Photo is …" (edited, Live, panorama, HDR, burst, screenshot…); ShotDex chỉ lọc được kiểu chụp
  ở menu Filter, không đưa vào smart album.

## Proposed outcome — kết quả mong muốn

Như Photos: sửa ngay trong album đang mở và thấy kết quả tại chỗ; album tự cập nhật khi dữ liệu đổi; sheet soạn gọn
(ẩn All/Any khi một điều kiện, −/+ trên dòng, + chèn ngay dưới, số khớp luôn thấy); đủ Edit / Rename / Duplicate /
Delete ở cả iOS và Mac; ngày có đơn vị và phủ định; thêm điều kiện "Photo is …" cho những loại PhotoKit đọc được.

## Constraints — ràng buộc

- **Không bỏ chức năng nào** (A6): 22 trường điều kiện, nhóm lồng, Media Type, Keep in Photos, Also on Server,
  Original, Filter/Sort trong album, chọn nhiều và mọi thao tác, Save as Smart Album từ tìm kiếm, Spotlight, biểu đồ
  Statistics, AI search.
- App chưa release: đổi nghĩa khoá JSON không cần migration; decode vẫn khoan dung.
- Dữ liệu người dùng gõ không vào `photo_metadata`; hai cột mới (`hasAdjustments`, `burstIdentifier`) là dữ liệu
  PhotoKit, indexer ghi lại được.
- 55.000 ảnh: cập nhật sống không được bắn câu đếm toàn thư viện liên tục (NF-01); không chặn main thread.
- Không đọc được ảnh ẩn qua fetch thường → "hidden" không có. Không có selfie / long exposure / ProRes / referenced /
  unable to upload (không có API hoặc không áp dụng).
- Bốn thiết bị: iPhone, iPad, Duo (chung Swift) và Mac (`ShotDexMac/Albums`). Board trên 4 canvas đi trước code.
