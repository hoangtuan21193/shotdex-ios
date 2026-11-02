# FS-19.08 — Gom ảnh chung của nhiều folder server (Mac)

`FS-19.08` · tier A (sheet) + B (cửa sổ tiến độ) · chỉ **Mac** · board `MAC_CommonPhotos` · `MAC_CommonPhotosRun`
· đề xuất `ShotDexMac/Servers/CommonPhotos/`, `ShotDex/Domain/CommonPhotos/` · AC ở [08b](08b-common-photos-ac.md)
· cập nhật 2026-11-02

**Một câu:** trong màn duyệt server trên Mac, chọn từ 2 folder trở lên → ShotDex tìm ảnh có **cùng nội dung** ở mọi
folder đó và chép (mặc định) hay dời chúng vào một folder chung, có tiến độ, log từng file, và kiểm SHA-256 trước khi
xoá bất cứ thứ gì.

Nguồn: [intent 2026-11-02](../../_intents/2026-11-02-common-photos-across-folders.md) (bước 3 của
[smart-album-on-nas](../../_intents/2026-10-24-smart-album-on-nas.md)).

## 1. Người dùng cần gì

- Hai người backup vào `Tuấn/` và `Vợ/` trên NAS; ảnh gửi qua lại nên nằm ở cả hai. Họ muốn gom phần chung vào `Shared/`
  để mỗi folder chỉ còn ảnh riêng — hàng chục nghìn file, tên có thể khác nhau, không so bằng mắt được.
- Phải chắc chắn: không ảnh nào bị xoá khỏi một folder mà chưa nằm an toàn ở folder chung.

## 2. Phạm vi

**Có:** chọn ≥ 2 folder cùng connection · folder chung chọn có sẵn hoặc tạo mới · Copy (mặc định) / Move · quét cả folder
con · kết quả xem trước có hai mức Likely the same → Same · tiến độ, dừng, làm tiếp · log trong app + CSV trong folder chung.

**Cố ý không có:**
- iPhone, iPad, Duo — người dùng chọn chỉ Mac (2026-11-02).
  Ngoại lệ có chủ ý của luật "tính năng Mac có thì iPhone/iPad cũng có" (NF-05 §1): việc chạy hàng giờ trên NAS
  hợp Mac, iOS dừng app nền — người dùng chốt 2026-11-02, ghi ở [FS-18.07](../FS-18-mac-app/07-spec-deltas.md).
- Ảnh cùng ngày chụp nhưng khác byte (nén lại, ghi thêm metadata, đã sửa) — không gợi ý, không gom (người dùng 2026-11-02).
- Folder ở hai connection khác nhau — một lượt chạy trên một connection.
- Hoàn tác sau khi Move — server không có thùng rác; thay bằng kiểm SHA trước khi xoá và CSV ghi đủ đường dẫn cũ.
- Folder chung giữ cây folder con — C phẳng (người dùng 2026-11-02).

## 3. Lối vào

- Màn duyệt server (board `MAC_ServerBrowser`, [03 §4](03-servers-as-sources.md)): ⌘-click / ⇧-click chọn nhiều folder
  trong một cột hoặc ở ô folder của lưới. Chuột phải → **Find Common Photos…** (phím `⇧⌘F` ghi ở menu File, không ở menu chuột phải). Dưới 2 folder → mục
  **ẩn** khỏi menu chuột phải (HIG: menu ngữ cảnh ẩn mục không dùng được); menu File luôn có mục này, mờ khi không ở màn duyệt.
- Menu bar **File › Find Common Photos…** cùng phím tắt, mở sheet với các folder đang chọn (có thể rỗng).
- Sheet có **Add Folder…** (mở bộ chọn folder của chính connection đó) để thêm folder ở cột khác.
- Chỉ connection là **nguồn** (có màn duyệt). Connection chỉ để upload không có lối vào ở bản này (người dùng chốt
  2026-11-02).

## 4. Sheet Find Common Photos (`MAC_CommonPhotos`)

| Phần | Nội dung |
|---|---|
| Folders | danh sách folder đã chọn (đường dẫn rút gọn, số file), nút − từng dòng, **Add Folder…** |
| Save to | popup chọn folder (bộ chọn folder của connection) + **New Folder…**; mặc định trống, nút chạy mờ tới khi chọn |
| Action | segmented **Copy** · **Move**; Copy chọn sẵn. Move hiện câu: "Moved photos are removed from every folder above. The server has no Trash." |
| Kết quả | sau **Scan**: "312 photos in all 3 folders · 4.2 GB", hai đếm **Same 280** · **Checking 32**, danh sách (thumbnail cache nếu có, tên, đường dẫn từng folder, cỡ) |
| Nút | **Cancel** · **Scan** → sau khi quét xong thành **Copy 280** / **Move 280** (chỉ đếm Same); chân trái "Only photos marked Same are copied." |

- Báo lỗi trong sheet, không chạy: folder chung nằm trong một folder nguồn · hai folder nguồn lồng nhau · < 2 folder.
- **Move** bấm chạy → hộp xác nhận: "Move 280 photos to “Shared”?" · "They're removed from Tuấn and Vợ after each copy in
  Shared is checked. The server has no Trash." · **Move** · Cancel.

## 5. Quét — nhanh rồi chắc

1. Liệt kê cây mọi folder (tên, cỡ, ngày sửa); bỏ mục ẩn, `.shotdex/`, file part; chỉ ảnh, video và `.xmp`.
2. Giữ những cỡ có mặt ở **mọi** folder; còn lại loại, không đọc byte nào.
3. **Likely the same** — trong nhóm cùng cỡ, có thêm cùng tên, cùng đường dẫn folder con, hoặc cùng ngày chụp (giây lẻ +
   máy). Ngày chụp lấy từ index nếu folder là nguồn; chưa có thì đọc 64 KB đầu, chỉ file đã qua bước 2. Hiện ngay.
4. Đọc 3 đoạn 64 KB (đầu, giữa, cuối) loại tiếp; rồi **SHA-256 cả file**, ứng viên Likely băm trước. Khớp → **Same**;
   lệch → rơi khỏi danh sách. SHA đã có (cùng cỡ + cùng ngày sửa) không băm lại.
5. Chỉ **Same** được chép/dời. Tên file khác nhau không ngăn khớp; ngày sửa không bao giờ dùng để so.

## 6. Chạy

- **Copy**: tải bản ở folder nguồn đầu (băm khi tải) → đẩy lên folder chung dạng file part → đọc lại SHA-256 → đổi tên.
- **Move**: hỏi lại bản ở folder nguồn đầu (cỡ + ngày sửa) → dời nó sang folder chung bằng lệnh đổi chỗ của server (không
  chép byte) → kiểm ở đích cỡ + ngày sửa (đổi chỗ giữ ngày sửa; lệch hay không có ngày sửa thì SHA-256) → hỏi lại mọi bản
  còn lại đúng cỡ + ngày sửa → xoá chúng. Server từ chối đổi chỗ (khác share SMB) → chép như Copy, kiểm SHA ở đích, rồi
  xoá mọi bản nguồn. **Không bản nguồn nào bị xoá trước khi bản ở đích được kiểm.**
  - Xoá một bản = đổi tên nó thành `<tên>.shotdex-removing`, kiểm bản ở đích còn đúng cỡ, rồi mới xoá. Đích biến mất theo
    → hai đường dẫn là một file (hai share trên một ổ): đổi tên lại, dừng lượt chạy.
  - Không bao giờ xoá bản trùng đường dẫn đích hay nằm trong folder đích; lượt chạy có folder chung trong folder nguồn bị
    từ chối trước khi chạm server.
  - Resume ở `placed`: đích được kiểm lại cả SHA-256 trước khi xoá gì. Một bản đã mất (bị xoá trước khi kịp ghi) không
    tính là "changed".
  - Sidecar nguồn chỉ xoá khi bản ở đích cùng byte, và khi không ảnh nào còn chạy cần nó (`IMG_1.JPG` + `IMG_1.MOV`).
- Một nội dung có nhiều bản trong cùng folder → folder chung nhận một bản; Move xoá mọi bản.
- `.xmp` đi theo ảnh của nó, theo luật nguồn folder ([FS-19.01 §3](01-folders-and-drives.md)): `DSC0001.xmp` là của RAW; JPEG/HEIC
  cạnh RAW chỉ nhận `DSC0001.JPG.xmp`. Lấy sidecar của bản được chép, bản đó không có thì của bản nguồn kế tiếp có. Ở
  folder chung nó mang tên cuối của ảnh (`IMG_2 (2).xmp`, hay `IMG_2 (2).JPG.xmp` nếu nguồn đặt kiểu tên đủ). Tên sidecar
  đã có byte khác → để nguyên, ảnh vẫn Copied, log ghi "sidecar not copied". Ảnh Skipped mà thiếu sidecar ở đích thì được
  thêm. Move: sidecar của các bản bị xoá cũng bị xoá.
- Trùng tên ở folder chung: cùng SHA → **Skipped (already there)**; khác → `IMG_0001 (2).JPG`. Không ghi đè.
- Một lệnh tới server một lúc mỗi connection ([03 §2](03-servers-as-sources.md)). Mac không ngủ khi đang chạy.
- Xong lượt: ghi `ShotDex Common Photos 2026-11-02 1430.csv` vào folder chung (chữ tiếng Anh cố định, UTF-8 có BOM, tên
  bắt đầu bằng `=`/`+`/`-`/`@` thêm `'` để bảng tính không chạy công thức); nguồn được **Rescan**; lịch sử upload,
  download và sổ Backup của mọi bản bị dời hay xoá **chuyển sang đường dẫn ở đích** (byte giống hệt đang nằm đó) như
  Rename của FS-17.01 §4b. CSV, Rescan hay sửa lịch sử dở chừng → lượt ở `finishing`, Resume làm lại.

## 7. Cửa sổ tiến độ (`MAC_CommonPhotosRun`)

| Trạng thái | Hiển thị |
|---|---|
| đang quét | "Listing… 12,408 files" → "Checking 32 of 312 · 1.1 GB left" |
| đang chạy | thanh tiến độ, "Copying 120 of 280 · 1.8 of 4.2 GB", dòng file đang làm ("IMG_4188.HEIC · reading back SHA-256 in Shared"), **Pause** · **Stop**; chân sidebar "Common photos · 120 of 280" |
| xong | "280 copied · 12 skipped · 0 failed", **Show CSV in Browser** · **Done** |
| lỗi nối | dừng ở file đang làm, câu lỗi FS-15.01 §3 + **Try Again**; phần đã xong giữ nguyên |
| Mac thoát / app tắt giữa chừng | lần mở sau: banner "Common photos to “Shared” stopped at 120 of 280" + **Resume** · **Discard** |

- Bảng log: một hàng mỗi ảnh — Status (Copying… · Copied · Moved · Skipped · Failed), Name, From (mọi đường dẫn nguồn), To, SHA-256
  rút gọn, lý do khi lỗi. Lọc theo Status, sắp được theo cột, ⌘C chép hàng.
- Lượt chạy cũng là một hàng trong **Activity** (⌥⌘0, [FS-18.01](../FS-18-mac-app/01-window-and-navigation.md)) — không
  modal; hàng có **Show Log** mở cửa sổ này. Đóng cửa sổ không dừng lượt chạy.

## 8. Dữ liệu

| | |
|---|---|
| Đọc từ | danh sách server (lệnh liệt kê) · SHA và ngày chụp đã có của bản sao server ([05](05-data.md), bảng file từng bản sao) |
| Ghi vào | bảng mới **Lượt gom** (connection, folder nguồn, folder chung, Copy/Move, trạng thái, lúc) + **Mục gom** (SHA, đường dẫn từng nguồn, đích, trạng thái, lỗi) |
| Người dùng tự nhập? | không — dữ liệu dẫn xuất, không vào `photo_metadata`; Clear Local Metadata Index không xoá lượt đang dở |

## 9. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| D6 | FS-19.04 "server-nguồn chỉ Hide" **có ngoại lệ** ở đây: thao tác file do người dùng chủ động, có kiểm SHA (người dùng 2026-11-02) |
| Hiệu năng | 2 × 20.000 file: bước 2–3 chạy trong bộ nhớ ≤ 1 s sau khi liệt kê xong (NF-01); byte đọc ≈ cỡ phần chung |
| Bộ nhớ | một file tạm một lúc khi chép; kiểm chỗ trống trước mỗi file (NF-02) |
| Riêng tư | byte chỉ đi giữa Mac và server của người dùng (NF-03 §2b); CSV chỉ ghi đường dẫn + SHA |
| Truy cập | mọi control có nhãn VoiceOver; bảng log đọc được theo hàng |

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| File bị đổi trên server giữa Scan và xoá | hỏi lại cỡ + ngày sửa ngay trước xoá; lệch → Failed, không xoá |
| Mất mạng giữa đổi chỗ và xoá | đích đã kiểm, bản nguồn còn lại → lần sau Resume xoá tiếp, không mất ảnh |
| C phẳng → nhiều tên trùng | luật ` (2)`, CSV ghi tên gốc |
