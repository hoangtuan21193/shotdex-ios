# FS-15.01 — Server và Settings

`FS-15.01` · `Features/ServerUpload/FileServerListScreen.swift` · `FileServerFormScreen.swift`
· `Data/Database/FileServerStore.swift` · `Domain/ServerUpload/FileServerNaming.swift` · cập nhật 2026-09-26

**Một câu:** danh sách connection trong Settings, form khai một connection, và nút thử kết nối nói rõ chỗ hỏng.

**Connection** = một dòng đã khai: một server + tài khoản + folder mặc định, có **tên riêng**. Cùng một server
thêm được nhiều lần (ví dụ "NAS – RAW" và "NAS – Phone", khác folder hoặc khác user); tên là thứ phân biệt
chúng ở menu ⋯ (FS-15.02 §1).

## 1. Lối vào

- Bố cục hẹp: section **File Servers** ngay sau **Export**, một hàng **File Servers** kèm số server
  (`None` khi chưa có) mở danh sách.
- Bố cục rộng: cùng hàng đó nằm trong mục **Sharing and Export**. Sidebar giữ 9 mục.
- Search của Settings tìm được hàng này bằng "server", "SMB", "SFTP", "NAS".

## 2. Danh sách connection

| Trạng thái | Hiển thị |
|---|---|
| rỗng | câu "Add a connection to upload originals to your NAS or computer." + nút **Add Connection** |
| có connection | mỗi hàng: tên · `SMB` hoặc `SFTP` · `host/đường dẫn`; chạm để sửa, vuốt để xoá |

- Nút **+** trên toolbar thêm connection (nhãn VoiceOver "Add Connection").
- Xoá connection (**Delete Connection**): hộp xác nhận có nút Huỷ; câu nói rõ **lịch sử upload vẫn giữ**, ảnh không bị đụng.

## 3. Form connection

| Ô | Mặc định | Luật |
|---|---|---|
| Name | host | không bắt buộc; bỏ trống thì lấy host. Trùng tên connection khác (không phân biệt hoa thường) thì thêm ` (2)`, ` (3)`… lúc lưu |
| Protocol | SMB | SMB / SFTP / WebDAV / FTPS / FTP ([FS-15.05](05-more-protocols.md)); đổi giao thức thì cổng mặc định đổi theo nếu người dùng chưa gõ cổng |
| Host | — | bắt buộc; tên, IPv4 hoặc tên `.local` |
| Port | 445 (SMB) · 22 (SFTP) | 1–65535 |
| Username / Password | — | mật khẩu che, lưu Keychain |
| Share | — | **chỉ SMB**, bắt buộc |
| Folder | rỗng = gốc share / thư mục home | folder **mặc định**; sheet upload đổi được mỗi lần. Đường dẫn tương đối, dấu `/` thừa bị bỏ |

- Tiêu đề form: **Add Connection** / **Edit Connection**. Chân section Folder không nhắc thư mục theo ngày — đó là
  công tắc ở sheet upload.
- **Save** mờ khi thiếu ô bắt buộc. Lưu **không** bắt buộc thử kết nối trước — server có thể đang tắt.
- Hàng **Test Connection** chạy bốn bước và dừng ở bước hỏng đầu tiên: tìm thấy máy → đăng nhập → mở thư
  mục → ghi thử rồi xoá một file nhỏ.

| Hỏng ở | Câu báo |
|---|---|
| tìm máy / hết giờ 10 s | "Can't reach <host>. Check that it's on and on the same network." |
| đăng nhập | "The username or password was rejected." |
| thư mục | "The folder <path> doesn't exist on <share>." |
| ghi thử | "You don't have permission to write to <path>." |
| quyền Local Network bị tắt | "ShotDex needs Local Network access." + nút mở Settings của hệ thống |
| xong | "Connected. Ready to upload." |

## 4. Host key (SFTP)

- Lần nối đầu, hệ thống SSH trả dấu vân tay host (SHA-256, dạng `SHA256:<base64>`). App hiện hộp
  "Trust this server?" với dấu vân tay và **Trust** / **Cancel**. Trust thì lưu vào server.
- Lần sau khớp thì im lặng. **Lệch thì chặn** mọi kết nối: "The identity of <host> changed. If you didn't
  reinstall the server, someone may be intercepting the connection." + nút **Forget Saved Key** (có xác nhận).
- Sửa host hoặc cổng trong form thì xoá dấu vân tay đã lưu.

## 5. Quyền Local Network

- Khai lý do dùng trong Info.plist. Hệ thống hỏi **khi mở form Add Connection**, vì form bắt đầu tìm server
  trong mạng ngay lúc đó ([FS-15.04](04-find-servers.md)) — không phải lúc mở app, cũng không đợi tới Test Connection.
- Server ngoài LAN (qua internet) không cần quyền này, và không bị chặn.
