# FS-19.08 — Gom ảnh chung của nhiều folder server (Mac)

`FS-19.08` · tier A (sheet) + B (cửa sổ tiến độ) · chỉ **Mac** · board `MAC_CommonPhotos` · `MAC_CommonPhotosRun`
· đề xuất `ShotDexMac/Servers/CommonPhotos/`, `ShotDex/Domain/CommonPhotos/` · AC ở [08b](08b-common-photos-ac.md)
· cập nhật 2026-11-03 (thêm hoàn tác, §6b; chạy lại chỉ ảnh mới + tự gom, §6c) · 2026-11-04 (xem kết quả Scan rồi mới quyết, chạy nhanh hơn, §6d)

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
con · kết quả xem trước có hai mức Likely the same → Same · tiến độ, dừng, làm tiếp · log trong app + CSV trong folder chung · **hoàn tác** cả lượt hoặc các hàng đã chọn
(§6b, người dùng 2026-11-03) · **chạy lại chỉ ảnh mới** và **tự gom** mỗi 15 phút (§6c, người dùng 2026-11-03).

**Cố ý không có:**
- iPhone, iPad, Duo — người dùng chọn chỉ Mac (2026-11-02).
  Ngoại lệ có chủ ý của luật "tính năng Mac có thì iPhone/iPad cũng có" (NF-05 §1): việc chạy hàng giờ trên NAS
  hợp Mac, iOS dừng app nền — người dùng chốt 2026-11-02, ghi ở [FS-18.07](../FS-18-mac-app/07-spec-deltas.md).
- Ảnh cùng ngày chụp nhưng khác byte (nén lại, ghi thêm metadata, đã sửa) — không gợi ý, không gom (người dùng 2026-11-02).
- Folder ở hai connection khác nhau — một lượt chạy trên một connection.
- Hoàn tác từ file CSV (DB của app mất, hoặc từ Mac khác) — chỉ hoàn tác từ log trong app (người dùng 2026-11-03).
- Trả ngày sửa cũ cho bản được trả về — client server chưa có lệnh đặt ngày sửa; bản trả về mang ngày sửa lúc hoàn tác.
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
| Kết quả | sau **Scan**: "312 photos in all 3 folders · 4.2 GB", hai đếm **Same 280** · **Checking 32**, danh sách (thumbnail cache nếu có, tên, đường dẫn từng folder, cỡ). **§6d:** danh sách chỉ gồm hàng Same, mỗi hàng ghi kế hoạch của nó, có ô chọn và mở so sánh được |
| Nút | **Cancel** · **Scan** → sau khi quét xong thành **Copy 280** / **Move 280** (chỉ đếm Same); chân trái "Only photos marked Same are copied." |

- Báo lỗi trong sheet, không chạy: folder chung nằm trong một folder nguồn · hai folder nguồn lồng nhau · < 2 folder.
- **Move** bấm chạy → hộp xác nhận: "Move 280 photos to “Shared”?" · "Each photo is copied to “Shared” and verified, then
  removed from Tuấn and Vợ. The server has no Trash; you can undo the run from Activity." · **Move** · **Cancel** (Cancel là nút mặc
  định: Return không xoá gì).

## 5. Quét — nhanh rồi chắc

1. Liệt kê cây mọi folder (tên, cỡ, ngày sửa); bỏ mục ẩn, `.shotdex/`, file part; chỉ ảnh, video và `.xmp`.
2. Giữ những cỡ có mặt ở **mọi** folder; còn lại loại, không đọc byte nào.
3. **Likely the same** (§6d: chỉ dùng bên trong để xếp thứ tự băm, không hiện trên màn) — trong nhóm cùng cỡ, có thêm cùng tên, cùng đường dẫn folder con, hoặc cùng ngày chụp (giây lẻ +
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

## 6b. Hoàn tác (người dùng 2026-11-03)

Hoàn tác đọc **log trong app** (bảng Lượt gom / Mục gom), không đọc CSV. Mỗi bản bị xoá ở lượt Move đã được kiểm cùng
SHA-256 với bản ở folder chung, nên trả về = chép lại đúng những byte đó.

- **Lối vào:** cửa sổ log (`MAC_CommonPhotosRun`) của lượt đã xong hoặc đã Stop có nút **Undo Copy…** / **Undo Move…**;
  chọn hàng trong bảng log → chuột phải **Undo Selected…** (chỉ hàng Copied/Moved). Lượt đang chạy, tạm dừng hay
  `finishing` thì không có nút này.
- **Hộp xác nhận** (Cancel là nút mặc định):
  - Copy: "Undo copying 280 photos?" · "The copies in “Shared” are removed. The photos in Tuấn and Vợ stay where they
    are." · **Undo Copy** · **Cancel**.
  - Move: "Undo moving 280 photos?" · "Each photo is put back in Tuấn and Vợ and checked, then removed from “Shared”." ·
    **Undo Move** · **Cancel**.
- **Undo Copy, mỗi ảnh Copied:**
  1. Hỏi lại một bản nguồn còn đúng cỡ + ngày sửa (lệch thì SHA-256). Không bản nào còn → **giữ** bản ở folder chung,
     hàng "Not undone — no other copy" (không bao giờ xoá bản cuối cùng).
  2. Bản ở folder chung phải còn đúng SHA-256 đã ghi; lệch (đã bị sửa) → giữ, "Not undone — changed in Shared".
  3. Xoá theo cách của §6 (đổi tên `.shotdex-removing`, kiểm, xoá). Sidecar mà **chính lượt này** đặt vào cũng bị xoá
     khi còn đúng SHA; sidecar có sẵn từ trước thì không đụng.
- **Undo Move, mỗi ảnh Moved:**
  1. Tải bản ở folder chung, băm khi tải; lệch SHA-256 đã ghi → không làm gì, "Not undone — changed in Shared".
  2. Mỗi bản nguồn bị xoá (trừ bản đã đổi chỗ sang đích): đường dẫn cũ trống → đẩy lên dạng file part → đọc lại SHA →
     đổi tên; đã có file **cùng byte** → coi như đã trả; có file **khác byte** → bỏ qua bản đó, log "Not put back —
     name taken", không ghi đè, không đổi tên. Sidecar của nó trả theo cùng cách, từ sidecar ở folder chung.
  3. Bản đã đổi chỗ (`movedFrom`): đường dẫn cũ trống → đổi chỗ bản ở folder chung về đó (không chép byte), sidecar đi
     theo. Đường dẫn cũ bị chiếm, hoặc lượt Move đã chép thay vì đổi chỗ (khác share) → bản ở folder chung chỉ bị xoá
     khi **mọi** bản nguồn đã được trả và kiểm; nếu không thì giữ lại ở folder chung.
  4. **Bất biến:** ở mọi bước, ảnh còn ít nhất một bản đã kiểm SHA trên server.
- Hàng Skipped, Failed, hay đã hoàn tác thì không đụng. Hoàn tác không hoàn tác được (không có "Redo").
- Trạng thái mỗi hàng sau hoàn tác: **Undone** · **Not undone** (kèm lý do) — hàng Not undone có thể thử lại bằng
  Undo Selected.
- Tiến độ, Pause/Stop, mất kết nối, quit giữa chừng, Resume: như lượt chạy (§7), câu "Undoing 120 of 280"; banner lần
  mở sau "Undo of common photos in “Shared” stopped at 120 of 280" + **Resume** · **Discard** (Discard để nguyên những
  gì đã trả).
- Xong: lịch sử upload/download và sổ Backup của các bản được trả **chuyển ngược** về đường dẫn cũ; nguồn và folder
  chung được Rescan; CSV của lượt bị xoá khi mọi hàng Copied/Moved đều Undone, còn không thì ghi thêm
  `ShotDex Common Photos <ngày giờ> Undo.csv` (cùng cột, Status = Undone / Not undone).
- **Giữ bao lâu:** Activity giữ **20 lượt đã xong** gần nhất (cả lượt đã hoàn tác); lượt thứ 21 đẩy lượt cũ nhất cùng
  các hàng của nó ra khỏi DB. Lượt dở dang không bao giờ bị đẩy ra. Hàng trong Activity có **Remove from List…**, chân
  Activity có **Remove Finished from List…** (thay "Clear" / "Clear Finished"); cả hai hỏi lại "Their logs are removed,
  so you can't undo these runs afterwards. Nothing on the server changes.", Cancel mặc định (người dùng 2026-11-03).
- Lịch sử trả **đúng từng chỗ cũ**: lượt Move ghi lại hàng lịch sử nào đến từ bản nào; bản không trả được (chỗ bị chiếm)
  thì lịch sử của nó ở lại đường dẫn đích (người dùng 2026-11-03).

## 6c. Chạy lại chỉ ảnh mới · tự gom (người dùng 2026-11-03)

Nguồn: [intent 2026-11-03-common-photos-new-only-and-sync](../../_intents/2026-11-03-common-photos-new-only-and-sync.md).

**Bộ gom** = connection + các folder nguồn (không kể thứ tự) + folder chung. Hai lượt cùng bộ là cùng một việc, khác
Copy/Move vẫn là cùng bộ.

### Nhớ những gì đã đọc

- Mỗi lần quét, ShotDex nhớ SHA-256 của **mọi file nó đã băm**: connection, đường dẫn trên server, cỡ, ngày sửa, SHA,
  và khoá ngày chụp nếu đã đọc. Nhớ cả folder **không phải nguồn** (người dùng 2026-11-03). Bảng riêng, không đụng
  `copy_files` hay `photo_metadata`.
- Lần quét sau, file có **đường dẫn + cỡ + ngày sửa** trùng thì lấy SHA đã nhớ, không đọc byte nào. Ngày sửa chỉ dùng để
  biết file có đổi hay không, không bao giờ dùng để nói hai file giống nhau (giữ luật §5).
- Chỉ lượt quét **Copy** tin SHA đã nhớ ở mọi folder: Copy không xoá gì và đọc lại SHA của bản nó ghi. Lượt quét
  **Move** vẫn băm lại mọi bản ngoài folder đầu như §5, vì Move xoá trên những bản đó. Đổi Copy → Move sau hay trong
  lúc quét thì kết quả bị bỏ, phải quét lại.
- File không còn trên server ở lần liệt kê sau: bỏ khỏi bảng nhớ.

### Chạy lại chỉ ảnh mới

- Chọn lại đúng một bộ đã từng chạy xong hay đã Stop (từ sheet, hay **Run Again…** ở hàng Activity / cửa sổ log — nút
  này mở cửa sổ Library nếu đã đóng, mở sheet đúng bộ và quét ngay), thì sheet ghi
  "Last gathered Nov 3, 2:30 PM · 280 already gathered", tiêu đề kết quả đếm "3 new photos in both folders". Không có
  ảnh mới: danh sách thay bằng "Nothing new since Nov 3, 2:30 PM" + nút **Scan Everything** (board `MAC_CommonPhotos`,
  tweak `state`). Scan chỉ đưa vào danh sách:
  - ảnh có mặt ở **mọi** folder nguồn, **và**
  - có ít nhất một bản là file **mới hoặc đổi** (đường dẫn, cỡ hay ngày sửa khác) so với lượt xong gần nhất của bộ.
- Ảnh đã có ở lượt trước với trạng thái Copied, Moved hay Skipped thì không hiện lại, không hỏi server.
- Ảnh mới chỉ ở A, chưa có ở B: không phải ảnh chung, nên chưa hiện. Lần sau B có thì nó vào (người dùng 2026-11-03).
- File đã gom, sau đó **đổi nội dung** ở A và B (cùng đường dẫn, cỡ hay ngày sửa khác): là ảnh mới, theo §5–§6. Bản cũ
  ở folder chung vẫn giữ; trùng tên thì theo luật ` (2)`.
- Ảnh đã gom mà bản ở **folder chung không còn** (người dùng xoá hay dời đi): lượt sau **chép lại**, miễn ảnh vẫn ở mọi
  folder nguồn (người dùng 2026-11-03). Mỗi lượt vì thế liệt kê cả folder chung (chỉ lệnh liệt kê, không đọc byte) để
  biết bản nào còn. Bản ở folder chung còn đúng tên (không phân biệt hoa thường) + cỡ thì coi là còn, không đọc lại.
  Đổi tên bản trong folder chung là "mất": ảnh được chép lại dưới tên cũ. Folder chung chưa có thì mọi ảnh là mới;
  không liệt kê được (mất kết nối sau một lần nối lại, không có quyền) thì kiểm lại mọi ảnh — Copy vẫn bỏ qua bản đã
  có cùng byte.
- **Scan Everything** (nút phụ trong sheet khi bộ đã từng chạy): quét như lần đầu, vẫn dùng SHA đã nhớ.
- "Lượt trước" = mọi lượt gom (không phải lượt hoàn tác) của bộ mà Activity còn giữ, đã xong, đã Stop hay đang
  `finishing`; tính ảnh Copied, Moved, Skipped (ảnh đã hoàn tác thì không). Server không cho ngày sửa thì so đường dẫn +
  cỡ.
- Chọn folder chung **sau** khi quét (hay trong lúc quét): kết quả bị bỏ những ảnh bộ đó đã gom, không quét lại; đổi
  sang folder chung khác thì kết quả cắt lại theo bộ mới. Chỉ khi lượt quét đã chỉ đọc phần mới của một bộ thì đổi
  folder chung mới phải quét lại.
- Giới hạn đã biết: sidecar `.xmp` đổi hay mới thêm mà ảnh không đổi thì không làm ảnh thành "mới"; chọn folder
  khác hoa thường (`Photos/Tuan` và `photos/tuan`) là bộ khác.

### Tự gom (Keep Gathering)

- Sheet có ô **Keep gathering new photos** (tắt sẵn). Bật rồi chạy: sau lượt đầu, helper Mac (`--agent`, đã chạy kiểm
  On Server, FS-19.07 §11) cứ **15 phút** chạy lại bộ đó theo kiểu "chỉ ảnh mới" (người dùng 2026-11-03), kể cả khi app
  đóng.
- Chỉ chạy khi Mac **cắm điện** và mạng **không tính tiền** (người dùng 2026-11-03); không đủ thì bỏ qua lượt đó, ghi lý
  do ("Waiting to Charge", "Waiting for Wi‑Fi" — chữ có sẵn của FS-19.07). Backup trên cùng connection đi trước (khoá
  kết nối, FS-19.07 §5).
- **Copy**: lượt tự gom tìm thấy ảnh thì chạy luôn như §6, có log, CSV, hoàn tác §6b.
- **Move**: lượt tự gom chỉ quét. Có ảnh thì gửi thông báo macOS "4 photos are ready to move to “Shared”" và hàng
  Activity "Ready to move 4"; bấm vào mở cửa sổ log với nút **Move 4…**, hỏi lại như §4 rồi chạy như §6. Không có gì bị
  dời hay xoá khi người dùng chưa bấm (người dùng 2026-11-03).
  - Ảnh chờ nằm trong một lượt trạng thái `ready`, mỗi bộ chỉ một lượt như vậy. Lượt tự gom sau thay danh sách của nó
    bằng kết quả mới, và chỉ gửi thông báo khi có ảnh chưa từng nằm trong danh sách. Lượt không tìm thấy gì thì xoá
    danh sách (ảnh đã bị dời bằng tay).
  - Lượt `ready` không có Resume, Stop, Discard hay hoàn tác, và không tính vào 20 lượt giữ lại. Ảnh đã dời trước đó
    trong ngày vẫn là một lượt đã xong riêng, hoàn tác được. Vì vậy một bộ Move có thể có hai hàng trong cùng một ngày.
  - Move N… chỉ dời đúng danh sách người dùng đang xem. Lượt tự gom đổi danh sách trong lúc hộp hỏi đang mở thì hỏi lại
    với danh sách mới. Không có connection hoặc đang có lượt khác chạy trên cùng folder thì lượt vẫn ở `ready`, header
    nói lý do.
  - Remove from List…, Stop Gathering, hay xoá connection: bỏ danh sách, không dời gì. Bộ vẫn đang tự gom thì lần
    kiểm sau liệt kê lại.
  - Bộ đổi từ Copy sang Move hay ngược lại: không gom thêm vào lượt của hành động kia.
  - Xin quyền thông báo khi bật Keep gathering cho bộ Move, không xin lúc mở app. Bấm thông báo mở cửa sổ log của lượt.
- Lượt tự gom không tìm thấy gì: không thêm hàng Activity, chỉ cập nhật "Checked 3 min ago" của bộ.
- Server không trả lời: bỏ lượt, ghi "NAS Home isn't reachable", lượt sau thử lại. Không bao giờ dừng giữa chừng một
  lượt Move mà không đi tiếp được theo §6 (Resume như cũ).
  - Server ngắt giữa lượt chạy: lượt sau (đủ điện, mạng, folder còn) chạy tiếp lượt đó, không quét lại. Ảnh đã xong
    không làm lại. Chạy xong thì hết dòng "isn't reachable".
  - Lượt người dùng tự Pause hay Stop, hay app thoát giữa chừng, là của người dùng: không lượt tự gom nào chạy tiếp nó.
    Lỗi không phải do server (Mac hết chỗ, sai mật khẩu, không có quyền, server đầy) cũng không tự chạy tiếp.
  - Một lượt của bộ còn dở, kể cả của ngày trước, giữ các ảnh của nó. Lượt tự gom sau không gom lại các ảnh đó vào
    lượt khác.
  - Bộ đổi Copy↔Move, bị dừng hay được bật lại: quên lượt đang chờ chạy tiếp.
- Folder chỉ tính là mất khi server nói hai lần: folder không có, **và** folder cha liệt kê được mà không có nó. Mọi
  trường hợp khác (không liệt kê được, lỗi giữa chừng) là server vắng, thử lại lượt sau. Bộ không còn đủ 2 folder hay
  connection bị xoá: cũng dừng.
- Folder nguồn hay folder chung không còn trên server: bộ **tạm dừng**, hàng Activity "“Vợ” isn't on NAS Home anymore ·
  Stopped gathering", không thử lại cho tới khi người dùng bật lại.
- Helper và app dùng chung một database. Mỗi bộ chỉ một lượt gom một lúc, mỗi lượt chạy chỉ một process: khoá trong DB,
  hết hạn sau 2 phút không gia hạn. Helper gom. App chỉ gom khi helper không chạy job (Keep Working After Quit tắt, hay
  macOS chưa cho). Khi đó ô Keep gathering ghi "… and ShotDex is open".
- Giới hạn đã biết: lượt đã bắt đầu chạy tiếp dù Mac rút điện hay chuyển sang mạng tính tiền giữa chừng. Luật điện và
  mạng chỉ áp lúc bắt đầu lượt.
- **Danh sách bộ đang tự gom**: mục **Gathering** đầu cửa sổ Activity, mỗi bộ một hàng ("Tuấn + Vợ → Shared · Copy ·
  checked 3 min ago · 128 gathered"), menu hàng **Run Now** · **Stop Gathering**. Stop Gathering không đụng log hay
  file.
  Chỗ này là Activity, không phải Settings (người dùng 2026-11-03).
- **Gộp theo ngày** (người dùng 2026-11-03): mọi lượt tự gom có ảnh trong một ngày (giờ máy) của một bộ là **một lượt**
  trong Activity — "Tuấn + Vợ → Shared · Nov 3 · 12 copied". Mỗi lượt tự gom thêm hàng vào lượt đó và ghi lại CSV của
  ngày (`ShotDex Common Photos 2026-11-03 auto.csv`). Hoàn tác cả ngày hay từng hàng như §6b. Ngày đã qua thì lượt của
  nó đóng lại, tính vào giới hạn 20 lượt như lượt tay.
- Bản cho iPhone/iPad: không (FS-19.08 chỉ Mac).
- **Board** (vẽ trước khi code, canvas Mac): `MAC_CommonPhotos` thêm tweak `state` (again · nothingNew: câu "Last gathered…", ô Keep
  gathering, nút Scan Everything) · `MAC_CommonPhotosRun` thêm trạng thái `readyToMove` · `MAC_Activity` thêm mục
  Gathering.

## 6d. Xem kết quả Scan rồi mới quyết · chạy nhanh hơn (người dùng 2026-11-04)

Nguồn: [intent 2026-11-04-common-photos-compare-before-run](../../_intents/2026-11-04-common-photos-compare-before-run.md).
Board: `MAC_CommonPhotos` (sửa: hàng kế hoạch, ô chọn, mục Left Out) · `MAC_CommonPhotosCompare` (mới) ·
`MAC_CommonPhotosRun` (danh sách ready có ô chọn). Vẽ board trước khi code (luật canvas). Tiền lệ phải đọc trước khi
vẽ: board `MAC_Duplicates` (so A/B) và `PhotoCompareScreen` của iOS, để không thành hai kiểu so sánh.

### Chỉ Same

- Danh sách sau Scan chỉ có hàng **Same** (SHA-256 cả file trùng). Hàng chưa xong băm không hiện: đầu danh sách vẫn đếm
  **Checking 32** như tiến độ, cho tới khi về 0.
- Likely bỏ khỏi màn (nhãn, đếm, VoiceOver). Bên trong vẫn dùng để băm trước ứng viên Likely (§5 bước 4).
- Luật §5 giữ nguyên: chỉ Same được chạy, tên hay ngày sửa không bao giờ làm hai file thành Same.

### Kết quả Scan là kế hoạch

Scan liệt kê luôn folder chung, nên mỗi hàng Same biết sẵn việc nó sẽ làm. Hàng ghi:

| Trường hợp | Dòng phụ của hàng |
|---|---|
| Copy, tên còn trống ở folder chung | `→ Shared/IMG_4021.HEIC` |
| Copy, folder chung có tên đó mà khác byte | `→ Shared/IMG_0001 (2).JPG` |
| Folder chung đã có bản cùng SHA | `Already in Shared` (hàng mờ, không đếm vào nút; vẫn được thêm sidecar thiếu như §6) |
| Move | `→ Shared/IMG_4021.HEIC · removes 2 copies` — rê chuột (`.help`) ra đủ đường dẫn từng bản sẽ bị xoá |

- Đầu danh sách: "280 photos · 31 videos · 4.2 GB · 2 already in Shared".
- **Bấm Copy N / Move N là chạy đúng kế hoạch đó.** Không băm lại SHA của bản nguồn:
  - Copy: SHA tính ngay trong lúc tải bản nguồn đầu, không tốn thêm lượt đọc. Lệch so với Scan → ảnh Failed "changed on
    the server", không ghi gì.
  - Move: kiểm cỡ + ngày sửa từng bản (§6). Chỉ băm khi một trong hai lệch.
- Folder chung đổi giữa Scan và chạy (có file mới trùng tên): lượt chạy chọn tên trống kế tiếp, không ghi đè (§6). Log
  và CSV ghi tên cuối thật.
- Kế hoạch là của lần Scan này. Đổi folder, đích, hay Copy ↔ Move thì bỏ kết quả, phải Scan lại (như §6c).

### So sánh hai bản

- Hàng Same → **Space** hay nhấp đúp → cửa sổ **Compare** (không modal, một cửa sổ cho cả sheet). ←/→ hoặc ↑/↓ sang
  hàng kế; Esc đóng.
- Hai khung cạnh nhau, mỗi khung một bản (folder đầu bên trái). Mỗi khung ghi: folder, tên, cỡ, ngày chụp, SHA-256 8 ký
  tự đầu. Dưới hai khung: "Same bytes — SHA-256 matches", kèm SHA đủ (chọn được để chép).
- Ba folder trở lên: khung phải có popup chọn bản để so với bản bên trái.
- **Ảnh:** hiện vừa khung. Cùng zoom và cùng vị trí cho cả hai khung (cuộn hay zoom một bên, bên kia theo).
- **Video:** một nút Play và một thanh tua cho cả hai; hai bên luôn cùng thời điểm (lệch ≤ 1 khung hình); tiếng chỉ bên
  trái.
- **Byte lấy ở đâu:** bản đã index thì dùng ảnh preview đã có. Chưa index thì **tải cả file** về thư mục tạm:
  - thanh tiến độ từng khung;
  - chỉ tải hai bản của hàng đang xem; sang hàng khác thì huỷ lượt tải dở;
  - file tạm xoá khi đóng Compare.
  - giữ tạm tối đa **2 GB** (người dùng 2026-11-04), bỏ cái cũ nhất trước, để quay lại hàng vừa xem không tải lại.
- Tải để xem không chặn Scan đang chạy: lệnh của Compare xếp sau lệnh của Scan trên cùng connection (03 §2). Lúc Scan còn
  chạy, khung ghi "Waiting for the scan…".
- Mất kết nối khi đang tải: khung ghi câu lỗi FS-15.01 §3 + **Try Again**; sheet và Scan không bị ảnh hưởng.
- RAW không giải mã được trên máy này: khung hiện preview nhúng nếu có, không có thì biểu tượng file + "No preview for
  this RAW". Đây không phải lỗi.

### Bỏ chọn từng hàng

- Mỗi hàng Same có ô chọn, mặc định chọn hết. Chọn nhiều hàng rồi Space bật/tắt cả nhóm. Menu chuột phải: **Leave
  Out** / **Include**, **Compare**.
- Nút đếm đúng số đang chọn: **Copy 278** / **Move 278**. Bỏ hết → nút mờ.
- Hàng bỏ ra được **nhớ cho bộ gom đó** (§6c), theo SHA-256 (đổi tên hay dời trong A/B vẫn nhận ra):
  - lượt quét lại, Run Again và tự gom không chạy ảnh đó;
  - danh sách có mục thu gọn **Left Out (2)** ở cuối, mở ra thấy hàng mờ với nút **Include**;
  - Include → lần chạy sau tính lại ảnh đó.
- Bảng riêng **Ảnh bỏ ra** (bộ gom, SHA-256, lúc bỏ). Đây là dữ liệu người dùng tự tạo (BD-02): không nằm trong
  `photo_metadata` hay `common_photo_scan_records`. Clear Local Metadata Index không xoá. Xoá bộ gom (Remove from List,
  xoá connection) thì xoá theo.

### Danh sách Move chờ của tự gom

- Cửa sổ log của lượt ready (§6c, AC-169) dùng cùng hàng: kế hoạch, ô chọn, Compare, Leave Out.
- **Move N…** đếm theo số đang chọn. Hộp xác nhận nói đúng số đó.
- Hàng bỏ ra ở đây cũng vào bảng Ảnh bỏ ra của bộ, nên lượt tự gom sau không đưa lại.

### Chạy nhanh hơn

Hôm nay Copy cho mỗi ảnh đi qua mạng **3 lần**: tải bản nguồn về Mac, đẩy lên folder chung, đọc lại bản ở đích để kiểm
SHA. Move không chép byte. Scan phải băm mọi bản cùng cỡ: đọc **2 lần** phần chung (mỗi folder một lần), lần sau dùng
SHA đã nhớ (§6c).

1. **Copy ngay trên server.** NAS tự chép file, byte không qua Mac. Có hay không tuỳ loại connection:

   | Connection | Lệnh | Hôm nay trong app |
   |---|---|---|
   | SMB | `FSCTL_SRV_COPYCHUNK` (Samba, Windows, Synology, QNAP có) | thư viện `SMBClient` có mã lệnh `srvCopyChunk` nhưng chưa có hàm gọi |
   | WebDAV | `COPY` (RFC 4918) | client mới có `MOVE` |
   | SFTP | không có trong giao thức (chỉ vài server có `copy-data`) | — |

   Server không làm được (lệnh bị từ chối, khác share) → lùi về tải + đẩy như hôm nay, không báo lỗi. Log ghi cách đã chép.

   Đã chốt (người dùng 2026-11-04): vá thêm hàm copychunk vào bản sao `SMBClient` trong repo (local package). Bản vá
   phải ghi rõ để giữ khi cập nhật thư viện. WebDAV `COPY` làm cùng lúc.
2. **Kiểm bản ở đích sau Copy.**

   Đã chốt (người dùng 2026-11-04): vẫn **đọc lại SHA** bản ở đích. Với server copy, đây là lần duy nhất byte qua mạng:
   1× thay cho 3×. Move giữ nguyên kiểm như §6.
3. **Băm song song khi Scan.** Hôm nay một lệnh tới server một lúc mỗi connection (03 §2).

   Đã chốt (người dùng 2026-11-04): **giữ một lệnh**. NAS một ổ cứng có thể chậm đi khi đọc hai file một lúc, và đo trên
   SMB ảo không nói được gì về NAS thật. Song song hoá chỉ xét lại khi có số đo trên NAS của người dùng; không thuộc §6d.
4. Không thêm cách nào bỏ băm khi Scan: SHA cả file là điều kiện của Same. Video lớn tốn thời gian theo đúng cỡ của nó.

**Đích đo được** (SMB ảo, 1 GB phần chung, 2 folder):

| Đo | Hôm nay | Sau §6d (phương án đề xuất) |
|---|---|---|
| Byte qua mạng khi Copy | ≈ 3 GB | ≤ 1.1 GB (server copy + đọc lại SHA) |
| Lệnh `sha256` lên bản nguồn khi chạy (Copy và Move) | Copy 0, Move 0 khi không đổi | 0 |
| Quét lại cùng bộ, không đổi | 0 byte (§6c) | 0 byte |

## 7. Cửa sổ tiến độ (`MAC_CommonPhotosRun`)

| Trạng thái | Hiển thị |
|---|---|
| đang quét | "Listing… 12,408 files" → "Checking 32 of 312 · 1.1 GB left" |
| đang chạy | thanh tiến độ, "Copying 120 of 280 · 1.8 of 4.2 GB", dòng file đang làm ("IMG_4188.HEIC · reading back SHA-256 in Shared"), **Pause** · **Stop**; chân sidebar "Common photos · 120 of 280" |
| xong | "280 copied · 12 skipped · 0 failed", **Undo Copy…** / **Undo Move…** · **Show CSV in Browser** · **Done** |
| đang hoàn tác / đã hoàn tác | "Undoing 120 of 280" · Pause · Stop → "280 undone · 2 not undone" (§6b) |
| lỗi nối | dừng ở file đang làm, câu lỗi FS-15.01 §3 + **Try Again**; phần đã xong giữ nguyên |
| Mac thoát / app tắt giữa chừng | lần mở sau: banner "Common photos to “Shared” stopped at 120 of 280" + **Resume** · **Discard** |

- Bảng log: một hàng mỗi ảnh — Status (Copying… · Copied · Moved · Skipped · Failed), Name, From (mọi đường dẫn nguồn), To, SHA-256
  rút gọn, lý do khi lỗi. Lọc theo Status, sắp được theo cột, ⌘C chép hàng.
- Lượt chạy cũng là một hàng trong **Activity** (⌥⌘0, [FS-18.01](../FS-18-mac-app/01-window-and-navigation.md)) — không
  modal; hàng có **Show Log** mở cửa sổ này. Đóng cửa sổ không dừng lượt chạy. Lượt đã xong vẫn ở Activity qua các lần
  mở app (20 lượt gần nhất, §6b) để còn mở log và hoàn tác.

## 8. Dữ liệu

| | |
|---|---|
| Đọc từ | danh sách server (lệnh liệt kê) · SHA và ngày chụp đã có của bản sao server ([05](05-data.md), bảng file từng bản sao) |
| Ghi vào (§6c) | bảng **SHA đã đọc** (connection, đường dẫn, cỡ, ngày sửa, SHA, khoá ngày chụp, lúc đọc) · bảng **Bộ tự gom** (connection, folder nguồn, folder chung, Copy/Move, bật/tắt, lúc kiểm cuối, lý do chờ/dừng, số đã gom); lượt gom thêm cột bộ gom để biết "lượt xong gần nhất của bộ" |
| Ghi vào | bảng mới **Lượt gom** (connection, folder nguồn, folder chung, Copy/Move, trạng thái, lúc) + **Mục gom** (SHA, đường dẫn từng nguồn, đích, trạng thái, lỗi; thêm cho §6b: sidecar lượt đã đặt ở đích + SHA của nó, trạng thái hoàn tác) + bảng phụ **hàng lịch sử đã dời** (lượt, ảnh, hàng lịch sử, đường dẫn trước khi dời) |
| Ghi vào (§6d) | bảng **Ảnh bỏ ra** (bộ gom, SHA-256, lúc bỏ) — người dùng tự tạo, bảng riêng; kế hoạch của từng ảnh (tên dự kiến ở đích, Already in Shared) đi cùng kết quả Scan, ghi vào `common_photo_items` khi bấm chạy |
| Người dùng tự nhập? | §6d: **có**, bảng Ảnh bỏ ra (Clear Local Metadata Index không xoá; xoá theo bộ gom). Còn lại không — dữ liệu dẫn xuất, không vào `photo_metadata`; Clear Local Metadata Index không xoá lượt đang dở |

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
| Hoàn tác Copy xoá bản cuối cùng (người dùng đã xoá A, B sau khi chép) | hỏi lại một bản nguồn trước khi xoá; không còn → giữ |
| File ở folder chung bị sửa sau lượt chạy | SHA lệch → không trả bản đó, không xoá gì |
| Hoàn tác Move chậm như lượt chạy | phải đẩy lại byte cho mọi bản không phải bản đã đổi chỗ; tiến độ đếm byte |
| §6c: file đổi nội dung mà giữ nguyên cỡ và ngày sửa (công cụ ghi đè giữ mtime) | SHA cũ bị dùng lại, ảnh có thể bị coi là chung sai. Copy vẫn an toàn (chép byte thật, kiểm SHA khi đọc lại); Move hỏi lại cỡ + ngày sửa và kiểm SHA ở đích như §6, nên không xoá nhầm. Scan Everything không giúp; giới hạn đã biết |
| §6d: server copy trên NAS ghi sai mà vẫn báo xong | đọc lại SHA ở đích (đã chốt) bắt được |
| §6d: tải cả file để Compare với RAW/video lớn | chỉ hai bản của hàng đang xem, huỷ khi sang hàng khác, trần cache tạm, xoá khi đóng |
| §6c: tự gom 15 phút trên NAS 50k file | mỗi lượt liệt kê lại hai cây (lệnh liệt kê, không đọc byte); đo ở `/verify`, nếu một lượt quá 2 phút thì giãn chu kỳ |
