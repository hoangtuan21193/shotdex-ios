# Intent: Chép lên server giữ nguyên ngày và thông tin file (Common Photos, Server Upload, Backup)

| Trường | Giá trị |
|---|---|
| Tác giả | Tuấn (qua Claude) |
| Ngày | 2026-11-05 |
| Trạng thái | accepted (2026-11-05) |
| Tiến độ | **đang làm** (2026-11-05) — task 3/13, 2/34 AC xanh (3 một phần) — plan [2026-11-05-fs1908-6e-dated-organize-fileinfo](../_plans/2026-11-05-fs1908-6e-dated-organize-fileinfo.md) |
| Nguồn | phản hồi người dùng 2026-11-05: "khi move hay copy file sang thư mục share phải keep được thông tin file, k đc đổi ngày edit hay meta data nào cả" |
| Spec sinh ra từ đây | [FS-19.08 §6e](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-193…226 ở [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

Intent anh em: [quét nhanh](2026-11-05-common-photos-dated-folders-scan.md) · [xếp folder đích](2026-11-05-common-photos-destination-layout.md).

## Problem — vấn đề

Ảnh gom vào folder Shared phải là **bản y hệt** bản gốc, không chỉ ở nội dung mà ở cả thông tin file. Người chụp
ảnh sắp và lọc theo ngày sửa trong Finder/Explorer, phần mềm backup và Lightroom cũng dựa vào nó. Hôm nay:

- **Nội dung và metadata trong file (EXIF, XMP nhúng) giữ nguyên** — Same nghĩa là SHA-256 trùng từng byte, và lượt
  chạy kiểm lại bản ở đích (§6).
- **Copy làm đổi ngày sửa (và ngày tạo) ở đích.** Copy đi đường dài: tải về file tạm trên Mac, đẩy lên đích
  (`CommonPhotosRunner.swift:374–384`).
  - SMB: thư viện `SMBClient` đặt ngày cho file đích theo **file tạm** (`FileWriter.restoreFileAttributes`, đọc
    `fstat` của file tạm) → ngày sửa và ngày tạo thành giờ tải về, không phải ngày của ảnh gốc.
  - WebDAV `PUT`: server đặt ngày là giờ ghi.
  - WebDAV `COPY` trên server (`WebDAVFileClient.swift:191`, §6d): tuỳ server — có server giữ, có server không;
    chưa đo.
  - SFTP: chưa xem.
- **Move giữ ngày** khi là đổi tên trên server (`client.move`, `CommonPhotosRunner.swift:528`) — NTFS/ext4 giữ ngày
  sửa khi rename. Chưa xem đường Move khi đổi tên không được (khác share/ổ) và phải chép rồi xoá.
- **`.xmp` sidecar** đi cùng ảnh theo cùng đường → cùng vấn đề.
- **Thuộc tính khác của file** (cờ chỉ-đọc/ẩn của Windows, tag Finder, luồng phụ ADS) không được chép; `RemoteFileClient`
  không có cách đặt ngày hay thuộc tính (`ShotDex/Domain/ServerUpload/RemoteFileClient.swift`).
- **Undo** đưa file về: đi đường Move thì giữ ngày, đường chép thì không.

**Đã đo (2026-11-05):**
- **Copy bằng chính runner + client SMB của app** (server SMB cục bộ impacket, nguồn đặt ngày 2020-01-02 03:04:05,
  một nguồn có tag Finder): 8 ảnh ở đích đều mang **giờ chạy** (2026-11-05 09:21), quyền đổi `rw-r--r--` →
  `rwxr-xr-x`, **tag mất**. Xác nhận đọc code.
- **NAS thật có nhận đặt không** (qua SMB mount của Finder, file tạm trong `Tuan/2026/07/25`, đã xoá): đặt được
  **ngày sửa, ngày tạo, cờ khoá (chỉ-đọc), tag Finder** (NTFS lưu tag dưới dạng luồng phụ). → Phía NAS không cản;
  thiếu là ở app.
- Chưa đo: WebDAV `PUT`/`COPY`, SFTP, đường Move chép-rồi-xoá. Mức độ: cao. Sau một lượt Copy hàng nghìn ảnh, cả folder Shared
mang cùng một ngày sửa — sắp theo ngày vô dụng, và người dùng không tin được bản ở đích là "bản gốc".

## Proposed outcome — kết quả mong muốn

- Sau Copy hay Move, mỗi file ở đích có **cùng ngày sửa** với bản gốc (tới giây), và cùng ngày tạo nếu server có.
- Nội dung giống từng byte như hôm nay — không ghi, sửa hay thêm gì vào EXIF/XMP.
- Sidecar `.xmp` cũng giữ ngày.
- Undo trả file về với đúng ngày cũ.
- Server không cho đặt ngày (một số WebDAV): người dùng được biết trước khi chạy, và CSV log ghi rõ file nào không
  giữ được ngày — không im lặng.
- Bản gốc nào ngày sửa khác nhau giữa các folder (cùng ảnh, ngày khác): rõ là lấy ngày của bản nào.

## Affected users and systems — phạm vi ảnh hưởng

- Tính năng: Find Common Photos — Copy, Move (đường chép rồi xoá), Undo, tự gom, CSV log. Có thể thêm một dòng chữ
  trên sheet/kế hoạch.
- Thiết bị: Mac.
- Tầng: Data (`SMBFileClient`, `WebDAVFileClient`, `SFTPFileClient`, `FilesFolderClient`, `RoutedRemoteFileClient`),
  Domain (`RemoteFileClient` protocol, `CommonPhotosRunner`, `CommonPhotosUndoer`). Protocol dùng chung với Server
  Upload (FS-15) và Backup (FS-22) — hai tính năng đó cũng chép file lên server, có thể cùng vấn đề.
- Dữ liệu đã lưu: không đổi schema bắt buộc; có thể thêm cột "đã giữ ngày" cho log.

## Constraints — ràng buộc

- Không sửa nội dung file để giữ thông tin — SHA-256 bản đích phải bằng bản gốc.
- Luật an toàn Move/Undo (§6, §6b) giữ nguyên; đặt ngày hỏng không được làm lượt chạy coi là hỏng ảnh, nhưng phải
  được ghi lại.
- Không thêm dependency (đổi cách gọi `SMBClient` đã có thì được).
- File có đích sẵn (Already there) không bị đụng — kể cả ngày của nó.

## Open questions — câu hỏi còn treo

1. ~~"Thông tin file" gồm gì?~~ **Đã trả lời (user 2026-11-05): tất cả có thể** — ngày sửa, ngày tạo, cờ Windows
   (chỉ-đọc, ẩn…), tag Finder, luồng phụ ADS; cái nào server/giao thức không cho thì báo, không im lặng.
2. ~~Bản gốc khác ngày giữa hai folder?~~ **Đã trả lời (user 2026-11-05): lấy của bản ở folder đầu.**
3. ~~Có sửa luôn Server Upload và Backup không?~~ **Đã trả lời (user 2026-11-05): gộp vào đây** — sửa chung ở
   `RemoteFileClient` một lần; Server Upload (FS-15) và Backup (FS-22) cùng giữ thông tin file. Phạm vi intent mở
   rộng theo.
4. ~~Đo trên NAS~~ **Đã đo (2026-11-05, Problem):** Copy của app mất ngày/quyền/tag; NAS nhận đặt ngày, cờ, tag.
   Còn WebDAV/SFTP chưa đo — NAS này không bật WebDAV/SFTP? (chưa xem).
5. ~~Ảnh đã gom trước đây có cần lệnh sửa ngày lại không?~~ **Đã trả lời (user 2026-11-05): có** — chỉ đặt lại
   ngày/thuộc tính theo bản gốc, không chép lại.
