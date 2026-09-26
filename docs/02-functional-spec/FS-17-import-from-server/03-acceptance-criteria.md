# FS-17.03 — Tiêu chí nghiệm thu

`FS-17.03` · `ShotDexTests/ServerImport*Tests.swift` · `ShotDexUITests/scripts/server-import*.json` · cập nhật 2026-09-26

Như FS-15: phần lớn chạy trên **server giả trong bộ nhớ** (`InMemoryRemoteFileClient` thêm range read) và
**PhotoKit giả** (bộ ghi asset nhận yêu cầu tạo), nên đường hỏng kiểm được không cần mạng; phần Photos thật chạy
trên simulator với server giả lập 127.0.0.1.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | folder có `A.CR3`, `A.JPG`, `B.heic`, `C.png`, `D.MOV`, `notes.txt`, `.DS_Store`, `E.NEF`, `e.jpeg`, folder `2025`, `.snapshots` | liệt kê | 1 folder (`2025`); 4 ô: `A` (RAW+JPG), `B` (HEIC), `C` (PNG), `E` (RAW+JPG, ghép không phân biệt hoa thường); dòng cuối "4 photos · 2 other files hidden" | `ServerFolderListingTests.imagesOnlyAndPairs` ⚠️ chưa có |
| AC-2 | danh sách đuôi | phân loại | đuôi ảnh lấy từ `CGImageSourceCopyTypeIdentifiers` ∩ `UTType.image`; `heic`, `dng`, `cr3`, `arw`, `raf`, `tif`, `webp` là ảnh; `mov`, `txt`, `xmp` không | `ServerFolderListingTests.formatsFromImageIO` ⚠️ chưa có |
| AC-3 | file CR3 mẫu 31.9 MB (`HAT_8841.CR3`) | làm thumbnail với đoạn 512 KB đầu | ra ảnh ≥ 320 px từ JPEG `PRVW` nhúng; chỉ đọc 512 KB (đếm byte client giả) | `RemoteThumbnailTests.cr3EmbeddedPreview` ⚠️ chưa có |
| AC-4 | JPEG 6.1 MB có EXIF thumbnail 160×120 | làm thumbnail | ảnh 160 px dùng tạm; vì < 320 px và file không phải RAW ≤ 25 MB → tải trọn, thumbnail cuối 400 px | `RemoteThumbnailTests.smallExifThumbUpgrades` ⚠️ chưa có |
| AC-5 | RAW 60 MB không có preview trong 512 KB đầu | làm thumbnail | không tải trọn; ô hiện icon định dạng + tên | `RemoteThumbnailTests.rawWithoutPreviewStaysIcon` ⚠️ chưa có |
| AC-6 | thumbnail đã cache | mở lại folder | 0 byte đọc từ server cho thumbnail; cache vượt 500 MB → xoá cũ nhất tới dưới trần | `ThumbnailCacheTests.hitAndEviction` ⚠️ chưa có |
| AC-7 | file đã upload qua ShotDex (lịch sử có connection, đường dẫn, số byte), asset còn trong thư viện | liệt kê | ô có dấu In Library; asset đã bị xoá khỏi thư viện → không có dấu | `ServerImportIndexTests.inLibraryFromHistory` ⚠️ chưa có |
| AC-8 | chọn cặp `A.CR3`+`A.JPG` | tải về | **một** yêu cầu tạo asset: `.photo` = JPG, `.alternatePhoto` = CR3, `originalFilename` đúng, `creationDate` = EXIF `2022-10-10 16:23:07` + offset | `ServerDownloadSessionTests.pairBecomesOneAsset` ⚠️ chưa có |
| AC-9 | file tải về thiếu 1 byte so với `SIZE` server | kiểm | ảnh đó lỗi, không có yêu cầu tạo asset, file tạm bị xoá; ảnh sau vẫn tải | `ServerDownloadSessionTests.sizeMismatchFails` ⚠️ chưa có |
| AC-10 | file có SHA-256 trong lịch sử upload, server trả nội dung khác cùng kích thước | kiểm | lỗi checksum, không tạo asset | `ServerDownloadSessionTests.knownChecksumMustMatch` ⚠️ chưa có |
| AC-11 | 5 ảnh, rớt mạng ở ảnh 3 | tải | ảnh 1–2 trong Photos + lịch sử; 3–5 "chưa tải"; Try Again chỉ tải 3–5 | `ServerDownloadSessionTests.connectionLossStops` ⚠️ chưa có |
| AC-12 | đích album "Trip" có sẵn | tải 2 ảnh | 2 asset nằm trong "Trip"; New Album "Picks" → album được tạo và chứa ảnh | `ServerDownloadSessionTests.savesIntoAlbum` + `scripts/server-import.json` ⚠️ chưa có |
| AC-13 | chọn 4 ảnh, 1 In Library, công tắc Skip bật | tải | 3 ảnh được tải; kết quả "1 photo skipped — already in your library." | `ServerDownloadModelTests.skipsInLibrary` ⚠️ chưa có |
| AC-14 | đang tải | app ra nền, xong, huỷ | màn hình tự khoá lại được ở cả ba lối; huỷ giữa ảnh → không có asset dở, file tạm xoá | `ServerDownloadModelTests.idleTimerRestoredOnEveryExit` ⚠️ chưa có |
| AC-15 | simulator iOS 26.5 + 18.6, iPad, server SMB giả lập có 6 ảnh (CR3+JPG, HEIC, PNG) | Utilities → On Server → connection → chọn 3 → Download → Library | lưới có thumbnail thật, nhãn định dạng; 3 ảnh mới trong Library với ngày chụp gốc; quay lại lưới thấy In Library | `scripts/server-import.json` ⚠️ chưa có |
| AC-16 | quyền `.limited` | mở sheet tải về | Save To chỉ có Library + câu "Allow full access to Photos to save into an album." | `ServerDownloadModelTests.limitedAccessOnlyLibrary` ⚠️ chưa có |
| AC-17 | folder: `IMG_10.CR3` (chụp 2026-01-03, sửa 2026-09-01), `IMG_2.JPG` (chụp 2026-01-05, sửa 2026-08-01), `scan.png` (không EXIF, sửa 2026-07-01) | Sort Name / Date Taken / Date Modified, rồi Descending | Name: `IMG_2`, `IMG_10`, `scan`; Date Taken: `IMG_10`, `IMG_2`, `scan` (scan dùng ngày sửa 07-01); Date Modified: `scan`, `IMG_2`, `IMG_10`; Descending đảo từng thứ tự; Date Taken chỉ sắp lại **một lần**, sau khi đọc xong cả folder | `ServerFolderSortTests.threeOrders` ⚠️ chưa có |

**Chưa chứng minh được:** tất cả (chưa code). Cần máy thật cho: iCloud, tốc độ LAN thật, và các dòng RAW không có
file mẫu trên máy này (NEF, ARW, RAF, ORF, RW2).
