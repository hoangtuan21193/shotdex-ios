# FS-17.06 — Sửa và dùng ảnh trên server, hỏi nơi lưu lúc xuất

`FS-17.06` · `Features/ServerImport/` (menu, sheet xuất) · `Features/Editing/` · `Collage/` · `VideoStudio/`
· `Creations/` · test `ShotDexTests/ServerEdit*Tests.swift` · cập nhật 2026-09-30 (đợt 1 và đợt 2 xong)

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
lệnh đó (AC-67, AC-76…84). Trong đợt 1 ba lệnh này không có trong menu, chứ không hiện rồi mờ. Combine Photos có
đủ ba hàng như album: Focus Stack, Panorama, Stack Exposures.

**Cố ý không có:**
- Adjust Date & Time, Adjust Location, Add to Collection, Duplicate, Favorite, Hide — vì chỉ có nghĩa với Photos.
- Giữ bản nháp sang lần mở sau — vì người dùng chốt: xuất xong hoặc Discard là xoá.
- Ghi ra RAW, hay thay một bản gốc RAW — vì ShotDex chỉ xuất JPEG/HEIC.
- Rename / Delete / New Folder vẫn theo luật Files (FS-17.01 §4b), không đổi thành lệnh album.

## 3. Menu

| Lối vào | Lệnh |
|---|---|
| Nhấn giữ một ảnh | Edit · Share · Copy · Import to Library — rồi nhóm Files: Rename · Delete |
| Chế độ chọn, thanh trên | nút chữ **Edit** cạnh ⋯, như chế độ chọn của album |
| Chế độ chọn, ⋯ | Paste Edits · Combine Photos · Create Collage · Create Video · Resize · Export EXIF (CSV) · Import to Library |
| Chế độ chọn, thanh dưới | Share · Delete (xoá trên server, hỏi như hiện nay) |
| Màn xem một ảnh | Edit · Share · Import to Library |

- Tên và glyph giống hệt menu của album (`SelectionBarViews`). Đổi tên một chỗ là đổi cả hai chỗ.
- Paste Edits chỉ hiện khi clipboard có nội dung (FS-03.10), và dán thì đi thẳng tới sheet xuất (§6).
- File không phải ảnh, hoặc ảnh không mở được, không nhận lệnh nào ngoài Rename và Delete.

## 4. Tải bản tạm

- Mọi lệnh ở §3, trừ Export EXIF, đều tải **bản gốc** trước. Cặp RAW+JPEG thì tải cả hai file, như Import (FS-17.02 §2).
- Kiểm chỗ trống **trước** khi tải: tổng dung lượng các file cộng 1 GB phải còn đủ, như FS-17.02 §1. Không đủ thì
  không tải và báo "Not enough space on this device — about Y more needed.", cùng câu với Import.
- Tải xong, file được kiểm như lúc Import (số byte đúng, ImageIO mở được). Hỏng thì ảnh đó lỗi, loạt vẫn chạy tiếp.
- Có tiến độ `Downloading 3 of 12` kèm nút Cancel. Cancel thì xoá phần đã tải và quay lại lưới.
- Một connection chỉ chạy một lệnh mỗi lúc: đang tải thì lưới không tải thumbnail mới.
- Export EXIF chỉ đọc phần đầu file, như lúc vẽ thumbnail. Không tải trọn file.
- Bản tạm nằm trong một thư mục tạm có tiền tố riêng. Lần khởi động sau quét đi các thư mục còn sót (NF-02 §2).

## 5. Editor với ảnh từ server

- Editor mở như với ảnh trong library: cùng panel, cùng mask, lens profile đọc từ EXIF trong file.
- Nút lưu (Save Copy / Save Changes, FS-03.06 §2) được thay bằng một nút **Export…** mở sheet xuất (§6).
- Loạt nhiều ảnh chạy như FS-03.09b, và nút Export… xuất **mọi ảnh đã sửa** của loạt trong một lần hỏi nơi lưu.
- Rời editor khi có sửa chưa xuất (Back, Cancel) thì hỏi như với ảnh library: "Discard this editing session?".
  Discard thì xoá bản tạm và recipe. Editor che toàn màn hình nên không vuốt đóng được.
- Rời mà chưa sửa gì thì không hỏi, chỉ xoá bản tạm. App bị giết thì bản tạm được dọn ở lần khởi động sau.
- Recipe chỉ sống trong phiên và không bao giờ vào kho recipe của ảnh Photos.
- Collage, Video, Combine Photos, Resize và Paste Edits cũng dùng bản tạm. Nút lưu của các màn đó mở cùng sheet xuất.

### 5b. Collage, Combine Photos, Create Video (đợt 2)

- Màn công cụ mở như với ảnh library, với các ảnh server đã tải. Nút lưu đổi thành **Export…**: công cụ render ra một
  file trong thư mục tạm, rồi mở sheet xuất ở chế độ **một file gộp** (§6b).
- **Được trộn ảnh library** (người dùng chốt 2026-09-30): picker thêm ảnh trong Collage và Video Studio vẫn còn, và
  ảnh library thêm vào không bị đổi gì. **Kéo thả** file từ app khác thì tắt trong lượt này, vì nó import file vào
  Photos trước.
- Không lưu gì vào Photos lúc bấm Export…, không tạo album "ShotDex Collages", không ghi dòng Creations: recipe chỉ
  sống trong phiên (§5).
- Focus Stack xếp khung theo ngày chụp EXIF trong file, rồi theo tên file, như với ảnh library.
- Rời công cụ khi đã làm gì đó thì hỏi "Discard?", như công cụ đó vẫn hỏi với ảnh library: Collage và Video khi có
  bước undo nào, Combine khi đã có nét retouch. Chưa làm gì thì không hỏi. Cả hai đường đều xoá bản tạm.
- Video Studio đọc ảnh server ở cỡ render, không giải mã full-res cho mỗi khung (NF-02).
- Paste Edits và Resize không mở editor: tải xong là vào thẳng sheet xuất. Resize thêm mục **Size** (các cỡ dựng sẵn
  của Resize: 4K, 2048 px, 1080 px). Sắp đổi ([FS-03.07b](../FS-03-photo-editor/07b-export-to-files.md) §8, chưa làm): Size ở mọi lần xuất không gộp.

## 6. Sheet xuất

| Hàng | Nội dung |
|---|---|
| **Original Folder** | tên connection + đường dẫn; mờ kèm lý do ở gốc SMB, hoặc khi folder cloud báo không ghi được |
| **Photos Library** | asset mới **chỉ gồm bản render** JPEG/HEIC, như kết quả Resize — bản gốc không vào library; ngày chụp, vị trí lấy từ EXIF gốc; `.limited` vẫn tạo được |
| **Other Folder…** | chọn connection đã lưu rồi duyệt tới folder, dùng bộ chọn folder của sheet upload (FS-15.02 §2). Sắp thêm dòng đầu **Folder in Files…** (FS-03.07b §8, chưa làm) |
| **Share…** | share sheet, mở sau khi các đích khác đã xong |
| Khi trùng bản gốc | chỉ hiện khi chọn Original Folder: **Save as New File** (mặc định) · **Replace Original** |
| Định dạng | JPEG / HEIC; Replace Original luôn giữ định dạng của bản gốc |
| Size *(FS-03.07b §8, chưa làm)* | mọi lần xuất không gộp: preset của Resize **kể cả preset tự tạo**, mặc định Original (Resize: 2048 px) |
| Tóm tắt | `3 photos · JPEG` — cỡ file chỉ biết sau khi render nên không ước |

- Chọn được một hay nhiều đích (dấu ✓). Nút **Export** mờ khi chưa chọn đích nào.
- Replace Original chỉ có khi **mọi** ảnh là JPEG hoặc HEIC đơn lẻ; bản render lấy đúng định dạng và tên của bản gốc.
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

### 6b. Chế độ một file gộp (Collage, Combine, Video)

| Hàng | Nội dung |
|---|---|
| **Name** | ô nhập tên, mặc định `<tên ảnh đầu>_collage` · `_focus-stack` · `_panorama` · `_stack` · `_video`; đuôi `.jpg` / `.heic` / `.mp4` hiện cạnh ô, không sửa được (người dùng chốt 2026-09-30) |
| Save To | bốn đích như §6; Original Folder là folder của ảnh server đầu tiên |
| Không có | Save as New File / Replace Original (không có bản gốc nào để thay), Format (công cụ đã chọn), Size |
| Tóm tắt | `Collage · JPEG` · `Focus Stack · JPEG` · `Video · MP4` |

- Tên rỗng, hoặc chỉ gồm `/ : \` và khoảng trắng, thì nút Export mờ. Ký tự `/ : \` bị bỏ khỏi tên.
- Trùng tên ở đích thì thêm ` (2)`, ` (3)`…, như §6.
- Photos Library nhận ảnh gộp như một ảnh, và video như một video.

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
| AC-52 | folder NAS có `a.JPG` | nhấn giữ `a.JPG` | menu có Edit, Share, Copy, Import to Library, Rename, Delete; không có Adjust Date, Add to Collection, Duplicate, Favorite, Hide | `ServerEditMenuTests.longPressMenu` + ảnh `assets/2026-09-30-fs1706-ios26-11-long-press-menu.png` |
| AC-53 | chọn 3 ảnh | nhìn thanh trên, mở ⋯ | nút Edit cạnh ⋯; ⋯ có các lệnh §3 của đợt này theo đúng thứ tự, tên + glyph trùng menu album | `ServerEditMenuTests.matchesAlbumMenu` + ảnh `…-ios26-20-selecting.png`, `…-ios26-21-selection-menu.png`, `…-ios18-20-selecting.png` |
| AC-54 | `a.JPG` 12 MB, máy còn 2 GB | Edit | tải 1 file, editor mở, server không có thay đổi nào (không ghi, không đổi tên) | `ServerEditSessionTests.downloadsOriginalOnly` |
| AC-55 | 3 RAW × 60 MB, máy còn 1.1 GB | Edit | không tải byte nào, báo "about 80 MB more needed" (cần 1.18 GB) | `ServerEditSessionTests.spaceCheckBeforeDownload` |
| AC-56 | đang tải ảnh 2/3 | Cancel | thư mục tạm bị xoá, quay lại lưới, không mở editor | `ServerEditSessionTests.cancelRemovesTemp` |
| AC-57 | editor, Exposure +1 | Cancel → Discard | bản tạm + recipe mất; mở lại `a.JPG` thì Exposure = 0 | `ServerEditSessionTests.discardDropsDraft` + ảnh `…-ios26-30-discard.png` |
| AC-58 | editor, chưa sửa gì | Cancel | không hỏi, bản tạm bị xoá | `ServerEditSessionTests.cleanLeaveNoPrompt` |
| AC-59 | thư mục tạm còn sót từ lần app bị giết | khởi động app | thư mục bị xoá | `TemporaryWorkspaceTests.aServerEditCopyLeftByAKilledAppIsSwept` |
| AC-60 | sửa `a.JPG`, chọn Original Folder + Save as New File | Export | có `a_edited.jpg` cạnh `a.JPG`, SHA khớp, `a.JPG` còn nguyên byte; bản tạm bị xoá | `ServerEditExportTests.newFileBesideOriginal` |
| AC-61 | `a_edited.jpg` đã có | xuất lần hai | ghi `a_edited (2).jpg` | `ServerEditExportTests.nameCollisionNumbers` |
| AC-62 | sửa `a.JPG` | Replace Original → xác nhận | `a.JPG` mang nội dung mới; bấm Cancel ở hộp xác nhận thì không ghi gì | `ServerEditExportTests.replaceNeedsConfirm` + `replaceKeepsOriginalWhenTheCheckFails` + ảnh `…-ios26-50-replace-confirm.png`; Cancel và Replace chạy thật trên SMB (impacket) 2026-09-30 |
| AC-63 | nguồn `b.CR3` | mở sheet | không có Replace Original, có câu RAW | `ServerEditExportTests.rawCannotBeReplaced` + ảnh `2026-10-02-fs1706-ios26-63-raw-no-replace.png` (Sony ARW mẫu CC0, cây, trên SMB) |
| AC-64 | chọn Photos Library + Other Folder (SFTP `/sel`) + Share | Export | 1 asset mới trong Photos; `/sel/a_edited.jpg`; share sheet mở sau cùng | `ServerEditExportTests.multipleDestinations` + ảnh `…-ios26-14-export-sheet.png`, `…-ios18-14-export-sheet.png`, `…-ios26-17-grid-after-export.png` |
| AC-65 | folder server từ chối ghi | Export tới Original Folder | đích đó báo "You can't write to this folder." + Choose Another Folder; bản tạm còn; không file `.shotdex-part` nào sót | `ServerEditExportTests.permissionDeniedOffersAnotherFolder` + `ServerComposedExportTests.composedRefusalShowsOnItsRow` + ảnh `2026-10-01-fs1706-ios18-65-permission-denied.png` (folder SMB chỉ đọc, 0 file `.shotdex-part`, bản tạm còn) |
| AC-66 | loạt 5 ảnh, sửa 3 | Export… | hỏi nơi lưu 1 lần, xuất 3 file, 2 ảnh chưa sửa không xuất | `ServerEditSessionTests.batchExportsEditedOnly` + `singleUntouchedPhotoStillExports` |
| AC-67 | (đợt 2) chọn 4 ảnh | Create Collage → Export… | sheet xuất §6b mở; Photos không có asset mới, không có dòng Creations | `ServerComposeToolTests.collageExportsToAFileNotToPhotos` + ảnh `…-ios26-61-collage.png`, `…-ios26-62-collage-export.png`, `…-ios26-63-composed-sheet.png`; chạy thật trên SMB 2026-09-30: `DSCF1000_collage.jpg` 2048×2048 lên share, Photos vẫn 71 ảnh |
| AC-68 | chọn 2 ảnh | Export EXIF (CSV) | CSV 2 dòng; mỗi file chỉ đọc phần đầu (≤ 1 MB) | `ServerEditHandoffTests.readsHeadOnly` |
| AC-69 | server tắt giữa lúc xuất (Original Folder), Photos đã xong | Export | Photos xong; Original Folder lỗi + Retry Failed; bản tạm + recipe còn | `ServerEditExportTests.failedDestinationKeepsDraft` |
| AC-70 | iOS 26.5, 18.6, iPad, Duo trong | menu + sheet | không bị cắt, cùng lệnh ở hai nhánh | iPhone 17 Pro 26.5 + iPhone 16 Pro 18.6: ảnh ở các AC trên; iPad Pro 13 (26.5, dọc): ảnh `…-ipad-20-selecting.png`, `…-ipad-21-selection-menu.png`, `…-ipad-63-composed-sheet.png`; iPad Pro 13 ngang (2026-10-02, `ui-drive` `server-edit-ipad-landscape.json` + `Tools/sim-shot`): ảnh `2026-10-02-fs1706-ipad-land-21-selection-menu.png`, `…-ipad-land-63-composed-sheet.png`; Duo màn ngoài 466×678 (`server-edit-duo.json`, element dump): sheet gộp nằm trong x 24…382 trước rail 84pt, Export x 301…378, Cancel x 28; Duo màn trong ⚠️ chưa có (sim gập sau khi boot lại, simctl không mở được) |
| AC-72 | clipboard có look (Exposure +1), chọn 2 ảnh | Paste Edits | tải 2 bản tạm, sheet xuất mở với `2 photos`; không ghi gì trước khi bấm Export | `ServerEditHandoffTests.pasteEditsGoesToExportSheet` |
| AC-73 | 1 ảnh 600×400 | Resize, cạnh dài 300 → Export tới Original Folder | `a_edited.jpg` 300×200; `a.JPG` giữ nguyên | `ServerEditHandoffTests.resizeExportsThroughSheet` |
| AC-74 | `a.JPG` có GPS, Share bỏ vị trí đang bật | Share | share sheet nhận file bản gốc đã bỏ GPS; đóng share sheet thì bản tạm bị xoá | `ServerEditHandoffTests.shareHandsOriginalAndCleansUp` |
| AC-75 | `b.CR3` 6000×4000 | Copy | pasteboard có ảnh cạnh dài ≤ 4096 px; bản tạm bị xoá | `ServerEditHandoffTests.copyBoundsAndCleansUp` |
| AC-76 | (đợt 2) chọn 3 ảnh | mở ⋯ | Paste Edits · Combine Photos (Focus Stack, Panorama, Stack Exposures) · Create Collage · Create Video · Resize · Export EXIF (CSV) · Import to Library, tên + glyph trùng album | `ServerEditMenuTests.matchesAlbumMenu` + ảnh `…-ios26-60-selection-menu-phase2.png`, `…-ios26-68-combine-submenu.png`, `…-ios18-60-selection-menu-phase2.png`, `…-ipad-21-selection-menu.png` |
| AC-77 | (đợt 2) collage từ `DSCF1000.JPG` + 3 ảnh | Export… | sheet có Name = `DSCF1000_collage`, không có Replace/Format/Size; Original Folder ghi `DSCF1000_collage.jpg`, lần hai `DSCF1000_collage (2).jpg`; đổi tên thành `Trip` thì ghi `Trip.jpg` | `ServerComposedExportTests.composedNamesFromFirstPhoto` + `composedWritesUnderTypedNameAndNeverReplaces` + `composedCarriesItsNameToPhotosAndShare` + ảnh `…-ios26-63-composed-sheet.png`, `…-ios18-63-composed-sheet.png` |
| AC-78 | (đợt 2) sheet gộp | xoá hết ô Name, hoặc nhập `/` | nút Export mờ | `ServerComposedExportTests.composedNameIsCleaned` + `composedEmptyNameDisablesExport` |
| AC-79 | (đợt 2) 3 JPEG server, ngày EXIF ngược thứ tự tên file | Combine → Focus Stack → Export… | khung xếp theo DateTimeOriginal; sheet mở với Name `…_focus-stack` | `ServerComposeToolTests.focusStackOrdersByEXIF` + `stackExposuresSavesAFileForTheSheet` + ảnh `…-ios26-69-focus-stack.png`, `…-ios26-70-focus-stack-sheet.png` |
| AC-80 | (đợt 2) 2 khung server chồng nhau | Combine → Panorama → Export… | khung đọc từ file, không gọi PhotoKit; sheet mở với Name `…_panorama` | `ServerComposeToolTests.panoramaReadsFilesAndKeepsTheResultInTheRun` + ảnh `…-ios26-71-panorama.png`, `…-ios26-72-panorama-sheet.png` (ảnh mẫu không chồng nhau thật nên bản ghép là một dải) |
| AC-81 | (đợt 2) 3 ảnh server | Create Video → Export… → Photos Library + Original Folder | sheet không có Format/Size/Replace; Photos có 1 video mới; `DSCF1000_video.mp4` cạnh ảnh gốc, SHA khớp | `ServerComposeToolTests.videoOfServerPhotosExportsToAFile` + `ServerComposedExportTests.moviesAreRecognisedByExtension` + ảnh `…-ios26-65-video-studio.png`, `…-ios26-66-video-sheet.png`, `…-ios26-67-library-after-video.png`; chạy thật: `DSCF1000_video.mp4` lên share, Photos thêm 1 video 0:09 |
| AC-82 | (đợt 2) collage 2 ảnh server + 1 ảnh library thêm qua picker | Export… → Original Folder | file ghi đúng; asset library không đổi; kéo thả file từ app khác không nhận | ảnh `…-ios26-73-collage-mixed.png`; chạy thật 2026-09-30: 2 ảnh server + 1 ảnh mây từ Recents → Original Folder ghi `DSCF1000_collage (2).jpg` 2048 px, Photos không thêm asset; kéo thả file ngoài bị từ chối: `ServerComposeToolTests.serverRunsRefuseFilesFromOtherApps` |
| AC-83 | (đợt 2) collage đã đổi layout | Close | hỏi Discard; Discard thì thư mục tạm mất. Chưa làm gì thì Close không hỏi | `ServerComposeToolTests.collageAsksBeforeDiscardingOnlyAfterAChange` + ảnh `…-ios18-61-collage-discard.png`; chạy thật: Discard, Cancel không sửa và Close đều để lại 0 thư mục `ShotDexServerEdit-*` (iPhone 17 Pro, iPhone 16 Pro, iPad) |
| AC-84 | (đợt 2) video 20 ảnh server 6000×4000 | dựng preview và xuất | mỗi khung đọc từ file ở cạnh dài ≤ cỡ render, không giải mã full-res | `ServerComposeSourceTests.decodesAtTheSizeAsked` + `ServerComposeToolTests.videoStillsDecodeAtTheRenderSize` |

**Chưa chứng minh được:** AC-70 trên màn trong của Duo.
(AC-71 thuộc FS-17.03.)

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Editor, collage và video chỉ nhận ảnh trong Photos | cần một nguồn ảnh dạng file cho cả ba; đo lại đường render ảnh RAW từ file ở bước plan |
| File cloud chưa tải về máy (iCloud Drive, Dropbox online-only) | đọc qua file coordination; Cancel phải dừng được lượt tải của app Files |
| Loạt lớn trên SMB chậm (60 MB × 20) | tiến độ theo byte, giữ màn hình sáng như Import |
