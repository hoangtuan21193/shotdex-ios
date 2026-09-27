# FS-15.02 — Luồng upload

`FS-15.02` · `Features/ServerUpload/ServerUploadSheet.swift` · `ServerUploadModel` · `ServerImport/ServerBrowserScreen` (chọn folder)
· `Domain/ServerUpload/` · `Data/Database/ServerUploadStore.swift` · cập nhật 2026-09-27

**Một câu:** chọn connection ngay trong menu ⋯, chọn folder đích (nhớ lần trước), rồi một sheet đi bốn bước —
chuẩn bị → đang đẩy → (trùng tên) → kết quả — và chỉ đề nghị xoá những tấm đã khớp checksum.

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
| Connection | ≥ 2 connection: picker theo tên, đổi được mà không phải mở lại menu. 1 connection: hàng chỉ đọc |
| Folder | folder đích; chạm để duyệt (§2a). Mở sẵn **folder dùng lần trước với connection này**; chưa đẩy lần nào thì folder khai trong form (rỗng = gốc) |
| Date Folders | công tắc; bật thì chia `năm/năm-tháng-ngày` theo ngày chụp bên trong Folder (§3) |
| Files | **Only RAW** · **All Originals** (mặc định) · **Originals + Edited** |
| Tóm tắt | `N photos · X files · ~Y GB`; ở Only RAW thêm `M have no RAW and will be skipped` |
| Ghi chú | "Keep ShotDex open until the upload finishes. The screen stays on." |

- Nút **Upload** mờ khi 0 file sẽ đẩy. Loại file **không** lưu sang lần sau — mỗi lần đều chọn.
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
2. Có file cùng tên ở đích → sang bước trùng tên (§5) **trước khi** ghi gì.
3. Ghi lên server dưới tên `<tên>.shotdex-part`, theo khối.
4. Đọc lại file `.shotdex-part` từ server theo khối, tính SHA-256.
5. Khớp → đổi tên thành tên thật, ghi một dòng lịch sử. Lệch → xoá `.shotdex-part`, file đó **lỗi**.
6. Xoá file tạm trên máy.

- **Không có tên thật nào trên server trỏ tới một file chưa kiểm.** Huỷ hay rớt mạng giữa chừng chỉ để lại
  `.shotdex-part`, và app cố xoá nó ngay khi còn kết nối.
- Một file một lúc. Lỗi mạng hay đầy đĩa server → **dừng cả lô** (file sau cũng sẽ hỏng); lỗi riêng một
  file (checksum lệch, không đọc được asset) → ghi lỗi, đi tiếp.

## 5. Trùng tên

- Hiện **hai ảnh cạnh nhau**: *On This Device* và *On Server* — cả hai dựng thumbnail 400px thẳng từ file
  (bản bên server tải về đĩa trước), không giải mã cả ảnh. Dưới mỗi ảnh: dung lượng.
- Ba nút: **Replace** (đỏ — ghi đè file trên server) · **Keep Both** · **Skip**, và công tắc **Apply to remaining conflicts** (mặc định tắt).
- **Keep Both** đặt tên `<tên> (2).<đuôi>`, rồi `(3)`… cho tới tên chưa có.
- File trên server trùng **cả SHA-256** với file sắp đẩy → coi như đã có: ghi lịch sử, không hỏi, không đẩy.

## 6. Tiến độ

- Hàng trên: `Uploading 12 of 40`; thanh tiến độ theo byte, **tính cả lượt đọc lại** (mỗi file = 2× dung
  lượng); dưới: `4.1 of 9.8 GB · about 6 min left` (ETA từ tốc độ 30 s gần nhất).
- Tên file đang đẩy và bước của nó: *Preparing* (iCloud) · *Uploading* · *Verifying*.
- Sheet không kéo xuống đóng được. Nút **Cancel** hỏi xác nhận ("Stop uploading? Files already uploaded stay
  on the server.").
- Trong lúc đẩy, **màn hình không tự khoá**; bật lại tự khoá ở mọi lối ra: xong, huỷ, lỗi, đóng sheet, app
  ra nền.
- App ra nền → lô dừng như bị huỷ. Quay lại thấy kết quả với **Upload Remaining**.

## 7. Kết quả và hỏi xoá

| Trường hợp | Hiển thị |
|---|---|
| có tấm xoá được | "Uploaded N photos (X GB) to <server>." + nút đỏ **Delete N from This Device** + **Done** |
| có lỗi | danh sách file lỗi kèm lý do + **Upload Remaining** |
| 0 tấm lên | chỉ lỗi + **Try Again**; không có nút xoá |

- **Tấm được đề nghị xoá** = mọi file gốc của asset đều có dòng lịch sử (bất kỳ server nào). Ở Only RAW, cặp
  RAW+JPEG mà JPEG chưa lên thì **không** nằm trong số N, và dòng phụ nói lý do.
- Bấm Delete → hộp xác nhận của app nói hậu quả: "They move to Recently Deleted and free up space after 30
  days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your
  other devices." → rồi hộp xác nhận của hệ thống. Huỷ ở hộp nào cũng không mất gì.
- Không xoá ngay thì xoá sau từ hàng **Uploaded to Server** (§8).

## 8. Sau khi đẩy

- **Collections → Utilities → On Server → Uploaded from This Device** (màn tên **Uploaded to Server**). Đổi 2026-09-27
  (người dùng: "không được hiện button create video… phải biết ảnh đã upload lên chỗ nào"): màn là **danh sách nơi
  đến** — mỗi hàng một connection + folder (tên connection, dưới là folder, bên phải số ảnh), mới nhất trước; chạm →
  lưới ảnh của nơi đó (không có nút làm video). Ảnh lên hai nơi có ở cả hai. Hàng cuối **All Uploaded Photos** → lưới
  mọi ảnh. Tên lấy theo connection hiện tại (đã đổi tên thì theo tên mới). Hàng chỉ hiện khi có ít nhất một ảnh. Menu
  **⋯ → Delete N from This Device** xoá đúng những ảnh qua được luật §7, cùng hai hộp xác nhận.
- **Dấu trên lưới**: glyph nhỏ ở góc dưới-trái ô, trên mọi lưới. Nhãn VoiceOver "Uploaded to server".
- **Photo Info**: mỗi nơi (server + folder) một dòng: tên server, dưới là folder, bên phải ngày; mới nhất trước.
- Ảnh bị xoá khỏi thư viện → dòng lịch sử **ở lại** (bảng giữ bằng chứng); nó chỉ không còn hiện ở đâu.
