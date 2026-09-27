# FS-17 — Tải ảnh từ file server về thư viện

`FS-17` · tier B (lưới ảnh server) + A (sheet tải về, danh sách connection) · `ShotDex/Features/ServerImport/`
· `Domain/ServerImport/` · `Data/Sources/FileServer/` · test `ShotDexTests/ServerImport*Tests.swift`
· cập nhật 2026-09-26

**Một câu:** Collections → Utilities → **On Server** → chọn connection → duyệt folder như lưới Library (chỉ file
ảnh, thumbnail thật) → chọn nhiều → **Import to Library** (chỉ thư viện, album có sẵn, hoặc album mới), RAW+JPEG gộp một ảnh, giữ ngày chụp,
kiểm file trước khi ghi vào Photos.

Nguồn: [intent](../../_intents/2026-09-26-import-from-server.md). Chiều ngược của
[FS-15](../FS-15-server-upload/README.md), dùng chung connection và client.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Duyệt ảnh trên server](01-browse.md) | lối vào, danh sách connection, lưới ảnh, thumbnail, cache, chọn nhiều |
| 02 | [Tải về thư viện](02-download.md) | đích, ghép cặp, kiểm file, ngày chụp, "đã có", tiến độ, lỗi |
| 03 | [Tiêu chí nghiệm thu](03-acceptance-criteria.md) | AC-1…30 (AC-18 từ lỗi 2026-09-27) |
| 04 | [Folder trong Collections (Network)](04-network-shortcuts.md) | thêm folder thành ô, mục Network, bìa lưu trên máy, AC-31…40 |
| 05 | [On Local Network, On Cloud](05-cloud-folders.md) | tách Utilities, folder Dropbox/Google Drive… qua app Files, duyệt + upload, AC-45…51 |

## 1. Người dùng cần gì

Kho ảnh (RAW nặng, và JPEG, HEIC, TIFF, PNG…) nằm trên NAS/Mac. Họ muốn **nhìn thấy ảnh** trên server từ điện
thoại, chọn vài tấm, lấy về Photos đúng như ảnh chụp từ máy ảnh — một ảnh cho cặp RAW+JPEG, đúng ngày chụp —
rồi sửa trong ShotDex.

## 2. Phạm vi

**Có:** mọi giao thức của FS-15 (SMB, SFTP, WebDAV) · mọi định dạng ảnh iOS đọc được · lưới có
thumbnail từ preview nhúng · folder con · chọn nhiều, chọn tất cả · tải vào Library hoặc album (có sẵn / mới) ·
gộp RAW + JPEG/HEIC · giữ ngày chụp · dấu "In Library" · kiểm file · tiến độ, huỷ, giữ màn hình sáng.

**Cố ý không có:** video (v1 chỉ ảnh) · tải nền · đồng bộ hai chiều · xoá/đổi tên/chuyển file trên server từ màn
duyệt · tìm kiếm trong server · sắp theo EXIF mà không đọc file (Date Taken phải đọc đoạn đầu của cả folder).

## 3. Quan hệ với FS-10 (Import đã bỏ)

FS-10 bỏ màn Import vì ShotDex **đọc** thư viện chứ không quản lý file, và bác lối Import ở ⋯ Library và
Collections. Người dùng chốt lại 2026-09-26: tải từ server là ngoại lệ, đặt trong **Utilities** — cùng chỗ với
"ảnh đã upload" — không thêm nút hay tab mới. Ảnh vẫn chỉ vào **thư viện hệ thống** qua PhotoKit; ShotDex không có
kho riêng. FS-10 ghi thêm dòng ngoại lệ này.

## 4. Dữ liệu

| | |
|---|---|
| Bảng lịch sử tải về (mới) | id asset tạo ra · id connection + tên lúc tải · đường dẫn trên server · số byte · SHA-256 · thời điểm |
| Vì sao bảng riêng | dữ liệu do người dùng tạo ra → không vào `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| "In Library" | file (connection, đường dẫn, số byte) có dòng trong lịch sử **upload** (FS-15) hoặc **tải về**, và asset của dòng đó còn trong thư viện |
| Cache thumbnail | thư mục Caches của app, khoá = connection + đường dẫn + số byte + ngày sửa; trần 500 MB, cũ nhất ra trước |

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Mạng | thumbnail đọc **một đoạn đầu file** (range read), không tải trọn RAW để xem lưới |
| Bộ nhớ | không giải mã full-res để làm thumbnail; tải theo khối ≤ 1 MB, không giữ cả file trong RAM (NF-02) |
| Đĩa | mỗi lần chép tạm **một ảnh** (cặp RAW+JPEG là một ảnh); kiểm chỗ trống trước khi tải |
| Riêng tư | chỉ nhận dữ liệu; NF-03 §2b ghi thêm |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678; lưới theo luật màn rộng (nhiều ô hơn, không ô to hơn) |
| iOS 26 vs trước | chế độ chọn và toolbar giống nhau hai nhánh |
| Truy cập | nhãn VoiceOver mỗi ô: tên file, định dạng, "In Library", đã chọn |

## 6. Chỗ đã quyết thay người dùng (theo lệnh "tự động làm spec và plan", 2026-09-26)

- **Chốt (người dùng 2026-09-26):** thẻ **On Server** ở Utilities **luôn hiện**. Mở ra: danh sách connection + hàng
  **Uploaded from This Device**; chưa có connection thì màn trống có nút **Add Connection**.
- **Chốt (người dùng 2026-09-26): kiểm file** — SHA-256 chỉ so được khi đã biết (file từng upload qua ShotDex, có trong lịch sử).
  Các file khác: kiểm **số byte khớp server** + ImageIO **mở được** file. Đọc file hai lần để có SHA thật thì gấp
  đôi thời gian — không làm.
- ⚠️ CẦN QUYẾT: chạm một ô (không ở chế độ chọn) → xem lớn bằng preview nhúng, có nút Download cho riêng tấm đó.
- **Chốt (người dùng 2026-09-26):** sắp mặc định theo **tên file**; menu Sort có Name · Date Taken · Date Modified,
  Ascending/Descending (FS-17.01 §2).

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Preview nhúng nằm sâu trong file ở một số dòng RAW | đo theo hãng bằng file mẫu (spike trong plan); không lấy được trong đoạn đầu → tải trọn nếu ≤ giới hạn, không thì ô chỉ có icon định dạng |
| CR3: ImageIO **không** đọc được thumbnail từ đoạn đầu (đo 2026-09-26: 4 MB vẫn không) | tự tách JPEG trong hộp `PRVW` (1620×1080, nằm trọn trong 274 KB đầu của file mẫu) |
| Photos từ chối một số định dạng khi ghi (WebP, AVIF, GIF động?) | báo lỗi theo file, lô đi tiếp; đo trong plan |
| Quyền `.limited` | tạo ảnh được; danh sách album có thể thiếu → nói rõ trong sheet |
| Folder hàng nghìn file | liệt kê một lần, lưới lazy, thumbnail chỉ cho ô sắp hiện, tối đa 4 luồng |
