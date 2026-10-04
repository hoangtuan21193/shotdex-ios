# ShotDex trên iPad, Mac và ảnh ở nhiều nơi — các quyết định

> Chốt 2026-10-04, sau 1 vòng · nguồn: `.planboard/mac-ipad-v2/plan.json`, `answers.json`, `rounds/1/digest.md`.
> Mỗi mục trỏ về plan gốc qua trường `tech` (FS-19, FS-20, FS-01.08c, FS-21, FS-18); bảng 68 mục cũ ở
> `.planboard/mac-ipad-plans/plan.json`.

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| Q1 ⚑ | Hide trên ảnh có bản Photos và bản NAS | OK — **khác đề xuất** | Hai lệnh riêng: Hide in Photos · Hide in ShotDex Only |
| Q2 | Báo gì khi nhập thẻ xong mà không nhả được | OK | Banner "You can remove … now", công tắc Eject chỉ hiện khi nhả được |
| Q3 | Nút Pause khi nhập thẻ | OK | Giữ: dừng sau file đang chép, Resume chạy tiếp |
| Q4 | iPhone bắt đầu so sánh từ một ảnh | OK — **khác đề xuất** | Chỉ từ chế độ chọn ≥ 2 ảnh |
| Q5 | Số cột lưới iPad/Mac | OK | 7 cột, 6 khi mở inspector |
| Q6 | Kéo ảnh không cần Select | OK | Có: nhấn giữ rồi kéo |
| Q7 | Cột công cụ Editor iPad | OK | Cố định bên phải, giữ ghim ảnh tham chiếu |
| Q8 | Viewer iPad trong cửa sổ hay phủ màn | OK | Trong cửa sổ, sidebar gọi lại được |
| Q9 ⚑ | Bán bản Mac chung hay riêng | OK | Universal Purchase: mua một lần, dùng cả ba |
| Q10 | Ai kiểm phần cần máy thật | OK — **khác đề xuất** | Bỏ qua, ghi "chưa kiểm (cần máy thật)" |
| A1 | Đọc ảnh thư mục, ổ, NAS | OK | Pipeline mới cho thư mục + NAS; PhotoKit giữ nguyên |
| A2 | Nhận ra cùng ảnh khi chỉ metadata đổi | OK | Hash phần dữ liệu ảnh cho 7 định dạng; còn lại băm cả file |
| A3 | Chỗ lưu sao, keyword, recipe của ảnh file | OK | Bảng riêng; một recipe chung mọi bản sao |
| A4 | Ghi `.xmp` không hỏng dữ liệu Lightroom | OK | Chỉ vá mục ShotDex quản, còn lại giữ từng byte |
| A5 | Ảnh nào hiện trong lưới | OK | Còn ≥ 1 bản xem được; tính lúc truy vấn, đo 55k |
| A6 | Cache preview | OK | Thư mục tự quản; 5 GB iOS, 25 GB Mac; gộp cache NAS |
| A7 | Tên lệnh xoá và hộp xác nhận | OK | Move / Delete / Hide N… theo đích; huỷ hộp Photos chỉ giữ phần Photos |
| A8 | Thời gian còn lại khi đọc ảnh | OK | Một cách tính, làm tròn phút |
| A9 | Áp chốt cũ vào tài liệu | OK | 30 ngày, Save to Photos, Duplicates theo nguồn, Merge file, album mọi nguồn |
| A10 | Sửa và thêm tiêu chí FS-19 | OK | AC-33, AC-66 sửa; AC-69…72 thêm |
| A11 | Chép và kiểm từng file khi nhập thẻ | OK | Đọc lại so SHA-256 rồi mới đổi tên |
| A12 | Nhập thẻ khi app ra nền / tắt | OK | iOS 26 chạy tiếp; danh sách backup nhớ qua lần mở |
| A13 | Đọc thẻ, nhận thẻ vừa cắm | OK | Ổ đọc kiểu ổ, máy ảnh qua ImageCaptureCore; hiện trong 2 s |
| A14 | Nhóm ngày; ảnh nhập vào ổ đang rút | OK | Ngày file rồi tinh theo EXIF; vẫn Imported |
| A15 | Tên file khi nhập | OK | `{date}_{originalNumber}`; chip Text chèn chữ thường |
| A16 | Compare là chế độ của Viewer | OK | Đổi tại chỗ, không màn mới |
| A17 | Cờ Reject và dấu Duplicates | OK | Một: chỉ ghi cờ thật |
| A18 | Xoá Reject và báo lỗi | OK | Một bộ định tuyến; banner + Try Again |
| A19 | Compare iPad trước khung mới; sáng/tối | OK | Chrome Viewer hiện có; theo Viewer |
| A20 | Khung sidebar, inspector | OK | Sidebar hệ thống; inspector 360 / sheet khi hẹp |
| A21 | Lệnh, phím, menu bar | OK | Một `CommandCatalog`, Mac dùng lại |
| A22 | Khung công cụ có cột phải | OK | `ToolInspectorLayout` chung |
| A23 | Chữ trên menu | OK | "Adjust Date & Time…", "Adjust Location…"; pill "Keep All N Photos" |
| A24 | Chiều cao panel chỉnh ảnh iPhone | OK | Giữ 264, sửa tài liệu |
| A25 | Màn iPad chưa có AC | OK | `/spec FS-21` thêm AC trước |
| A26 | Chia mã iOS / Mac | OK | Target Mac riêng, chung Domain/Data |
| A27 | Ảnh, màu, cỡ riêng của Mac | OK | `PlatformImage`; `MacTheme` chỉ Mac |
| A28 | Cuộn lưới 55k, ảnh phóng, timeline trên Mac | OK | AppKit; `Table` cho danh sách |
| A29 | Hoàn tác trên Mac | OK | `UndoManager` của cửa sổ |
| A30 | 13 màn Mac chưa có AC | OK | `design-parity` + AC FS gốc; AC mới cho Activity, Support |
| A31 | Phím khi xem ảnh | OK | "." = Favorite, ←/→ lùi tiến, mọi thiết bị |
| A32 | Số liệu Mac trong tài liệu | OK | Sửa theo số đo thật |

⚑ = quan trọng (critical). Không quyết định nào "Không OK"; mọi dòng sinh task trong plan tương ứng.

## Q1 — Hide trên ảnh có bản Photos và bản NAS

- **Chốt:** hai lệnh riêng **Hide in Photos** (bản Photos vào album Hidden của Photos như hôm nay, các bản file/NAS
  ShotDex ẩn) và **Hide in ShotDex Only** (ShotDex ẩn mọi bản sao, Photos không đổi). "Hide" trơn chỉ khi ảnh nằm ở một
  nơi. Đã ghi vào FS-19.04 §3 + AC-73; task E15 của plan FS-19.
- **Vì sao:** mỗi tên một nghĩa, người dùng tự chọn có đụng tới Photos (và mọi máy qua iCloud) hay không.
- **Đã cân nhắc:** một lệnh Hide ẩn cả hai nơi (đề xuất) — gọn menu nhưng ẩn luôn trong app Photos dù chỉ muốn ẩn trong
  ShotDex; ShotDex tự ẩn không đụng Photos — ảnh vẫn hiện trong Photos, khác nghĩa Hide hôm nay.
- **Lịch sử:** vòng 1 — chọn `two-commands`.

## Q4 — iPhone bắt đầu so sánh từ một ảnh

- **Chốt:** iPhone và Duo ngoài chỉ so sánh từ chế độ chọn ≥ 2 ảnh; không "Compare with Next" trong ⋯, không nút trên
  Viewer Single. Màn rộng (iPad, Duo trong, Mac) giữ 2-Up từ Single với Candidate = ảnh kế. Đã ghi vào FS-01.08c §2, §7,
  AC-26; task 20 của plan 08c.
- **Vì sao:** không thêm gì vào thanh trên vốn đã chật, không phải vẽ lại màn xem ảnh iPhone.
- **Đã cân nhắc:** "Compare with Next" trong ⋯ (đề xuất) — khó thấy, thêm một dòng menu; nút Single/2-Up ở thanh trên —
  chật thanh và phải vẽ `PH_Viewer` trước.
- **Lịch sử:** vòng 1 — chọn `selection-only`.

## Q9 — Bán bản Mac chung hay riêng (quan trọng)

- **Chốt:** Universal Purchase, cùng bundle id `com.hoangtuan.shotdex` cho target `ShotDexMac`; app group
  `group.com.hoangtuan.shotdex` cần provisioning trên macOS.
- **Vì sao:** đã lên App Store thì không đổi được; người mua trên iPhone không phải trả lần nữa, một trang App Store.
- **Đã cân nhắc:** bán riêng (`com.hoangtuan.shotdex.mac`) — đặt giá riêng được nhưng người dùng trả hai lần.
- **Lịch sử:** vòng 1 — đồng ý mặc định.

## Q10 — Ai kiểm phần cần máy thật

- **Chốt:** bỏ qua; cột chứng minh ghi "chưa kiểm (cần máy thật)" cho FS-18 AC-14, 44, 62, 63, 65 và FS-20 AC-20 (+
  phần thẻ/đầu đọc thật của AC-10, AC-27). FS-19 không đo M1–M3. Không máy ảo macOS 15, không script tay; plan FS-18 bỏ
  M59, M60, M62, M63.
- **Vì sao:** không tốn thời gian bây giờ.
- **Đã cân nhắc:** người dùng kiểm tay theo danh sách (đề xuất) — chừng một buổi; đợi có máy rồi kiểm — bản Mac chờ theo.
  Cái giá đã chấp nhận: phát hành khi năm điều đó chưa ai thử trên máy thật.
- **Lịch sử:** vòng 1 — chọn `skip`.
