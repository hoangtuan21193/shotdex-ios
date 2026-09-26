# FS-17.03 — Tiêu chí nghiệm thu

`FS-17.03` · `ShotDexTests/ServerImport*Tests.swift` · `ShotDexUITests/scripts/server-import*.json` · cập nhật 2026-09-26

Như FS-15: phần lớn chạy trên **server giả trong bộ nhớ** (`InMemoryRemoteFileClient` thêm range read) và
**PhotoKit giả** (bộ ghi asset nhận yêu cầu tạo), nên đường hỏng kiểm được không cần mạng; phần Photos thật chạy
trên simulator với server giả lập 127.0.0.1.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | folder có `A.CR3`, `A.JPG`, `B.heic`, `C.png`, `D.MOV`, `notes.txt`, `.DS_Store`, `E.NEF`, `e.jpeg`, folder `2025`, `.snapshots` | liệt kê | 1 folder (`2025`); 4 ô: `A` (RAW+JPG), `B` (HEIC), `C` (PNG), `E` (RAW+JPG, ghép không phân biệt hoa thường); dòng cuối "4 photos · 2 other files hidden" | `ServerFolderListingTests.imagesOnlyAndPairs` |
| AC-2 | danh sách đuôi | phân loại | đuôi ảnh lấy từ `CGImageSourceCopyTypeIdentifiers` ∩ `UTType.image`; `heic`, `dng`, `cr3`, `arw`, `raf`, `tif`, `webp` là ảnh; `mov`, `txt`, `xmp` không | `ServerFolderListingTests.formatsFromImageIO` |
| AC-3 | file dạng CR3: thumbnail 160 px ở 13 KB, preview 1200 px ở 90 KB, tổng 3 MB; và 10 file RAW thật (CR3×2, NEF, ARW, RAF, ORF, RW2, PEF, DNG×2) | làm thumbnail | ảnh ≥ 320 px, thu về 400 px; đọc ≤ 1 MB (RAF: 256 KB + preview theo con trỏ); không tải trọn RAW | `RemoteThumbnailTests.cr3EmbeddedPreview` + `.secondReadFindsALaterPreview` + `.rafPreviewFollowsTheHeaderPointer` + chạy `EmbeddedPreview.swift` trên 10 file mẫu (FS-17.01 §3) |
| AC-4 | JPEG 2000 px có EXIF thumbnail 160 px | làm thumbnail | ảnh 160 px dùng tạm; vì < 320 px và file không phải RAW ≤ 25 MB → tải trọn, thumbnail từ ảnh thật | `RemoteThumbnailTests.smallExifThumbUpgrades` |
| AC-5 | RAW 6 MB không có preview trong 1 MB đầu | làm thumbnail | đọc đúng 1 MB, không tải trọn; ô hiện icon định dạng + tên | `RemoteThumbnailTests.rawWithoutPreviewStaysIcon` |
| AC-6 | thumbnail đã cache | mở lại folder | 0 byte đọc từ server cho thumbnail; cache vượt 500 MB → xoá cũ nhất tới dưới trần | `ThumbnailCacheTests.hitAndEviction` + `.evictsLeastRecentlyUsedOverTheLimit` |
| AC-7 | file đã upload qua ShotDex (lịch sử có connection, đường dẫn, số byte), asset còn trong thư viện | liệt kê | ô có dấu In Library; asset đã bị xoá khỏi thư viện → không có dấu | `ServerImportIndexTests.inLibraryFromHistory` |
| AC-8 | chọn cặp `A.CR3`+`A.JPG` | tải về | **một** yêu cầu tạo asset: `.photo` = JPG, `.alternatePhoto` = CR3, `originalFilename` đúng, `creationDate` = EXIF `2022-10-10 16:23:07` + offset | `ServerDownloadSessionTests.pairBecomesOneAsset` |
| AC-9 | file tải về thiếu 1 byte so với `SIZE` server | kiểm | ảnh đó lỗi, không có yêu cầu tạo asset, file tạm bị xoá; ảnh sau vẫn tải | `ServerDownloadSessionTests.sizeMismatchFails` |
| AC-10 | file có SHA-256 trong lịch sử upload, server trả nội dung khác cùng kích thước | kiểm | lỗi checksum, không tạo asset | `ServerDownloadSessionTests.knownChecksumMustMatch` |
| AC-11 | 5 ảnh, rớt mạng ở ảnh 3 | tải | ảnh 1–2 trong Photos + lịch sử; 3–5 "chưa tải"; Try Again chỉ tải 3–5 | `ServerDownloadSessionTests.connectionLossStops` |
| AC-12 | đích album "Trip" có sẵn | tải 2 ảnh | 2 asset nằm trong "Trip"; New Album "Picks" → album được tạo và chứa ảnh | `ServerDownloadSessionTests.savesIntoAlbum` + `scripts/server-import-album.json` (New Album "Picks" → "Saved 2 photos to Picks." → Collections › My Albums có Picks) |
| AC-13 | chọn 4 ảnh, 1 In Library, công tắc Skip bật | tải | 3 ảnh được tải; kết quả "1 photo skipped — already in your library." | `ServerDownloadModelTests.skipsInLibrary` |
| AC-14 | đang tải | app ra nền, xong, huỷ | màn hình tự khoá lại được ở cả ba lối; huỷ giữa ảnh → không có asset dở, file tạm xoá | `ServerDownloadModelTests.idleTimerRestoredOnEveryExit` |
| AC-15 | simulator iOS 26.5 + 18.6, iPad, server SMB giả lập có 6 ảnh (CR3+JPG, HEIC, PNG) | Utilities → On Server → connection → chọn 3 → Download → Library | lưới có thumbnail thật, nhãn định dạng; 3 ảnh mới trong Library với ngày chụp gốc; quay lại lưới thấy In Library | `scripts/server-import.json` + `scripts/server-import-grid.json` (iPhone 17 iOS 26.5, SMB giả lập: lưới CR3+JPG/NEF/ORF/HEIC/PNG có thumbnail thật và nhãn, Date Taken, chọn 3 → Save to Photos → "Saved 3 photos to Library." → 3 ô In Library; xem lớn; Skip đếm 1) + `scripts/server-import-verify-rerun.json` (iPhone 16 Pro iOS 18.6: lưới, chọn, tải 2 ảnh, In Library); iPad ⚠️ chưa chạy trọn (driver không gõ được ô Password trong sheet form trên iPad), Duo ⚠️ |
| AC-16 | quyền `.limited` | mở sheet tải về | Save To chỉ có Library + câu "Allow full access to Photos to save into an album." | `ServerDownloadModelTests.limitedAccessOnlyLibrary` |
| AC-17 | folder: `IMG_10.CR3` (chụp 2026-01-03, sửa 2026-09-01), `IMG_2.JPG` (chụp 2026-01-05, sửa 2026-08-01), `scan.png` (không EXIF, sửa 2026-07-01) | Sort Name / Date Taken / Date Modified, rồi Descending | Name: `IMG_2`, `IMG_10`, `scan`; Date Taken: `IMG_10`, `IMG_2`, `scan` (scan dùng ngày sửa 07-01); Date Modified: `scan`, `IMG_2`, `IMG_10`; Descending đảo từng thứ tự; Date Taken chỉ sắp lại **một lần**, sau khi đọc xong cả folder | `ServerFolderSortTests.threeOrders` + `scripts/server-import.json` (Date Taken sắp lại một lần sau thanh Reading dates) |
| AC-18 | iOS 18.6 (tab bar tự vẽ), folder có 5 ảnh | Select, chọn 2 | tab bar ẩn, thanh **Download 2** hiện và bấm được; thoát chọn → tab bar trở lại (lỗi 2026-09-27: thanh nằm sau tab bar, bấm không ăn) | `scripts/server-import-verify-rerun.json` (iPhone 16 Pro iOS 18.6: `93-selected` thanh Download rõ, `95-result` "Saved 2 photos to Library.", `96-in-library` tab bar trở lại) |

**Chưa chứng minh được** (verify 2026-09-27): AC-15 trên iPad và Duo; máy thật (iCloud, LAN thật). Các dòng RAW khác
đã đo trên 10 file mẫu (AC-3).