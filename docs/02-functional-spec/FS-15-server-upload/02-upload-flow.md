# FS-15.02 — Luồng upload

`FS-15.02` · `Features/ServerUpload/ServerUploadSheet.swift` · `ServerUploadModel` · `ServerImport/ServerBrowserScreen` (chọn folder)
· `Domain/ServerUpload/` · `Data/Database/ServerUploadStore.swift` · cập nhật 2026-10-02

**Một câu:** chọn connection ngay trong menu ⋯, chọn folder đích (nhớ lần trước), rồi một sheet đi bốn bước —
chuẩn bị → (trùng tên, hỏi trước cho cả lô) → đang đẩy → kết quả — và chỉ đề nghị xoá những tấm đã khớp checksum.

## 1. Lối vào

Chế độ chọn → **⋯** ở Library, album thường, smart album (không ở On This Day —
[FS-01.06](../FS-01-library/06-multi-select.md)). Dòng upload mờ khi chưa chọn ảnh, và đổi dạng theo số
connection (một **connection** = một dòng đã khai trong Settings → File Servers, FS-15.01):

| Số connection | Dòng trong ⋯ | Chạm vào |
|---|---|---|
| 0 | **Upload to Server…** | sheet mở thẳng form **Add Connection**; lưu xong vào bước chuẩn bị với connection vừa tạo |
| 1 | **Upload to <tên>** | sheet mở ở bước chuẩn bị với connection đó |
| ≥ 2 | menu con **Upload to** ▸ | liệt kê **tên** từng connection, sắp theo tên, dòng phụ là đường dẫn folder (như hàng connection, FS-15.01 §2); cuối menu là **Add Connection…** |

- Chọn một tên trong menu con → sheet mở với **đúng connection đó**, không phải connection dùng lần trước.
- **Add Connection…** trong menu con → form; lưu xong vào bước chuẩn bị với connection mới.

## 2. Bước chuẩn bị

| Hàng | Nội dung |
|---|---|
| Connection | hàng mở **menu**: tên các connection theo thứ tự tên (đang dùng có ✓), đường kẻ, rồi **Add Connection…** ở cuối — đổi connection không phải mở lại ⋯. 1 connection: vẫn là menu (1 tên ✓ + Add Connection…) |
| Folder | folder đích; chạm để duyệt (§2a). Mở sẵn **folder dùng lần trước với connection này**; chưa đẩy lần nào thì folder khai trong form (rỗng = gốc) |
| Date Folders | công tắc; bật thì chia `năm/năm-tháng-ngày` theo ngày chụp bên trong Folder (§3) |
| Files | **Only RAW** · **All Originals** (mặc định) · **Originals + Edited** |
| Tóm tắt | `N photos · X files · ~Y GB`; ở Only RAW thêm `M have no RAW and will be skipped` |
| Ghi chú | theo nhánh iOS — FS-15.02b §5 |

Board: `PH_ServerUpload`, `IP_ServerUpload`, `DI_ServerUpload`, `DC_ServerUpload` (H4 — Add Connection… vào menu).

- **Add Connection…** chỉ nằm trong menu Connection, không là hàng riêng: section Connection là Connection → Folder →
  Date Folders, ngay dưới là câu giải thích Date Folders (H4). 0 connection: sheet mở thẳng form (§1).
- Một connection hay nhiều, hàng Connection cùng một dạng menu (K30) — Add Connection… luôn ở một chỗ.
- Nút **Upload** mờ khi 0 file sẽ đẩy. Loại file **không** lưu sang lần sau — mỗi lần đều chọn.
- Sheet này chỉ đẩy file gốc. Bản đã đổi cỡ theo preset Resize lên server đi qua sheet **Export…**, không ghi lịch sử
  upload ([FS-03.07b](../FS-03-photo-editor/07b-export-to-files.md) §7, chốt 2026-10-02, làm 2026-10-04 — `RemoteFolderWriter`).
- **Folder** và **Date Folders** nhớ **theo từng connection**, ghi lại lúc bấm Upload. Connection mới: Date
  Folders **tắt**. Sửa ô Folder trong form connection thì quên folder đã nhớ — form thắng.
- **All Originals** = mọi file gốc của asset (RAW, JPEG kèm, đoạn video Live Photo, video). **Originals +
  Edited** thêm bản đã sửa nếu ảnh có chỉnh trong Photos.

## 2a. Duyệt folder trên server

Đổi 2026-09-27: dùng **màn duyệt kiểu Files của FS-17.01** ở chế độ chọn folder (FS-17.01 §5) — một giao diện cho
cả xem ảnh và chọn folder.

- Đẩy trong sheet, mở ở folder đang chọn; ‹ › đi theo lịch sử, tiêu đề mở menu folder cha tới gốc (gốc = các folder
  máy tính chia sẻ với SMB, thư mục home với SFTP, gốc Path với WebDAV).
- Ảnh trong folder hiện mờ để người dùng biết mình đang ở đúng chỗ; không chọn được. Nút dưới **Choose “<folder>”**
  chọn folder đang mở và quay về bước chuẩn bị. ⋯ → **New Folder**: hỏi tên, tạo trên server, mở luôn folder đó.
- Tên folder mới: không rỗng, không chứa `/`, không bắt đầu bằng `.`. Trùng folder đã có thì mở folder đó, không báo lỗi.
- Đang nối: spinner. Hỏng (không tới được máy, sai mật khẩu, host key chưa tin…) → câu lỗi của FS-15.01 §3 +
  **Try Again**; ‹ vẫn về được. Folder gõ tay trong form không còn trên server thì bước đẩy tự tạo lại (§3) — duyệt
  không bắt buộc.
- Một kết nối dùng cho cả lượt duyệt; đóng khi đóng sheet.

## 3. Đường dẫn trên server

| Date Folders | Đường dẫn |
|---|---|
| tắt | `<folder>/<tên file gốc>` |
| bật | `<folder>/<năm>/<năm-tháng-ngày>/<tên file gốc>` — ngày chụp theo giờ máy; không có ngày chụp thì dùng ngày tạo asset |

Bản đã sửa: `<tên gốc>_edited.<đuôi của bản sửa>`, cạnh bản gốc. Thư mục thiếu thì tạo.

## 4. Đẩy một file

1. Chép file gốc ra thư mục tạm của app (tải từ iCloud nếu cần), rồi tính SHA-256 của file tạm theo khối 1 MB.
2. Tên đã có ở đích → làm theo câu trả lời của bước dò trùng tên (§5); tên mới xuất hiện sau lúc dò → **Keep Both**.
3. Ghi lên server dưới tên `<tên>.shotdex-part`, theo khối.
4. Đọc lại file `.shotdex-part` từ server theo khối, tính SHA-256.
5. Khớp → đổi tên thành tên thật, ghi một dòng lịch sử. Lệch → xoá `.shotdex-part`, file đó **lỗi**.
6. Xoá file tạm trên máy.

- **Không có tên thật nào trên server trỏ tới một file chưa kiểm.** Huỷ hay rớt mạng giữa chừng chỉ để lại
  `.shotdex-part`, và app cố xoá nó ngay khi còn kết nối.
- Một file một lúc. Lỗi mạng hay đầy đĩa server → **dừng cả lô** (file sau cũng sẽ hỏng); lỗi riêng một
  file (checksum lệch, không đọc được asset) → ghi lỗi, đi tiếp.

## 5. Trùng tên — dò cả lô trước khi đẩy

Board: chưa có board bước dò và màn trùng tên — cần vẽ trên bốn hàng thiết bị (H4, K28).

- Bấm **Upload** → bước **Checking the server…** (spinner, Cancel): liệt kê **một lần** mỗi folder đích của lô (Date
  Folders bật: mỗi folder ngày), trong app đang mở, trước khi ghi byte nào. *Vì lô chạy nền thì không ai ở đó trả lời.*
- Tên trùng mà lịch sử upload có dòng cho đúng file đó, đúng đường dẫn, cùng số byte → không hỏi (lần đẩy trước).
- Còn tên trùng → hỏi **hết, ngay bây giờ**, mỗi file một màn dưới đây, tiêu đề `1 of 7 Already on the Server`.
  Trả lời xong file cuối (hoặc bật Apply to Remaining Conflicts) thì lô mới bắt đầu đẩy; Cancel → về bước chuẩn bị.
- Liệt kê hỏng (không tới được máy, mất mạng, sai mật khẩu) → về bước chuẩn bị với câu lỗi FS-15.01 §3 + **Try
  Again**; chưa ghi gì lên server, chưa gửi yêu cầu chạy nền.
- Rời app trong lúc dò → huỷ lượt dò; quay lại thấy bước chuẩn bị, bấm Upload để dò lại.
- Đang đẩy mà gặp tên **xuất hiện sau lúc dò** (người khác vừa chép lên) → **Keep Both**, không dừng, không hỏi;
  kết quả ghi "1 file appeared on the server during the upload and was saved as IMG_1 (2).CR3."
  *Vì Replace đè một file người dùng chưa thấy, còn Skip làm mất một bản không ai biết.*

Màn mỗi file:

- Hiện **hai ảnh cạnh nhau**: *On This Device* và *On Server* — cả hai dựng thumbnail 400px thẳng từ file
  (bản bên server tải về đĩa trước), không giải mã cả ảnh. Dưới mỗi ảnh: dung lượng.
- Thứ tự từ trên xuống: hai ảnh → công tắc **Apply to Remaining Conflicts** (mặc định tắt) → **Replace** (đỏ — ghi
  đè file trên server) · **Keep Both** · **Skip**. *Vì công tắc nằm dưới nút thì người dùng đã bấm Replace trước khi
  thấy nó* (H4).
- **Keep Both** đặt tên `<tên> (2).<đuôi>`, rồi `(3)`… cho tới tên chưa có.
- Lúc đẩy, file trên server trùng **cả SHA-256** với file sắp đẩy → coi như đã có: ghi lịch sử, không đẩy, bất kể
  câu trả lời (Replace không ghi lại một file giống hệt).

## 6. Tiến độ

- Hàng trên: `Uploading 12 of 40`; thanh tiến độ theo byte, **tính cả lượt đọc lại** (mỗi file = 2× dung
  lượng); dưới: `4.1 of 9.8 GB · about 6 min left` (ETA từ tốc độ 30 s gần nhất).
- Tên file đang đẩy và bước của nó: *Preparing* (iCloud) · *Uploading* · *Verifying*.
- Sheet không kéo xuống đóng được. Nút **Cancel** hỏi xác nhận ("Stop uploading? Files already uploaded stay
  on the server.").
- Rời app trong lúc đẩy: iOS 26 chạy tiếp, trước iOS 26 dừng — luật đủ ở [FS-15.02b](02b-background-upload.md).
- Khi màn hình bị giữ sáng (trước iOS 26, hoặc iOS 26 bị hệ thống từ chối chạy nền), bật lại tự khoá ở mọi lối ra:
  xong, huỷ, lỗi, hệ thống dừng, đóng sheet, app ra nền.

## 7. Kết quả và hỏi xoá

| Trường hợp | Hiển thị |
|---|---|
| có tấm xoá được | "Uploaded N photos (X GB) to <server>." + nút đỏ **Delete N from This Device** + **Done** |
| có lỗi | danh sách file lỗi kèm lý do + **Upload Remaining** |
| 0 tấm lên | chỉ lỗi + **Try Again**; không có nút xoá |
| hệ thống dừng lô ở nền | **Upload Paused** + **Resume** (FS-15.02b §3) |
| server từ chối mật khẩu | thêm **Edit Connection** cạnh Upload Remaining (FS-15.02b §4) |

- **Tấm được đề nghị xoá** = mọi file gốc của asset đều có dòng lịch sử (bất kỳ server nào). Ở Only RAW, cặp
  RAW+JPEG mà JPEG chưa lên thì **không** nằm trong số N, và dòng phụ nói lý do.
- Bấm Delete → hộp xác nhận của app nói hậu quả: "They move to Recently Deleted and free up space after 30
  days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your
  other devices." → rồi hộp xác nhận của hệ thống. Huỷ ở hộp nào cũng không mất gì.
- Không xoá ngay thì xoá sau từ hàng **Free Up Space** của màn Uploaded to Server (FS-15.02c §2).

## 8. Sau khi đẩy

Màn **Uploaded to Server**, hàng **Free Up Space**, dấu trên lưới, Photo Info: [FS-15.02c](02c-after-upload.md).

> **Giữ thông tin file (2026-11-05):** file đẩy lên mang ngày/cờ theo [FS-19.08 §6e “Giữ thông tin file”](../FS-19-photo-sources/08-common-photos.md#6e-folder-theo-ngày-quét-nhanh-hơn--xếp-folder-chung--giữ-thông-tin-file-người-dùng-2026-11-05), đặt trước khi đổi tên part; ảnh Photos theo quyết ở đó. AC-219.

## 9. Mac (FS-18, hàng 25a của `docs/design/mac/MAC_LOOP.md`, 2026-11-08)

- **Lối vào:** File › **Upload to Server…** ⇧⌘U trên ảnh đang chọn ở lưới/danh sách/viewer (mờ khi không chọn ảnh). Một
  **sheet** trên cửa sổ Library — không cửa sổ riêng (user 2026-11-07). Cùng `ServerUploadModel` với iOS (dùng chung từ
  `Features/ServerUpload/`, phần duyệt folder và giữ màn hình chỉ có trên iOS).
- **Bước chuẩn bị** (Form): Connection (menu tên, theo tên; mở sẵn connection dùng lần trước) · Folder (ô chữ, rỗng = gốc share;
  nhớ theo connection như §2) · Date Folders + câu giải thích · Files (Only RAW · All Originals · Originals + Edited) · tóm tắt
  "3 photos · 3 files · ~1.2 MB"; ảnh không có trong Photos (thư mục, server) ghi "N aren't in Photos and aren't uploaded
  from here yet". Không có connection nào: "No server yet" + **Open Servers Settings…**. Nút **Cancel** (Esc) · **Upload** (Return, mờ khi 0 file).
- **Upload** giao lô cho Activity (hàng 25c, 2026-11-08): sheet đóng, popover **Activity** mở với mục **Uploads** đầu
  danh sách — cửa sổ Library dùng tiếp được trong lúc đẩy (MAC_STYLE: việc lâu không nằm trong sheet). Lô thuộc app
  (`MacUploads`), không thuộc cửa sổ: đóng cửa sổ không dừng nó. Nút Activity trên toolbar tô amber khi đang đẩy.
- **Hàng upload:** "Upload to Test SMB" + % · thanh 5pt · "2 of 3 files · 19 KB of 502 KB · about 1 minute left" ("Connecting to
  Test SMB…" trước file đầu) · nút ■ Stop hỏi ngay trong hàng ("Stop? Files already uploaded stay on the server." Keep Uploading ·
  Stop). Trùng tên (§5) hỏi trong hàng: "“DSC04101.JPG” is already on Test SMB", hai cỡ, **Apply to Remaining Conflicts**,
  Replace (chữ đỏ, trái) · Skip · **Keep Both**. Xong: "Uploaded 3 photos (1.2 MB), each file checked · N skipped · N failed ·
  N not sent · lý do", **Upload Remaining**/**Try Again** khi còn file, **Remove from List**. Giữ 10 hàng đã xong gần nhất.
- Một câu hỏi trùng tên đang chờ: Activity tự mở trên cửa sổ đang trước (cả khi quay lại app); app ở sau thì Dock nảy một lần.
  Hàng có câu hỏi lên đầu mục Uploads.
- Mac giữ máy không ngủ khi đang đẩy (`ProcessInfo` activity). Quit khi đang đẩy hỏi một lần "Photos are uploading. Stop and
  quit?" (Keep Uploading · Stop and Quit; có lượt Common Photos thì câu phụ nói nó tạm dừng) → dừng mọi lô, chờ tới 10 s để xoá
  file dở trên server, rồi mới thoát.
- Demo (`-ShotDexDemoLibrary`) chỉ tới được 127.0.0.1: mọi host khác trỏ vào cổng đóng, nên không bao giờ ghi lên server LAN thật.
- **Ngoài Activity** (hàng 25e): chân sidebar thay dòng index bằng "Uploading to Test SMB · 42%" + thanh 4pt khi có lô đang đẩy
  (bấm → Activity); bảng On Server: hàng có cùng server và folder (hoặc folder ngày bên trong) của lô đang đẩy ghi "Uploading 2 of 3"
  + thanh 60pt ở cột Last Upload. Model dùng chung đọc Keychain, ghi DB, dọn thư mục tạm và tính kết quả ngoài main thread; tiến
  độ byte cập nhật tối đa 10 lần/giây.
- *Còn lại:* Pause/Resume, danh sách từng file, ô ảnh Uploading/Waiting, giữ kết quả qua lần mở app (hàng 25f); duyệt folder
  trên server và **Upload…** của màn duyệt server (25d); upload ảnh chỉ có ở thư mục/server.

## 10. Mac — chỗ On Server (hàng 25b, board `MAC_ServerUpload`, 2026-11-08)

Sidebar › Utilities › **On Server**: bản Mac của Uploaded to Server (§8), trong cửa sổ Library.

- Tiêu đề "On Server", dòng phụ "40 photos · 2 servers" (ảnh trên server bất kỳ · số server đã đẩy tới).
- **Free Up Space** (thẻ đầu): "N photos · ~X GB are safely on a server and can leave this Mac" — chỉ ảnh mà **mọi** file gốc
  đã khớp checksum trên một server (`ServerUploadEligibility`, theo lịch sử upload — như iOS §7, không hỏi lại server).
  Thẻ ghi thêm "N more photos on a server can't leave yet…" khi bảng có nhiều ảnh hơn. Nút **Free Up Space…** (chữ đỏ, không
  nổi bật — lệnh xoá) hỏi "Remove N photos from This Mac?" (bản trên server không đổi; Photos → Recently Deleted, file thư mục →
  Thùng rác; + `FreeUpSpaceNote`) → **Continue** kiểm lại ngay lúc đó rồi chạy luồng Move to Trash của lưới (FS-19.04). Kiểm lại
  không còn ảnh nào: hộp "Nothing Was Removed". 0 ảnh: "Nothing to remove: …", nút mờ. Nút tắt khi đang đọc/kiểm.
- **Where They Are** (bảng): Server · Folder · Photos · Last Upload, mỗi nơi đã đẩy tới một hàng (mới nhất trước), hàng cuối
  **Every photo on any server** (ảnh đã đẩy ∪ ảnh có mặt ở nguồn server, FS-19.07 §11). Chọn hàng → lưới dưới là ảnh của nơi đó,
  tiêu đề "folder · server". Mặc định hàng cuối.
- Lưới: ô vuông 140–200 cách 2, nhãn định dạng (RAW/HEIC/JPG/MOV) và **On Server**; tối đa 600 ảnh mới nhất ("The newest 600 of N"). Chưa có gì: "Nothing on a Server Yet" + cách đẩy (File › Upload to Server…).
- Đọc cả thư viện từ DB (không phải lưới đang mở). Đọc lại sau mỗi lần đẩy (gom 1,5 s) và khi ảnh rời thư viện; danh sách
  file của từng ảnh (PhotoKit) giữ lại giữa các lần đọc, chỉ hỏi ảnh mới. Mọi đọc DB/PhotoKit ngoài main thread.
- *Sau:* trạng thái Uploading/Waiting trong ô và thanh tiến độ ở cột Last Upload (hàng 25c).

