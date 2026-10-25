# Intent: Smart album "đã có trên NAS" — kiểm cả thư viện, chạy nền, làm tiếp được

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-10-24 |
| Trạng thái | accepted (2026-10-25) |
| Tiến độ | **đang làm** (2026-10-26) — task 10/22 (T0 board, T1 khoá connection, T2 test rename, T3 bảng file gốc + SHA từ sổ Backup, T4 SHA bản sao server từ sổ Backup, T5 băm server theo cỡ, T6 băm Photos theo cỡ, T7 truy vấn đủ file gốc, T8 Folder + chip tên, T9 cổng chạy + chạy khi về trước mặt), 13/33 AC xanh trọn (AC-75, 76, 77, 78, 79, 81, 82, 84, 86, 94, 97, 100, 101; AC-74 trừ so board, AC-80 trừ dòng chữ, AC-83 trừ dòng chữ, AC-85 phần hash, AC-99 trừ dòng chữ); plan [2026-10-25-fs1907-on-server-check](../_plans/2026-10-25-fs1907-on-server-check.md) |
| Nguồn | phản hồi người dùng (2026-10-24, review giải pháp "ảnh gia đình" trong phiên) |
| Spec sinh ra từ đây | [FS-19.07](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md) · [07b](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md) |

## Bối cảnh

Hai vợ chồng, hai Apple Account, cùng chụp ảnh con; ảnh gửi qua lại nên trùng ở hai thư viện iCloud, và **iCloud đã
đầy**. Kế hoạch của người dùng:

1. Trên NAS có folder gốc (ví dụ `iCloud Photo/`) với ba folder thật `Tuấn/`, `Vợ/`, `Shared/`.
2. Mỗi iPhone dùng Backup của ShotDex (FS-22) chép bản gốc vào folder của người đó.
3. **Một script riêng của người dùng, không phải ShotDex**, tìm ảnh trùng giữa hai folder và dời/gộp chúng vào `Shared/`.
4. Trên mỗi iPhone, một smart album gom những ảnh **đã có trên một folder NAS chỉ định** (ví dụ `Shared/`) → xoá trên
   máy để giải phóng iCloud, an toàn vì bản gốc đã nằm trên NAS.
5. Khi iCloud có chỗ: tạo iCloud Shared Library, đưa ảnh từ `Shared/` về.

Intent này **chỉ** là bước 4. Bước 1–2 đã có (FS-22, mỗi máy một job vào folder riêng). Bước 3 nằm ngoài ShotDex.
Bước 5 (đưa ảnh từ NAS về Photos vào một album, giữ cặp Live Photo) là intent riêng:
[2026-10-24-restore-from-nas-to-album](2026-10-24-restore-from-nas-to-album.md).

## Problem — vấn đề

Hôm nay người dùng **không biết được ảnh nào trên iPhone đã có bản trên một folder NAS cụ thể**, nên không xoá được gì
mà vẫn chắc chắn không mất ảnh.

- Backup (FS-22) biết file **nó** đã chép lên đâu, nhưng script của người dùng sẽ dời và đổi tên file trên NAS
  (`Tuấn/…` → `Shared/…`). Sổ Backup lúc đó chỉ sai chỗ: nó nói "đã ở `Tuấn/2025/…`", NAS không còn file đó ở đấy.
- Ảnh có thể lên NAS bằng con đường khác ShotDex (máy kia chép, script gộp, chép tay) — ShotDex không biết.
- Smart album có điều kiện **Source** (FS-19), nhưng chỉ theo cả nguồn, và ảnh Photos chưa bao giờ được băm (bước băm
  có code nhưng chưa nối) nên ảnh Photos không gộp được với file NAS — điều kiện đó chưa trả lời được câu hỏi này
  (sửa 2026-10-25 khi viết spec; bản đầu ghi nhầm là không có điều kiện nào về server).
- Free Up Space (FS-15.02c) chỉ tính theo lịch sử upload của chính máy, không theo hiện trạng NAS.
- Số lượng lớn: hàng chục nghìn ảnh, hàng trăm GB. Kiểm một lượt mất hàng giờ qua Wi‑Fi; iOS sẽ dừng app giữa chừng
  nhiều lần. Kiểm lại từ đầu mỗi lần là không dùng được.
- iCloud đầy + Optimize Storage: phần lớn bản gốc không nằm trên máy, phải tải về mới băm được.

Mức độ: chặn cả kế hoạch giải phóng iCloud của gia đình; xoá nhầm ảnh con là mất hẳn sau 30 ngày.

## Proposed outcome — kết quả mong muốn

1. Trong Smart Album editor có điều kiện mới: **On Server** — chọn một connection FS-15 + một folder (gồm mọi folder con),
   toán tử **is / is not**. "is" = mọi file gốc của ảnh/video đều có trên folder đó; "is not" = ít nhất một file chưa có
   (để thấy cái gì chưa lên NAS).
2. "Có trên NAS" nghĩa là **cùng nội dung (SHA-256)**, bất kể tên file, đường dẫn hay ai chép lên — script dời hay đổi
   tên file thì ảnh vẫn được nhận ra.
3. **Đủ mọi file gốc** mới tính: Live Photo cần cả ảnh lẫn video đi kèm, RAW+JPEG cần cả hai. Thiếu một file thì ảnh không
   vào "is". Chỉ so bản gốc, không so bản đã sửa.
4. Ảnh ShotDex chưa từng băm (chưa backup, hoặc bản gốc chỉ ở iCloud) được **tải bản gốc về để băm**, theo luật của
   Backup: một file tạm một lúc, xoá ngay sau khi băm, chờ khi máy còn trống < 2 GB.
5. Việc kiểm **chạy tự động**: tiếp tục mỗi khi mở ShotDex và chạy ở nền trong giới hạn iOS. **Tiến độ được lưu** — iOS
   dừng app, người dùng tắt app, mất Wi‑Fi, khởi động lại máy thì lần sau làm tiếp từ chỗ đã dừng, không kiểm lại cái
   đã kiểm. Người dùng thấy đang kiểm tới đâu (đã kiểm N / tổng, còn bao nhiêu GB phải tải, lần kiểm NAS cuối lúc nào).
6. Album luôn theo kịp NAS: **mỗi lần mở ShotDex** liệt kê lại folder (chỉ tên + cỡ + ngày sửa, không đọc nội dung), và
   ở nền khi có lượt. File mới xuất hiện, file bị dời/đổi tên/xoá được nhận ra mà không đọc lại toàn bộ NAS — chỉ băm file
   mới hoặc đổi cỡ/ngày sửa.
7. **Xoá an toàn:** xoá ảnh từ album này thì ngay trước khi xoá, ShotDex hỏi lại NAS từng file đã khớp còn đúng chỗ, đúng
   cỡ không. File nào mất → ảnh đó bị bỏ khỏi lượt xoá và người dùng được báo. Hộp xoá nói rõ: ảnh vào Recently Deleted,
   iCloud chỉ nhả dung lượng sau khi dọn Recently Deleted (hoặc sau 30 ngày).
8. **Dấu "On NAS" trên lưới Library** cho ảnh có trên bất kỳ folder nào đang được kiểm (bởi một smart album On Server);
   Photo Info ghi rõ folder và đường dẫn file khớp. Ảnh chưa kiểm xong không có dấu.
9. Điều kiện chạy (Wi‑Fi, sạc) **theo cài đặt của job Backup** cùng connection; connection không có job Backup thì chỉ
   Wi‑Fi, không cần sạc.

## Affected users and systems — phạm vi ảnh hưởng

- **Ai:** người dùng có NAS và muốn giải phóng iPhone/iCloud dựa trên những gì đã nằm trên NAS — không riêng gia đình
  hai người.
- **Thiết bị:** iPhone · iPad · Duo trong/ngoài (smart album editor và album detail đã chạy ở cả ba). Mac: ngoài phạm vi.
- **Màn:** Smart Album editor (`SmartAlbumEditorSheet`, `SmartAlbumRuleRow`), Smart Album detail
  (`SmartAlbumDetailScreen`/`Model`) — hàng tiến độ kiểm, hộp xoá; dấu trên ô lưới Library (mọi lưới dùng chung ô ảnh) và
  Photo Info (FS-02); có thể Free Up Space (FS-15.02c).
- **Tầng:**
  - Domain: so khớp nội dung, quyết định "đủ mọi file gốc".
  - Data: bảng mới cho tiến độ kiểm và kết quả từng ảnh; tái dùng bảng Backup (SHA-256 đã biết của file đã chép),
    *Nội dung ở đích* + liệt kê cây + băm theo cỡ của FS-22.05, connection FS-15; smart album query phải đọc được kết quả
    này (hôm nay query chạy trên `photo_metadata`).
  - Chạy nền: tái dùng `BackupBackgroundService` / BG processing / iOS 26 continued task của FS-22.
- **Dữ liệu đã lưu:** thêm bảng (migration mới). Kết quả kiểm là dữ liệu dẫn xuất, nhưng tốn hàng giờ để tính lại → không
  được nằm trong `photo_metadata`, không bị Clear Local Metadata Index xoá. App chưa release — không cần tương thích ngược.

## Constraints — ràng buộc

Quyết định của người dùng (2026-10-24):
- ShotDex **không** tìm hay gộp ảnh trùng, không dời/xoá file trên NAS — script riêng của người dùng làm việc đó.
- So bằng **SHA-256**, không bằng tên + cỡ.
- Ảnh chưa biết SHA → **tải bản gốc về để băm**.
- **Đủ mọi file gốc** mới tính là có.
- **Kiểm lại trên NAS ngay trước khi xoá.**
- NAS chưa có dữ liệu — không cần tương thích với cây có sẵn.

Quyết định của người dùng (2026-10-25, trả lời Open questions):
- Liệt kê lại folder NAS **mỗi lần mở app** (không giới hạn 1 giờ).
- Điều kiện chạy theo job Backup cùng connection.
- Một điều kiện On Server = một folder gồm folder con; nhiều folder thì nhiều điều kiện nối bằng Any.
- Ảnh chưa kiểm xong không vào cả "is" lẫn "is not"; đầu album có dòng tiến độ.
- Thêm dấu "On NAS" trên lưới Library, tính theo bất kỳ folder nào đang kiểm.

Ràng buộc có sẵn:
- Không bao giờ làm đầy bộ nhớ iPhone: một bản gốc tạm một lúc, chờ khi trống < 2 GB (FS-22).
- Không đọc ghi sổ chung `.shotdex/backup-index/` theo cách làm hỏng Backup: script ngoài không ghi sổ đó, nên ShotDex phải
  tự liệt kê NAS; vẫn được đọc sổ để khỏi băm lại file máy khác đã băm.
- Không băm cả NAS: chỉ đọc file NAS khi có ảnh trên máy cùng cỡ mà file đó chưa có SHA (FS-22.05 §3).
- So nguồn với kết quả cho 55.000 mục trong một truy vấn, không truy vấn từng mục (NF-01).
- Không thêm dependency, dữ liệu không rời mạng nhà.
- Smart album đang có (rule metadata) không đổi hành vi; nhánh iOS 26 / trước 26 như mọi màn khác.
- Không test bằng ảnh có mặt người.

## Open questions — câu hỏi còn treo

Q1–Q5 đã trả lời 2026-10-25 (xem Constraints). Còn:

_Người dùng 2026-10-25: câu cần thử trên máy thật thành **spike trong `/spec`** (đo trước, chốt AC sau); câu "spec" do `/spec` quyết._

| # | Câu hỏi | Ai trả lời | Đề xuất mặc định |
|---|---|---|---|
| Q6 | Tải bản gốc từ iCloud khi iCloud đầy và bật Optimize Storage — có tải được không, Photos có giữ lại bản đã tải chiếm máy không? | đo trên máy thật | giả định tải được (FS-22 đã giả định); đo trước khi spec |

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
