# FS-15.05 — WebDAV, FTPS, FTP

`FS-15.05` · `Data/Sources/FileServer/WebDAVFileClient.swift` · `FTPFileClient.swift` · `Core/Models/FileServer.swift`
· cập nhật 2026-09-26

**Một câu:** ba giao thức mới đi sau cùng giao thức `RemoteFileClient`, nên upload có kiểm SHA-256, trùng tên,
duyệt folder và tải về (FS-17) chạy y như SMB/SFTP; giao thức không mã hoá thì cảnh báo.

Nguồn: [intent](../../_intents/2026-09-26-more-file-protocols.md). **NFS bị bỏ** (người dùng chốt 2026-09-26).

## 1. Giao thức và ô của form

| Giao thức | Cổng mặc định | Ô riêng | Ghi chú |
|---|---|---|---|
| SMB | 445 | Share | như cũ |
| SFTP | 22 | — | như cũ, host key |
| **WebDAV** | 443 (HTTPS) · 80 (HTTP) | **Path** (đường dẫn gốc, ví dụ `/remote.php/dav/files/me`), công tắc **Use HTTPS** (mặc định bật) | Nextcloud, ownCloud, Synology, QNAP |
| **FTPS** | 21 (explicit) · 990 (implicit) | **TLS Mode**: Explicit (mặc định) / Implicit | chỉ passive (EPSV → PASV) |
| **FTP** | 21 | — | không mã hoá, cảnh báo §3 |

- Picker Protocol liệt kê theo thứ tự trên. Đổi giao thức thì ô riêng đổi theo, cổng để trống là cổng mặc định
  của lựa chọn hiện tại.
- Folder vẫn là đường dẫn tương đối: trong share (SMB), trong home (SFTP), dưới Path (WebDAV), từ thư mục đăng nhập
  (FTP/FTPS).

## 2. Việc từng client phải làm

Cùng một danh sách thao tác `RemoteFileClient` (FS-15.02 §4, FS-15.02 §2a, FS-17):

| Thao tác | WebDAV | FTP/FTPS |
|---|---|---|
| liệt kê file / folder | `PROPFIND` Depth 1 | `MLSD`, không có thì `LIST` |
| kích thước | `PROPFIND` getcontentlength / `HEAD` | `SIZE` |
| tạo folder | `MKCOL` từng cấp | `MKD` từng cấp |
| ghi theo khối từ file | `PUT` stream từ file | `STOR` qua kênh dữ liệu |
| đọc theo khối (checksum, tải về) | `GET` stream | `RETR` stream |
| đọc một đoạn (thumbnail FS-17) | `GET` + `Range` | `REST` + `RETR`, huỷ sau N byte |
| đổi tên `.shotdex-part` → tên thật | `MOVE` + `Overwrite: F` | `RNFR`/`RNTO` |
| xoá | `DELETE` | `DELE` |

- Kiểm SHA-256 bằng đọc lại vẫn bắt buộc (FS-15.02 §4). Server từ chối `Range`/`REST` → tải về vẫn chạy, chỉ
  thumbnail FS-17 phải tải trọn file.
- Đăng nhập WebDAV: Basic hoặc Digest qua `URLCredential`, **không bao giờ** gửi Basic qua HTTP mà chưa cảnh báo.

## 3. Cảnh báo không mã hoá

- Chọn **FTP**, hoặc **WebDAV** tắt Use HTTPS → dưới picker hiện: "Passwords and photos are sent unencrypted. Use
  this only on your home network." (màu cảnh báo của hệ thống, không phải đỏ).
- Không chặn lưu. Không cảnh báo lại mỗi lần upload.

## 4. Chứng chỉ TLS (WebDAV HTTPS, FTPS)

- Chứng chỉ hợp lệ theo hệ thống → không hỏi.
- Chứng chỉ tự ký / không khớp tên (NAS nhà rất hay) → hộp **Trust This Server?** như host key SFTP (FS-15.01 §4),
  hiện dấu vân tay SHA-256 của chứng chỉ lá. Trust → lưu; lần sau khác → chặn, câu "The identity of <host>
  changed…" + **Forget Saved Key**.
- Dùng chung cột dấu vân tay đã tin (`hostKeyFingerprint`) — ⚠️ CẦN QUYẾT: đổi tên cột thành
  `trustedFingerprint` (app chưa phát hành, không cần giữ tương thích).

## 5. Thư viện

- WebDAV: `URLSession`, không thêm gì.
- FTP/FTPS: iOS không còn API FTP. ⚠️ CẦN QUYẾT: thư viện nào — chờ kết quả khảo sát (giấy phép MIT/BSD/Apache,
  iOS 17+, passive, stream, `REST`, TLS kênh dữ liệu có **tái dùng phiên TLS** — vsftpd/FileZilla Server bắt buộc).
  Không có thư viện đạt thì tự viết trên Network framework, và điểm khó nhất là tái dùng phiên TLS ở kênh dữ liệu.

## 6. Dữ liệu

- `transferProtocol` thêm `webdav`, `ftps`, `ftp`.
- Cột mới: `tlsMode` (FTPS: `explicit`/`implicit`), `usesTLS` (WebDAV). Path của WebDAV dùng cột `share` hiện có
  (cùng vai "gốc bên dưới host").
- Migration thêm cột có mặc định; không đụng `photo_metadata`.

## 7. Riêng tư

- NF-03 §2b ghi thêm: FTP và WebDAV qua HTTP gửi mật khẩu và ảnh **không mã hoá**, chỉ khi người dùng tự chọn, có
  cảnh báo §3.
