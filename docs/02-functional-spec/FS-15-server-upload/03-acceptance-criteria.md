# FS-15.03 — Tiêu chí nghiệm thu

`FS-15.03` · `ShotDexTests/ServerUpload*Tests.swift` · `ShotDexUITests/scripts/server-upload*.json`
· cập nhật 2026-09-24

Luồng upload chạy trên một **server giả trong bộ nhớ** ở unit test, nên mọi đường hỏng (rớt mạng, checksum
lệch, huỷ) kiểm được mà không cần mạng. Phần chỉ máy thật trả lời được nằm cuối bảng.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh `IMG_1234.CR3` chụp 2026-09-24 14:05 giờ máy, thư mục đích `Photos` | dựng đường dẫn | `Photos/2026/2026-09-24/IMG_1234.CR3`; bản sửa `IMG_1234_edited.JPG` | `ServerUploadPathTests.pathFollowsCaptureDate` |
| AC-2 | asset RAW+JPEG đã sửa trong Photos | chọn lần lượt Only RAW / All Originals / Originals + Edited | ra đúng 1 / 2 / 3 file; asset chỉ JPEG ở Only RAW ra 0 file và được đếm "skipped" | `ServerUploadPlanTests.resourceSelectionPerKind` |
| AC-3 | 3 file 10 MB, server giả | đẩy cả lô | server có đúng 3 file tên thật, 0 file `.shotdex-part`; 3 dòng lịch sử có SHA-256 bằng SHA-256 của nguồn | `ServerUploadSessionTests.uploadsVerifiesAndRecords` |
| AC-4 | server giả trả sai 1 byte khi đọc lại file thứ 2 | đẩy 3 file | file 2 báo lỗi checksum, **không** có tên thật và không có `.part` trên server, không có dòng lịch sử; file 1 và 3 thành công | `ServerUploadSessionTests.checksumMismatchLeavesNoFile` |
| AC-5 | server giả rớt kết nối giữa file 2 của 4 | đẩy | lô dừng; file 1 đã lên; file 3, 4 là "chưa đẩy"; Upload Remaining chỉ đẩy lại 2, 3, 4 | `ServerUploadSessionTests.connectionLossStopsBatch` |
| AC-6 | lô 5 file, đang ở file 3 | huỷ | file 1, 2 ở lại trên server kèm lịch sử; `.part` của file 3 bị xoá; file tạm trên máy bị xoá | `ServerUploadSessionTests.cancelCleansPartAndTemp` |
| AC-7 | server có `IMG_1.CR3` và `IMG_1 (2).CR3` khác nội dung | chọn Keep Both | file mới thành `IMG_1 (3).CR3` | `ServerUploadPathTests.keepBothPicksNextFreeName` + `ServerUploadConflictTests.keepBothWritesBesideTheOld` |
| AC-8 | 3 file trùng tên, khác nội dung | chọn Skip + bật Apply to remaining ở file đầu | hỏi đúng 1 lần; 0 file bị ghi đè; 3 file là "skipped" | `ServerUploadConflictTests.applyToRemainingAsksOnce` |
| AC-9 | file trên server trùng tên **và** trùng SHA-256 | đẩy | không hỏi, không ghi, có dòng lịch sử, tính là đã lên | `ServerUploadConflictTests.identicalFileCountsAsUploaded` |
| AC-10 | lô 2 asset: A (1 file RAW, lên ổn), B (RAW+JPEG, Only RAW) | xem kết quả | đề nghị xoá **1** tấm (A); B nằm ngoài kèm lý do "JPEG not on a server" | `ServerUploadEligibilityTests.pairNeedsBothFiles` |
| AC-11 | 1 server có 7 dòng lịch sử | xoá server | 7 dòng vẫn còn, giữ tên server, id server rỗng; mật khẩu trong Keychain bị xoá | `ServerUploadStoreTests.deletingServerKeepsHistory` |
| AC-12 | thư viện có 3 ảnh đã upload trong 50 ảnh | mở Utilities | có hàng Uploaded to Server; mở ra thấy đúng 3 ảnh; 3 ô trên Library có dấu, 47 ô không | `ServerUploadStoreTests.uploadedIdsQuery` + `scripts/server-upload-run.json` (glyph trên 3 ô) + `scripts/server-upload-sftp-conflict.json` (hàng **On Server**, lưới 3 ảnh) + `scripts/server-upload-info.json` (dòng Photo Info), iPhone 17 iOS 26.5 |
| AC-13 | form SFTP, host mới | Test Connection lần đầu | hộp Trust hiện dấu vân tay `SHA256:…`; Trust thì lưu; lần sau dấu vân tay khác → bị chặn với câu "identity … changed" | `FileServerHostKeyTests.trustThenMismatchBlocks` + `scripts/server-upload-sftp-conflict.json` (hộp Trust hiện đúng dấu vân tay `ssh-keygen -lf` của server) |
| AC-14 | chọn 4 ảnh, đã có 2 server, lần trước dùng "NAS" | ⋯ → Upload to Server | sheet mở ở bước chuẩn bị, server là "NAS", Files là All Originals; cả nhánh iOS 26.5 và 18.6 | `ServerUploadModelTests.startsOnTheLastServerWithAllOriginals` + `scripts/server-upload-run.json` (iPhone 17 iOS 26.5); iOS 18.6, iPad, Duo ⚠️ chưa có |
| AC-15 | đang đẩy | app ra nền, hoặc lô xong, hoặc huỷ | màn hình tự khoá lại được (không còn bị giữ sáng) ở cả ba lối | `ServerUploadModelTests.idleTimerRestoredOnEveryExit` |
| AC-16 | iPhone thật + Mac này (SMB và SFTP), 20 RAW ProRAW, một phần chỉ có trên iCloud | đẩy rồi Delete | 20 file trên Mac khớp `shasum -a 256`; hộp Local Network hiện đúng lúc Test Connection; ảnh vào Recently Deleted | một phần: simulator → SMB/SFTP giả lập trên Mac, CR3 32 MB khớp `shasum -a 256`, Keep Both ra `IMG_0001 (2).JPG`; máy thật, iCloud-only, hộp Local Network, Delete ⚠️ chưa có |

**Chưa chứng minh được:** AC-14 trên iOS 18.6, iPad và Duo; AC-16 trên máy thật (iCloud-only, hộp Local
Network, Delete tới Recently Deleted). AC-16 cần người dùng bật **File Sharing** và **Remote Login** trên Mac —
ShotDex không tự bật được. Màn tiến độ chưa có ảnh: trên localhost 38 MB đẩy xong trước lần chụp đầu.

**Server giả lập cho các script** (chỉ nghe 127.0.0.1): `smbserver.py -smb2support -username tester -password
secret -port 4450 -ip 127.0.0.1 photos <thư mục>` (impacket) và một SFTP asyncssh ở cổng 2222, user `tester`.
