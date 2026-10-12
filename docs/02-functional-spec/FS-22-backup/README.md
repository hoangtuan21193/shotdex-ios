# FS-22 — Backup: theo dõi một nguồn, chép bản gốc lên ổ mạng

`FS-22` · tier A · mã: chưa có (đề xuất `ShotDex/Features/Backup/`, `ShotDex/Domain/Backup/`,
`ShotDex/Data/Database/BackupStore.swift`) · test: chưa có (đề xuất `ShotDexTests/Backup*Tests.swift`) · cập nhật 2026-10-12

**Một câu:** Collections › Utilities › **Backup** giữ các job "nguồn → đích"; mỗi job luôn theo dõi nguồn, có file mới
là chép bản gốc đầy đủ lên connection FS-15, ghi sổ từng file nên bị iOS dừng ở đâu thì chạy tiếp từ đó.

Nguồn: [intent 2026-10-12-backup](../../_intents/2026-10-12-backup.md) (accepted, Q1–Q5 đã trả lời).

Board (iPhone, `docs/design/iphone/project/`, luồng 1→5): `PH_Backup` (1/5) · `PH_BackupNew` (2/5) ·
`PH_BackupOrganize` (3/5) · `PH_BackupCustomDate` (4/5) · `PH_BackupRunning` (5/5); lối vào `PH_Collections`.
iPad (`docs/design/ipad/project/`): `IP_Backup` · `IP_BackupNew` · `IP_BackupOrganize` · `IP_BackupCustomDate` ·
`IP_BackupRunning`, lối vào hàng **Backup** đầu Utilities ở sidebar. Duo (`docs/design/duo/project/`): trong `DI_Backup…`,
ngoài `DC_Backup…` (cùng 5 bước), lối vào `DI_Collections` / `DC_Collections`. Mac: ngoài phạm vi FS-22.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Job và Organize](01-jobs-and-organize.md) | danh sách job, tạo/sửa job, nguồn, đích, What to Copy, Organize, tên file, trùng tên |
| 02 | [Chạy và theo dõi](02-running-and-watching.md) | theo dõi liên tục, nền iOS 26 / trước 26, Wi‑Fi, iCloud, dừng/chạy tiếp, trạng thái hiển thị |
| 03 | [Dữ liệu](03-data.md) | bảng job, sổ từng file, mốc thay đổi, dùng lại bảng FS-15/FS-19 |
| 04 | [Tiêu chí nghiệm thu](04-acceptance-criteria.md) | AC-1…AC-30 |

## 1. Người dùng cần gì

- Người chụp muốn **cả** thư viện (hoặc cả một ổ/thư mục) nằm trên NAS ở nhà, theo cây folder họ quen, không phải chọn
  ảnh rồi Upload từng lô.
- Chụp xong, ảnh mới tự lên NAS khi về Wi‑Fi nhà — không lịch, không nút.
- Hàng chục nghìn file, hàng trăm GB: phải biết đã chép tới đâu, và iOS dừng app thì không chép lại từ đầu.

## 2. Phạm vi

**Có:**
- Nguồn: Photos Library, một nguồn thư mục/ổ hoặc server của FS-19. Đích: một connection FS-15 (SMB/SFTP/WebDAV) + folder.
- Bản gốc đầy đủ (ảnh, RAW, video), tải từ iCloud khi cần; tuỳ chọn thêm bản đã sửa.
- Theo dõi liên tục, chạy nền trong giới hạn iOS, sổ từng file sống qua kill/khởi động lại/Clear Local Metadata Index.
- Organize ở đích: mức folder, kiểu tên từng mức, Custom ngày, chỗ đặt Videos, tên file, trùng tên giữ cả hai.

**Cố ý không có:**
- Xoá ở nguồn hay ở đích, đồng bộ hai chiều, mirror (file xoá ở nguồn vẫn nằm ở đích) — *vì Backup chỉ chép; giải phóng
  máy là FS-15.02c.*
- Lịch chạy (giờ cố định) — *vì người dùng chọn theo dõi liên tục.*
- Dịch vụ đám mây mới, dependency mới — *vì ràng buộc intent.*
- Khôi phục từ đích về máy — đã có ở FS-17 (tải, mở ảnh từ server).
- Upload FS-15 giữ nguyên làm việc lô chọn tay; Backup **dùng chung lõi** (connection, ghi `.shotdex-part`, kiểm
  SHA-256, bảng lịch sử upload), không gộp màn.

## 3. Ràng buộc chung

| Mặt | Ràng buộc |
|---|---|
| Bộ nhớ | đọc/ghi theo khối 1 MB, một file tạm một lúc như FS-15.02 §4; video không bao giờ nằm cả trong RAM ([NF-02](../../04-non-functional-design/NF-02-memory.md)) |
| Đĩa | file tạm iCloud xoá ngay sau khi kiểm xong; còn < 2 GB trống thì job chờ, không tải thêm |
| Hiệu năng | so nguồn với sổ cho 55.000 mục ≤ 3 s trên iPhone 17 (một truy vấn, không truy vấn từng mục) ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Dữ liệu người dùng | job và sổ ở bảng riêng, không cột nào trong `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 · Mac |
| iOS 26 vs trước | cùng một bộ màn, cùng trạng thái; chỉ khác cách chạy nền ([02 §3](02-running-and-watching.md#3-chạy-nền)) |
| Truy cập | mỗi hàng job đọc được một câu VoiceOver: tên, trạng thái, tiến độ |

## 4. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Tác vụ xử lý tiếp tục của FS-15.02b có trong spec nhưng chưa có trong code | Backup làm phần dùng chung đó; Upload FS-15 nối vào sau, ngoài FS-22 |
| iOS chọn giờ lượt nền; máy ít sạc thì lượt dài hiếm khi chạy | trạng thái ghi "checked N min ago" thật; chép bù ngay khi mở app |
| Phần mở rộng tải nền Photos là API iOS 26.1, sim có thể không gọi | test giả lập lời gọi; thử trên máy thật trước khi ship |
| Lượt đầu hàng trăm GB tải iCloud | một file tạm một lúc, xoá ngay sau khi kiểm; chờ khi trống trừ cỡ file < 2 GB |
| Photos có thể giữ bản gốc vừa tải trong bộ đệm của nó | iOS tự dọn khi cần chỗ (Optimize Storage); app không xoá được — cần đo trên máy thật với thư viện lớn |
