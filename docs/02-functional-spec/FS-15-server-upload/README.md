# FS-15 — Upload lên file server

`FS-15` · tier A (Settings, sheet upload) + B (dấu trên lưới) · `ShotDex/Features/ServerUpload/`
· `Data/Sources/FileServer/` · `Domain/ServerUpload/` · test `ShotDexTests/ServerUpload*Tests.swift`
· cập nhật 2026-09-24

**Một câu:** khai file server SMB/SFTP trong Settings, chọn ảnh → ⋯ → **Upload to Server**, nhận bản gốc
trên server đã kiểm checksum, rồi được hỏi có xoá khỏi máy không.

Nguồn: [intent](../../_intents/2026-09-24-local-network-upload.md).

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Server và Settings](01-servers-and-settings.md) | danh sách server, form, thử kết nối, host key, quyền Local Network |
| 02 | [Luồng upload](02-upload-flow.md) | lối vào, chọn file, đường dẫn, trùng tên, checksum, tiến độ, huỷ, xoá |
| 03 | [Tiêu chí nghiệm thu](03-acceptance-criteria.md) | 16 AC và cái nào chưa chứng minh |

## 1. Người dùng cần gì

Máy đầy vì RAW (25–80 MB một file). Bản lưu lâu dài nằm trên NAS hoặc máy tính. Họ cần chọn ảnh bằng
chính bộ lọc của ShotDex, đẩy **đúng file gốc** lên server, và chỉ xoá khỏi máy những tấm **chắc chắn** đã
nằm nguyên vẹn trên đó.

## 2. Phạm vi

**Có:** SMB 2/3 và SFTP · nhiều server · chọn loại file mỗi lần đẩy · thư mục theo ngày chụp · hỏi khi
trùng tên, có so hai ảnh · kiểm SHA-256 sau khi ghi · hỏi xoá khi xong · hàng **Uploaded to Server** trong
Utilities · dấu trên lưới · lịch sử upload trong Photo Info.

**Cố ý không có:**
- FTP — không mã hoá, và hệ thống đã bỏ FTP khỏi tầng mạng.
- Đẩy từ thẻ nhớ / ổ ngoài — ShotDex đọc thư viện, không quản lý file ([FS-10](../FS-10-import.md)).
- Upload chạy nền — hệ thống chỉ cho vài chục giây; người dùng giữ app mở, màn hình không tự khoá.
- Đăng nhập SFTP bằng khoá SSH — v1 chỉ mật khẩu.
- Tự động đẩy ảnh mới, đồng bộ hai chiều, xoá trên server.

## 3. Hai thư viện mới

| Thư viện | Giao thức | Giấy phép | Vì sao chọn |
|---|---|---|---|
| SMBClient | SMB 2/3 | MIT | Swift thuần, không C; ghi/đọc theo khối từ file |
| Citadel (trên SwiftNIO SSH của Apple) | SFTP | MIT / Apache 2 | SSH viết bằng Swift; có hàm kiểm host key |

- Loại các thư viện bọc libsmb2 / libssh: LGPL, không hợp phân phối qua App Store.
- Cả hai chỉ app chính link; kit và extension không thấy chúng ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)).

## 4. Dữ liệu

| | |
|---|---|
| Bảng server | tên · giao thức · host · cổng · user · share (SMB) · thư mục đích · dấu vân tay host (SFTP) · lần dùng cuối |
| Mật khẩu | **Keychain**, khoá theo id server; không bao giờ vào database hay log |
| Bảng lịch sử upload | id ảnh · id server + **tên server lúc đẩy** · loại file · đường dẫn trên server · số byte · SHA-256 · thời điểm |
| Người dùng tự nhập? | có → **hai bảng riêng**, không cột nào trong bảng metadata ([BD-02](../../01-basic-design/BD-02-database-design.md)) |

- **Xoá một server không xoá lịch sử của nó**: ảnh đã lên đó vẫn là ảnh đã lên server. Vì thế dòng lịch sử
  giữ tên server, và id server được phép rỗng.

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Riêng tư | ngoại lệ thứ hai của [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md): chỉ gửi tới địa chỉ người dùng tự khai |
| Bộ nhớ | đọc/ghi theo khối ≤ 1 MB; **không** giữ cả file trong RAM ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Đĩa | mỗi lần chỉ chép tạm **một** file gốc ra đĩa; xoá ngay sau khi xong, và lúc khởi động |
| Hiệu năng | dấu trên lưới đọc từ **một tập id nạp một lần**, không truy vấn theo ô ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 |
| iOS 26 vs trước | menu ⋯ của chế độ chọn và Settings giống nhau ở cả hai nhánh |
| Truy cập | nhãn VoiceOver cho dấu trên lưới, thanh tiến độ, hai ảnh so trùng |

## 6. Chỗ đã quyết thay người dùng (theo lệnh "plan rồi code auto", 2026-09-24)

- ⚠️ CẦN QUYẾT: **biểu tượng** — hành động và hàng Utilities dùng `server.rack`; dấu trên lưới dùng
  `externaldrive.fill.badge.checkmark`. Hai symbol mới vào từ điển icon của `DESIGN.md` §8.
- ⚠️ CẦN QUYẾT: **Settings** — section **File Servers** đứng sau Export ở bố cục hẹp; ở bố cục rộng nằm trong
  mục **Sharing and Export** (giữ 9 mục để sidebar vừa 669pt).
- ⚠️ CẦN QUYẾT: **ở "chỉ RAW"**, cặp RAW+JPEG chỉ được đề nghị xoá khi JPEG cũng đã có trên một server
  — xoá asset là mất cả hai file.
- ⚠️ CẦN QUYẾT: tên bản đã sửa trên server là `<tên gốc>_edited.<đuôi>`, cùng thư mục với bản gốc.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Không kiểm được trên simulator: tốc độ LAN, hộp quyền Local Network, bản gốc chỉ có trên iCloud | kiểm trên iPhone thật với Mac này (File Sharing + Remote Login) — AC ghi `⚠️ chưa có` tới lúc đó |
| Citadel kéo theo SwiftNIO (~6 gói) | chỉ link vào app chính; build time tăng một lần |
| Mạng rớt giữa file | file đó hỏng, lô dừng, file tạm trên server bị dọn khi kết nối lại được |
| Checksum làm thời gian gần gấp đôi | tiến độ tính cả lượt đọc lại; ETA theo tốc độ đo được |
