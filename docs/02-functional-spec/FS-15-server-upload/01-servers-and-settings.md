# FS-15.01 — Server và Settings

`FS-15.01` · `Features/ServerUpload/FileServerListScreen.swift` · `FileServerFormScreen.swift`
· `Data/Database/FileServerStore.swift` · `Domain/ServerUpload/FileServerNaming.swift` · cập nhật 2026-09-27

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
| có connection | mỗi hàng: **tên** và dưới nó **đường dẫn folder** (`PHOTOS/Import`; SFTP `Home/…`) — không giao thức, không host (đổi 2026-09-27: tên + folder là thứ phân biệt hai connection); chạm để sửa, vuốt để xoá |

- Nút **+** trên toolbar thêm connection (nhãn VoiceOver "Add Connection").
- Xoá connection (**Delete Connection**): hộp xác nhận có nút Huỷ; câu nói rõ **lịch sử upload vẫn giữ**, ảnh không bị đụng.

## 3. Form connection

| Ô | Mặc định | Luật |
|---|---|---|
| Name | host | không bắt buộc; bỏ trống thì lấy host. Trùng tên connection khác (không phân biệt hoa thường) thì thêm ` (2)`, ` (3)`… lúc lưu |
| Protocol | SMB | SMB / SFTP / WebDAV ([FS-15.05](05-more-protocols.md)); đổi giao thức thì cổng mặc định đổi theo nếu người dùng chưa gõ cổng |
| Host | — | bắt buộc; tên, IPv4 hoặc tên `.local` |
| Port | 445 (SMB) · 22 (SFTP) | 1–65535 |
| Username / Password | — | mật khẩu che, lưu Keychain |
| Folder | SMB: bắt buộc · SFTP: rỗng = home · WebDAV: rỗng = gốc Path | folder **mặc định**; sheet upload đổi được mỗi lần. Đường dẫn tương đối, dấu `/` thừa bị bỏ. Nút **Choose…** mở màn chọn folder (FS-17.01 §5). SMB: cấp đầu là một folder máy tính chia sẻ (`Photos/2024`) — không còn ô Share riêng (§3a) |

- Tiêu đề form: **Add Connection** / **Edit Connection**. Chân section Folder không nhắc thư mục theo ngày — đó là
  công tắc ở sheet upload.
- **Save** mờ khi thiếu ô bắt buộc. Lưu **không** bắt buộc thử kết nối trước — server có thể đang tắt.
- Hàng **Test Connection** chạy bốn bước và dừng ở bước hỏng đầu tiên: tìm thấy máy → đăng nhập → mở thư
  mục → ghi thử rồi xoá một file nhỏ.

| Hỏng ở | Câu báo |
|---|---|
| tìm máy / hết giờ 10 s | "Can't reach <host>. Check that it's on and on the same network." |
| đăng nhập | "The username or password was rejected." |
| thư mục | "The folder <path> doesn't exist on the server." |
| ghi thử | "You don't have permission to write to <path>." |
| quyền Local Network bị tắt | "ShotDex needs Local Network access." + nút mở Settings của hệ thống |
| xong | "Connected. Ready to upload." |

## 3a. Không còn "Share"

Đổi 2026-09-27. Người dùng: "mục share hơi khó hiểu, nó khác gì folder". Share của SMB là **folder cấp đầu mà máy
tính chia sẻ ra** (`Photos` trên Windows); Folder là đường dẫn bên trong nó. Hai ô cho một đường dẫn là hai khái niệm
người dùng phải học, trong khi Files và Finder cho thấy share như folder bình thường.

- Form SMB chỉ có **Folder**; `Photos/2024` nghĩa là share `Photos`, folder `2024`. Chân section SMB: "Choose… signs
  in and shows the folders this computer shares."
- Dữ liệu: connection SMB lưu `share` rỗng, cả đường dẫn trong `folder` / `uploadFolder`. Migration v23 gộp các dòng
  cũ: `folder = share/folder`, `uploadFolder = share/uploadFolder`, đường dẫn trong lịch sử upload và tải về của
  connection SMB đó được thêm `share/` ở đầu (để dấu In Library và luật xoá vẫn khớp).
- Client SMB coi cấp đầu của mọi đường dẫn là share: liệt kê gốc = danh sách share hiện được (bỏ share tên kết thúc
  `$`), mở share khi cần, đổi share trong cùng phiên đăng nhập. Ghi file ở gốc: không được.
- WebDAV giữ ô **Path** (địa chỉ WebDAV như `remote.php/dav/files/you` là một phần của URL, không duyệt được từ gốc).

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
