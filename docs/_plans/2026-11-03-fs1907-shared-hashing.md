# Kế hoạch — FS-19.07 §12 Băm dùng chung (Mac băm hộ, máy khác chỉ đọc)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.07 §12`](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md) · AC: [`07b §4`](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md) (AC-144…158), spike S5–S8 (07b §1) |
| Intent | [2026-11-03-mac-hashes-for-on-server-check](../_intents/2026-11-03-mac-hashes-for-on-server-check.md) |
| Commit spec | `0206b87e` (intent `8790f174`) |
| Ngày | 2026-11-03 |
| Trạng thái | gần xong — H1–H8 xong; còn spike S5–S9 cần thiết bị (loop: [FS1907_HASH_LOOP.md](FS1907_HASH_LOOP.md)) |

## 1. Hiểu đúng chưa

Khi *Share Index Across Devices* bật, helper Mac băm SHA-256 **mọi** file gốc trong Photos và **mọi** ảnh, video trên
nguồn server. Không chỉ ứng viên cùng cỡ như hôm nay. Kết quả đi hai đường:

- **(A)** sổ `.shotdex/hash-index/` ở gốc mỗi nguồn trên NAS, cùng định dạng sổ Backup;
- **(C)** hai loại record mới trong zone CloudKit `SharedIndex`.

iPhone, iPad và Duo lấy SHA dùng chung trước, chỉ khi khoá còn khớp, rồi tự băm phần còn thiếu và đẩy lên. Mỗi lượt,
mỗi máy gửi, máy nhận tự băm lại 10 file ngẫu nhiên. Lệch thì bỏ mọi SHA máy đó gửi trước lúc lệch. Xoá vẫn hỏi lại
server như §9.

## 2. Đối chiếu AC ↔ code

Bằng chứng do agent khảo sát đọc từ checkout này. Mọi AC là **❌ chưa có**: phần chung chỉ có đường tự băm của từng
máy.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-144 Mac băm mọi mục Photos | ❌ | chỉ ứng viên cùng cỡ: `CopyFileStore.photosCandidates` `ShotDex/Data/Database/CopyFileStore.swift:160-173` (EXISTS :167-169); tải tạm + xoá `PhotosFileHashPass.swift:50-62` đã đúng | cờ "băm hết" cho Mac |
| AC-145 Mac băm mọi file NAS + ghi sổ | ❌ | ứng viên: `CopyFileStore.serverCandidates` :265-284 (EXISTS :273-277); chưa có sổ ngoài Backup | cờ "băm hết" + ghi sổ |
| AC-146 iPhone đọc sổ, 0 tải | ❌ | Backup đọc sổ của nó: `BackupRunner.readSharedIndex` `ShotDex/Domain/Backup/BackupRunner.swift:461-496`; kiểm FS-19.07 không đọc sổ nào, chỉ seed từ Backup theo đường dẫn + cỡ `ServerFileHashPass.swift:28-34` | đọc sổ sau khi liệt kê |
| AC-147 dòng lệch ngày sửa bị bỏ | ❌ | `BackupContentIndex.merged` có luật ngày sửa :95-107 (gắn `BackupDestinationFile`) | luật khớp đường dẫn + cỡ + ngày sửa |
| AC-148 `.shotdex/` không thành ảnh | ⚠️ một phần ✅ | liệt kê bỏ tên `.`: `ServerTreeListing.swift:14`; FS-19.08 dùng cùng listing | test khoá lại + kiểm không ghi ngoài `.shotdex/` |
| AC-149 iPhone dùng SHA Photos từ Mac | ❌ | `IndexShareService` chỉ có `PhotoExif`/`PlaceCell` `ShotDex/Data/Sources/IndexShareService.swift:240-259`; ánh xạ cloud id có sẵn :119-126; **không có seam test** (không fake `SharedIndexSource`) | record mới + protocol để giả kênh |
| AC-150 sửa sau khi Mac băm → tự băm | ❌ | `saveListing` đặt lại hash khi stamp đổi `CopyFileStore.swift:112-117` | so ngày sửa khi nhận |
| AC-151 danh tính server | ❌ | `ServerIdentity.sameFiles` `ShotDex/Domain/ServerUpload/ServerIdentity.swift:9-17` | khoá `ServerFileHash` theo danh tính này |
| AC-152 kiểm 10 file ngẫu nhiên | ❌ | — | Domain chọn mẫu + Data băm lại |
| AC-153 lệch → bỏ SHA của máy đó | ❌ | `copy_files` không có cột máy gửi (`AppDatabase+OnServer.swift:20-39`); `origin` chỉ `backup`/`hashed` (`CopyFileStore.swift:41-46`) | migration v48: `sharedFrom` + bảng máy bị nghi |
| AC-154 xoá vẫn hỏi server | ✅ code đạt | `PhotoDeletionGate` khớp theo `sha256` không xét origin `PhotoDeletionGate.swift:205-206`, liệt kê lại và so cỡ + ngày sửa :146 | chỉ viết test khoá lại với SHA `shared` |
| AC-155 tắt chia sẻ / không iCloud | ⚠️ một phần ✅ | `IndexShareService.database(evenWhenOff:)` chặn khi tắt hay thiếu entitlement :63-74; `sharesIndex` :39-41 | nối các đường mới qua cùng cổng + test |
| AC-156 hai chiều | ❌ | outbox chung `cloud_outbox` `AppDatabase+SharedIndex.swift:30-35`, `push` :214-238 | đẩy SHA `hashed` lên outbox |
| AC-157 nhả khoá cho Backup, làm tiếp | ✅ phần lớn | `LockedRemoteFileClient` `ConnectionLock.swift:81`, priority `.normal` `OnServerCheck.swift:239`; vòng lặp dừng khi không còn việc :184 | test khoá lại với chế độ băm hết |
| AC-158 hai máy ghi sổ cùng lúc | ❌ (logic có sẵn ở Backup) | đoạn theo máy: `BackupContentIndex.segmentName/nextNumber` :30-48; mã máy `BackupDeviceIdentity.current()` `ShotDex/Data/Sources/FileServer/BackupDeviceIdentity.swift:12-21` | dùng lại |

### 2a. Tái dùng

- **Sổ NAS:**
  - `BackupContentIndex.segmentName/parseSegment/nextNumber/encode/decode`: thuần, dùng nguyên.
  - Luồng ghi `VerifiedRemoteWrite` (part, đọc lại, đổi tên) như `BackupRunner.publishSharedIndex` :497-524.
  - Mã máy `BackupDeviceIdentity`.
- **CloudKit:** `IndexShareService` (zone, outbox, `pull`/`push` theo lô, `cloudIdentifiers(for:)`) và `SharedIndexStore`
  (outbox). Không tạo kênh thứ hai.
- **Băm:**
  - `PhotosFileHashPass` (tải tạm một file một lúc, cổng chỗ trống).
  - `ServerFileHashPass` (`client.sha256` theo luồng).
  - `CopyFileStore.saveHash`.
- **Cổng xoá:** `PhotoDeletionGate`, không đổi.

### 2b. Claude tự quyết (kỹ thuật)

- **"Băm hết" là một cờ**, không phải pass mới: `CopyFileStore.photosCandidates/serverCandidates(…, everything:)` bỏ
  điều kiện EXISTS cùng cỡ. `OnServerCheck.Environment` nhận cờ từ `sharesIndex`, chỉ trên Mac. Vòng lặp và cổng giữ
  nguyên.
- **Migration v48-sharedHashes:**
  - `copy_files.sharedFrom TEXT NULL`: mã máy gửi.
  - Bảng `hash_index_segments` (sourceId, tên đoạn, cỡ đã đọc), như `backup_index_segments`.
  - Bảng `distrusted_hash_devices` (mã máy, lúc lệch).
  - Origin thêm `shared` (CloudKit) và `ledger` (sổ NAS). Cột `origin` là chữ tự do, không cần đổi.
- **Seam test cho CloudKit:** protocol Domain `SharedHashSource` (kéo SHA cho khoá đã biết, đẩy SHA của mình) với một
  bản giả trong test. `IndexShareService` là bản thật. Đây cũng là chỗ BD-03.05 đang thiếu fake.
- **Khoá `PhotoFileHash`:** cloud id + `fileKey` + ngày sửa ảnh + cỡ. Thêm cỡ để chống trường hợp S6 (bản sửa khác byte)
  mà không cần đợi spike.
- **Mẫu kiểm ngẫu nhiên:** Domain thuần `SharedHashAudit.sample(rows:k:seed:)`, test bằng seed cố định.

## 3. File đổi

| File | Đụng gì | Tầng |
|---|---|---|
| `ShotDex/Data/Database/AppDatabase+OnServer.swift` (+ đăng ký) | v48 | Data |
| `ShotDex/Data/Database/CopyFileStore.swift` | `everything:`, `origin` mới, `sharedFrom`, đọc/ghi theo máy, bỏ theo máy | Data |
| `ShotDex/Domain/OnServer/ServerHashIndex.swift` (mới) | đường dẫn sổ, luật khớp dòng ↔ listing (đường dẫn + cỡ + ngày sửa) | Domain |
| `ShotDex/Data/Sources/FileServer/ServerFileHashPass.swift` | đọc sổ sau liệt kê, ghi đoạn cuối lượt | Data |
| `ShotDex/Domain/OnServer/SharedHashSource.swift` (mới) | protocol kênh SHA dùng chung | Domain |
| `ShotDex/Data/Sources/IndexShareService.swift`, `SharedIndexStore.swift` | record `PhotoFileHash`, `ServerFileHash`; kéo/đẩy | Data |
| `ShotDex/Domain/OnServer/SharedHashAudit.swift` (mới) | chọn mẫu K = 10, quyết định bỏ theo máy | Domain |
| `ShotDex/Data/Sources/OnServerCheck.swift` | cờ băm hết (Mac), bước kéo SHA dùng chung + kiểm ngẫu nhiên trong lượt | Data |
| `ShotDex/Data/Database/OnServerProgressQueries.swift` + `OnServerProgressLine` | câu lệch §12.4 | Data/Features |
| `ShotDexMac/MacDependencies.swift`, `ShotDex/App/AppDependencies.swift` | nối kênh, cờ | App |
| boards `PH_/IP_/DI_/DC_SmartAlbum`, `MAC_SmartAlbum` | tweak dòng tiến độ lệch | Design |
| `ShotDexTests/SharedHashTests.swift` (mới), `PhotosHashTests`, `ServerSourceIndexTests`, `PhotoDeletionGateTests`, `OnServerScheduleTests`, `CommonPhotosSMBTests` | test | Test |

## 4. Thứ tự task (một task một commit)

| # | Task | AC | Test |
|---|---|---|---|
| H1 | v48 + `CopyFileStore` origin `shared`/`ledger`, `sharedFrom`, bỏ theo máy; test khoá AC-154 | nền; AC-154 | `SharedHashTests.storeKeepsSender`, `PhotoDeletionGateTests.sharedHashStillReverifies` |
| H2 | Mac băm hết: cờ `everything` trong hai câu ứng viên + `OnServerCheck` nhận cờ (chỉ Mac, theo `sharesIndex`) | AC-144, phần băm của AC-145, AC-157 | `PhotosHashTests.macHashesEveryItem`, `ServerSourceIndexTests.macHashesEveryFile`, `OnServerScheduleTests.yieldsToBackupAndResumes` |
| H3 | Sổ NAS: `ServerHashIndex` + đọc sau liệt kê + ghi đoạn cuối lượt | AC-145 (sổ), 146, 147, 148, 158 | `SharedHashTests.ledgerWrittenAtSourceRoot`, `readerSkipsDownloads`, `staleLineIgnored`, `ledgerNeverAPhoto`, `twoWritersTwoSegments` |
| H4 | e2e sổ trên SMB ảo (Mac ghi, "iPhone" đọc: 0 lần tải) | AC-146 (e2e) | `CommonPhotosSMBTests` → `OnServerSMBTests.ledgerSavesDownloads` (mới) |
| H5 | `SharedHashSource` + record CloudKit + `SharedIndexStore`; kéo/đẩy; khớp cloud id + ngày sửa + cỡ, danh tính server | AC-149, 150, 151, 155, 156 | `SharedHashTests.photoHashesFromMac`, `editedOnPhoneRehashes`, `serverIdentityMustMatch`, `offDoesNothing`, `twoWay` (kênh giả) |
| H6 | Kiểm ngẫu nhiên + bỏ theo máy + tin lại dòng mới | AC-152, 153 | `SharedHashTests.auditsTen`, `mismatchDropsOlderHashes`, `newerHashesTrustedAgain` |
| H7 | Câu lệch trong dòng tiến độ + 5 board (sáng/tối) + ảnh sim/Mac | AC-153 (UI) | `OnServerProgressTests.mismatchLine`; ảnh `PH_/IP_/DI_/DC_SmartAlbum`, `MAC_SmartAlbum` |
| H8 | `/verify`; ghi spike S5–S8 là việc cần thiết bị | tất cả | — |

## 5. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| CloudKit chưa từng chạy trên máy thật (BD-03.05 chỉ biên dịch); Mac ký thiếu iCloud | chắc chắn | test qua kênh giả; AC cần thiết bị ghi "một phần"; spike S5–S7 trước khi bật cho người dùng |
| Khoá Photos lệch giữa máy (S5) hoặc bản sửa khác byte (S6) | trung bình | khoá thêm cỡ file; lệch thì máy tự băm; kiểm ngẫu nhiên bắt phần còn lại |
| Mac băm cả NAS hàng giờ, đè Backup | trung bình | priority `.normal`, nhả khoá giữa file (AC-157); spike S8 |
| Sổ NAS bị sửa tay hay hỏng | thấp | dòng phải khớp đường dẫn + cỡ + ngày sửa; dòng hỏng thì bỏ; kiểm ngẫu nhiên; xoá vẫn hỏi server |
| Bỏ theo máy xoá nhầm SHA tự băm | thấp | chỉ bỏ dòng `origin in (shared, ledger)` có `sharedFrom` = máy đó |
| Migration v48 | thấp | thêm cột/bảng, không đổi dữ liệu; agent `data-migration` duyệt |
| Bộ nhớ khi kéo 270k record | trung bình | lô 400 như `push` hiện có; ghi theo lô |

Agent chạy sau khi làm: `data-migration` (H1), `swift-concurrency` (H2, H5, H6), `photokit-guard` (H2: Mac tải bản gốc
để băm), `perf-profiler` (H3/H5: đọc sổ 200k dòng, kéo record), `design-parity` (H7, bằng mắt trên Mac).

## 6. Cách chứng minh là xong

- Test: các test ở §4. e2e sổ trên SMB ảo `127.0.0.1:4450`.
- Ảnh:
  - dòng tiến độ có câu lệch trên iPhone, iPad, Duo trong và ngoài (sim);
  - cùng dòng đó trên Mac (`Tools/mac-shot`), sáng và tối.
- Tài liệu:
  - 07b cột "Chứng minh bằng" và dòng Tiến độ của intent;
  - BD-03.05 §2 thêm hai loại record;
  - `docs/design/*` (publish canvas từng thiết bị).
- Chưa chứng minh được trong repo (cần thiết bị): S5–S8, kênh CloudKit thật.
