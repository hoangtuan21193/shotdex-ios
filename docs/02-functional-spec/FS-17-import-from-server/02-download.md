# FS-17.02 — Tải về thư viện

`FS-17.02` · `Features/ServerImport/ServerDownloadSheet.swift` · `ServerDownloadModel` · `Domain/ServerImport/ServerDownloadSession.swift`
· `Data/Database/ServerDownloadStore.swift` · cập nhật 2026-09-27

**Một câu:** chọn đích (Library hoặc album), tải từng ảnh ra đĩa tạm, kiểm, ghi vào Photos đúng một asset mỗi ảnh
với ngày chụp gốc, ghi lịch sử — cùng khuôn tiến độ/huỷ/lỗi với upload FS-15.

## 1. Bước chuẩn bị (sheet "Import to Library")

Đổi 2026-09-27 (người dùng: "download không biết là về đâu"; chốt chữ **Import to Library**, và "cho chọn album có
sẵn, new album, hoặc chỉ library — phải dễ hiểu"). Section **Import To** là ba lựa chọn rõ ràng, một dấu ✓ đứng trước
cái đang chọn:

| Hàng | Nội dung |
|---|---|
| **Library Only** (mặc định) | ảnh vào thư viện, không vào album nào |
| **Existing Album** | đẩy danh sách album của người dùng (theo tên), chọn một → quay lại, tên album hiện bên phải hàng; mờ khi chưa có album nào |
| **New Album…** | hỏi tên, tạo album, tên hiện bên phải hàng |
| chân section | câu nói kết quả: "Photos are added to your library only, not to any album." / "Photos are added to your library and to the album “Trip”." — ảnh luôn vào thư viện, album chỉ là nơi nó hiện thêm |
| Skip Photos Already in Library | công tắc, mặc định **bật**; chỉ hiện khi có ảnh đã chọn đang "In Library", kèm số |
| Tóm tắt | `N photos · X files · ~Y GB` |
| Ghi chú | "Keep ShotDex open until the import finishes. The screen stays on." |

- Nút **Import** (lối vào là nút **Import to Library**, FS-17.01 §4a) mờ khi 0 ảnh sẽ tải, hoặc khi dung lượng ước
  tính + 1 GB > chỗ trống trên máy (câu "Not enough space on this device — about Y GB needed.").
- Quyền `.limited`: chỉ còn **Library Only**, dòng phụ "Allow full access to Photos to add them to an album too." + Open
  Settings.

## 2. Tải một ảnh

1. Tải từng file của ảnh (cặp RAW+JPEG = 2 file) ra thư mục tạm theo khối, tính SHA-256 trong lúc tải.
2. **Kiểm**: số byte = số byte trên server; ImageIO mở được file; nếu lịch sử (upload/tải về) có SHA-256 cho đúng
   file này thì phải khớp (FS-17 §6). Hỏng → xoá file tạm, ảnh đó **lỗi**, lô đi tiếp.
3. Ghi vào Photos trong **một** `performChanges`:
   - một file → resource `.photo`;
   - cặp → JPEG/HEIC là `.photo`, RAW là `.alternatePhoto` (cách Photos lưu ảnh RAW+JPEG từ máy ảnh);
   - `originalFilename` = tên file trên server;
   - `creationDate` = `DateTimeOriginal` + `OffsetTimeOriginal` trong EXIF; không có thì ngày sửa file trên server;
   - đích là album → thêm placeholder vào album trong cùng lượt thay đổi.
4. Ghi một dòng lịch sử tải về (FS-17 §4), cập nhật dấu "In Library" trên lưới.
5. Xoá file tạm.

- Một ảnh một lúc. Lỗi mạng / hết chỗ → **dừng cả lô** (như FS-15); lỗi riêng một ảnh (kiểm hỏng, Photos từ chối định
  dạng) → ghi lỗi, đi tiếp.
- Photos báo lỗi định dạng (`PHPhotosError` invalid resource) → lý do "Photos can't store this format (WEBP)."

## 3. Tiến độ, huỷ, rời app

Giống FS-15.02 §6: `Importing 3 of 12` (tiêu đề sheet "Importing", xong: "Import Finished"), thanh theo byte, `1.2 of 3.4 GB · about 2 min left`, tên file và bước
(*Downloading* · *Checking* · *Saving*); sheet không kéo xuống đóng được; **Cancel** hỏi xác nhận ("Stop Importing? Photos already imported stay in your library."); màn hình không tự khoá trong lúc tải, bật lại ở mọi lối
ra; app ra nền = huỷ.

## 4. Kết quả

| Trường hợp | Hiển thị |
|---|---|
| có ảnh lưu được | "Imported N photos into your library." / "Imported N photos into your library and “<album>”." + **Show** (đích Library: chuyển sang tab Library) + **Done**. ⚠️ Show cho đích album chưa làm — mở album từ stack server cần dựng lại mục album của Collections |
| có lỗi | danh sách file lỗi kèm lý do + **Try Again** (chỉ những ảnh lỗi/chưa tải) |
| bỏ qua | "M photos skipped — already in your library." |

- Ảnh mới vào index qua `photoLibraryDidChange` như mọi ảnh khác — không gọi index riêng.
- Ảnh vừa tải về có dấu "In Library" ngay trên lưới server khi quay lại.
