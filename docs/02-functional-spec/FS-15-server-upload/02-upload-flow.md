# FS-15.02 — Luồng upload

`FS-15.02` · `Features/ServerUpload/ServerUploadSheet.swift` · `ServerUploadModel` · `Domain/ServerUpload/`
· `Data/Database/ServerUploadStore.swift` · cập nhật 2026-09-24

**Một câu:** một sheet đi bốn bước — chuẩn bị → đang đẩy → (trùng tên) → kết quả — và chỉ đề nghị xoá
những tấm đã khớp checksum.

## 1. Lối vào

- Chế độ chọn → **⋯ → Upload to Server** ở Library, album thường, smart album (không ở On This Day —
  [FS-01.06](../FS-01-library/06-multi-select.md)). Mờ khi chưa chọn ảnh.
- Chưa có server nào: dòng vẫn bật, sheet mở thẳng vào form **Add Server**, lưu xong quay về bước chuẩn bị.

## 2. Bước chuẩn bị

| Hàng | Nội dung |
|---|---|
| Server | server dùng lần trước; chạm để chọn server khác |
| Files | **Only RAW** · **All Originals** (mặc định) · **Originals + Edited** |
| Tóm tắt | `N photos · X files · ~Y GB`; ở Only RAW thêm `M have no RAW and will be skipped` |
| Ghi chú | "Keep ShotDex open until the upload finishes. The screen stays on." |

- Nút **Upload** mờ khi 0 file sẽ đẩy. Loại file **không** lưu sang lần sau — mỗi lần đều chọn.
- **All Originals** = mọi file gốc của asset (RAW, JPEG kèm, đoạn video Live Photo, video). **Originals +
  Edited** thêm bản đã sửa nếu ảnh có chỉnh trong Photos.

## 3. Đường dẫn trên server

`<thư mục đích>/<năm>/<năm-tháng-ngày>/<tên file gốc>` — ngày chụp theo giờ máy. Ảnh không có ngày chụp
dùng ngày tạo asset. Bản đã sửa: `<tên gốc>_edited.<đuôi của bản sửa>`. Thư mục thiếu thì tạo.

## 4. Đẩy một file

1. Chép file gốc ra thư mục tạm của app (tải từ iCloud nếu cần) — tính SHA-256 trong lúc chép.
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

- Hiện **hai ảnh cạnh nhau**: *On iPhone* (thumbnail từ thư viện) và *On Server* (tải file về đĩa, dựng
  thumbnail từ file, không giải mã cả ảnh). Dưới mỗi ảnh: dung lượng và ngày sửa.
- Ba nút: **Replace** · **Keep Both** · **Skip**, và công tắc **Apply to remaining conflicts** (mặc định tắt).
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
| có tấm xoá được | "Uploaded N photos (X GB) to <server>." + nút đỏ **Delete N from iPhone** + **Done** |
| có lỗi | danh sách file lỗi kèm lý do + **Upload Remaining** |
| 0 tấm lên | chỉ lỗi + **Try Again**; không có nút xoá |

- **Tấm được đề nghị xoá** = mọi file gốc của asset đều có dòng lịch sử (bất kỳ server nào). Ở Only RAW, cặp
  RAW+JPEG mà JPEG chưa lên thì **không** nằm trong số N, và dòng phụ nói lý do.
- Bấm Delete → hộp xác nhận của app nói hậu quả: "They move to Recently Deleted and free up space after 30
  days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your
  other devices." → rồi hộp xác nhận của hệ thống. Huỷ ở hộp nào cũng không mất gì.
- Không xoá ngay thì xoá sau từ hàng **Uploaded to Server** (§8).

## 8. Sau khi đẩy

- **Collections → Utilities → Uploaded to Server**: lưới mọi ảnh còn trong thư viện đã lên ít nhất một
  server, mới nhất trước. Hàng chỉ hiện khi có ít nhất một ảnh.
- **Dấu trên lưới**: glyph nhỏ ở góc dưới-trái ô, trên mọi lưới. Nhãn VoiceOver "Uploaded to server".
- **Photo Info**: dòng "Uploaded to <tên server> · <ngày>" cho mỗi server, mới nhất trước.
- Ảnh bị xoá khỏi thư viện → dòng lịch sử **ở lại** (bảng giữ bằng chứng); nó chỉ không còn hiện ở đâu.
