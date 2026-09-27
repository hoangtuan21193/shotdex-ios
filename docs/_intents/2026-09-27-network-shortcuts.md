# Intent: Folder trên server thành một ô trong Collections, mở một chạm

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-27 |
| Trạng thái | accepted — người dùng 2026-09-27: "làm shortcut network theo đề xuất đi" |
| Tiến độ | **đang làm** (2026-09-27) — task 3/4 (còn ảnh 18.6/iPad + /verify), plan [2026-09-27-network-shortcuts](../_plans/2026-09-27-network-shortcuts.md) |
| Nguồn | phản hồi người dùng (2026-09-27) |
| Spec sinh ra từ đây | [FS-17.04](../02-functional-spec/FS-17-import-from-server/04-network-shortcuts.md) |

## Problem — vấn đề

Người chụp có vài folder trên NAS mở đi mở lại (folder buổi chụp đang sửa, folder "Chọn lọc"). Hôm nay mỗi lần
phải: Collections → kéo tới Utilities → On Server → connection → đi xuống từng cấp folder. Năm chạm và một lần cuộn
cho một việc lặp lại mỗi ngày; album trong Photos thì một chạm.

## Proposed outcome — kết quả mong muốn

- Trong màn duyệt server, "thêm folder này vào Collections". Collections có mục **Network** (chỉ hiện khi có ít
  nhất một ô) với các ô trông như album: ảnh bìa, tên. Chạm → thấy ảnh trong folder đó ngay.
- Không nhầm với album: ô cho thấy đây là folder trên server; mở ra vẫn là màn duyệt server với luật của nó (menu
  kiểu Files, xoá là xoá thật trên server có hỏi), không phải menu album. Cầu nối sang Photos duy nhất là **Import
  to Library**.

Debate đã chốt 2026-09-27 (người dùng chọn đề xuất): **không** làm menu ⋯ giống album (Edit/Compress/Delete ngay trên
server) — cùng tên nút mà hậu quả khác (Delete album chỉ gỡ khỏi album; delete server là mất vĩnh viễn), Compress
ghi đè bản gốc trên kho bản gốc, Edit không có chỗ lưu rõ ràng.

## Affected users and systems — phạm vi ảnh hưởng

- Collections (mục mới), màn duyệt server (menu ⋯, nhấn giữ folder).
- iPhone · iPad · Duo — mục Network dùng lại hàng ô cuộn ngang của My Albums.
- Data: bảng mới `server_shortcuts` (dữ liệu người dùng tự tạo → bảng riêng, BD-02). Features: Albums, ServerImport.

## Constraints — ràng buộc

- Không ghi gì lên server khi tạo/bỏ ô. Bỏ ô không đụng folder.
- Ảnh bìa phải hiện khi server tắt/không cùng mạng: lưu sẵn trên máy, không đọc mạng khi vẽ Collections.
- Không token/màu mới (DESIGN.md); dùng `AlbumCoverTile`.

## Open questions

Không — các mặc định ghi trong spec, người dùng đã chọn hướng.
