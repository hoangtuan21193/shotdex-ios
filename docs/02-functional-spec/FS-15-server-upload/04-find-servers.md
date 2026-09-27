# FS-15.04 — Tự tìm server trong mạng, Connect As

`FS-15.04` · `Data/Sources/FileServer/LocalServerBrowser.swift` · `Domain/ServerUpload/DiscoveredServer.swift`
· `Features/ServerUpload/FileServerFormScreen.swift` · cập nhật 2026-09-27

**Một câu:** mở Add Connection là hệ thống hỏi quyền Local Network, form liệt kê các máy đang chia sẻ file trong
cùng mạng; chạm một máy là đăng nhập ngay tại đó (Connect As), rồi chọn folder bằng màn duyệt.

Nguồn: [intent](../../_intents/2026-09-26-server-discovery.md).

## 1. Khi nào tìm

- Chỉ ở form **Add Connection** (Settings và sheet upload). Form **Edit Connection** không tìm — địa chỉ đã có.
- Bắt đầu tìm ngay khi form hiện; đóng form là dừng. Không tìm nền, không tìm ở nơi khác.
- NWBrowser báo "bị từ chối" **ngay khi** hộp Local Network hiện, trước khi người dùng trả lời. Lần từ chối đầu coi là
  "đang hỏi": giữ spinner. App active lại (hộp đóng, hoặc quay về từ Settings) → **tìm lại**; bị từ chối sau lần đó mới
  hiện câu "Local Network access is off" (lỗi 2026-09-27: bấm Allow xong danh sách không tự quét lại).
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

## 3. Chạm một máy — Connect As

Đổi 2026-09-27. Người dùng: "click vào một server có sẵn trong local network thì nên để test connection sau khi nhập
user pass". Trước đây chạm chỉ điền Host/Port rồi để người dùng tự tìm ô Username, Password, Share và Test Connection
ở dưới. Giờ theo Finder ("Connect As…") và Files ("Connect to Server"):

1. Chạm hàng → đẩy màn **Connect to “<tên máy>”** trong form: đầu màn icon loại máy + tên + host; **Name** (điền sẵn
   tên máy, sửa được); **Connect Using** (chỉ khi máy mở nhiều giao thức, thứ tự SMB, SFTP, WebDAV (HTTPS), WebDAV;
   mặc định cái đầu); **Username**, **Password**. Không có câu giải thích (người dùng 2026-09-27: "ai cũng hiểu").
   Nút **Connect** là nút lớn đầy chiều ngang ở đáy màn — cùng kiểu nút **Choose** của bước sau; mờ khi thiếu
   Username/Password. Return ở ô Password cũng là Connect.
2. **Connect** = đăng nhập thật (10 s). Đang nối: spinner trong nút, ô bị khoá. SFTP/WebDAV tự ký lần đầu: hộp Trust
   của FS-15.01 §4 rồi nối tiếp.
3. **Hỏng → báo ngay dưới ô Password**, bằng câu FS-15.01 §3 ("The username or password was rejected.", "Can't reach
   …"); giữ nguyên chữ đã gõ, focus về Password khi sai mật khẩu. Không rời màn.
4. **Được → đẩy màn chọn folder** (FS-17.01 §5) ở gốc: SMB = các folder máy chia sẻ, SFTP = Home. **Choose = lưu
   connection và đóng form** (đổi 2026-09-27: trước đó quay về form đã điền, bắt bấm Save lần nữa — "hơi loạn"). Lưu:
   Name (qua luật đánh số FS-15.01 §3), Protocol, Host = tên `.local` phân giải được hoặc IP với máy tìm bằng quét 445,
   Port, Username, mật khẩu vào Keychain, Folder. Lưu hỏng → hiện form đã điền cùng câu lỗi, không mất gì đã gõ.
   Sửa sau bằng **Edit Connection** (FS-17.01 §1).
5. ‹ ở màn chọn folder về Connect As; ‹ ở Connect As về form không đổi gì. Chân mục Servers Found: "Tap one to sign in."

- Hàng vừa dùng có dấu ✓. Mọi ô vẫn sửa được sau khi điền. Server nhập tay đi thẳng các ô của form như cũ.

## 4. Loại dịch vụ nghe

| Bonjour | Giao thức |
|---|---|
| `_smb._tcp` | SMB |
| `_sftp-ssh._tcp`, `_ssh._tcp` | SFTP (`_ssh` chỉ khi không có `_sftp-ssh` cùng máy) |
| `_webdavs._tcp` | WebDAV qua HTTPS |
| `_webdav._tcp` | WebDAV qua HTTP |
| `_device-info._tcp` | không phải giao thức — chỉ lấy model cho icon |

Tất cả khai trong `NSBonjourServices` của Info.plist; loại không khai thì iOS không trả về.

## 4b. Quét cổng 445 — máy Windows và NAS không bật Bonjour

Windows không quảng bá Bonjour; Finder tìm nó bằng WS-Discovery/NetBIOS — multicast/broadcast, mà iOS chỉ cho khi Apple
cấp entitlement multicast. Người dùng chốt 2026-09-27: **quét unicast**, không xin entitlement.

- Song song với Bonjour, khi form mở: lấy IPv4 + netmask của Wi-Fi (`getifaddrs`), liệt kê các địa chỉ trong dải —
  **tối đa /24** (254 địa chỉ, dải lớn hơn thì chỉ /24 chứa máy này), trừ chính máy này.
- Mở TCP tới cổng **445** từng địa chỉ, tối đa **32** cùng lúc, chờ **1 s**; mở được = có SMB.
- Tên máy: gói **NetBIOS Node Status** unicast tới UDP 137 (RFC 1002 §4.2.18), lấy tên máy (loại `0x20` server, else
  `0x00` workstation, không phải group); không trả lời trong 1 s → hiện **địa chỉ IP**.
- Bỏ địa chỉ đã có trong Bonjour (tên `.local` của Bonjour phân giải ra IP để so) — Mac bật File Sharing chỉ hiện một
  hàng.
- Hàng quét được: icon `pc`, dòng phụ `SMB`; Host điền **địa chỉ IP** (tên NetBIOS không phân giải được qua DNS trên iOS).
- "No servers found" chỉ hiện khi đã hết 5 s **và** quét xong.

## 5. Chọn folder trong form

- Không còn hàng Share (FS-15.01 §3a). Hàng **Folder** có ô gõ tay và nút **Choose…**, bật khi Host, Username, Password
  đã có (mật khẩu đã lưu cũng tính).
- Choose… → đăng nhập, mở màn chọn folder (FS-17.01 §5) ở folder đang gõ (rỗng = gốc). SMB: gốc liệt kê các folder
  máy chia sẻ (bỏ tên kết thúc `$`, như `IPC$`, `ADMIN$`).
- Hỏng (sai mật khẩu, không tới được máy) → câu lỗi FS-15.01 §3 **ngay dưới hàng Folder**, màu đỏ, không mở màn chọn;
  ô vẫn gõ tay được. Sửa Username/Password/Host thì câu lỗi mất.

## 6. Ràng buộc

- Không thư viện mới: Bonjour qua `NWBrowser` (Network framework); folder chia sẻ qua `SMBClient.listShares()`.
- Không đọc tên Wi-Fi (cần quyền vị trí).
- Không gửi gì ra ngoài mạng nội bộ; tìm máy không phải một ngoại lệ mới của NF-03.
- Server qua internet: không tìm được, nhập tay. Windows tìm qua quét cổng 445 (§4b).
