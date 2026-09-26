# FS-15.04 — Tự tìm server trong mạng, chọn share

`FS-15.04` · `Data/Sources/FileServer/LocalServerBrowser.swift` · `Domain/ServerUpload/DiscoveredServer.swift`
· `Features/ServerUpload/FileServerFormScreen.swift` · cập nhật 2026-09-26

**Một câu:** mở Add Connection là hệ thống hỏi quyền Local Network, form liệt kê các máy đang chia sẻ file trong
cùng mạng; chạm một máy là địa chỉ được điền sẵn, và share SMB chọn từ danh sách thay vì gõ.

Nguồn: [intent](../../_intents/2026-09-26-server-discovery.md).

## 1. Khi nào tìm

- Chỉ ở form **Add Connection** (Settings và sheet upload). Form **Edit Connection** không tìm — địa chỉ đã có.
- Bắt đầu tìm ngay khi form hiện; đóng form là dừng. Không tìm nền, không tìm ở nơi khác.
- Lần đầu tìm là lúc hệ thống bật hộp **Local Network** (FS-15.01 §5 đổi theo: hỏi khi mở Add Connection, không
  còn đợi Test Connection). Câu giải thích trong hộp là `NSLocalNetworkUsageDescription` hiện có.

## 2. Mục "Servers Found on This Network"

Section đầu tiên của form, trên các ô nhập tay.

| Trạng thái | Hiển thị |
|---|---|
| đang tìm, chưa thấy gì | một hàng spinner "Looking for servers…" |
| thấy máy | mỗi máy một hàng: icon loại máy · tên máy · giao thức nó mở (`SMB · SFTP`); spinner nhỏ ở tiêu đề khi còn tìm |
| 5 s không thấy gì | "No servers found. Enter the address below." |
| quyền Local Network bị từ chối | "ShotDex can't look for servers because Local Network access is off." + nút **Open Settings** |

- Chân section: "Computers and NAS drives sharing files on the same network as this device. Tap one to fill in its
  address." — câu này là thứ nói cho người dùng biết danh sách là **máy app vừa tìm thấy trong mạng nội bộ**.
- Icon theo `_device-info._tcp` (model): MacBook → `laptopcomputer`, Mac để bàn → `desktopcomputer`, NAS/không rõ →
  `externaldrive.connected.to.line.below`.
- Máy nghe nhiều dịch vụ gộp thành **một hàng** (khoá: tên dịch vụ Bonjour). Máy biến mất khỏi mạng thì hàng
  biến mất.
- Sắp xếp theo tên. Tên máy lấy từ tên dịch vụ Bonjour ("Hoang's MacBook Pro").

## 3. Chạm một máy

- Một giao thức → điền luôn. Nhiều giao thức → menu chọn giao thức (thứ tự: SMB, SFTP, WebDAV (HTTPS), WebDAV).
- Điền: **Name** = tên máy (vẫn qua luật đánh số trùng tên, FS-15.01 §3), **Protocol**, **Host** = tên `.local`
  phân giải được (không lưu IP), **Port** = cổng trong bản ghi dịch vụ (để trống nếu bằng cổng mặc định).
- Hàng vừa chọn có dấu ✓. Người dùng vẫn sửa được mọi ô sau khi điền.
- ⚠️ CẦN QUYẾT: nhiều giao thức thì hỏi bằng menu (đề xuất) hay mỗi giao thức một hàng riêng.

## 4. Loại dịch vụ nghe

| Bonjour | Giao thức |
|---|---|
| `_smb._tcp` | SMB |
| `_sftp-ssh._tcp`, `_ssh._tcp` | SFTP (`_ssh` chỉ khi không có `_sftp-ssh` cùng máy) |
| `_webdavs._tcp` | WebDAV qua HTTPS |
| `_webdav._tcp` | WebDAV qua HTTP |
| `_device-info._tcp` | không phải giao thức — chỉ lấy model cho icon |

Tất cả khai trong `NSBonjourServices` của Info.plist; loại không khai thì iOS không trả về.

## 5. Chọn share (SMB)

- Hàng **Share** có nút **Choose…**, bật khi Host, Username, Password đã có.
- Chạm → đăng nhập, lấy danh sách share của máy, hiện dạng danh sách; bỏ share hệ thống (tên kết thúc bằng `$`,
  như `IPC$`, `ADMIN$`). Chọn một share → điền ô Share.
- Hỏng (sai mật khẩu, không tới được máy) → câu lỗi của FS-15.01 §3 ngay dưới hàng Share; ô vẫn gõ tay được.
- Folder chọn bằng màn duyệt của FS-15.02 §2a (sheet upload); form vẫn giữ ô Folder gõ tay.

## 6. Ràng buộc

- Không thư viện mới: Bonjour qua `NWBrowser` (Network framework); share qua `SMBClient.listShares()`.
- Không đọc tên Wi-Fi (cần quyền vị trí).
- Không gửi gì ra ngoài mạng nội bộ; tìm máy không phải một ngoại lệ mới của NF-03.
- Windows (NetBIOS/WS-Discovery) và server qua internet: không tìm được, nhập tay.
