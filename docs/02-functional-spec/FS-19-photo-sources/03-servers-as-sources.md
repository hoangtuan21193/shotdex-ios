# FS-19.03 — Server là nguồn được index

`FS-19.03` · board `MAC_SettingsServers` · `MAC_ServerBrowser` · `IP_ServerList` · `IP_ServerForm` · `IP_ServerBrowser`
· dùng lại client SMB/SFTP/WebDAV của [FS-15](../FS-15-server-upload/README.md) · cập nhật 2026-10-04

**Một câu:** trên mọi thiết bị, một connection có thể là **nguồn**: ShotDex đọc folder của nó như một thư mục, thumbnail
lấy từ preview nhúng, bản gốc chỉ tải khi mở, sửa hay xuất (D5). Không còn Import to Library; có **Save to Photos**.

## 1. Connection là nguồn hay chỉ để upload

- Form connection (board `IP_ServerForm`, Mac tương tự) có công tắc **Add as Source** — "Indexed like a folder and listed
  under Sources". Tắt = chỉ là đích upload như hôm nay.
- **Folder** của connection là thứ được index **và** là chỗ upload bắt đầu — "Folder is what ShotDex indexes and where
  uploads start; each upload can pick another."
- Danh sách connection (Settings › Servers trên Mac, File Servers trên iPad, iPhone, Duo), cột Status: **Connected · indexed** · **Upload
  only** · **Not reachable** · **Password rejected**. Chân bảng: "A connection added as a source is indexed like a folder and
  shows under Sources; the others are upload destinations. Passwords are kept in your Keychain. Deleting a connection never
  deletes anything on the server."
- Xoá connection là nguồn = Remove Source ([01b §2](01b-offline-access-and-cache.md)) + xoá connection; không đụng server.
- Quyền Local Network, tìm server gần, Connect As, host key, WebDAV qua HTTP: giữ nguyên FS-15.01, FS-15.04, FS-15.05.

## 2. Index

- Liệt kê đệ quy từ Folder của connection; ẩn file và folder bắt đầu bằng `.`; ghép RAW+JPEG như [01 §3](01-folders-and-drives.md).
- Mỗi file: đọc **256 KB đầu** (đọc theo dải) → EXIF + preview nhúng → thumbnail 400px, theo đúng thang thử của
  [FS-17.01 §3](../FS-17-import-from-server/01-browse.md) (CR3 tách hộp preview, RAF theo con trỏ, tối đa 1 MB với RAW khác).
- **Hash nhanh** trong lượt này (3 lần đọc dải 64 KB, [02 §1](02-identity-and-sidecars.md)); hash đầy đủ ở nền sau đó,
  tải từng file rồi bỏ byte. NAS 1.102 ảnh ~33 GB: ~5 phút ở gigabit, hàng giờ qua Wi-Fi chậm.
- **Một lệnh tới server một lúc** mỗi connection (phiên SMB không an toàn khi chạy song song — FS-17.01 §3).
- Sidecar `.xmp` cạnh file trên share được đọc trong cùng lượt ([02 §4](02-identity-and-sidecars.md)).
- Mạng: theo luật index ([BD-03.03 §2](../../01-basic-design/BD-03-metadata-indexing-flow/03-network-thermal-and-gate.md)) —
  iPad có SIM, iPhone, Duo chỉ dùng dữ liệu di động khi bật **Use Cellular Data for Indexing**.

## 3. Thấy thay đổi trên server

- SMB/SFTP/WebDAV không báo thay đổi đáng tin, nên ShotDex **so lại danh sách** (kích thước + ngày sửa):
  khi mở app · khi server từ "Not reachable" về lại · khi bấm **Rescan** (toolbar màn duyệt, board `MAC_ServerBrowser`).
- **Không** quét theo giờ khi app đang mở — chỉ ba lúc trên. *Vì* mỗi lượt so là một lệnh liệt kê cả cây trên NAS.
- File đổi tên/chuyển trên server: hash giữ danh tính như [02 §2](02-identity-and-sidecars.md).

## 4. Duyệt nguồn server

- Chạm nguồn server ở sidebar → màn duyệt kiểu Files (FS-17.01 §2): đường dẫn, ‹ ›, Icons/List, Sort By, New Folder,
  **Rescan**, **Upload…**, chân "1 folder · 36 photos · 2 other files hidden" và "15.21 GB free of 152.09 GB".
- Ảnh trong màn duyệt là **ảnh của thư viện**: cùng ô, cùng glyph sao/cờ, cùng menu như ở All Photos.
- **Không có Import to Library** ở thiết bị nào (D5). Ai cần ảnh trong Photos dùng **Save to Photos** — một lệnh **xuất**
  (menu Share/Export, như xuất ảnh đã sửa): chép bản gốc vào Photos. Asset mới là một bản sao của **cùng ảnh** khi băm
  xong ([02 §1b](02-identity-and-sidecars.md)) — số ảnh trong thư viện không tăng.
- Rename theo FS-17.01 §4b (đường dẫn bản sao đổi theo, hash giữ danh tính). **Delete không có** — D6, chỉ Hide ([04](04-deleting-and-duplicates.md)).
- Tìm, lọc, thống kê chạy trên ảnh server như mọi nguồn — từ dữ liệu đã index, **không** hỏi server.

## 5. Thumbnail và bản gốc

- Thumbnail và preview của server nằm trong **cache chung** của mọi nguồn ([01b §5](01b-offline-access-and-cache.md)) —
  không có pane Server Thumbnails riêng. Chân mục cache: "Originals are never stored here; they download when you open,
  edit or export a photo."
- Thumbnail bị bỏ vì vượt trần → khi server tắt, ô đó xám + nhãn định dạng; dựng lại ở lượt so sau khi server về.
- **Bản gốc** tải vào thư mục tạm khi: mở xem đầy đủ, Edit, Export, Share, kéo ra ngoài, Combine/Collage/Video. Viewer
  hiện preview cache ngay, đổi sang bản gốc khi tải xong. Rời viewer/editor → xoá bản tạm (dọn lúc khởi động như NF-02 §2).
- Kiểm chỗ trống trước khi tải; RAW > 25 MB có tiến độ và Cancel.

## 6. Server không với tới

- Nguồn chuyển Offline: "NAS Home isn't reachable · Its 1,102 photos stay in your library with saved previews." + **Try
  Again**. Ảnh ở lại, như ổ rút ra ([01b §2](01b-offline-access-and-cache.md)): lọc, chấm sao được, Edit/Export mờ.
- Mở ảnh khi server tắt: preview cache + câu "NAS Home isn't reachable. Showing the saved preview." Không có preview → ô
  xám, không lỗi bật lên.
- **Password rejected**: không hỏi lại mật khẩu mỗi lần thử; hàng nguồn ghi trạng thái + **Edit Connection…**.
- Lượt index đang chạy mà server rớt: dừng ở file đang đọc, giữ phần đã xong, chạy tiếp khi server về.

## 7. Sửa ảnh trên server-nguồn

- Mọi thiết bị: recipe **tự lưu** như ảnh thư mục (D16, [02 §8](02-identity-and-sidecars.md)); Export tạo file mới.
- Thay [FS-17.06](../FS-17-import-from-server/06-edit-and-export.md) (không giữ nháp, hỏi nơi lưu khi xuất) trên iPhone và Duo.
- Rating/keyword ghi sidecar **lên share** (cần quyền ghi; không có thì như [02 §5](02-identity-and-sidecars.md), ca chỉ đọc).
  Đây là dữ liệu rời máy tới server của người dùng — NF-03 §2b phải thêm dòng này.

## 8. Upload vẫn còn

- Upload ([FS-15](../FS-15-server-upload/README.md)) giữ nguyên, kể cả chạy nền, kiểm SHA-256, Free Up Space.
- Đẩy vào một folder nằm trong nguồn server → file vừa kiểm checksum **vào thư viện ngay** (đã biết byte), không chờ lượt so.
- Ảnh Photos có tham gia hash ([02 §1b](02-identity-and-sidecars.md)), nên file vừa đẩy lên là **bản sao** của ảnh đó:
  số ảnh không tăng. Free Up Space xoá khỏi Photos thì ảnh **vẫn ở thư viện** qua bản sao NAS; câu xác nhận thêm
  "They stay in ShotDex from NAS Home."

## 9. iPhone và Duo

- Như iPad: connection là nguồn hoặc chỉ để upload; nguồn server hiện trong nhóm Sources (chỗ theo board `PH_*` /
  `DI_*` / `DC_*`, chưa vẽ). Collections › Utilities › Local Network / Cloud Folders mở **Connect to Server…** / thêm
  thư mục, không còn màn duyệt-rồi-nhập.
- Upload theo FS-15 giữ nguyên. FS-17 sửa theo: Import to Library bỏ, sửa và xuất theo §7 — AC của nó đổi cùng lượt.
