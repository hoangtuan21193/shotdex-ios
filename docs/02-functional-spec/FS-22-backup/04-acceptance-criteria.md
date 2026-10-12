# FS-22.04 — Tiêu chí nghiệm thu

`FS-22.04` · cập nhật 2026-10-12

Server giả: SMB (impacket) và WebDAV (wsgidav) ở 127.0.0.1 như FS-15. Ảnh test không có mặt người (Vision kiểm trước).

## 1. Bảng

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Collections, chưa có job, có 1 connection | mở Utilities | ô **Backup** đứng đầu Utilities; chạm → màn rỗng có **New Backup** | ⚠️ chưa có — `scripts/backup-entry.json` |
| AC-2 | chưa có connection FS-15 nào | mở Backup | nút là **Add a Server**, chạm mở form FS-15.01 | ⚠️ chưa có — `scripts/backup-entry.json` |
| AC-3 | New Backup, đã chọn nguồn + connection, chưa chọn folder | nhìn Start | Start mờ; chọn folder → Start sáng; mặc định Only on Wi‑Fi bật, Include Edited tắt | ⚠️ chưa có — `BackupJobFormTests.startNeedsSourceDestinationFolder` |
| AC-4 | Organize Year › Month › Day, Month `Oct`, Day `2025.10.12`, Videos Apart at the Top | đường dẫn cho `IMG_1.HEIC` và `IMG_2.MOV` chụp 2025-10-12 | `2025/Oct/2025.10.12/IMG_1.HEIC` và `Videos/2025/Oct/2025.10.12/IMG_2.MOV` | `BackupPathPlannerTests.yearMonthDayVideosAtTop` |
| AC-5 | 6 mức × 3 kiểu tên file × 5 chỗ Videos (bộ hợp lệ) | lập đường dẫn cho 1 ảnh + 1 video | mọi đường dẫn khớp bảng 01 §3–§5; không tên folder nào chứa `/` | `BackupPathPlannerTests.everyCombinationMatchesTable` |
| AC-6 | Custom ngày, gõ separator `a/b` rồi `:` | gõ | cả `/` và `:` bị chặn, ô giữ `ab`; separator `年` cho `2025年10年12` | `BackupDateNameTests.forbiddenCharactersRefused` + ⚠️ chưa có `scripts/backup-organize.json` (phần ô gõ) |
| AC-7 | job mới, Photos 10 ảnh + 2 video (2 ảnh chỉ trên iCloud), WebDAV giả | Start | đích có 12 file khớp `shasum -a 256`, 0 `.shotdex-part`; sổ 12 dòng `uploaded`; trạng thái `Watching · Up to Date` | `BackupRunnerTests.firstRunUploadsAndRecords` + ⚠️ chưa có `scripts/backup-run.json` (phần màn hình) |
| AC-8 | đích đã có `IMG_3.CR3` cùng cỡ và `IMG_4.CR3` khác cỡ | chạy | `IMG_3` sổ `found`, 0 byte ghi; `IMG_4` thành `IMG_4 (2).CR3`; không hộp hỏi nào | `BackupRunnerTests.nameAndSizeMatchIsFoundOtherwiseKeepBoth` |
| AC-9 | lượt 3.580 file, app bị giết sau file 812 (sổ 812 dòng) | mở lại app | chạy tiếp từ file 813; tổng byte ghi lên đích = byte của 2.768 file còn lại (+ tối đa 1 file dở) | `BackupRunnerTests.resumesAfterKillWithoutRecopy` |
| AC-10 | job Up to Date, app mở ở Backup | chụp/thêm 3 ảnh vào thư viện sim | ≤ 10 s sau, dòng trạng thái `3 New · Uploading`; xong → `Watching · Up to Date`, đích có 3 file mới | ⚠️ chưa có — `BackupWatcherTests.libraryChangeQueuesNewItems` + `scripts/backup-watch.json` |
| AC-11 | job Up to Date, app ở nền, thêm 2 ảnh | mở app | lượt so chạy ngay khi về trước mặt; 2 ảnh lên đích, không chép lại ảnh nào khác | ⚠️ chưa có — `BackupWatcherTests.catchUpOnForeground` |
| AC-12 | mốc thay đổi Photos của job hỏng | lượt so | so toàn bộ với sổ, không lỗi; kết quả giống mốc tốt | ⚠️ chưa có — `BackupWatcherTests.expiredTokenFallsBackToFullDiff` |
| AC-13 | Only on Wi‑Fi bật, mạng đắt (di động giả) | có 12 mục mới | 0 byte đẩy; trạng thái `Waiting for Wi‑Fi` · `12 new`; mạng đổi sang Wi‑Fi → tự chạy | `BackupRunnerTests.waitsForWiFi` |
| AC-14 | server giả tắt giữa file 5/10 | đang chạy | file 1–4 trong sổ, file 5 không; trạng thái `Can't Reach <tên>`; bật server + Retry → chép 5–10 | `BackupRunnerTests.unreachableThenRetry` |
| AC-15 | 1 ảnh iCloud tải hỏng ở 3 lượt đầu | 4 lượt chạy | sổ `failed`, lỗi cuối có câu; 5/5 hiện `1 File Not Copied`; Retry chạy lại đúng file đó | `BackupRunnerTests.failedItemRetriedThreeTimesThenListed` |
| AC-16 | đang chạy file 5/10 | bấm Pause | dừng ≤ 2 s, `.shotdex-part` file 5 bị xoá; thêm ảnh mới không làm job chạy; Resume → chép 5–10 | ⚠️ chưa có — `BackupRunnerTests.pauseStopsWatchingUntilResume` |
| AC-17 | iOS 26.5, Start với 40 file | rời app | có đúng 1 yêu cầu tác vụ xử lý tiếp tục; hệ thống dừng → `Paused` + "iOS stopped ShotDex at N of 40" | ⚠️ chưa có — `BackupBackgroundTests.continuedTaskOnUserStart` |
| AC-18 | iOS 18.6, đang chạy, Keep Screen On bật | rời app / chạy xong / Pause | màn được tự khoá lại ở cả ba lối; lượt nền dài được xin khi rời app | ⚠️ chưa có — `BackupBackgroundTests.pre26KeepsScreenAndSchedules` |
| AC-19 | 2 mã tác vụ nền mới | build | cả 2 có trong Info.plist; được đăng ký trước khi app khởi động xong | ⚠️ chưa có — `BackupBackgroundTests.identifiersRegistered` |
| AC-20 | sổ 4.118 dòng | Clear Local Metadata Index rồi index lại | sổ vẫn 4.118 dòng; lượt so kế 0 byte đẩy | `BackupStoreTests.ledgerSurvivesIndexClear` |
| AC-21 | sổ 55.000 dòng, nguồn 55.000 mục + 3 mới | lượt so | trả đúng 3 mục, ≤ 3 s trên iPhone 17 sim | `BackupStoreTests.diffAt55kIsOneQuery` |
| AC-22 | quyền `.limited`, 120 ảnh được cho | Start | chép 120 ảnh; dòng 2 có `Limited Access`; quyền bị từ chối → `No Photos Access` + Open Settings | `BackupSourceTests.limitedAccessCopiesVisibleOnly` (từ chối + chỉ chép mục nguồn liệt kê) + ⚠️ chưa có ảnh sim `.limited` |
| AC-23 | nguồn FS-19 thư mục 20 RAW, ổ rút ra giữa lượt | đang chạy | `Source Offline`; cắm lại + mở app → chép phần còn lại | `BackupSourceTests.folderSourceOfflineThenResume` |
| AC-24 | Include Edited bật, 1 ảnh đã sửa trong Photos | chạy | đích có `IMG_5.HEIC` và `IMG_5_edited.JPG`; sửa lại ảnh → lượt sau thêm `IMG_5_edited (2).JPG`, gốc không chép lại | `BackupRunnerTests.editedVersionAddedBesideOriginal` |
| AC-25 | 1/5 có 4 job ở 4 trạng thái (Up to Date, Uploading, Waiting for Wi‑Fi, Paused) | chụp sáng + tối | khớp board `PH_Backup` (Tools/design-board compare ≤ 2pt); VoiceOver đọc tên + trạng thái + tiến độ mỗi thẻ | ⚠️ chưa có — `scripts/backup-states.json` + design-parity |
| AC-27 | iOS 26.5, quyền đầy đủ, job Photos → WebDAV giả | thêm 2 ảnh khi app đã đóng, rồi mở app | phần mở rộng đã PUT 2 file `.shotdex-part`; lượt mở app kiểm SHA-256, đổi tên thật, sổ 2 dòng `uploaded`; 0 file đẩy lại | ⚠️ chưa có — `BackupUploadExtensionTests.partFilesVerifiedOnNextRun` + `scripts/backup-webdav-extension.json` |
| AC-28 | job duy nhất Photos → WebDAV bị xoá, hoặc quyền xuống `.limited` | thao tác | phần mở rộng tải nền bị tắt | ⚠️ chưa có — `BackupUploadExtensionTests.disabledWithoutWebDAVJobOrFullAccess` |
| AC-26 | cùng nguồn + connection + folder đã có job | Start | báo "This backup already exists." và không tạo job thứ hai | ⚠️ chưa có — `BackupJobFormTests.duplicateJobRefused` |

## 2. Chưa chứng minh được

- Mọi AC trừ AC-4, AC-5, AC-20, AC-21 — chưa có code.
- AC-17 lượt dừng của hệ thống không gây được trên sim: chứng minh bằng test giả lập lời dừng, không bằng ảnh.
- Bố cục iPad và Duo trong/ngoài: board đã vẽ (2026-10-12); AC-25 áp cho `IP_Backup`, `DI_Backup`, `DC_Backup` như `PH_Backup`,
  chứng minh bằng design-parity từng thiết bị. Mac ngoài phạm vi FS-22.
- AC-27 phần mở rộng có thể không được iOS gọi trên sim: nếu vậy chứng minh bằng test giả lập lời gọi, ghi rõ.
