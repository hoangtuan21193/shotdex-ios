# FS-19.08b — Gom ảnh chung: tiêu chí nghiệm thu

`FS-19.08b` · cho [08](08-common-photos.md) · AC-115…AC-130 · cập nhật 2026-11-02

Dữ liệu thử: server cục bộ (impacket smbserver + WebDAV trên Mac, memory `server-upload-fs15`), ảnh phong cảnh không
có mặt người. Test domain chạy trên client giả của `ShotDexTests/BackupFakes.swift` và GRDB trong bộ nhớ.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-115 | A có 3 file cỡ 1.000/2.000/3.000 byte, B có 2 file cỡ 2.000/4.000 | quét | đúng 1 cặp vào bước băm; 0 byte nội dung của 3 file còn lại được đọc (client giả đếm lệnh đọc) | ✅ `CommonPhotosMatcherTests.sizeFilterReadsNothingElse` |
| AC-116 | A `IMG_1.JPG` và B `2025-06-01 IMG_1.JPG` cùng byte | quét xong | 1 ảnh **Same** dù khác tên | ✅ `CommonPhotosMatcherTests.renamedFileMatches` |
| AC-117 | A, B có file cùng cỡ, cùng tên, khác 1 byte ở giữa | quét xong | ở **Likely** khi mới liệt kê; sau băm rơi khỏi danh sách; nút chạy đếm 0 | ✅ `CommonPhotosMatcherTests.sameSizeDifferentBytesDropped` (+ `headAndTailSamples`, `fullHashCatchesWhatSamplesMiss`) |
| AC-118 | A, B có ảnh cùng ngày chụp + giây lẻ + máy, khác cỡ | quét xong | không có trong Likely lẫn Same | ✅ `CommonPhotosMatcherTests.sameCaptureDifferentSizeIgnored` |
| AC-119 | 3 folder A, B, D; ảnh X ở cả ba, ảnh Y chỉ ở A và B | quét xong | Same = {X}; Y không có | ✅ `CommonPhotosMatcherTests.intersectionOfAllFolders` |
| AC-120 | A 20.000 file, B 20.000 file, 300 chung (danh sách giả) | chạy bước lọc cỡ + Likely | xong ≤ 1 s trên Mac M1; Likely ≥ 300 | ✅ `CommonPhotosMatcherTests.twentyThousandEachUnderOneSecond` (Debug, sim) |
| AC-121 | 5 ảnh Same, folder chung rỗng, Copy | chạy | 5 file ở đích, SHA đọc lại khớp; A, B không đổi; 5 hàng log Copied | ✅ `CommonPhotosRunnerTests.copyVerifiesReadBack` |
| AC-122 | như AC-121, client giả trả SHA đọc lại sai cho file thứ 3 | chạy | file part thứ 3 bị xoá, không có tên thật ở đích; log Failed "checksum mismatch"; 4 file kia Copied | ✅ `CommonPhotosRunnerTests.copyMismatchLeavesNothing` |
| AC-123 | 5 ảnh Same, Move, cùng share | chạy | A, B mất 5 file; đích có 5; lệnh đổi chỗ dùng 5 lần, 0 lần tải; log Moved | ⚠️ chưa có — `CommonPhotosRunnerTests.moveRenamesThenDeletes` |
| AC-124 | Move, client giả từ chối đổi chỗ (khác share) | chạy | chép + kiểm SHA rồi mới xoá; thứ tự lệnh: tải → đẩy → đọc lại → xoá | ⚠️ chưa có — `CommonPhotosRunnerTests.crossShareMoveCopiesFirst` |
| AC-125 | Move, bản ở B đổi cỡ sau Scan | chạy tới ảnh đó | bản B không bị xoá; log Failed "changed on server"; bản ở đích giữ | ⚠️ chưa có — `CommonPhotosRunnerTests.changedSourceNotDeleted` |
| AC-126 | đích đã có `IMG_1.JPG` cùng SHA và `IMG_2.JPG` khác SHA | Copy `IMG_1`, `IMG_2` | `IMG_1` Skipped (already there); `IMG_2` thành `IMG_2 (2).JPG`; không file nào bị ghi đè | ✅ `CommonPhotosRunnerTests.nameClashRules` (+ `sameNameTwiceInOneRun`) |
| AC-127 | ảnh Same ở `A/2025/06/` và `B/x/` | Copy | file nằm thẳng ở đích (phẳng); `.xmp` cùng tên gốc đi theo | ⚠️ chưa có — `CommonPhotosRunnerTests.flatDestinationWithSidecar` |
| AC-128 | 10 ảnh, mất kết nối sau ảnh thứ 4 | Resume khi server về | chạy tiếp từ ảnh 5; 4 ảnh đầu không đọc lại; tổng log 10 hàng | ⚠️ chưa có — `CommonPhotosRunnerTests.resumeAfterDisconnect` |
| AC-129 | lượt chạy xong 3 Copied, 1 Skipped | xong | đích có CSV `ShotDex Common Photos <ngày giờ>.csv`, 4 hàng + tiêu đề, cột Status/Name/From/To/SHA-256 | ⚠️ chưa có — `CommonPhotosRunnerTests.writesCsvLog` |
| AC-130 | Mac, màn duyệt NAS cục bộ, ⌘-click 2 folder | chuột phải → Find Common Photos… → chọn đích → Scan → Copy | sheet và cửa sổ tiến độ khớp board `MAC_CommonPhotos` / `MAC_CommonPhotosRun` (lệch ≤ 2pt), sáng và tối | ⚠️ chưa có — `Tools/mac-shot` + `Tools/design-board compare` |

Kiểm thêm khi `/verify`: folder chung nằm trong folder nguồn → sheet báo lỗi, nút chạy mờ; 1 folder → mục menu mờ; lịch
sử upload trỏ tới file bị dời được sửa đường dẫn (`ServerFileHistory`).

**Đã chứng minh (2026-11-03):** AC-115…122, 126 — test chạy trên sim iPhone Duo 27.1; quét thêm e2e trên SMB ảo
(impacket, `CommonPhotosSMBTests.scanFindsTheSharedPhotos`: 8 ảnh khác tên tìm ra Same).
**Chưa chứng minh được:** AC-123…125, 127…130.
