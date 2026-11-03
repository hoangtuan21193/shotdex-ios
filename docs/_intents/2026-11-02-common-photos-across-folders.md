# Intent: Gom ảnh có ở mọi folder server đã chọn vào một folder chung (Mac)

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-02 |
| Trạng thái | accepted (2026-11-02) |
| Tiến độ | **đang làm** (2026-11-03) — bản đầu 15/15 task, 15/16 AC xanh, còn AC-130; thêm hoàn tác (spec §6b, AC-131…143 chưa làm; plan [2026-11-03-fs1908-undo](../_plans/2026-11-03-fs1908-undo.md) đang làm, task 3/9); plan [2026-11-03-fs1908-common-photos](../_plans/2026-11-03-fs1908-common-photos.md) |
| Nguồn | phản hồi người dùng (2026-11-02: "trên ổ SMB có folder A và B, muốn tạo folder C chứa ảnh có ở cả A và B, Copy hoặc Move, mặc định Copy") |
| Spec sinh ra từ đây | [FS-19.08](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

## Bối cảnh

Đây chính là **bước 3** của kế hoạch giải phóng iCloud ở
[2026-10-24-smart-album-on-nas](2026-10-24-smart-album-on-nas.md): hai người backup vào `Tuấn/` và `Vợ/`, ảnh gửi qua
lại nên trùng ở cả hai, và ảnh trùng cần gom vào `Shared/`. Intent đó ghi bước 3 là "một script riêng của người dùng,
không phải ShotDex". Intent này đưa bước 3 vào ShotDex, trên Mac.

## Problem — vấn đề

Hôm nay người dùng **không có cách nào trong ShotDex để biết ảnh nào có ở cả folder A lẫn folder B trên NAS**, càng
không gom được chúng sang một chỗ.

- Duplicates (FS-19.04 §4, D7) chỉ gom trong **một** nguồn và chỉ hiện, không chép hay dời file.
- On Server check (FS-19.07) so ảnh **trong Photos** với một folder NAS, không so hai folder NAS với nhau.
- Backup (FS-22.05) bỏ qua ảnh đã có trong folder đích, nhưng chỉ khi chép mới — ảnh trùng có sẵn ở hai folder thì
  không ai đụng tới.
- Server browser trên iPhone/iPad (FS-17.01) có Rename/Delete từng mục, không có chép hay dời giữa các folder. Mac chưa
  có server browser trong code (board `MAC_ServerBrowser` đã có).
- Làm tay: hàng chục nghìn file, tên có thể khác nhau (`IMG_1234.HEIC` ở A, `2025-06-01 IMG_1234.HEIC` ở B) — so bằng mắt
  là không làm được, và dời nhầm là mất ảnh khỏi folder của một người.

Mức độ: chặn bước 3 của kế hoạch iCloud gia đình; người dùng phải viết script ngoài, không có log hay kiểm tra.

## Proposed outcome — kết quả mong muốn

1. Trên **Mac**, người dùng **chọn từ 2 folder trở lên** (A, B, có thể thêm folder thứ ba…; cùng connection
   SMB/WebDAV/SFTP), rồi chọn hoặc tạo mới folder chung C, chọn **Copy** (mặc định) hoặc **Move**, xem trước có bao
   nhiêu ảnh chung và bao nhiêu GB, rồi chạy.
2. **Ảnh chung** = nội dung (SHA-256 cả file) có mặt ở **mọi** folder đã chọn, bất kể tên hay folder con nào. Chọn
   A, B, D thì ảnh chỉ có ở A và B không tính.
3. **Copy**: C nhận một bản của mỗi ảnh chung; folder nguồn không đổi.
   **Move**: C nhận một bản; ảnh đó **biến mất khỏi mọi folder đã chọn** — mỗi folder chỉ còn ảnh không chung.
4. **Folder con**: quét cả cây của mọi folder đã chọn; C **phẳng** — mọi ảnh vào thẳng C.
5. **Trùng tên trong C**: file ở C đã cùng nội dung → bỏ qua (coi là xong); khác nội dung → đặt tên `IMG_0001 (2).JPG`.
   Không bao giờ ghi đè.
6. **Progress** suốt lượt chạy: đang quét / đang băm / đang chép — đếm N/tổng và GB; dừng được, chạy lại thì làm tiếp,
   không chép lại cái đã xong.
7. **Log từng file**: đường dẫn ở từng folder nguồn, đường dẫn ở C, SHA-256, kết quả (Copied · Moved · Skipped · Failed + lý do). Xem được trong app; xong
   lượt thì ghi `ShotDex Common Photos <ngày giờ>.csv` vào C.
8. **Đúng là đúng**: không file nào bị xoá ở folder nguồn trước khi bản ở C đã được kiểm là đủ byte và đúng SHA-256. Lượt hỏng
   giữa chừng không bao giờ để một ảnh chỉ còn ở chỗ không ai biết.

## Affected users and systems — phạm vi ảnh hưởng

- **Ai:** người dùng có NAS với nhiều folder chép chồng lên nhau (backup của nhiều máy, chép tay, import nhiều lần).
- **Thiết bị:** **chỉ Mac** (người dùng 2026-11-02). iPhone · iPad · Duo: ngoài phạm vi — không thêm vào server browser iOS.
- **Màn (Mac):** chọn nhiều folder trong server browser Mac (board `MAC_ServerBrowser`; chưa có trong code); một sheet
  mới chọn/tạo C + Copy/Move + xem trước; cửa sổ tiến độ và log. Cần board mới trên canvas Mac.
- **Tầng:**
  - Domain: so khớp hai danh sách theo cỡ rồi SHA-256; lập kế hoạch tên ở C (`ServerUploadPath.nextFreeName` có sẵn);
    thứ tự an toàn cho Move.
  - Data: `RemoteFileClient` đã có `entries`, `download` (trả SHA-256), `upload`, `sha256(of:)` đọc lại, `move` (không
    ghi đè; SMB từ chối khác share), `remove`, `createDirectory` — **không có lệnh copy phía server**, nên Copy = tải về
    Mac rồi đẩy lên. Hash đã biết trong `copy_files` (server là nguồn FS-19 trên Mac) dùng lại được.
  - Bảng lưu lượt chạy + từng file để làm tiếp và hiện log (migration mới). Không đụng `photo_metadata`.
- **Dữ liệu đã lưu:** thêm bảng. App chưa release — không cần tương thích ngược.

## Constraints — ràng buộc

Quyết định của người dùng (2026-11-02):
- Khớp bằng **SHA-256 cả file** — không bằng tên, EXIF hay hash phần ảnh.
- Move **lấy ảnh khỏi mọi folder nguồn**.
- Trùng tên ở C: cùng nội dung bỏ qua, khác thì thêm ` (2)`.
- Quét cả folder con; C phẳng.
- Log trong app + file CSV trong C.
- **Chỉ Mac.**
- Phải có progress và log, "để đảm bảo ảnh move hay copy đúng".
- **Điểm vào: chọn từ 2 folder trở lên** ("nhỡ select 3 folder cũng ok, trên 2 là được"), rồi xuất ra một folder chung
  người dùng **chọn hoặc tạo mới**.
- Intent này **thay** dòng "ShotDex không dời/xoá file trên NAS" của intent 2026-10-24 (đồng ý 2026-11-02).

Claude tự quyết (sửa được khi duyệt):
- **Luồng:** chọn ≥ 2 folder (⌘-click trong server browser Mac) → nút/menu **Find Common Photos…** (mờ khi < 2) → sheet
  liệt kê folder đã chọn, ô **Save to** chọn folder hoặc **New Folder**, Copy/Move (Copy chọn sẵn) → **Scan** hiện
  "312 photos in all 3 folders · 4.2 GB" + danh sách → **Copy 312** / **Move 312** → cửa sổ tiến độ có bảng log.
- **Quét nhanh theo tầng** (người dùng hỏi 2026-11-02 "so tên và dung lượng trước, ngày tháng nữa?"):
  1. Liệt kê cây mọi folder: tên + cỡ + ngày sửa, **không đọc nội dung**.
  2. Lọc theo **cỡ**: cỡ không có mặt ở mọi folder thì loại ngay, không đọc byte nào. Đây là bộ lọc chính — hai ảnh
     khác nhau trùng cỡ đến từng byte là hiếm, nên còn lại gần như chỉ ảnh trùng thật.
  3. **Gợi ý ngay** (người dùng 2026-11-02: "ngày chụp giống, cùng thư mục con thì phải suggest là giống ngay"): trong
     các nhóm cùng cỡ, chấm điểm bằng tín hiệu rẻ — cùng tên, cùng đường dẫn folder con (`2025/06/…` ở cả hai bên),
     cùng ngày chụp EXIF (kèm phần giây lẻ + máy). Đủ tín hiệu → Scan hiện ngay là **Likely the same**, số đếm và
     danh sách ra trong vài giây, trước khi băm. Ngày chụp lấy từ index của Mac nếu folder là nguồn; chưa có thì đọc
     64 KB đầu file, chỉ cho file đã qua lọc cỡ.
  4. Không tín hiệu nào là cổng: tên khác vẫn bắt được (đổi tên); **ngày sửa** file không dùng để so (Finder/NAS/app
     khác đổi nó), chỉ để biết SHA đã lưu còn dùng được (cùng cỡ + cùng ngày sửa → không băm lại).
     Cùng ngày chụp nhưng **khác cỡ** (nén lại, ghi thêm metadata, đã sửa) → **không** tính là ảnh chung, không gợi ý
     (người dùng 2026-11-02).
  5. Ứng viên cùng cỡ: đọc **3 đoạn 64 KB** (đầu, giữa, cuối, `readRange`) loại tiếp file khác nhau.
  6. **SHA-256 đầy đủ** cho số còn lại, ứng viên Likely the same băm trước — gợi ý chuyển thành **Same** (chắc chắn)
     hoặc rơi khỏi danh sách. Chỉ ảnh Same mới được chép/dời. Copy: băm ngay trong lúc tải về để chép, không tốn thêm lượt đọc. Move: phải
     đọc trọn các bản một lần trước khi xoá. SHA đã có trong `copy_files` (server là nguồn trên Mac) dùng lại.
  Tổng byte phải đọc ≈ dung lượng phần ảnh chung, không phải cả NAS.
- **Thứ tự Copy:** tải file từ A (tính SHA khi tải) → đẩy lên C qua file part → đọc lại SHA ở C → đổi tên part thành tên
  thật. Lệch SHA → xoá part, ghi Failed.
- **Thứ tự Move:** dời bản ở folder nguồn đầu tiên sang C bằng `move` (cùng share, không chép byte) → kiểm C đúng cỡ →
  hỏi lại các bản còn lại đúng cỡ, đúng ngày sửa → xoá chúng. Khác share (SMB từ chối `move`) → chép như Copy, kiểm SHA
  ở C, rồi mới xoá mọi bản nguồn.
  Hộp xác nhận Move nói rõ xoá trên server không có thùng rác.
- **Một nội dung có nhiều bản** (hai file giống hệt ngay trong A): C nhận một bản; Move lấy mọi bản đó khỏi mọi folder nguồn.
- Folder đã chọn lồng nhau (B nằm trong A) → báo lỗi, không chạy.
- **File nào tính:** ảnh và video app nhận diện; `.xmp` cùng tên gốc đi theo ảnh của nó; bỏ file ẩn, `.shotdex/`,
  `.shotdex-part`. C nằm trong một folder nguồn → báo lỗi, không chạy (C nằm ngoài, kể cả cạnh chúng, thì được).
- **Một lệnh tới server một lúc** mỗi connection (SMBClient không chạy song song được).

Mâu thuẫn chính sách:
- Intent 2026-10-24 ghi "ShotDex **không** tìm hay gộp ảnh trùng, không dời/xoá file trên NAS — script riêng làm". Intent
  này **thay** dòng đó cho bước 3 — người dùng đồng ý 2026-11-02; `/spec` sửa intent cũ trỏ sang đây.
- FS-19 D6 ("Xoá file trên NAS — chỉ Hide") áp cho **nguồn** trong thư viện. Tính năng này là thao tác file trên server
  như Rename/Delete của FS-17.01 §4b, không phải xoá ảnh trong thư viện; sau Move, lượt so lệch của nguồn nhận file dời
  bằng hash (FS-19.02 §2). `/spec` phải ghi rõ ranh giới này ở FS-19 README.
- Lịch sử upload/backup trỏ tới đường dẫn bị dời hay xoá phải được sửa như Rename/Delete (`ServerFileHistory`), để
  "đã có trên NAS" (FS-15.02c, FS-19.07) không sai.

Ràng buộc có sẵn:
- Không thêm dependency; dữ liệu không rời mạng nhà.
- Không test bằng ảnh có mặt người. Test cục bộ bằng SMB impacket / WebDAV trên máy (memory `server-upload-fs15`).
- Board và code phải khớp: board Mac trước khi code.

## Open questions — câu hỏi còn treo

Q1–Q9 đã trả lời 2026-11-02 (xem Constraints). Không còn câu treo; luồng màn hình duyệt lần cuối ở board Mac trong `/spec`.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
