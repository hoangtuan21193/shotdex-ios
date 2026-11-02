# Kế hoạch — FS-19.08 Gom ảnh chung của nhiều folder server (Mac)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.08`](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC: [`08b`](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) (AC-115…130) |
| Intent | [2026-11-02-common-photos-across-folders](../_intents/2026-11-02-common-photos-across-folders.md) |
| Commit spec | `a64935f3` (intent `45653bb5`) |
| Ngày | 2026-11-03 |
| Trạng thái | đang làm — duyệt 2026-11-03 (Q1, Q2: dựng cả màn duyệt server lẫn Activity); T1+T2 `eefcf32c`, T3 `73c2c833`, T4 `abdfa2fc`, T5 `700e1af6`, T6 `f16d735b`, T7 `8e18c6ca`, T8 `aad1cd00`, T9a `043fb941`, T9b xong (loop: [FS1908_LOOP.md](FS1908_LOOP.md)) |

## 1. Hiểu đúng chưa

Trên Mac, người dùng chọn ≥ 2 folder của **một** connection là nguồn server. ShotDex liệt kê cây các folder, loại ngay
mọi file không có cỡ trùng ở **mọi** folder, gợi ý **Likely the same** (cùng cỡ + cùng tên / cùng folder con / cùng ngày
chụp), rồi đọc 3 đoạn 64 KB và băm SHA-256 cả file để thành **Same**. Chỉ Same được **Copy** (mặc định: tải → đẩy file
part → đọc lại SHA → đổi tên) hay **Move** (đổi chỗ trên server, kiểm, rồi xoá các bản còn lại; không bao giờ xoá trước khi
đích được kiểm) vào folder chung phẳng, có log từng file, CSV trong folder chung, làm tiếp được sau khi mất kết nối.

## 2. Đối chiếu AC ↔ code

Logic quét và chạy là **mới hoàn toàn**; nhưng mọi viên gạch phía server đã có. Không AC nào ✅ sẵn.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-115 lọc cỡ không đọc byte | ❌ | `RemoteFileClient.entries(in:)` `ShotDex/Domain/ServerUpload/RemoteFileClient.swift:33` cho tên/cỡ/ngày sửa; fake đếm `bytesRead` `ShotDexTests/ServerUploadFakes.swift:128`, `rangeReadPaths` :167, `sha256Paths` :111 | `CommonPhotosMatcher` mới (Domain, thuần) |
| AC-116 khác tên vẫn khớp | ❌ | SHA cả file: `RemoteFileClient.sha256(of:)` :30 | so bằng SHA, tên chỉ để xếp thứ tự |
| AC-117 cùng cỡ khác byte rơi | ❌ | `readRange(_:offset:length:)` :36 có ở cả SMB/WebDAV/SFTP/Files; `RemoteRangeReader.swift:6` cache đoạn | 3 đoạn 64 KB rồi SHA |
| AC-118 cùng ngày chụp khác cỡ bỏ | ❌ | ngày chụp đọc từ đầu file: `EmbeddedPreview.captureDate(from:)` `ShotDex/Domain/ServerImport/EmbeddedPreview.swift:80`; `RemoteThumbnailer.swift:54-60` đọc 64 KB | Likely chỉ xét trong nhóm cùng cỡ — đúng theo cấu trúc |
| AC-119 giao của mọi folder | ❌ | — | nhóm theo SHA, giữ nhóm có mặt ở mọi folder |
| AC-120 2×20k ≤ 1 s | ❌ | — | dictionary theo cỡ, O(n); test đo thời gian |
| AC-121 Copy đọc lại SHA | ❌ | `VerifiedRemoteWrite` `ShotDex/Domain/ServerUpload/VerifiedRemoteWrite.swift:8` (`uploadPart` :12, `readBackSHA256` :18, `moveIntoPlace` :24, `discardPart` :33); `download` trả SHA :41 | `CommonPhotosRunner` (actor) dùng lại `VerifiedRemoteWrite`, **không** dùng nhánh replace của `moveIntoPlace` |
| AC-122 SHA đọc lại sai | ❌ | fake `corruptReadBack` :13 lật mọi lần đọc lại | fake thêm lật theo đường dẫn |
| AC-123 Move = đổi chỗ | ❌ | `move(_:to:)` :44 (đích phải trống); fake `move` :206 | fake thêm log `moved` + đếm tải |
| AC-124 khác share → chép trước | ❌ | SMB từ chối khác share `SMBFileClient.swift:153-155` | fake thêm `refuseMove` + log lệnh có thứ tự |
| AC-125 nguồn đổi sau Scan | ❌ | fake `modified` :125, `put` :26 | hỏi lại `entries` folder cha trước khi xoá |
| AC-126 trùng tên | ❌ | `ServerUploadPath.nextFreeName(for:existing:)` `ShotDex/Domain/ServerUpload/ServerUploadPath.swift:44-55` (`name (2).ext`) | dùng lại; cùng SHA → Skipped |
| AC-127 phẳng + `.xmp` | ❌ | ghép file đi kèm: `ShotDex/Domain/Sources/PairingRule.swift` | dùng `PairingRule` cho `.xmp` cùng tên gốc |
| AC-128 Resume | ❌ | fake `dropConnectionOnDownload` :132; chưa có bảng lượt chạy | bảng mới (migration v46) + Resume bỏ qua mục đã xong |
| AC-129 CSV | ❌ | `ExifCSVExporter` `ShotDex/Features/Shared/ExifCSVExporter.swift:7` chỉ cho `PhotoMetadata`, không vào target Mac | `CommonPhotosCSV` mới ở Domain; dời hàm escape thành helper dùng chung |
| AC-130 UI Mac | ❌ | **không có màn duyệt server trên Mac** (chỉ `MacServerFolderPicker` `ShotDexMac/Backup/MacBackupFormSheet.swift:207-275`, chỉ folder, không chọn nhiều, không chuột phải); **không có cửa sổ Activity** (chỉ ở spec FS-18.01 :73-75); không target test Mac | xem 2b |

Kiểm thêm của 08b:
- folder chung trong folder nguồn / lồng nhau / < 2 folder → `CommonPhotosSelection.validate` (Domain), test.
- lịch sử upload trỏ tới file bị dời: `ServerFileHistory.move(_:to:on:)` `ShotDex/Data/Database/ServerFileHistory.swift:42` và
  `forgetUploads(at:on:)` :20 — có sẵn, nhưng **Mac chưa nối** `fileHistory` (`ShotDexMac/MacDependencies.swift`). `copy_files`
  không được `ServerFileHistory` đổi đường dẫn — Rescan sau lượt chạy làm việc đó.

### 2b. ⚠️ Cần người dùng quyết

| # | Chỗ lệch | Spec nói | Code có |
|---|---|---|---|
| Q1 | Lối vào | ⌘-click 2 folder trong **màn duyệt server** (`MAC_ServerBrowser`) → chuột phải | Mac chỉ có bộ chọn folder trong sheet; plan FS-22.06 U2 cũng chỉ làm sheet chọn folder |
| Q2 | Tiến độ | lượt chạy là một hàng trong **Activity** (⌥⌘0) | Activity chưa có, cũng không có protocol "việc chạy lâu" dùng chung |

**Người dùng chốt 2026-11-03:** Q1 — **dựng màn duyệt server Mac trước** (board `MAC_ServerBrowser`), đúng spec. Q2 —
**dựng Activity luôn**, lượt gom là việc đầu tiên trong đó. Activity chưa có board → vẽ `MAC_Activity` trước khi code.

## 3. Dùng lại (không viết lại)

- `RemoteFileClient` + 4 client; `LockedRemoteFileClient` / `ConnectionLock` `ShotDex/Data/Sources/FileServer/ConnectionLock.swift:8,81`
  (runner phải đi qua khoá — bộ chọn folder Mac hiện **bỏ qua** khoá, `MacBackupFormSheet.swift:251`).
- `VerifiedRemoteWrite`, `ServerUploadPath` (`partSuffix`, `nextFreeName`, `join`), `FileChecksum.sha256`.
- `RemoteRangeReader` (cache đoạn), `EmbeddedPreview.captureDate(from:)`.
- `copy_files` (`AppDatabase+OnServer.swift:19-42`, SHA + cỡ + `modifiedAt`) để khỏi băm lại file đã băm.
- `ServerFileHistory`, `ServerSourceRefresh.rescan(sourceId:)` `ServerSourceRefresh.swift:53`.
- Giữ máy thức: mẫu `MacIndexActivity` `ShotDexMac/MacDependencies.swift:137-150` (`beginActivity` `.idleSystemSleepDisabled`).
- Fake `InMemoryRemoteFileClient` — mở rộng, không viết fake mới.
- Domain/Data tự build cho Mac (`Tools/mac-membership` chỉ loại `App/`, `Features/`), nên test ở `ShotDexTests` (iOS) phủ được lõi.

## 4. File đổi

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Domain | `ShotDex/Domain/CommonPhotos/CommonPhotosMatcher.swift`, `CommonPhotosCaptureKey.swift` | lọc cỡ → Likely (thuần); khoá ngày chụp từ đầu file | mới |
| Data | `ShotDex/Data/Sources/FileServer/ServerTreeListing.swift` (tách từ `ServerSourceIndexer.list`), `CommonPhotos/CommonPhotosScanner.swift` | liệt kê cây, đọc đầu file — phần chạm server ở Data, không ở Domain | mới / sửa |
| Domain | `ShotDex/Domain/CommonPhotos/CommonPhotosSelection.swift` | kiểm folder (≥ 2, lồng nhau, đích trong nguồn) | mới |
| Domain | `ShotDex/Domain/CommonPhotos/CommonPhotosRunner.swift` | struct (một task tuần tự; `ConnectionLock` giữ một lệnh một lúc): Copy, Move, trùng tên, `.xmp`, kiểm lại trước xoá, tiến độ, huỷ, Resume | mới |
| Domain | `ShotDex/Domain/CommonPhotos/CommonPhotosCSV.swift` | CSV log; helper escape dùng chung với `ExifCSVExporter` | mới + sửa nhỏ |
| Data | `ShotDex/Data/Database/AppDatabase+CommonPhotos.swift` | migration **v46** `common_photo_runs`, `common_photo_items` (không đụng `photo_metadata`) | mới |
| Data | `ShotDex/Data/Database/CommonPhotosStore.swift` | ghi/đọc lượt + mục, lượt dở | mới |
| Data | `AppDatabase.swift` | đăng ký migration | sửa 1 dòng |
| Mac | `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift` + `…Model` | sheet `MAC_CommonPhotos` | mới |
| Mac | `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosRunWindow.swift` | cửa sổ `MAC_CommonPhotosRun`, bảng log | mới |
| Mac | `ShotDexMacApp.swift`, `MacDependencies.swift`, `MacSidebar.swift` | File › Find Common Photos… ⇧⌘F, scene cửa sổ, `fileHistory`, chân sidebar, banner Resume | sửa |
| Mac | `ShotDexMac/Servers/MacServerBrowser*.swift` | màn duyệt server Mac: cột folder, ⌘/⇧-click chọn nhiều, chuột phải, Rescan; client qua `ConnectionLock`; dùng lại `ServerFolderListing` (Domain) | mới |
| Domain | `ShotDex/Domain/Activity/LongRunningJob.swift` | protocol việc chạy lâu (tên, tiến độ, trạng thái, Pause/Stop, Show Log) — lượt gom là bản đầu | mới |
| Mac | `ShotDexMac/Activity/MacActivityWindow.swift` | cửa sổ Activity ⌥⌘0, Window › Activity | mới |
| Design | `docs/design/mac/project/MAC_Activity.dc.html` (mới), `MAC_ServerBrowser.dc.html` (kiểm chọn nhiều + menu chuột phải có Find Common Photos…) | board sáng/tối, publish canvas Mac | mới / sửa |
| Test | `ShotDexTests/CommonPhotosMatcherTests.swift`, `CommonPhotosRunnerTests.swift`, `ServerUploadFakes.swift` | AC-115…129; fake thêm log lệnh, `moved`, `refuseMove`, lật SHA theo đường dẫn | mới / sửa |

## 5. Thứ tự task

Một task = một commit, test kèm; build iOS + `ShotDexMac` sau mỗi commit.

| # | Task | AC | Test |
|---|---|---|---|
| T1 | Matcher bước 1–3: liệt kê, lọc cỡ, Likely (cùng tên / folder con / ngày chụp trong nhóm cùng cỡ) + fake log lệnh | AC-115 (phần lọc), 118, 120 | `CommonPhotosMatcherTests.sizeFilterReadsNothingElse`, `.sameCaptureDifferentSizeIgnored`, `.twentyThousandEachUnderOneSecond` |
| T2 | Matcher bước 4–5: 3 đoạn 64 KB, SHA cả file (Likely trước), SHA đã có, giao mọi folder | AC-115, 116, 117, 119 | `.renamedFileMatches`, `.sameSizeDifferentBytesDropped`, `.intersectionOfAllFolders` |
| T3 | Migration v46 + `CommonPhotosStore` (`data-migration` duyệt) | nền AC-128 | `CommonPhotosStoreTests.roundTrip`, `.unfinishedRun` |
| T4 | Runner Copy: tải (băm) → part → đọc lại → đổi tên; lệch SHA → xoá part, Failed; **trùng tên kéo lên đây** (review: chép mà chưa kiểm tên là ghi đè được trên client không từ chối) | AC-121, 122, 126 | `CommonPhotosRunnerTests.copyVerifiesReadBack`, `.copyMismatchLeavesNothing`, `.nameClashRules` |
| T5 | Đích phẳng + `.xmp` đi theo | AC-127 | `.flatDestinationWithSidecar` |
| T6 | Runner Move: đổi chỗ → kiểm cỡ → hỏi lại bản còn lại → xoá; khác share → chép, kiểm, xoá | AC-123, 124, 125 | `.moveRenamesThenDeletes`, `.crossShareMoveCopiesFirst`, `.changedSourceNotDeleted` |
| T7 | Resume sau mất kết nối (mục đã xong không đọc lại) | AC-128 | `.resumeAfterDisconnect` |
| T8 | CSV vào folder chung + Rescan nguồn + sửa lịch sử upload (nối `fileHistory` cho Mac) | AC-129 + kiểm thêm | `.writesCsvLog`, `ServerFileHistoryTests` hiện có |
| T9a | Màn duyệt server Mac (`MAC_ServerBrowser`): sidebar nguồn server → cột folder, liệt kê, Rescan, qua `ConnectionLock` | nền AC-130 | `mac-shot` sáng/tối + `design-board compare` |
| T9b | Chọn nhiều folder (⌘/⇧-click) + chuột phải **Find Common Photos…** + File › Find Common Photos… ⇧⌘F; 1 folder → mục mờ | AC-130 (lối vào) | `mac-shot` |
| T10 | Nối `afterRun` phía Mac (review T8): `ServerFileHistory.move` cho từng `HistoryChange` (uploads, downloads, backup ledger); Rescan **mọi** nguồn chứa folder chạy **và** nguồn chứa đích; `ServerSourceRefresh` trả nil / `disconnected` / `stoppedBy` → throw để lượt ở `finishing` cho Resume; sheet cảnh báo khi đích không thuộc nguồn nào (ảnh dời sang đó thành mồ côi ở nguồn cũ). Sheet `MAC_CommonPhotos`: folder, Save to + New Folder…, Copy/Move, Scan, kết quả, lỗi, xác nhận Move | AC-130 | `mac-shot` sáng/tối + `design-board compare` |
| T11 | Cửa sổ `MAC_CommonPhotosRun` + bảng log + giữ máy thức + banner Resume + chân sidebar | AC-130 | `mac-shot` sáng/tối + `design-board compare` |
| T11a | Vẽ board `MAC_Activity` (sáng/tối, publish) | nền AC-130 | `Tools/design-board render` |
| T11b | Protocol `LongRunningJob` + cửa sổ Activity ⌥⌘0; lượt gom là một hàng, **Show Log** mở `MAC_CommonPhotosRun`; đóng cửa sổ không dừng lượt | AC-130 | `mac-shot` + `design-board compare`; test Domain `LongRunningJobTests` nếu có logic |
| T12 | `/verify FS-19.08`, `design-parity` 2 board, `Tools/gate` | tất cả | — |

Logic trước (T1–T8, test được trên iOS host), rồi T9a → T9b → T10 → T11a → T11 → T11b → T12. T9a cũng là nền cho
FS-22.06 U2 (bộ chọn folder) — làm một màn, không hai.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Move xoá nhầm (file đổi giữa Scan và xoá, mất mạng giữa đổi chỗ và xoá; đích là một nguồn dưới đường dẫn khác) | thấp, hậu quả mất ảnh | hỏi lại cỡ + ngày sửa ngay trước xoá; mục ghi DB trước mỗi bước; T6/T7 test thứ tự lệnh |
| `moveIntoPlace` xoá đích trước khi đổi tên nếu "replace" | chắc chắn nếu gọi nhầm | runner không bao giờ truyền replace; test AC-126 khoá |
| SMB song song làm hỏng phiên | vừa | mọi lệnh qua `LockedRemoteFileClient`; `swift-concurrency` duyệt |
| Băm cả file lớn qua NAS chậm (video 4K) | cao về thời gian | chỉ băm sau khi 3 đoạn khớp; một file tạm một lúc; kiểm chỗ trống trước mỗi file (NF-02) |
| WebDAV `sha256` = tải về rồi băm (`WebDAVFileClient.swift:126`) — đọc lại tốn gấp đôi | chắc chắn trên WebDAV | chấp nhận: đọc lại là điều kiện an toàn |
| Đọc đầu file 64 KB tuần tự cho nhóm cùng cỡ khác tên (RAW không nén cùng cỡ, ví dụ 5k×5k → ~640 MB) | thấp | chỉ đọc khi tên/folder con chưa khớp; khoá từ index (`known`) không đọc lại; song song vô ích vì `ConnectionLock` một lệnh một lúc |
| Khoá ngày chụp của RAW mà ImageIO không đọc được đầu (CR3, RAF) | chắc chắn | không có khoá (thiếu giây lẻ + máy, dễ khớp nhầm) — vẫn được băm, chỉ không gợi ý Likely |
| 20k mục log trong bảng SwiftUI | vừa | `Table` lười + truy vấn theo trang; `perf-profiler` |
| Không target test Mac | chắc chắn | lõi ở Domain/Data test trên iOS host; UI chứng minh bằng `mac-shot` + compare (như FS-22.06) — cần quyền Screen Recording cho Terminal |
| Phiên khác đang sửa cùng checkout | đã thấy | chỉ stage đường dẫn mình đổi |
| Màn duyệt + Activity làm phình phạm vi (2 màn lớn trước tính năng chính) | chắc chắn | người dùng chọn; logic T1–T8 không chờ; Activity chỉ cần đủ cho lượt gom, index/upload/ingest nối sau |
| Màn duyệt Mac trùng việc với FS-22.06 U2 | vừa | T9a là màn duyệt duy nhất; U2 dùng lại nó làm bộ chọn folder |

## 7. Phản biện

Chạy `challenger` sau khi người dùng chốt Q1/Q2.

## 8. Agent ở giai đoạn Deploy

`data-migration` (T3) · `swift-concurrency` (T4–T7) · `ux-reviewer` (Move + xác nhận) · `design-parity` (T10–T11) ·
`copy-consistency` (chuỗi sheet/log) · `a11y-voiceover` (bảng log).

## 9. Cách chứng minh là xong

- Test: `CommonPhotosMatcherTests.*`, `CommonPhotosRunnerTests.*`, `CommonPhotosStoreTests.*` — sửa cột "Chứng minh bằng" của 08b mỗi task.
- Màn hình: sheet (trống, sau Scan, lỗi, xác nhận Move), cửa sổ tiến độ (đang chạy, xong, lỗi nối, banner Resume) — sáng + tối,
  `Tools/mac-shot`, so `Tools/design-board compare` với `MAC_CommonPhotos` / `MAC_CommonPhotosRun`.
- E2E: impacket SMB cục bộ (cùng share → Move bằng đổi chỗ; hai share → nhánh chép), ảnh phong cảnh không mặt người.
- Tài liệu: 08b cột chứng minh; FS-18.01 §Activity (protocol + hàng đầu tiên); FS-19.03 §4 (màn duyệt Mac đã có); dòng Tiến độ intent.
