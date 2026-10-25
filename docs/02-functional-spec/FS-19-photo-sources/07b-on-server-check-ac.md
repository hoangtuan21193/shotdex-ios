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
| AC-74 | 1 | nguồn `NAS Home` ở gốc `iCloud Photo/`; 100 mục Photos đã kiểm xong; 40 có đủ file trong `Shared/`, 25 chỉ trong `Tuấn/` | lưu album: Source is NAS Home · Folder `Shared` | *Matches 40 photos*; chip `Source: NAS Home › Shared` | `OnServerRuleTests.folderScope` (40 / 25 / mọi tầng con / `Shared copy` không tính) · chip: `.chipNamesSourceAndFolder` |
| AC-75 | 1 | như AC-74, gộp ảnh FS-19 tắt | đổi Folder thành trống | *Matches 65 photos* | `OnServerRuleTests.wholeSourceWithoutMerge` (65 có / 35 không; 0 dòng gộp; ảnh riêng của NAS không tính) |
| AC-76 | 1 | 1 ảnh trong album AC-74; script dời `Shared/2025/a.HEIC` → `Shared/x/b.HEIC` | app về trước mặt | ảnh vẫn trong album; 0 lần đọc trọn `b.HEIC` | `ServerSourceIndexTests.renameKeepsIdentity` (cùng bản sao, cùng ảnh, 0 lần đọc trọn, SHA giữ nguyên) — album đọc SHA theo bản sao nên ảnh ở lại; `OnServerRuleTests.folderScope` phủ mọi tầng con |
| AC-77 | 1 | Live Photo, trên `Shared/` chỉ có `IMG_1.HEIC`, thiếu `IMG_1.MOV` | đếm **is** / **is not** | không trong **is**; trong **is not** | `OnServerRuleTests.livePhotoNeedsVideo` |
| AC-78 | 1 | RAW+JPEG, cả `.ARW` và `.JPG` trên `Shared/` | đếm **is** | có trong **is** | `OnServerRuleTests.rawPairBothFiles` (JPEG là file đi kèm của bản RAW) |
| AC-79 | 1 | trên `Shared/`: một bản JPEG nén lại và một bản cùng ảnh nhưng có XMP nhúng thêm, của hai HEIC trong Photos | đếm **is** | cả hai mục không trong **is** | `OnServerRuleTests.notByteIdenticalIsNotPresent` |
| AC-80 | 1 | 100 mục, 30 kiểm xong, 70 có ứng viên chưa băm | mở **is not** của Shared | 70 mục không có mặt; dòng `Checking · 30 of 100` | `OnServerRuleTests.uncheckedInNeither` (ứng viên chưa băm ở cả hai phía; mục chưa liệt kê cũng vậy) · dòng: `OnServerProgressTests.checkingCounts` · ảnh iPhone 26.5 (album thật qua WebDAV: 3 ảnh, `Checked … ago`) |
| AC-81 | 1 | 500/1.000 file đã băm | giết app, mở lại | lượt tiếp bắt đầu ở file 501; 0 file trong 500 bị đọc lại | `PhotosHashTests.resumesAfterKill` (20 file, dừng ở lần tải 11: lượt sau tải đúng 10 file còn lại, không file nào đã băm) |
| AC-82 | 1 | 3 mục chỉ-iCloud có ứng viên, trống 12 GB | lượt băm | ≤ 1 file tạm mỗi lúc, xoá ngay sau khi băm; 3 mục có hash | `PhotosHashTests.oneTempFileAtATime` (thư mục tạm rỗng trước mỗi lần tải và sau lượt; 1 mục đọc hỏng ghi lỗi, không chặn 3 mục kia) · tải iCloud thật: S1 |
| AC-83 | 1 | trống 2,5 GB, file kế là video 1 GB | lượt tới file đó | dừng, không tải; `Waiting for space` | `PhotosHashTests.waitsForSpace` (dừng, 0 lần tải, cờ chờ chỗ) · dòng chữ: `OnServerProgressTests.waitsLimitedAndDone` |
| AC-84 | 1 | NAS 1.000 file, 40 có cỡ bằng một file gốc Photos chưa khớp | lượt băm server | đúng 40 file được đọc trọn | `ServerSourceIndexTests.fullHashOnlySizeCandidates` (50 file: 4 ứng viên + 1 file mất sau listing được đọc; file cùng cỡ với ảnh đã khớp không đọc; lỗi ghi lại, lượt sau chỉ đọc lại file lỗi) · hash giữ qua lần dời: `renameKeepsIdentity` |
| AC-85 | 1 | Backup đẩy 10 ảnh vào `Shared/` (nằm trong nguồn) | Backup xong, mở **is** | 10 ảnh có mặt; 0 lần đọc lại từ NAS | `BackupRunnerTests.recordsServerCopyHash` (phần hash: 10 bản sao có SHA từ sổ, 0 lần đọc trọn, 0 lần tải; phần "có mặt" ⚠️ chờ T7) |
| AC-86 | 1 | job Backup *Only on Wi‑Fi*, máy đang dùng di động | lượt kiểm tới lúc chạy | 0 lệnh tới server, 0 tải iCloud; `Waiting for Wi‑Fi` | `OnServerScheduleTests.followsBackupJob` (0 lần liệt kê, 0 lần băm server, 0 lượt Photos; chờ Wi‑Fi cả hai phía) · nền đợt 1: `.runsUntilNothingLeft`, `.unreachableSourceWaits`, `.backgroundStopsAndSaysOpenApp` |
| AC-87 | 1 / 2 | album AC-74; script xoá `Shared/2025/c.HEIC` | app về trước mặt | ảnh rời **is**, vào **is not** (đợt 1); ô lưới mất glyph (đợt 2) | `ServerSourceIndexTests.rescanOnForeground` (đợt 1: liệt kê lại khi về trước mặt, ảnh từ **is** sang **is not**) · `.noTimedRescan`; glyph ⚠️ đợt 2 |
| AC-88 | 1 | album 20 mục; sau lượt so cuối script xoá 2 file | Select All → Delete → xác nhận | 18 vào Recently Deleted; alert nêu 2 mục "no longer on NAS Home" | `PhotoDeletionGateTests.reverifiesServerCopy` (18 xoá, alert nêu 2; liệt kê lại nguồn một lần trước khi kết luận) |
| AC-89 | 1 | như AC-88, server tắt | Delete → xác nhận | alert "Can't reach NAS Home" + Delete Anyway / Cancel; Cancel → 0 mục bị xoá | `PhotoDeletionGateTests.unreachableAsks` · ảnh iPhone 26.5 (WebDAV tắt: alert Can't Reach NAS Home + Delete Anyway / Cancel) |
| AC-90 | 1 | hộp xác nhận xoá từ album AC-74 | mở hộp | có câu Recently Deleted / iCloud space | `PhotoDeletionGateTests.confirmNamesRecentlyDeleted` · ảnh iPhone 26.5 (album thật, cổng hỏi WebDAV xong mới hiện hộp) |
| AC-91 | 2 | ảnh có bản ở `Shared/2025/a.HEIC` | mở Photo Info | mục On Server có `NAS Home` / `iCloud Photo/Shared/2025/a.HEIC`; Uploaded to Server như cũ | ⚠️ chưa có — ảnh iPhone, iPad, Duo trong |
| AC-92 | 1 | quyền `.limited`, 50 mục được cấp | mở **is** | chỉ 50 mục được kiểm; câu "Only photos ShotDex can access are checked." | câu: `OnServerProgressTests.waitsLimitedAndDone`; chỉ mục được cấp được kiểm vì chỉ chúng có trong index · ảnh ⚠️ T14 |
| AC-93 | 1 | iPhone 402×874, iOS 26.5 và 18.6 | thêm Source = NAS Home, chạm Folder, chọn `Shared` | dòng Folder ghi `Shared`; số khớp cập nhật; khớp board ± 2pt | ảnh iPhone 26.5 (WebDAV cục bộ: Folder mở màn duyệt ở `Shared`, chọn `2025` → `Shared/2025`, 3 → 2 photos); 18.6 + `design-board compare` ⚠️ T14 |
| AC-94 | 1 | connection không có job Backup, đang dùng di động, *Use Cellular Data for Indexing* bật | lượt kiểm | 0 lệnh tới server; `Waiting for Wi‑Fi` | `OnServerScheduleTests.noJobMeansWiFiOnly` |
| AC-95 | 1 | ảnh có bản Photos + bản NAS; script đã xoá file NAS sau lượt so cuối | chọn ảnh ở **Library** → Delete | ảnh không bị xoá; alert "no longer on NAS Home" | `PhotoDeletionGateTests.libraryDeleteRoutes` |
| AC-96 | 2 | folder server có `IMG_1.HEIC` + `IMG_1.MOV`, và `IMG_2.MOV` một mình | index nguồn | Library có 1 Live Photo (IMG_1) và 1 video (IMG_2) | `ServerSourceIndexTests.pairsLivePhoto` (cả khi tắt ghép RAW + JPEG; vai trò file `companion:video`) · `FolderSourceIndexTests.pairsLivePhoto` |
| AC-97 | 1 | 2 job Backup cùng connection: một *Only on Wi‑Fi*, một không | đang dùng di động | không chạy; `Waiting for Wi‑Fi` | `OnServerScheduleTests.strictestJobWins` (cả Only While Charging) |
| AC-98 | 1 | ảnh trong album AC-74 | xoá nó | bản NAS không bị ẩn; ảnh vẫn trong Library từ NAS Home | `PhotoDeletionGateTests.serverCopyStaysVisible` |
| AC-99 | 1 | ảnh đã sửa trong Photos; bản gốc có trên `Shared/`, bản sửa không | đếm **is**, mở dòng tiến độ | không trong **is**; ghi "Edited — edit not on NAS Home" | `OnServerRuleTests.editedNeedsRender` (phần **is**) · dòng: `OnServerProgressTests.editedLine` |
| AC-100 | 1 | 500 mục Backup đã chép, dấu nguồn còn khớp | lượt kiểm đầu | 0 lần tải iCloud cho 500 mục đó | `PhotosHashTests.seedsFromBackupLedger` (6 mục, NAS có file cùng cỡ: 4 lấy SHA từ sổ, 0 lần tải; chỉ mục chưa backup bị tải) |
| AC-101 | 1 | 100 mục chưa backup; 10 có file NAS cùng cỡ | lượt kiểm | đúng 10 lần tải; 90 mục vào **is not** | `PhotosHashTests.downloadsOnlySizeCandidates` (đúng 10 lần tải, mới nhất trước) · mục không có file cùng cỡ vào **is not**: `OnServerRuleTests.notByteIdenticalIsNotPresent` |
| AC-102 | 1 | file khớp bị ghi đè cùng cỡ, đổi ngày sửa, sau lượt so cuối | xoá mục đó | không bị xoá; alert "no longer on NAS Home" | `PhotoDeletionGateTests.modifiedDateBlocks` |
| AC-103 | 1 | file khớp bị dời sang folder khác trong cùng nguồn sau lượt so cuối | xoá mục đó | tìm lại được bằng hash nhanh + cỡ; mục bị xoá | `PhotoDeletionGateTests.reResolvesMovedFile` (0 lần đọc trọn) |
| AC-104 | 1 | thêm một lời gọi xoá PhotoKit mới ngoài cổng (ngoài danh sách lối cũ) | chạy test | test hỏng, nêu file:dòng | `PhotoDeletionGateTests.noNewDirectDeletes` (đếm lời gọi theo file; 3 lối đợt 1 phải đi qua `photoDeletionGate`) |
| AC-105 | 2 | kiểm còn 1.000 file; app không mở | hệ thống chạy tác vụ nền | tiến độ tăng; dừng sạch khi hết hạn | ⚠️ chưa có — test giả lập tác vụ + S3 |
| AC-106 | 2 | gộp Photos ↔ server bật | một lượt kiểm gộp 10 ảnh | 0 lần ghi sidecar lên NAS | `PhotoIdentityMergeTests.checkMergeWritesNoSidecar` (10 ảnh gộp, 0 dòng `pending_sidecar`, id Photos giữ lại) · `.deletingMergedKeepsServerCopy` · `.partialMatchStaysApart` |
| AC-S1…S4 | — | spike §1 | — | số đo ghi vào intent | harness `OnServerSpike` (DEBUG, `-ShotDexOnServerSpike S1/S2/S4`) chạy trên sim; số đo ⚠️ cần máy thật — bảng trong intent |

**Chưa chứng minh được:** cả bảng — tính năng chưa có code.
