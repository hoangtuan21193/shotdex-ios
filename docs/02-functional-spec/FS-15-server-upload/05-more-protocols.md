# FS-15.05 — WebDAV

`FS-15.05` · `Data/Sources/FileServer/WebDAVFileClient.swift` · `Domain/ServerUpload/PropfindParser.swift` · `Core/Models/FileServer.swift`
· cập nhật 2026-09-26

**Một câu:** WebDAV đi sau cùng giao thức `RemoteFileClient`, nên upload có kiểm SHA-256, trùng tên,
duyệt folder và tải về (FS-17) chạy y như SMB/SFTP; giao thức không mã hoá thì cảnh báo.

Nguồn: [intent](../../_intents/2026-09-26-more-file-protocols.md). **NFS bị bỏ**, rồi **FTP và FTPS cũng bị bỏ** (người dùng chốt
2026-09-26, sau khảo sát: không có thư viện Swift nào đạt, còn libcurl + OpenSSL thì phải tự build và giữ cập nhật).

## 1. Giao thức và ô của form

| Giao thức | Cổng mặc định | Ô riêng | Ghi chú |
|---|---|---|---|
| SMB | 445 | — (share là cấp đầu của Folder, FS-15.01 §3a) | như cũ |
| SFTP | 22 | — | như cũ, host key |
| **WebDAV** | 443 (HTTPS) · 80 (HTTP) | **Path** (đường dẫn gốc, ví dụ `/remote.php/dav/files/me`), công tắc **Use HTTPS** (mặc định bật) | Nextcloud, ownCloud, Synology, QNAP |

- Picker Protocol liệt kê theo thứ tự trên. Đổi giao thức thì ô riêng đổi theo, cổng để trống là cổng mặc định
  của lựa chọn hiện tại.
- Folder vẫn là đường dẫn tương đối: từ gốc máy, cấp đầu là share (SMB), trong home (SFTP), dưới Path (WebDAV).

## 2. Việc từng client phải làm

Cùng một danh sách thao tác `RemoteFileClient` (FS-15.02 §4, FS-15.02 §2a, FS-17):

| Thao tác | WebDAV |
|---|---|
| liệt kê file / folder | `PROPFIND` Depth 1 |
| kích thước | `PROPFIND` getcontentlength / `HEAD` |
| tạo folder | `MKCOL` từng cấp |
| ghi theo khối từ file | `PUT` luồng từ file, có `Content-Length` (không chunked) |
| đọc theo khối (checksum, tải về) | `GET` stream |
| đọc một đoạn (thumbnail FS-17) | `GET` + `Range` |
| đổi tên `.shotdex-part` → tên thật | `MOVE` + `Overwrite: F` |
| xoá | `DELETE` |

- Kiểm SHA-256 bằng đọc lại vẫn bắt buộc (FS-15.02 §4). Server bỏ qua `Range` → tải về vẫn chạy, chỉ
  thumbnail FS-17 phải tải trọn file.
- Đăng nhập WebDAV: Basic hoặc Digest qua `URLCredential`, **không bao giờ** gửi Basic qua HTTP mà chưa cảnh báo.

## 3. Cảnh báo không mã hoá

- **WebDAV** tắt Use HTTPS → dưới picker hiện: "Passwords and photos are sent unencrypted. Use
  this only on your home network." (màu cảnh báo của hệ thống, không phải đỏ).
- Không chặn lưu. Không cảnh báo lại mỗi lần upload.

## 4. Chứng chỉ TLS (WebDAV HTTPS)

- Chứng chỉ hợp lệ theo hệ thống → không hỏi.
- Chứng chỉ tự ký / không khớp tên (NAS nhà rất hay) → hộp **Trust This Server?** như host key SFTP (FS-15.01 §4),
  hiện dấu vân tay SHA-256 của chứng chỉ lá, dạng hex có dấu `:` như `openssl x509 -fingerprint -sha256`. Trust → lưu; lần sau khác → chặn, câu "The identity of <host>
  changed…" + **Forget Saved Key**.
- Dùng chung cột dấu vân tay đã tin, **đổi tên thành `trustedFingerprint`** ở migration v22 (app chưa phát hành).

## 5. Thư viện

- WebDAV: `URLSession`, không thêm gì.

## 6. Dữ liệu

- `transferProtocol` thêm `webdav`.
- Cột mới `usesTLS` (WebDAV); `hostKeyFingerprint` đổi tên thành `trustedFingerprint` (migration v22). Path của WebDAV dùng cột `share` hiện có
  (cùng vai "gốc bên dưới host").
- Migration thêm cột có mặc định; không đụng `photo_metadata`.

## 7. Riêng tư

- NF-03 §2b ghi thêm: WebDAV qua HTTP gửi mật khẩu và ảnh **không mã hoá**, chỉ khi người dùng tự chọn, có
  cảnh báo §3.
