# FS-22.01 — Job và Organize

`FS-22.01` · board `PH_Backup` (1/5) · `PH_BackupNew` (2/5) · `PH_BackupOrganize` (3/5) · `PH_BackupCustomDate` (4/5)
· cập nhật 2026-10-12

**Một câu:** một job là một nguồn → một đích + cách xếp folder; danh sách job nói mỗi job đang theo dõi, đang chép
hay đang chờ gì.

## 1. Lối vào và danh sách job (1/5)

- Collections › Utilities: ô **Backup** đứng đầu hàng Utilities (board `PH_Collections`).
- Màn **Backup**: mỗi job một thẻ — tên nguồn, connection đích, `<folder> · <What to Copy>`, dòng trạng thái
  ([02 §5](02-running-and-watching.md#5-trạng-thái-hiển-thị)), một nút hành động theo trạng thái (Pause · Resume · Retry).
- Chạm thẻ → màn đang chạy (5/5) của job đó. Vuốt trái / menu ngữ cảnh: **Edit** (mở 2/5 điền sẵn) · **Back Up Now**
  (quét lại nguồn ngay) · **Delete Job** (xác nhận; không xoá file nào ở đích, sổ của job xoá theo).
- Rỗng: một câu "Back up a whole library to your NAS." + nút **New Backup**. Chưa có connection FS-15 nào → nút thành
  **Add a Server**, mở form FS-15.01.
- iPad (regular width): chạm thẻ = **chọn**, chi tiết job (nội dung 5/5) hiện ở cột phải; đầu cột có **Back Up Now** và
  **Edit**; Delete Job ở menu nhấn giữ. Duo trong: hai cột, chạm thẻ vẫn mở 5/5 như iPhone.
- Thư mục đích mặc định theo tên loại máy: `Backup/iPhone`, `Backup/iPad`.
- Dòng chú thích cuối màn giữ câu của board: chép bản gốc đầy đủ, file đã có ở đích bỏ qua, dừng thì làm tiếp.

## 2. New Backup / Edit (2/5)

| Nhóm | Hàng | Luật |
|---|---|---|
| Source | Photos Library · từng nguồn FS-19 · **Folder** (chỉ nguồn FS-19) | một nguồn một job; nguồn offline hiện `Offline`, vẫn chọn được. Nguồn FS-19 phải chọn thư mục bên trong (Back Up the Whole Source hoặc một thư mục con), danh sách lấy từ bản sao FS-19 đã quét nên chọn được cả khi ổ rút |
| Destination | Connection · Folder | connection FS-15; Folder mở màn duyệt FS-15.02 §2a. **Không có thư mục mặc định** (người dùng 12/10): hiện `Choose…` tới khi duyệt và chọn; đổi connection thì chọn lại |
| Organize | một dòng tóm tắt + ví dụ đường dẫn | mở 3/5 |
| What to Copy | Photos & Videos · Photos Only · Videos Only | mặc định Photos & Videos |
| | Include Edited Versions | mặc định tắt (Q4); bật → thêm bản sửa cạnh bản gốc ([§5](#5-tên-file-và-trùng-tên)) |
| Automatic Backup | Only on Wi‑Fi | mặc định **bật** (quyết định 2026-10-12). Chân mục nói rõ không phải chép một lần: sau lượt đầu, ảnh/video mới tự lên server |
| | Only While Charging | mặc định tắt |

- Dòng tóm tắt dưới What to Copy: `<số mục> items · <chưa có trong sổ> not backed up yet · about <GB>` — đếm từ sổ của
  job, không đọc đích. Job mới: "not backed up yet" = tổng.
- **Start** mờ khi thiếu nguồn, thư mục trong nguồn (nguồn FS-19), connection hay folder đích. Start → lưu job, về 1/5, job bắt đầu ngay ([02](02-running-and-watching.md)).
- Một nguồn + một đích + một folder chỉ có một job; trùng → Start báo "This backup already exists." và trỏ tới job đó.
- Edit đổi Organize, tên file hay folder đích: file đã chép **không** bị dời; file mới theo luật mới. Câu dưới nút Save
  nói điều đó. Đổi nguồn hay connection = job mới (hai hàng đó khoá khi Edit).

## 3. Organize — mức folder và kiểu tên (3/5)

Ngày lấy từ ngày chụp (EXIF, không có thì ngày tạo trong Photos / ngày sửa file).

| Levels | Cây |
|---|---|
| Year › Month › Day (mặc định) | `2025/Oct/2025.10.12/` |
| Year › Month | `2025/Oct/` |
| Year › Date | `2025/2025.10.12/` |
| Date Only | `2025.10.12/` |
| Album | tên album Photos / thư mục con của nguồn; mục ở nhiều album → album đầu theo thứ tự Photos; không album → `Unfiled` |
| No Folders | mọi file thẳng vào folder đích |

| Mức | Các kiểu (menu hiện chính ví dụ, không token kiểu yyyy-MM) |
|---|---|
| Year | `2025` · `25` |
| Month | `10` · `2025-10` · `Oct` · `October` · `10月` · `Tháng 10` · Custom… |
| Day | `2025-10-12` · `2025.10.12` · `2025_10_12` · `20251012` · `12` · Custom… |

- Tên tháng chữ theo **ngôn ngữ app**, không theo locale máy NAS. Tên folder không bao giờ chứa `/`.
- **Preview** trên cùng đổi ngay khi chọn (§4).

## 4. Custom ngày (4/5) và Photos and Videos

- Custom…: **Order** Y M D · D M Y · M D Y; **Year** 2025/25; **Month** 10/Oct/October; **Day** 12; **Separator**
  None · `-` · `.` · `_` · Space, hoặc gõ tự do (`" - "`, `年`).
- Ký tự `/ \ : * ? " < > |` bị chặn ngay khi gõ, câu chú thích của board giải thích. Separator rỗng + các phần toàn số
  vẫn hợp lệ (`20251012`). Done mờ khi tên ví dụ rỗng.
- **Videos** và **RAW Files** (người dùng 12/10), mỗi cái chọn riêng: Together · Apart at the Top (`Videos/2025/Oct/…`,
  `RAW/2025/…`) · Apart in Each Year · in Each Month · in Each Day (`2025/Videos/…`, `…/2025.10.12/RAW/`). RAW in Each Day
  = thư mục RAW nằm **trong thư mục ngày của ảnh**. JPEG của cặp RAW+JPEG ở lại với ảnh; bản sửa không vào thư mục RAW.
  Mục chỉ có ở Levels đang chọn; No Folders và Album chỉ có Together · Apart at the Top. Mặc định Videos Apart at the
  Top, RAW Together.
- **Preview** vẽ cây gộp của 3 file mẫu: ảnh (`IMG_8812.HEIC`), RAW của nó (`IMG_8812.CR3`) và một video (`IMG_8813.MOV`).

## 5. Tên file và trùng tên

| File Names | Ví dụ cho `IMG_8812.HEIC` chụp 2025-10-12 14:03:27 |
|---|---|
| Original (mặc định) | `IMG_8812.HEIC` |
| Date and Time | `2025-10-12 14.03.27.HEIC` |
| Date and Original | `2025-10-12 14.03.27 IMG_8812.HEIC` |

- Ảnh nhiều tài nguyên (RAW+JPEG, Live Photo): mọi file cùng một gốc tên, giữ đuôi riêng (`IMG_8812.CR3`, `IMG_8812.JPG`,
  `IMG_8812.MOV`). Bản sửa: `<gốc>_edited.<đuôi>`.
- Dò trùng ở đích theo **tên + cỡ** (Q3): cùng tên cùng số byte = đã có, ghi sổ `found`, không đẩy. Cùng tên khác cỡ =
  file khác → **Keep Both** `<tên> (2).<đuôi>` như FS-15.02 §5. Không bao giờ ghi đè, không bao giờ hỏi.
- File app tự đẩy luôn kiểm SHA-256 bằng đọc lại như FS-15.02 §4 trước khi đổi tên `.shotdex-part` thành tên thật.
