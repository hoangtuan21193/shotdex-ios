# FS-20 — Nhập từ thẻ nhớ (mọi thiết bị)

`FS-20` · tier B (lưới thẻ) + inspector · `Features/Ingest/` (chưa có) · test `ShotDexTests/Ingest*Tests.swift` (chưa có)
· cập nhật 2026-10-04 · nguồn: intent [Mac](../../_intents/2026-10-04-macos-app.md) (D8) và
[iPad](../../_intents/2026-10-04-ipad-mac-style.md) · board `MAC_Ingest`, `MAC_IngestProgress`, `IP_Ingest`;
`PH_Ingest`, `DI_Ingest`, `DC_Ingest` chưa vẽ

**Một câu:** cắm thẻ (hoặc máy ảnh) → ShotDex liệt kê ảnh mới trên thẻ, bỏ qua ảnh đã nhập → chép vào một
thư mục nguồn (và một ổ backup), đặt tên theo mẫu, ghi metadata vào sidecar `.xmp`, kiểm từng bản chép, rồi
nhả thẻ. Ảnh chép xong là ảnh của một nguồn thư mục (FS-19), không vào Photos.

## 1. Người dùng cần gì

Sau buổi chụp: thẻ 64 GB, ~800 khung mới, vài trăm khung đã chép hôm trước. Họ muốn đổ phần mới vào ổ lưu trữ
theo năm/ngày, tên có ngày, có một bản backup trên ổ thứ hai, gắn tên tác giả, và **biết chắc** mọi bản chép
khớp từng byte trước khi format thẻ. Hôm nay phải làm bằng Finder hoặc Lightroom rồi mới mở ShotDex.

## 2. Khác FS-10 (Import đã bỏ) ở đâu

| | FS-10 (đã gỡ 2026-09-24) | FS-20 |
|---|---|---|
| Đích | thư viện Photos | **thư mục trên đĩa**, thành nguồn thư mục (FS-19); Photos không đổi |
| Nguồn | folder bất kỳ, lọc RAW | thẻ nhớ hoặc máy ảnh đang cắm |
| Lối vào | hàng trong Settings | hàng thẻ trong nhóm Sources, chạm mới mở (§4) |
| Thiết bị | iPhone, iPad | Mac, iPad, iPhone, Duo (§9) |

Lý do FS-10 bị bỏ ("ShotDex không quản lý file") không còn đúng khi app có nguồn thư mục (D3–D6): ở đó ShotDex
**là** nơi quản lý file, và nhập thẻ là cách file vào nguồn đó. FS-10 cần một dòng ngoại lệ trỏ về đây.

## 3. Cố ý không có
- Xoá hay format thẻ sau khi nhập — vì format phải làm trên máy ảnh; app xoá nhầm là mất bản duy nhất.
- Nhập vào Photos — Photos có màn nhập riêng của hệ thống.
- Sửa nội dung file ảnh — file chép nguyên byte; mọi thứ app ghi nằm trong `.xmp` (D3).
- Áp preset chỉnh màu lúc nhập — chưa ai đòi; làm sau bằng Paste Edits.

## 4. Lối vào và nhận thẻ

- Cắm thẻ (SD/CFexpress qua đầu đọc, hoặc máy ảnh USB) → một **hàng thẻ** hiện trong nhóm **Sources** của sidebar
  (tên ổ + glyph thẻ); rút thẻ → hàng biến mất. Bố cục iPhone: hàng nằm cùng chỗ với nguồn thư mục FS-19.
- **Chạm hàng mới mở** màn **Import from Card**, thay chỗ lưới; sidebar giữ nguyên. Cắm thẻ không tự mở màn,
  không có banner — *vì người cắm thẻ để đọc ảnh trong Finder/Files không muốn bị kéo đi.*
- Đầu màn: thẻ cắm vào (`EOS_DIGITAL · SD card · 41.2 of 64 GB used · Canon EOS R6 Mark II`), bên phải
  `812 new photos` / `234 already imported · skipped` và nút **Eject**.
- **Đọc thẻ qua hai đường**, cùng một màn:
  - khung truy cập máy ảnh của hệ thống — thấy thẻ có DCIM và máy ảnh USB, không phải chọn ổ; máy ảnh USB chỉ đi đường này;
  - chọn ổ thẻ **một lần** trong trình chọn của hệ thống, nhớ bằng bookmark; lần sau cắm cùng thẻ thì không hỏi lại.
- Thẻ không hiện qua khung máy ảnh → hàng thẻ có **Choose Card…** mở trình chọn ổ. Bookmark hỏng → chọn lại, câu của 07b §4.

## 5. Màn chọn ảnh

- Lưới xếp theo ngày chụp, **cũ trước**, nhóm theo ngày + nơi chụp. Ngày mà mọi ảnh đã nhập thì thu gọn thành
  một dòng (`Sunday, September 27 · Nara · 228 already imported`).
- Segmented **All 1,046 · New 812** (mặc định New), **Check All**, **Uncheck All**, bên phải `811 checked · 24.6 GB`.
- Ô ảnh mới có ô tick góc trên-trái, mặc định **tick**; chạm ô = tick/bỏ tick. Ô đã nhập có nhãn **Imported**,
  không có ô tick, không chọn được.
- Cặp cùng tên gốc khác đuôi (`.CR3` + `.JPG`) là **một ô**, chép cả hai, cùng tên mới khác đuôi (07b §5).
- **"Đã nhập"** = có trong lịch sử nhập theo **tên gốc + byte + giờ chụp**; chỉ đọc danh mục thẻ, nhãn hiện ngay khi mở.
- Hash nội dung chạy nền (~7 phút cho 41 GB ở 100 MB/s) rồi tinh chỉnh: khớp lịch sử mà hash khác → New; không
  trong lịch sử mà hash trùng ảnh của một nguồn thư mục → Imported. Import không chờ hash nền.
- Ảnh đã nhập mà file ở đích **không còn** (bị xoá, nguồn bị gỡ) → lại là **New**, tick như ảnh mới.
- Chép kèm: video **MP4/MOV** là một ô riêng (badge thời lượng); ghi âm **WAV** cùng tên gốc với ảnh đi cùng ô ảnh đó,
  cùng tên mới. Bỏ qua **THM** và file hệ thống của máy (thư mục MISC, file danh mục, file ẩn).

## 6. Inspector — đích, tên, metadata

Mac: inspector 300pt bên phải. iPad ngang: inspector 360pt; iPad dọc: sheet (như mọi inspector iPad).

| Section | Hàng | Luật |
|---|---|---|
| Destination | thư mục đích | popup: các nguồn thư mục đã có + **New Folder…**; dòng phụ `Joins the T7 RAW Archive source · 1.31 TB free`. Thư mục mới thành nguồn mới (FS-19) |
| | Folders | mẫu thư mục bằng token **Year** / **Date** theo ngày chụp; ví dụ `RAW/2026/2026-10-03` — cùng luật Date Folders của 07b §3 |
| Backup | công tắc + đích | **Also Copy to a Backup Drive**, mặc định tắt; đích là thư mục bất kỳ. Bản backup **không** vào thư viện |
| File Names | preset + ô mẫu | preset **Date and Number**; ô mẫu chip + chữ tự gõ; ví dụ dùng ảnh đầu mẻ `2026-10-03_Kyoto_6123.CR3` |
| Metadata | preset + 3 ô | preset có tên; **Creator**, **Copyright**, **Keywords** (chip, xoá được); luôn ghi `.xmp`, kể cả khi công tắc XMP trong Settings tắt |
| After Import | công tắc | **Eject EOS_DIGITAL After Import**, mặc định bật |
| Tóm tắt | footer | `811 photos · 24.6 GB · about 4 min to T7 RAW Archive` |

- **Một bộ token chung** cho Import và Export (07b §5): Original Name · Original Number · Date · Time · Camera · Lens ·
  Sequence · Text. Cùng chữ trên chip, cùng luật: ký tự exFAT cấm → `-`, token thiếu bị bỏ cùng dấu nối thừa, ≤ 200 ký tự.
- Công tắc XMP trong Settings (D3) tắt **không** chặn lượt nhập: preset metadata là yêu cầu rõ ràng, nên chỉ file của
  lượt nhập này có `.xmp`; ảnh khác trong nguồn vẫn theo công tắc.
- Nhớ sang lần sau: đích, backup, mẫu thư mục, mẫu tên, preset metadata, Eject. Nút **Import 811 Photos** (toolbar,
  nổi bật) mờ khi 0 ảnh tick, đích không mở được, ổ backup đang bật mà không cắm, hoặc thiếu chỗ (§7).

## 7. Chép, kiểm, backup

1. **Trước byte đầu:** tính toàn bộ tên của mẻ; kiểm chỗ trống ở đích và backup (tổng byte của mẻ).
2. Mỗi file: chép theo khối ≤ 1 MB vào tên tạm `.shotdex-part`, đọc lại, so SHA-256 với bản trên thẻ, rồi mới
   đổi sang tên thật (khuôn FS-15.02 §4). *Khác 07b §6 (không đọc lại) vì thẻ là bản duy nhất.*
3. Ghi `.xmp` cạnh file: preset metadata + ngày chụp. SHA-256 **cả file** của bước 2 dùng để kiểm và ghi lịch sử nhập;
   hash nội dung của nguồn (FS-19.02 §1, phần ảnh) băm từ **cùng các khối** đọc lúc chép, không đọc thẻ lần hai (D4, plan Q4).
4. Backup: chép cùng tên, cùng kiểm, sau bản chính của **cùng file**.
5. Bước 2–3 xong là ảnh vào nguồn, lưới cập nhật giữa mẻ. Mọi bản chính **và** backup đã kiểm → nhả thẻ (nếu bật),
   banner `Imported 811 photos. EOS_DIGITAL ejected.`

- **Không bao giờ ghi đè.** Tên trùng với file có sẵn ở đích, hoặc với file khác trong mẻ → ` (2)`, ` (3)`…
  (07b §6 Keep Both); so không phân biệt hoa thường.
- **Tiến độ không chặn màn.** Chân sidebar `Importing from EOS_DIGITAL 51%`, nguồn đích có vòng quay. Mac: panel **Window ›
  Activity** (⌥⌘0) — thanh Copy · Verify · Backup, file và trạng thái, **Pause**, **Stop Import…**; iPad: chạm chân sidebar.
- **Stop Import…** hỏi *"Stop importing? Photos already imported stay in “T7 RAW Archive”."* → dừng ≤ 1 s, xoá
  tên tạm; không nhả thẻ.
- **App ra nền giữa mẻ** (iPad, iPhone, Duo): iOS/iPadOS 26 xin hệ thống chạy tiếp như việc người dùng khởi động —
  tiến độ hiện ở giao diện hệ thống. Trước 26: dừng như Stop; quay lại có **Import Remaining** (07c §2).

## 8. Đường hỏng

| Hỏng | Phạm vi | Câu báo + lối ra |
|---|---|---|
| thẻ bị rút giữa mẻ | **dừng mẻ** ≤ 2 s | *"EOS_DIGITAL was disconnected. 412 of 811 imported."*; cắm lại → ảnh đã xong hiện Imported, **Import Remaining** |
| đích đầy | **dừng mẻ** | *"“T7 RAW Archive” is full — 412 of 811 imported."*; tên tạm bị xoá |
| thiếu chỗ trước khi chạy | không ghi gì | footer *"Needs 24.6 GB, 12.0 GB free on T7."*, Import mờ |
| ổ backup không cắm | không chạy | hàng Backup *Not connected*; footer *"Connect “LaCie Backup” or turn off backup."* |
| ổ backup bị rút giữa mẻ | bản chính chạy tiếp | thẻ **không** nhả; tổng kết *"Backup incomplete — 357 of 811."* + **Back Up Remaining** |
| SHA-256 lệch | một file | chép lại 1 lần từ thẻ; còn lệch → file lỗi, tên tạm xoá, không vào nguồn, thẻ không nhả, **Retry Failed** |
| file thẻ không đọc được | một file | tên file + *"Couldn't read this file from the card."*, mẻ chạy tiếp |

- Lỗi của **đích hoặc thẻ** dừng cả mẻ; lỗi của **một file** thì chạy tiếp — cùng luật FS-15.02 §4, 07c §3.
- Có lỗi thì thẻ **không bao giờ** tự nhả, kể cả khi bật Eject: người dùng không được format thẻ còn bản duy nhất.

## 9. Dữ liệu và ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Lưu ở đâu | lịch sử nhập (thẻ, tên gốc, byte, giờ chụp, SHA-256, đường dẫn đích): **bảng riêng** ([BD-02](../../01-basic-design/BD-02-database-design.md)), `data-migration` duyệt. Preset metadata, mẫu, lựa chọn: cài đặt của app |
| Bộ nhớ | một file mỗi lúc, khối ≤ 1 MB; đỉnh RAM không tăng theo số ảnh ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Hiệu năng | thumbnail lưới lấy từ preview nhúng (như FS-17), không giải mã RAW ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Riêng tư | không mạng; preset chỉ nằm trên máy ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md)) |
| Thiết bị | Mac 1440×900 · iPad 1376×1032 ngang · iPad dọc 1032×1376, Duo trong 951×669, iPhone 402×874, Duo ngoài 466×678 (rail 84pt): inspector thành sheet dưới 1100pt (FS-21) |
| iOS 26 vs trước | iPad/iPhone/Duo: cùng hàng, cùng chữ ở hai nhánh; khác duy nhất là ra nền (§7) |
| Truy cập | ô đọc *"IMG_5884.CR3, checked"* / *"Imported"*; VoiceOver đọc phần trăm Copy/Verify/Backup |

iPhone và Duo có đủ nhập thẻ (luật "phone có mọi tính năng iPad"): iPhone USB-C đọc được đầu đọc thẻ, và đích là
nguồn thư mục FS-19 có trên mọi máy.

## 10. Tiêu chí nghiệm thu

27 AC ở [01-acceptance-criteria.md](01-acceptance-criteria.md).
