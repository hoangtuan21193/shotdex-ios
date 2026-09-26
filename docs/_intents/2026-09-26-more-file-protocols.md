# Intent: Nối được với nhiều loại server file hơn (WebDAV, FTPS, FTP)

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-26 |
| Trạng thái | accepted — người dùng duyệt 2026-09-26 |
| Tiến độ | **đang làm** (2026-09-26) — task 11/14 của plan (1/4 khối C), 1/6 AC xanh |
| Nguồn | phản hồi người dùng (2026-09-26) |
| Spec sinh ra từ đây | [FS-15.05](../02-functional-spec/FS-15-server-upload/05-more-protocols.md) — AC-31…AC-36 |

## Problem — vấn đề

ShotDex hôm nay chỉ nói chuyện được SMB và SFTP (`FileServer.TransferProtocol` —
[FileServer.swift](../../ShotDex/Core/Models/FileServer.swift)). Nhiều người lưu ảnh ở chỗ khác:

- **Nextcloud / ownCloud**, Synology/QNAP mở ra internet qua **WebDAV** (HTTPS) — đường phổ biến nhất để vào NAS
  khi không ở nhà, vì SMB không nên mở ra internet.
- NAS đời cũ, router có ổ USB, máy chủ thuê chỉ mở **FTP** hoặc **FTPS**.

Những người này hôm nay không dùng được upload FS-15, và sẽ không dùng được tải ảnh về
([intent import](2026-09-26-import-from-server.md)).

## Proposed outcome — kết quả mong muốn

- Form connection có thêm **WebDAV**, **FTPS**, **FTP**. Mỗi giao thức có đúng các ô nó cần (WebDAV: URL/đường
  dẫn gốc + HTTP/HTTPS; FTPS/FTP: cổng, chế độ TLS).
- Mọi thứ đang chạy với SMB/SFTP chạy y hệt với ba giao thức mới: Test Connection, duyệt folder, upload có kiểm
  SHA-256, trùng tên, tên tạm `.shotdex-part`, và tải về.
- Chọn **FTP** thường → cảnh báo rõ: mật khẩu và ảnh đi không mã hoá, chỉ nên dùng trong mạng nhà.
- WebDAV/FTPS dùng chứng chỉ tự ký (NAS nhà rất hay) → hỏi tin dấu vân tay chứng chỉ, giống host key SFTP.

## Affected users and systems — phạm vi ảnh hưởng

- Settings → File Servers (form), sheet upload, duyệt folder, tải về.
- Data: ba client mới sau giao thức `RemoteFileClient` có sẵn; factory. Domain: không đổi luồng upload.
- Database: giá trị mới cho cột `transferProtocol`; có thể thêm cột (đường dẫn gốc WebDAV, chế độ TLS, dấu vân
  tay chứng chỉ) → migration.
- NF-03 (riêng tư): FTP thường gửi dữ liệu không mã hoá — ghi vào ngoại lệ thứ hai, có cảnh báo.
- Bonjour: `_webdav._tcp`, `_webdavs._tcp`, `_ftp._tcp` cho [intent tự tìm máy](2026-09-26-server-discovery.md).

## Constraints — ràng buộc

- **Bỏ NFS** — người dùng chốt 2026-09-26 (không có thư viện iOS, NAS hay chặn theo IP/UID).
- WebDAV: dùng `URLSession` có sẵn, không thêm thư viện.
- FTP/FTPS: iOS không còn API FTP (CFFTP bị gỡ) → cần thư viện hoặc tự viết client. Giấy phép phải hợp App Store
  (MIT/BSD/Apache, không GPL/LGPL) — cùng luật khi chọn SMBClient/Citadel.
- Đọc/ghi theo khối ≤ 1 MB (NF-02); không giữ cả file trong RAM.
- Kiểm checksum sau khi ghi vẫn bắt buộc: giao thức nào không cho đọc lại theo khối thì chưa được coi là hỗ trợ.

## Open questions — câu hỏi còn treo

- Thư viện FTP/FTPS nào đạt giấy phép và chạy được trên iOS 17+? — spike trước `/spec` hoặc trong `/plan`.
- WebDAV: có bắt buộc HTTPS khi ra internet không (đề xuất: cho HTTP nhưng cảnh báo như FTP)?
- FTP: chỉ passive mode (đề xuất: có — active mode gần như không qua được NAT của điện thoại).
