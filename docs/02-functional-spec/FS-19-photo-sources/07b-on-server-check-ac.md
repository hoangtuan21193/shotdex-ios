# FS-19.07b — Ảnh Photos đã có trên server: spike và tiêu chí nghiệm thu

`FS-19.07b` · quy tắc: [07](07-on-server-check.md) · cập nhật 2026-11-03 (§4 băm dùng chung, AC-144…158; spike S5–S8)

## 1. Spike trên máy thật (đo trước, chốt AC sau)

Simulator không có iCloud thật, Optimize Storage hay lịch chạy nền thật. Mỗi spike là một build thử (không ship) ghi số vào
`docs/_intents/2026-10-24-smart-album-on-nas.md`. S1, S2, S4 trước đợt 1 ship; S3 trước đợt 2.

| # | Câu hỏi | Cách đo | Đạt khi | Quyết định phụ thuộc |
|---|---|---|---|---|
| S1 | iCloud **đầy** + Optimize Storage: tải bản gốc chỉ-iCloud qua PhotoKit có chạy không? | iPhone thật, iCloud đầy; tải 50 ảnh + 5 video 4K chỉ-iCloud; ghi kết quả, thời gian, mã lỗi | ≥ 54/55 tải được | không đạt → mục đó `Can't download from iCloud`, không chặn cả lượt |
| S2 | Photos có giữ bản gốc vừa tải (máy đầy dần)? | đo chỗ trống trước/sau tải 10 GB rồi xoá file tạm; đo lại sau 1 giờ và 24 giờ | giảm ≤ 1 GB sau 24 giờ | không đạt → thêm trần GB tải mỗi lượt |
| S3 | Một đêm cắm sạc, tác vụ nền được bao nhiêu phút, băm bao nhiêu GB? | 20.000 mục, cắm sạc qua đêm, đọc log; iOS 26.5 và 18 | ghi số | thiết kế chạy nền đợt 2 |
| S4 | Băm video 4K 3 GB đọc luồng: bộ nhớ đỉnh, thời gian, nhiệt? | Instruments, iPhone 17, 3 video | bộ nhớ tăng ≤ 64 MB; không bị giết | không đạt → giảm khối đọc, chỉ băm video khi sạc |
| S5 | (§12) Cùng một ảnh trên Mac và iPhone: `cloudIdentifier` ánh xạ được, `modificationDate` (giây) trùng? | 200 ảnh, cả ảnh đã sửa; ghi cloud id + ngày sửa trên hai máy | ≥ 199/200 trùng | không đạt → khoá Photos thêm cỡ từng file, hoặc bỏ chia sẻ phía Photos |
| S6 | (§12) Bản gốc **và bản sửa** tải qua iCloud có cùng byte trên hai máy? | 50 ảnh (20 đã sửa, 5 Live Photo, 5 RAW+JPEG); SHA từng file trên Mac và iPhone | 50/50 trùng, kể cả bản sửa | bản sửa lệch → không chia sẻ SHA bản sửa, máy nhận tự băm bản sửa |
| S7 | (§12) CloudKit: đẩy lần đầu 70k `PhotoFileHash` + 200k `ServerFileHash` | Mac thật, đếm thời gian, lỗi throttle, dung lượng iCloud tăng | xong ≤ 2 giờ; không lỗi không thử lại được; tăng ≤ 100 MB | không đạt → đẩy theo lô nhỏ hơn, giãn thời gian; hoặc chỉ đẩy `ServerFileHash` của file có ứng viên |
| S8 | (§12) Mac băm cả NAS qua mạng nhà | 1 TB ảnh/video trên NAS, Mac cắm dây và qua Wi‑Fi | ghi GB/giờ; Backup chạy cùng lúc không chậm quá 20% | thiết kế thứ tự và giới hạn tốc độ băm NAS |
| S9 | (§12) Mac bật Optimize Storage: tải bản gốc qua PhotoKit để băm rồi xoá file tạm — thư viện Photos của Mac có giữ lại bản gốc đã tải không? | 500 ảnh chỉ-iCloud, đo dung lượng thư viện Photos trước, ngay sau và sau 24 giờ | tăng ≤ 1 GB sau 24 giờ | không đạt → băm theo lô có ngân sách GB mỗi ngày, hoặc chỉ băm ảnh đã có trên Mac |

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
| AC-87 | 1 / 2 | album AC-74; script xoá `Shared/2025/c.HEIC` | app về trước mặt | ảnh rời **is**, vào **is not** (đợt 1); ô lưới mất glyph (đợt 2) | `ServerSourceIndexTests.rescanOnForeground` (đợt 1: liệt kê lại khi về trước mặt, ảnh từ **is** sang **is not**) · `.noTimedRescan` · glyph: `OnServerIndexTests.glyphFollowsCopies` + ảnh lưới iPhone 26.5 (4/6 ảnh có dấu) |
| AC-88 | 1 | album 20 mục; sau lượt so cuối script xoá 2 file | Select All → Delete → xác nhận | 18 vào Recently Deleted; alert nêu 2 mục "no longer on NAS Home" | `PhotoDeletionGateTests.reverifiesServerCopy` (18 xoá, alert nêu 2; liệt kê lại nguồn một lần trước khi kết luận) |
| AC-89 | 1 | như AC-88, server tắt | Delete → xác nhận | alert "Can't reach NAS Home" + Delete Anyway / Cancel; Cancel → 0 mục bị xoá | `PhotoDeletionGateTests.unreachableAsks` · ảnh iPhone 26.5 (WebDAV tắt: alert Can't Reach NAS Home + Delete Anyway / Cancel) |
| AC-90 | 1 | hộp xác nhận xoá từ album AC-74 | mở hộp | có câu Recently Deleted / iCloud space | `PhotoDeletionGateTests.confirmNamesRecentlyDeleted` · ảnh iPhone 26.5 (album thật, cổng hỏi WebDAV xong mới hiện hộp) |
| AC-91 | 2 | ảnh có bản ở `Shared/2025/a.HEIC` | mở Photo Info | mục On Server có `NAS Home` / `iCloud Photo/Shared/2025/a.HEIC`; Uploaded to Server như cũ | `OnServerIndexTests.photoInfoLocations` · ảnh iPhone 26.5 (`NAS Home` / `iCloud Photo/Shared/2025/IMG_0002.JPG`) · board `PH_/IP_/DI_/DC_Metadata` (iPad, Duo chưa chụp app) |
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
| AC-105 | 2 | kiểm còn 1.000 file; app không mở | hệ thống chạy tác vụ nền | tiến độ tăng; dừng sạch khi hết hạn | `OnServerScheduleTests.backgroundSlotStopsCleanly` (tiến độ tăng 3 đợt, hết hạn thì dừng giữa hai đợt, còn việc cho lượt sau) · `OnServerBackgroundService` ghi một dòng `S3` mỗi lượt nền · số đo S3 ⚠️ cần máy thật |
| AC-106 | 2 | gộp Photos ↔ server bật | một lượt kiểm gộp 10 ảnh | 0 lần ghi sidecar lên NAS | `PhotoIdentityMergeTests.checkMergeWritesNoSidecar` (10 ảnh gộp, 0 dòng `pending_sidecar`, id Photos giữ lại) · `.deletingMergedKeepsServerCopy` · `.partialMatchStaysApart` |
| AC-S1…S4 | — | spike §1 | — | số đo ghi vào intent | harness `OnServerSpike` (DEBUG, `-ShotDexOnServerSpike S1/S2/S4`) chạy trên sim; số đo ⚠️ cần máy thật — bảng trong intent |

**Chưa chứng minh được** (kiểm 2026-10-26, iPhone 17 iOS 26.5 qua WebDAV cục bộ):
- AC-74, AC-93: so board ± 2pt (`Tools/design-board compare` qua `ui-drive`) và iOS 18.6 chưa chạy; số và chip đã có test.
- AC-85: phần "có mặt trong **is**" sau một lượt Backup thật chưa có test đầu-cuối (SHA từ sổ đã có; truy vấn **is** đọc
  SHA đó — `OnServerRuleTests`).
- AC-92: ảnh dưới quyền `.limited` chưa chụp.
- AC-91 và mọi AC có UI: ảnh iPad, Duo trong/ngoài chưa chụp (board đã vẽ).
- S1–S4: cần iPhone thật — harness và log đã có (intent, mục Số đo spike).

## 3. Mac

Quy tắc: [07 §11](07-on-server-check.md#11-mac-2026-11-02). Helper và spike SM-1…4: [FS-22.06](../FS-22-backup/06-mac.md).
Logic (AC-74…AC-106) không chứng minh lại; dưới đây chỉ phần Mac.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-107 | Mac, nguồn `NAS Home` gốc `iCloud Photo/`, như AC-74 | New Smart Album… ⌥⌘N: Source is NAS Home, Folder → Choose… chọn `Shared` | sheet hiện dòng Folder `Shared`; lưu → sidebar có album, mở ra *40 photos*, chip `Source is NAS Home › Shared` | ⚠️ chưa có (`mac-smart-album-onserver.json`) + `design-parity` `MAC_SmartAlbumEditor`, `MAC_SmartAlbum` |
| AC-108 | album AC-107, kiểm 30/100 | nhìn thanh dưới toolbar | `Checking · 30 of 100` cùng hàng số mục; xong → `Checked … ago` | `OnServerProgressTests` (dùng lại) + ⚠️ chưa có (ảnh cửa sổ) |
| AC-109 | còn 1.000 file chưa kiểm, helper bật | Quit ShotDex | helper kiểm tiếp; mở lại app sau 10 phút, tiến độ đã tăng | ⚠️ chưa có `MacAgentTests.onServerRunsAfterQuit`; đo tay 2026-11-02: app đã thoát, helper một mình kiểm 8812 → 9012/55375 trong ~1 phút (log `agent on server pass`, SMB impacket ở 127.0.0.1) |
| AC-110 | app đã Quit 30 phút, script xoá `Shared/2025/c.HEIC` | mở lại album | ảnh rời **is** mà không cần app về trước mặt trước đó (helper liệt kê lại theo 30 phút) | ⚠️ chưa có (`MacAgentTests.periodicRelisting`) |
| AC-111 | album 20 mục, 2 file đã bị xoá trên NAS | ⌘A → ⌘⌫ → xác nhận | 18 vào Recently Deleted; `NSAlert` nêu 2 mục "no longer on NAS Home" | `PhotoDeletionGateTests.reverifiesServerCopy` (dùng lại) + ⚠️ chưa có (`mac-onserver-delete.json`) |
| AC-112 | như AC-111, server tắt | ⌘⌫ → xác nhận | `NSAlert` "Can't reach NAS Home" · Delete Anyway (đỏ) · Cancel (mặc định); Return = Cancel, 0 mục bị xoá | ⚠️ chưa có (`mac-onserver-delete.json`) |
| AC-113 | ảnh có bản ở `Shared/2025/a.HEIC` | chọn ảnh, ⌘I | Get Info có mục On Server: `NAS Home` / `iCloud Photo/Shared/2025/a.HEIC`; ô lưới có glyph | `OnServerIndexTests.photoInfoLocations` (dùng lại) + ⚠️ chưa có (`design-parity` `MAC_GetInfoSingle`) |
| AC-114 | — | 3 mục Photos chưa liệt kê: A chụp 2017 nhưng index lúc 1.800.000.000, B chụp 2025 index lúc 1.700.000.000, C chụp 2020 index lúc 1.700.000.000 | lấy hàng đợi liệt kê | thứ tự A, B, C — mục vào thư viện gần nhất trước, cùng lúc thì ngày chụp mới hơn trước | `PhotosHashTests.listsRecentlyAddedFirst` |

## 4. Băm dùng chung (§12)

Quy tắc: [07 §12](07-on-server-check.md#12-băm-dùng-chung--mac-băm-hộ-máy-khác-chỉ-đọc-2026-11-03). Spike S5–S8 ở §1.
Thư viện thử không có ảnh mặt người.
- Server thử: SMB ảo `127.0.0.1:4450` (memory `common-photos-fs1908`) và WebDAV cục bộ.
- CloudKit: test domain dùng kênh giả (`SharedIndexSource`); kênh thật cần thiết bị (như BD-03.05).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-144 | Mac, 4 mục Photos: 3 bản gốc có trên Mac, 1 chỉ-iCloud; *Share Index Across Devices* bật | một lượt helper | `copy_files` có SHA của cả 4 (`origin = hashed`); bản chỉ-iCloud được tải vào thư mục tạm, băm, thư mục tạm rỗng sau lượt; mục vào thư viện gần nhất được băm trước | ✅ `PhotosHashTests.macHashesEveryItem` (Mac thật: spike S9) |
| AC-145 | nguồn server có 5 ảnh, không mục Photos nào cùng cỡ | lượt helper Mac | cả 5 được băm (không chỉ ứng viên); gốc nguồn có `.shotdex/hash-index/<mã máy>-000001.jsonl` 5 dòng (đường dẫn tương đối, cỡ, ngày sửa, SHA); không file part nào còn lại | ✅ `SharedHashTests.ledgerWrittenAtSourceRoot` (+ `macHashesEveryServerFile`) |
| AC-146 | sổ AC-145 trên NAS, iPhone chưa có SHA nào của nguồn | iPhone liệt kê nguồn rồi kiểm | 0 lệnh tải file nào từ NAS (client giả đếm); 5 file có SHA `origin = shared` | ✅ `SharedHashTests.readerSkipsDownloads` (+ `ledgerTrustRules`); e2e SMB ảo `OnServerSMBTests.ledgerSavesDownloads` |
| AC-147 | như AC-146, nhưng `b.HEIC` đổi ngày sửa sau khi Mac ghi sổ | iPhone kiểm | dòng của `b.HEIC` bị bỏ; đúng 1 file bị tải để băm; 4 file kia dùng sổ | ✅ `SharedHashTests.staleLineIgnored` |
| AC-148 | nguồn có `.shotdex/hash-index/` | liệt kê nguồn, quét Find Common Photos (FS-19.08), đếm ảnh nguồn | không có file nào trong `.shotdex/` thành ảnh, ứng viên hay số đếm; không lệnh ghi nào ngoài `.shotdex/` (client giả ghi lại lệnh) | ✅ `SharedHashTests.ledgerNeverAPhoto` |
| AC-149 | Mac đã đẩy `PhotoFileHash` của 10 mục; iPhone có 10 mục cùng cloud id, cùng ngày sửa, cả 10 chỉ-iCloud | iPhone kiểm (kênh giả) | 0 lần tải iCloud cho 10 mục; album **is** / **is not** đúng như khi iPhone tự băm | ⚠️ chưa có |
| AC-150 | như AC-149, mục 3 sửa trên iPhone sau khi Mac băm (ngày sửa lệch) | iPhone kiểm | mục 3 được tải và băm lại trên iPhone; 9 mục kia không tải | ⚠️ chưa có |
| AC-151 | `ServerFileHash` từ Mac cho connection `smb://nas.local`; iPhone có connection cùng danh tính và một connection `smb://192.168.1.5` | iPhone kiểm cả hai | connection cùng danh tính: 0 lần tải; connection khác danh tính: tự băm như hôm nay | ⚠️ chưa có |
| AC-152 | 100 mục khớp **is** nhờ SHA từ Mac, K = 10 | một lượt kiểm trên iPhone | đúng 10 file được iPhone tự băm lại; khớp hết → 100 mục vẫn **is** | ⚠️ chưa có |
| AC-153 | như AC-152, 1 trong 10 file kiểm ngẫu nhiên lệch SHA; sau đó Mac gửi thêm 5 SHA mới | lượt đó, rồi lượt sau | mọi SHA Mac gửi trước lúc lệch bị bỏ; các mục về "chưa kiểm xong" rồi iPhone tự băm; dòng tiến độ `Hashes from <tên Mac> didn't match — checking on this iPhone.`; không lượt xoá nào dùng SHA đã bỏ; lượt sau 5 SHA mới được dùng (kèm kiểm ngẫu nhiên) | ⚠️ chưa có |
| AC-154 | mục khớp **is** chỉ nhờ SHA từ Mac; file trên NAS bị xoá sau đó | xoá mục khỏi album | `PhotoDeletionGate` hỏi lại server, mục **không** bị xoá, alert "no longer on NAS Home" | ✅ `PhotoDeletionGateTests.sharedHashStillReverifies` |
| AC-155 | *Share Index Across Devices* tắt (hoặc không có iCloud, hoặc Mac thiếu entitlement) | Mac và iPhone chạy kiểm | không kéo, không đẩy record nào; iPhone tự băm như hôm nay; không crash | ⚠️ chưa có |
| AC-156 | iPhone tự băm 2 mục Mac chưa băm tới | iPhone đẩy lên, rồi Mac kiểm | Mac dùng 2 SHA đó (0 lần đọc file cho chúng), `origin = shared` | ⚠️ chưa có |
| AC-157 | helper Mac đang băm file NAS thứ 40/100, Backup bắt đầu lượt | Backup cần connection | băm nhả khoá giữa hai file, Backup đi trước; sau Backup băm tiếp từ file 41; không file tạm nào còn lại | ⚠️ một phần — làm tiếp từ file kế: `SharedHashTests.macHashesEveryServerFile` (dừng sau 2, lượt sau 3, không đọc lại); nhả khoá cho Backup là `LockedRemoteFileClient` có sẵn, chưa test riêng |
| AC-158 | Mac và iPhone cùng ghi sổ vào một nguồn trong một lượt | cả hai ghi xong | hai đoạn riêng (`<mã Mac>-…`, `<mã iPhone>-…`), không dòng nào mất; máy thứ ba đọc được cả hai | ✅ `SharedHashTests.twoWritersTwoSegments` (hai máy ghi lần lượt; mỗi máy chỉ ghi đoạn của mình nên ghi đồng thời không đụng nhau) |

