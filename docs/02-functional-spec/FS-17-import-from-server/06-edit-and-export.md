# FS-17.06 — Sửa và dùng ảnh trên server, hỏi nơi lưu lúc xuất

`FS-17.06` · `Features/ServerImport/` (menu, sheet xuất) · `Features/Editing/` · `Collage/` · `VideoStudio/`
· `Creations/` · test `ShotDexTests/ServerEdit*Tests.swift` · cập nhật 2026-09-30

**Một câu:** ảnh trong folder On Local Network / On Cloud có các lệnh làm được trên file như ảnh trong album. Bản
gốc được tải về máy làm bản tạm, và lúc xuất app hỏi lưu đi đâu. Bản gốc trên server không bị đụng nếu người dùng
không chọn thay.

Nguồn: [intent](../../_intents/2026-09-29-network-folder-edit.md). Thay mục "Không có menu album" của
[FS-17.04 §3](04-network-shortcuts.md).

## 1. Người dùng cần gì

Ảnh nằm trên NAS hoặc Dropbox, người chụp muốn sửa một tấm, ghép collage hay share luôn. Không phải import vào
Photos trước, không để lại bản sao trong library, và biết chắc bản gốc trên server còn nguyên.

## 2. Phạm vi

**Có:** Edit (một tấm và cả loạt) · Paste Edits · Share · Copy · Combine Photos · Create Collage · Create Video ·
Resize · Export EXIF (CSV) · Import to Library (đã có). Lối vào: nhấn giữ ô, chế độ chọn, màn xem một ảnh.

**Hai đợt** (plan 2026-09-30): đợt 1 là mọi lệnh trừ Combine Photos, Create Collage, Create Video; đợt 2 thêm ba
lệnh đó (AC-67). Trong đợt 1 ba lệnh này không có trong menu, chứ không hiện rồi mờ.

**Cố ý không có:**
- Adjust Date & Time, Adjust Location, Add to Collection, Duplicate, Favorite, Hide — vì chỉ có nghĩa với Photos.
- Giữ bản nháp sang lần mở sau — vì người dùng chốt: xuất xong hoặc Discard là xoá.
- Ghi ra RAW, hay thay một bản gốc RAW — vì ShotDex chỉ xuất JPEG/HEIC.
- Rename / Delete / New Folder vẫn theo luật Files (FS-17.01 §4b), không đổi thành lệnh album.

## 3. Menu

| Lối vào | Lệnh |
|---|---|
| Nhấn giữ một ảnh | Edit · Share · Copy · Import to Library — rồi nhóm Files: Rename · Delete |
| Chế độ chọn, ⋯ | Edit · Paste Edits · Combine Photos · Create Collage · Create Video · Resize · Export EXIF (CSV) · Import to Library |
| Chế độ chọn, thanh dưới | Share · Delete (xoá trên server, hỏi như hiện nay) |
| Màn xem một ảnh | Edit · Share · Import to Library |

- Tên và glyph giống hệt menu của album (`SelectionBarViews`). Đổi tên một chỗ là đổi cả hai chỗ.
- Paste Edits chỉ hiện khi clipboard có nội dung (FS-03.10), và dán thì đi thẳng tới sheet xuất (§6).
- File không phải ảnh, hoặc ảnh không mở được, không nhận lệnh nào ngoài Rename và Delete.

## 4. Tải bản tạm

- Mọi lệnh ở §3, trừ Export EXIF, đều tải **bản gốc** trước. Cặp RAW+JPEG thì tải cả hai file, như Import (FS-17.02 §2).
- Kiểm chỗ trống **trước** khi tải: tổng dung lượng các file cộng 1 GB phải còn đủ, như FS-17.02 §1. Không đủ thì
  không tải và báo "Not enough space on this device — about Y GB needed."
- Tải xong, file được kiểm như lúc Import (số byte đúng, ImageIO mở được). Hỏng thì ảnh đó lỗi, loạt vẫn chạy tiếp.
- Có tiến độ `Downloading 3 of 12` kèm nút Cancel. Cancel thì xoá phần đã tải và quay lại lưới.
- Một connection chỉ chạy một lệnh mỗi lúc: đang tải thì lưới không tải thumbnail mới.
- Export EXIF chỉ đọc phần đầu file, như lúc vẽ thumbnail. Không tải trọn file.
- Bản tạm nằm trong một thư mục tạm có tiền tố riêng. Lần khởi động sau quét đi các thư mục còn sót (NF-02 §2).

## 5. Editor với ảnh từ server

- Editor mở như với ảnh trong library: cùng panel, cùng mask, lens profile đọc từ EXIF trong file.
- Nút lưu (Save Copy / Save Changes, FS-03.06 §2) được thay bằng một nút **Export…** mở sheet xuất (§6).
- Loạt nhiều ảnh chạy như FS-03.09b, và nút Export… xuất **mọi ảnh đã sửa** của loạt trong một lần hỏi nơi lưu.
- Rời editor khi có sửa chưa xuất (Cancel, vuốt đóng) thì hỏi "Discard edits?". Discard thì xoá bản tạm và recipe.
- Rời mà chưa sửa gì thì không hỏi, chỉ xoá bản tạm. App bị giết thì bản tạm được dọn ở lần khởi động sau.
- Recipe chỉ sống trong phiên và không bao giờ vào kho recipe của ảnh Photos.
- Collage, Video, Combine Photos, Resize và Paste Edits cũng dùng bản tạm. Nút lưu của các màn đó mở cùng sheet xuất.

## 6. Sheet xuất

| Hàng | Nội dung |
|---|---|
| **Original Folder** | tên connection + đường dẫn; mờ kèm lý do ở gốc SMB, hoặc khi folder cloud báo không ghi được |
| **Photos Library** | asset mới **chỉ gồm bản render** JPEG/HEIC, như kết quả Resize — bản gốc không vào library; ngày chụp, vị trí lấy từ EXIF gốc; `.limited` vẫn tạo được |
| **Other Folder…** | chọn connection đã lưu rồi duyệt tới folder, dùng bộ chọn folder của sheet upload (FS-15.02 §2) |
| **Share…** | share sheet, mở sau khi các đích khác đã xong |
| Khi trùng bản gốc | chỉ hiện khi chọn Original Folder: **Save as New File** (mặc định) · **Replace Original** |
| Tóm tắt | `3 photos · JPEG · ~42 MB`, định dạng theo cài đặt xuất của editor |

- Chọn được một hay nhiều đích (dấu ✓). Nút **Export** mờ khi chưa chọn đích nào.
- **Replace Original** hỏi thêm một lần, nút đỏ: "Replace 3 originals on NAS? The originals are deleted and cannot
  be recovered." Ảnh có bản gốc RAW thì không có lựa chọn này, kèm câu "Originals in RAW stay — edits are saved as JPEG or HEIC."
- Tên file mới: `<tên gốc>_edited.<đuôi>`, cùng quy ước với FS-15.02 §3 (người dùng chốt 2026-09-29). Trùng thì thêm
  ` (2)`, ` (3)`…, như Keep Both của FS-15.02 §5.
- Ghi lên server theo đúng khuôn FS-15.02 §4: `.shotdex-part` → đọc lại → SHA-256 khớp → đổi tên thật. **Không** ghi
  lịch sử upload: dòng lịch sử gắn một asset trong Photos, mà bản xuất từ server không có.
- Không thử ghi trước khi mở sheet. Server từ chối ghi thì đích đó báo "You can't write to this folder." kèm
  **Choose Another Folder**; bản tạm và recipe được giữ như mọi đích lỗi.
- Mỗi đích chạy độc lập. Xong hết thì xoá bản tạm và recipe, đóng editor, rồi quay lại lưới. Lưới tải lại folder nếu
  có ghi vào đó.
- Một đích lỗi (rớt mạng, server đầy) thì bản tạm và recipe được **giữ lại**. Sheet hiện kết quả từng đích kèm
  **Retry Failed**; rời sheet thì mới hỏi Discard (người dùng chốt 2026-09-29). Vì một lần rớt Wi‑Fi không được làm mất công sửa.

## 7. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Đĩa | loạt 20 RAW × 60 MB là 1.2 GB bản tạm. Kiểm trước, không tải dở rồi mới báo đầy |
| Bộ nhớ | editor vẫn mỗi lần một bản gốc; preview loạt nằm trên đĩa (NF-02 §2, FS-03.09b §2) |
| Mạng | một lệnh mỗi connection; tải theo khối ≤ 1 MB (FS-17 §5) |
| Riêng tư | chỉ ghi vào folder người dùng chọn; cloud qua bookmark (FS-17.05) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678; sheet xuất là tier A |
| iOS 26 vs trước | menu, sheet và nút Export… giống nhau ở hai nhánh |
| Truy cập | hàng mờ đọc được lý do; tiến độ tải có nhãn VoiceOver |

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-52 | folder NAS có `a.JPG` | nhấn giữ `a.JPG` | menu có Edit, Share, Copy, Import to Library, Rename, Delete; không có Adjust Date, Add to Collection, Duplicate, Favorite, Hide | ảnh `scripts/server-edit.json` ⚠️ chưa có |
| AC-53 | chọn 3 ảnh | mở ⋯ | 8 lệnh §3 theo đúng thứ tự, tên + glyph trùng menu album | `ServerEditMenuTests.matchesAlbumMenu` ⚠️ chưa có + ảnh |
| AC-54 | `a.JPG` 12 MB, máy còn 500 MB | Edit | tải 1 file, editor mở, server không có thay đổi nào (không ghi, không đổi tên) | `ServerEditSessionTests.downloadsOriginalOnly` ⚠️ chưa có |
| AC-55 | 3 RAW × 60 MB, máy còn 1.1 GB | Edit | không tải byte nào, báo "about 1.2 GB needed" | `ServerEditSessionTests.spaceCheckBeforeDownload` ⚠️ chưa có |
| AC-56 | đang tải ảnh 2/3 | Cancel | thư mục tạm bị xoá, quay lại lưới, không mở editor | `ServerEditSessionTests.cancelRemovesTemp` ⚠️ chưa có |
| AC-57 | editor, Exposure +1 | Cancel → Discard | bản tạm + recipe mất; mở lại `a.JPG` thì Exposure = 0 | `ServerEditSessionTests.discardDropsDraft` ⚠️ chưa có + ảnh |
| AC-58 | editor, chưa sửa gì | Cancel | không hỏi, bản tạm bị xoá | `ServerEditSessionTests.cleanLeaveNoPrompt` ⚠️ chưa có |
| AC-59 | thư mục tạm còn sót từ lần app bị giết | khởi động app | thư mục bị xoá | `TemporaryDirectorySweepTests` (thêm tiền tố) ⚠️ chưa có |
| AC-60 | sửa `a.JPG`, chọn Original Folder + Save as New File | Export | có `a_edited.jpg` cạnh `a.JPG`, SHA khớp, `a.JPG` còn nguyên byte; bản tạm bị xoá | `ServerEditExportTests.newFileBesideOriginal` ⚠️ chưa có |
| AC-61 | `a_edited.jpg` đã có | xuất lần hai | ghi `a_edited (2).jpg` | `ServerEditExportTests.nameCollisionNumbers` ⚠️ chưa có |
| AC-62 | sửa `a.JPG` | Replace Original → xác nhận | `a.JPG` mang nội dung mới; bấm Cancel ở hộp xác nhận thì không ghi gì | `ServerEditExportTests.replaceNeedsConfirm` ⚠️ chưa có + ảnh hộp |
| AC-63 | nguồn `b.CR3` | mở sheet | không có Replace Original, có câu RAW | `ServerEditExportTests.rawCannotBeReplaced` ⚠️ chưa có + ảnh |
| AC-64 | chọn Photos Library + Other Folder (SFTP `/sel`) + Share | Export | 1 asset mới trong Photos; `/sel/a_edited.jpg`; share sheet mở sau cùng | `ServerEditExportTests.multipleDestinations` ⚠️ chưa có + ảnh |
| AC-65 | folder server từ chối ghi | Export tới Original Folder | đích đó báo "You can't write to this folder." + Choose Another Folder; bản tạm còn; không file `.shotdex-part` nào sót | `ServerEditExportTests.permissionDeniedOffersAnotherFolder` ⚠️ chưa có + ảnh |
| AC-66 | loạt 5 ảnh, sửa 3 | Export… | hỏi nơi lưu 1 lần, xuất 3 file, 2 ảnh chưa sửa không xuất | `ServerEditExportTests.batchExportsEditedOnly` ⚠️ chưa có |
| AC-67 | (đợt 2) chọn 4 ảnh | Create Collage → lưu | sheet xuất §6 mở, không tự lưu vào Photos | ảnh ⚠️ chưa có |
| AC-68 | chọn 2 ảnh | Export EXIF (CSV) | CSV 2 dòng; mỗi file chỉ đọc phần đầu (≤ 1 MB) | `ServerEditExifTests.readsHeadOnly` ⚠️ chưa có |
| AC-69 | server tắt giữa lúc xuất (Original Folder), Photos đã xong | Export | Photos xong; Original Folder lỗi + Retry Failed; bản tạm + recipe còn | `ServerEditExportTests.failedDestinationKeepsDraft` ⚠️ chưa có |
| AC-70 | iOS 26.5, 18.6, iPad, Duo trong | menu + sheet | không bị cắt, cùng lệnh ở hai nhánh | ảnh ⚠️ chưa có |
| AC-72 | clipboard có look (Exposure +1), chọn 2 ảnh | Paste Edits | tải 2 bản tạm, sheet xuất mở với `2 photos`; không ghi gì trước khi bấm Export | `ServerEditSessionTests.pasteEditsGoesToExportSheet` ⚠️ chưa có |
| AC-73 | chọn 1 ảnh 6000×4000 | Resize 50% → lưu | sheet xuất mở; xuất Original Folder ra `a_edited.jpg` 3000×2000 | `ServerEditExportTests.resizeExportsThroughSheet` ⚠️ chưa có |
| AC-74 | `a.JPG` có GPS, Share bỏ vị trí đang bật | Share | share sheet nhận file bản gốc đã bỏ GPS; đóng share sheet thì bản tạm bị xoá | `ServerEditSessionTests.shareHandsOriginalAndCleansUp` ⚠️ chưa có |
| AC-75 | `b.CR3` 6000×4000 | Copy | pasteboard có ảnh cạnh dài ≤ 4096 px; bản tạm bị xoá | `ServerEditSessionTests.copyBoundsAndCleansUp` ⚠️ chưa có |

**Chưa chứng minh được:** AC-52…AC-70, AC-72…AC-75 — chưa có code. (AC-71 thuộc FS-17.03.)

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Editor, collage và video chỉ nhận ảnh trong Photos | cần một nguồn ảnh dạng file cho cả ba; đo lại đường render ảnh RAW từ file ở bước plan |
| File cloud chưa tải về máy (iCloud Drive, Dropbox online-only) | đọc qua file coordination; Cancel phải dừng được lượt tải của app Files |
| Loạt lớn trên SMB chậm (60 MB × 20) | tiến độ theo byte, giữ màn hình sáng như Import |
