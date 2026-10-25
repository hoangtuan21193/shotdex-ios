# FS-19.07b — Ảnh Photos đã có trên server: spike và tiêu chí nghiệm thu

`FS-19.07b` · quy tắc: [07](07-on-server-check.md) · cập nhật 2026-10-25

## 1. Spike trên máy thật (đo trước, chốt AC sau)

Simulator không có iCloud thật, Optimize Storage hay lịch chạy nền thật. Mỗi spike là một build thử (không ship) ghi số vào
`docs/_intents/2026-10-24-smart-album-on-nas.md`. S1, S2, S4 trước đợt 1 ship; S3 trước đợt 2.

| # | Câu hỏi | Cách đo | Đạt khi | Quyết định phụ thuộc |
|---|---|---|---|---|
| S1 | iCloud **đầy** + Optimize Storage: tải bản gốc chỉ-iCloud qua PhotoKit có chạy không? | iPhone thật, iCloud đầy; tải 50 ảnh + 5 video 4K chỉ-iCloud; ghi kết quả, thời gian, mã lỗi | ≥ 54/55 tải được | không đạt → mục đó `Can't download from iCloud`, không chặn cả lượt |
| S2 | Photos có giữ bản gốc vừa tải (máy đầy dần)? | đo chỗ trống trước/sau tải 10 GB rồi xoá file tạm; đo lại sau 1 giờ và 24 giờ | giảm ≤ 1 GB sau 24 giờ | không đạt → thêm trần GB tải mỗi lượt |
| S3 | Một đêm cắm sạc, tác vụ nền được bao nhiêu phút, băm bao nhiêu GB? | 20.000 mục, cắm sạc qua đêm, đọc log; iOS 26.5 và 18 | ghi số | thiết kế chạy nền đợt 2 |
| S4 | Băm video 4K 3 GB đọc luồng: bộ nhớ đỉnh, thời gian, nhiệt? | Instruments, iPhone 17, 3 video | bộ nhớ tăng ≤ 64 MB; không bị giết | không đạt → giảm khối đọc, chỉ băm video khi sạc |

## 2. Tiêu chí nghiệm thu

Thư viện thử không có ảnh mặt người. Server thử: WebDAV cục bộ (công thức trong memory `backup-fs22`). Số AC cố định.

| # | Đợt | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|---|
| AC-74 | 1 | nguồn `NAS Home` ở gốc `iCloud Photo/`; 100 mục Photos đã kiểm xong; 40 có đủ file trong `Shared/`, 25 chỉ trong `Tuấn/` | lưu album: Source is NAS Home · Folder `Shared` | *Matches 40 photos*; chip `Source: NAS Home › Shared` | ⚠️ chưa có — `OnServerRuleTests.folderScope` |
| AC-75 | 1 | như AC-74, gộp ảnh FS-19 tắt | đổi Folder thành trống | *Matches 65 photos* | ⚠️ chưa có — `OnServerRuleTests.wholeSourceWithoutMerge` |
| AC-76 | 1 | 1 ảnh trong album AC-74; script dời `Shared/2025/a.HEIC` → `Shared/x/b.HEIC` | app về trước mặt | ảnh vẫn trong album; 0 lần đọc trọn `b.HEIC` | `ServerSourceIndexTests.renameKeepsIdentity` (phần server: cùng bản sao, cùng ảnh, 0 lần đọc trọn); phần album ⚠️ chờ T8 |
| AC-77 | 1 | Live Photo, trên `Shared/` chỉ có `IMG_1.HEIC`, thiếu `IMG_1.MOV` | đếm **is** / **is not** | không trong **is**; trong **is not** | ⚠️ chưa có — `OnServerRuleTests.livePhotoNeedsVideo` |
| AC-78 | 1 | RAW+JPEG, cả `.ARW` và `.JPG` trên `Shared/` | đếm **is** | có trong **is** | ⚠️ chưa có — `OnServerRuleTests.rawPairBothFiles` |
| AC-79 | 1 | trên `Shared/`: một bản JPEG nén lại và một bản cùng ảnh nhưng có XMP nhúng thêm, của hai HEIC trong Photos | đếm **is** | cả hai mục không trong **is** | ⚠️ chưa có — `OnServerRuleTests.notByteIdenticalIsNotPresent` |
| AC-80 | 1 | 100 mục, 30 kiểm xong, 70 có ứng viên chưa băm | mở **is not** của Shared | 70 mục không có mặt; dòng `Checking · 30 of 100` | ⚠️ chưa có — `OnServerRuleTests.uncheckedInNeither` + `ui-drive` `on-server-album.json` |
| AC-81 | 1 | 500/1.000 file đã băm | giết app, mở lại | lượt tiếp bắt đầu ở file 501; 0 file trong 500 bị đọc lại | ⚠️ chưa có — `PhotosHashTests.resumesAfterKill` |
| AC-82 | 1 | 3 mục chỉ-iCloud có ứng viên, trống 12 GB | lượt băm | ≤ 1 file tạm mỗi lúc, xoá ngay sau khi băm; 3 mục có hash | ⚠️ chưa có — `PhotosHashTests.oneTempFileAtATime` |
| AC-83 | 1 | trống 2,5 GB, file kế là video 1 GB | lượt tới file đó | dừng, không tải; `Waiting for space` | ⚠️ chưa có — `PhotosHashTests.waitsForSpace` |
| AC-84 | 1 | NAS 1.000 file, 40 có cỡ bằng một file gốc Photos chưa khớp | lượt băm server | đúng 40 file được đọc trọn | ⚠️ chưa có — `ServerSourceIndexTests.fullHashOnlySizeCandidates` |
| AC-85 | 1 | Backup đẩy 10 ảnh vào `Shared/` (nằm trong nguồn) | Backup xong, mở **is** | 10 ảnh có mặt; 0 lần đọc lại từ NAS | ⚠️ chưa có — `BackupRunnerTests.recordsServerCopyHash` |
| AC-86 | 1 | job Backup *Only on Wi‑Fi*, máy đang dùng di động | lượt kiểm tới lúc chạy | 0 lệnh tới server, 0 tải iCloud; `Waiting for Wi‑Fi` | ⚠️ chưa có — `OnServerScheduleTests.followsBackupJob` |
| AC-87 | 1 / 2 | album AC-74; script xoá `Shared/2025/c.HEIC` | app về trước mặt | ảnh rời **is**, vào **is not** (đợt 1); ô lưới mất glyph (đợt 2) | ⚠️ chưa có — `ServerSourceIndexTests.rescanOnForeground` + `ui-drive` |
| AC-88 | 1 | album 20 mục; sau lượt so cuối script xoá 2 file | Select All → Delete → xác nhận | 18 vào Recently Deleted; alert nêu 2 mục "no longer on NAS Home" | ⚠️ chưa có — `PhotoDeletionGateTests.reverifiesServerCopy` |
| AC-89 | 1 | như AC-88, server tắt | Delete → xác nhận | alert "Can't reach NAS Home" + Delete Anyway / Cancel; Cancel → 0 mục bị xoá | ⚠️ chưa có — `PhotoDeletionGateTests.unreachableAsks` |
| AC-90 | 1 | hộp xác nhận xoá từ album AC-74 | mở hộp | có câu Recently Deleted / iCloud space | ⚠️ chưa có — ảnh chụp |
| AC-91 | 2 | ảnh có bản ở `Shared/2025/a.HEIC` | mở Photo Info | mục On Server có `NAS Home` / `iCloud Photo/Shared/2025/a.HEIC`; Uploaded to Server như cũ | ⚠️ chưa có — ảnh iPhone, iPad, Duo trong |
| AC-92 | 1 | quyền `.limited`, 50 mục được cấp | mở **is** | chỉ 50 mục được kiểm; câu "Only photos ShotDex can access are checked." | ⚠️ chưa có |
| AC-93 | 1 | iPhone 402×874, iOS 26.5 và 18.6 | thêm Source = NAS Home, chạm Folder, chọn `Shared` | dòng Folder ghi `Shared`; số khớp cập nhật; khớp board ± 2pt | ⚠️ chưa có — `Tools/design-board compare` |
| AC-94 | 1 | connection không có job Backup, đang dùng di động, *Use Cellular Data for Indexing* bật | lượt kiểm | 0 lệnh tới server; `Waiting for Wi‑Fi` | ⚠️ chưa có — `OnServerScheduleTests.noJobMeansWiFiOnly` |
| AC-95 | 1 | ảnh có bản Photos + bản NAS; script đã xoá file NAS sau lượt so cuối | chọn ảnh ở **Library** → Delete | ảnh không bị xoá; alert "no longer on NAS Home" | ⚠️ chưa có — `PhotoDeletionGateTests.libraryDeleteRoutes` |
| AC-96 | 2 | folder server có `IMG_1.HEIC` + `IMG_1.MOV`, và `IMG_2.MOV` một mình | index nguồn | Library có 1 Live Photo (IMG_1) và 1 video (IMG_2) | ⚠️ chưa có — `ServerSourceIndexTests.pairsLivePhoto` |
| AC-97 | 1 | 2 job Backup cùng connection: một *Only on Wi‑Fi*, một không | đang dùng di động | không chạy; `Waiting for Wi‑Fi` | ⚠️ chưa có — `OnServerScheduleTests.strictestJobWins` |
| AC-98 | 1 | ảnh trong album AC-74 | xoá nó | bản NAS không bị ẩn; ảnh vẫn trong Library từ NAS Home | ⚠️ chưa có — `PhotoDeletionGateTests.serverCopyStaysVisible` |
| AC-99 | 1 | ảnh đã sửa trong Photos; bản gốc có trên `Shared/`, bản sửa không | đếm **is**, mở dòng tiến độ | không trong **is**; ghi "Edited — edit not on NAS Home" | ⚠️ chưa có — `OnServerRuleTests.editedNeedsRender` |
| AC-100 | 1 | 500 mục Backup đã chép, dấu nguồn còn khớp | lượt kiểm đầu | 0 lần tải iCloud cho 500 mục đó | `PhotosHashTests.seedsFromBackupLedger` (6 mục: 4 lấy SHA từ sổ, 1 đổi dấu nguồn và 1 chưa backup thì không; phần "0 lần tải" khi có ứng viên cùng cỡ ⚠️ chờ T6) |
| AC-101 | 1 | 100 mục chưa backup; 10 có file NAS cùng cỡ | lượt kiểm | đúng 10 lần tải; 90 mục vào **is not** | ⚠️ chưa có — `PhotosHashTests.downloadsOnlySizeCandidates` |
| AC-102 | 1 | file khớp bị ghi đè cùng cỡ, đổi ngày sửa, sau lượt so cuối | xoá mục đó | không bị xoá; alert "no longer on NAS Home" | ⚠️ chưa có — `PhotoDeletionGateTests.modifiedDateBlocks` |
| AC-103 | 1 | file khớp bị dời sang folder khác trong cùng nguồn sau lượt so cuối | xoá mục đó | tìm lại được bằng hash nhanh + cỡ; mục bị xoá | ⚠️ chưa có — `PhotoDeletionGateTests.reResolvesMovedFile` |
| AC-104 | 1 | thêm một lời gọi xoá PhotoKit mới ngoài cổng (ngoài danh sách lối cũ) | chạy test | test hỏng, nêu file:dòng | ⚠️ chưa có — `PhotoDeletionGateTests.noNewDirectDeletes` |
| AC-105 | 2 | kiểm còn 1.000 file; app không mở | hệ thống chạy tác vụ nền | tiến độ tăng; dừng sạch khi hết hạn | ⚠️ chưa có — test giả lập tác vụ + S3 |
| AC-106 | 2 | gộp Photos ↔ server bật | một lượt kiểm gộp 10 ảnh | 0 lần ghi sidecar lên NAS | ⚠️ chưa có — `PhotoIdentityMergeTests.checkMergeWritesNoSidecar` |
| AC-S1…S4 | — | spike §1 | — | số đo ghi vào intent | ⚠️ cần máy thật |

**Chưa chứng minh được:** cả bảng — tính năng chưa có code.
