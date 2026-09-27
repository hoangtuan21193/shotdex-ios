# Intent: Ảnh trên Dropbox, Google Drive… duyệt và upload như NAS

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-27 |
| Trạng thái | accepted — người dùng 2026-09-27 chọn: tên "On Local Network" / "On Cloud"; đi qua app Files; cả xem lẫn upload |
| Tiến độ | **đang làm** (2026-09-27) — task 2/4, plan [2026-09-27-cloud-folders](../_plans/2026-09-27-cloud-folders.md) |
| Nguồn | phản hồi người dùng (2026-09-27) |
| Spec sinh ra từ đây | [FS-17.05](../02-functional-spec/FS-17-import-from-server/05-cloud-folders.md) |

## Problem — vấn đề

- "On Server" trong Utilities không nói rõ là ảnh trên ổ mạng; người chưa có NAS không biết đó là gì.
- Nhiều người chụp giữ ảnh trên Dropbox / Google Drive / OneDrive / iCloud Drive chứ không có NAS. Hôm nay ShotDex
  không duyệt, không Import, không upload được tới đó.

## Proposed outcome — kết quả mong muốn

- Utilities có hai mục: **On Local Network** (NAS, máy tính cùng Wi-Fi — màn On Server hiện nay) và **On Cloud**.
- On Cloud: thêm một folder của bất kỳ dịch vụ nào có trong app Files; duyệt như màn server (lưới, Import to Library,
  Rename/Delete, New Folder, ô trong Collections) và chọn được trong **Upload to ▸**.

## Affected users and systems — phạm vi ảnh hưởng

- Collections → Utilities, màn duyệt server, sheet upload, form connection.
- Data: connection kiểu mới "Files" lưu bookmark của folder (migration), không mật khẩu.
- Không thêm dependency, không đăng nhập trong ShotDex, không key API; cần app của dịch vụ đã cài.

## Constraints — ràng buộc

- Chỉ chạm folder người dùng tự chọn (security-scoped bookmark); không đọc gì khác.
- Không tải trọn ảnh chỉ để vẽ thumbnail khi dịch vụ cho thumbnail (QuickLook).
- Quyết định đã chốt: **không** gọi thẳng API Dropbox/Google (Google `drive.readonly` cần duyệt + CASA).

## Open questions

Không.
