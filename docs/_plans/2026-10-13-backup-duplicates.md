# Kế hoạch — Backup: không chép trùng giữa các máy (FS-22.05, AC-31…AC-39)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-22.05`](../02-functional-spec/FS-22-backup/05-duplicates-across-devices.md), AC-31…AC-39 |
| Intent | [`2026-10-12-backup`](../_intents/2026-10-12-backup.md) |
| Ngày | 2026-10-13 |
| Trạng thái | đã duyệt (2026-10-13, người dùng) |

## Context

Người dùng và vợ cùng backup iPhone vào một folder NAS, có nhiều ảnh chung, "không muốn trùng". Spec FS-22.05 (đã duyệt,
commit d279467c): so bằng SHA-256 với mọi file trong cây folder đích của job; sổ chung trên NAS `.shotdex/backup-index/`
(mỗi máy ghi đoạn riêng); liệt kê cây đích lúc chạy lần đầu + mỗi ngày; chỉ băm file NAS khi cùng cỡ với file sắp chép.

Quyết định mới (người dùng 2026-10-13): chữ trạng thái dùng **tên connection** — `Checking NAS Home · 12,408 files`,
`Already on NAS Home · 312`. Sửa 05 §5, AC-34, AC-39 trong task 1.

## Đối chiếu AC ↔ code

Tất cả ❌ — không có đường code dedup nào. Điểm nối:

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-31, AC-32 | ❌ | `BackupRunner.copy` `BackupRunner.swift:275-356`; SHA cục bộ có sẵn ở `:309` trước khi đẩy | tra SHA trong bảng nội dung đích trước bước Keep Both `:305` |
| AC-33 | ❌ | `RemoteFileClient.sha256(of:)` `RemoteFileClient.swift:30` có ở mọi client | băm file NAS cùng cỡ, ghi SHA một lần |
| AC-34 | ❌ | không có walk đệ quy trên protocol; mẫu `ServerSourceIndexer.list` `:139-157` (bỏ dot, chỉ ảnh — không dùng thẳng) | walker mới + trạng thái Checking |
| AC-35 | ❌ | `fileSize(at:)` `RemoteFileClient.swift:16` | kiểm còn + đúng cỡ, sai thì xoá dòng |
| AC-36 | ❌ | part được nhận tại chỗ trong `copy` `:315-334`, không có lượt riêng | tra trùng trước nhánh nhận part; trùng → `discardPart` |
| AC-37 | ❌ | — | dòng đích ghi ngay sau khi đẩy |
| AC-38 | ❌ | ledger không có index sha (`AppDatabase+Backup.swift:58`) | bảng mới có index (jobId, sha256) |
| AC-39 | ❌ | `Outcome` chỉ `uploaded/found/failed` `BackupJob.swift:94-101`; 5 truy vấn `IN ('uploaded','found')` `BackupStore.swift:81-140`; mẫu màn `BackupFilesScreen` `BackupRunningScreen.swift:235-254` | `duplicate` + hàng + màn danh sách |

Không có dòng ⚠️ (code chưa có gì để lệch).

## Tái dùng

- `FileChecksum.sha256(of:)` `RemoteFileClient.swift:142` (băm cục bộ, đã kiểm cancel từng khối 1 MB).
- `VerifiedRemoteWrite` (`uploadPart` → `moveIntoPlace`) để ghi đoạn sổ chung nguyên tử (part rồi đổi tên; máy khác bỏ qua `.shotdex-part`).
- `readRange` / `download` để đọc đoạn sổ (tải về file tạm, đọc từng dòng).
- `KeychainPasswordStore` pattern `ServerPasswordStore.swift:15` cho mã máy (service riêng `com.hoangtuan.shotdex.backup-device`).
- `BackupStore.record(_:upload:)` `:152-178` — mở rộng để `duplicate` cũng thêm dòng `server_uploads` (index `(serverId, remotePath)` không unique, nhiều ảnh trỏ một file được).
- Fakes: `BackupFixture`, `InMemoryRemoteFileClient` — thêm `sha256Paths: [String]` để đếm "đọc đúng một lần"; hai fixture dùng chung một client để giả hai máy.

## File đổi

| File | Tầng | Việc |
|---|---|---|
| `Data/Database/AppDatabase+Backup.swift` | Data | migration `v35-backupDestinationIndex`: bảng `backup_destination_files` (jobId → cascade, path, size, modified, sha256?, origin `listed`/`index`/`own`, needsPublish, seenAt; unique(jobId,path); index (jobId,sha256), (jobId,size)); bảng `backup_index_segments` (jobId, name, size, readAt; unique(jobId,name)); `backup_ledger.localName`; `backup_job_state.lastTreeScanAt` |
| `Core/Models/BackupJob.swift` | Model | `Outcome.duplicate`, `localName`, `lastTreeScanAt` |
| `Data/Database/BackupStore.swift` | Data | 5 truy vấn tính cả `duplicate`; `duplicateEntries/Count`; CRUD bảng đích (lookup sha, cùng cỡ chưa băm, upsert listing, xoá dòng không thấy, rows needsPublish); đổi folder đích → xoá bảng đích + `lastTreeScanAt` |
| `Domain/Backup/BackupContentIndex.swift` (mới) | Domain thuần | dòng JSONL encode/decode khoan dung; luật gộp listing ↔ dòng sổ (cỡ khớp; mtime khác thì bỏ SHA cũ; mtime nil = chưa biết); tên đoạn `<device>-<n>.jsonl`, số kế |
| `Domain/Backup/BackupDestinationScan.swift` (mới) | Domain | walk đệ quy qua `entries(in:)`, bỏ `.shotdex/` và `*.shotdex-part`, báo đếm |
| `Domain/Backup/BackupRunner.swift` | Domain | `pass()`: sau `connect` — quét cây nếu chưa quét/ >24 h, đọc đoạn sổ chưa đọc; `copy()`: băm → tra trùng → (băm file NAS cùng cỡ) → Keep Both/đẩy; cuối lượt ghi đoạn sổ từ dòng `needsPublish`; `BackupProgress.Phase.checkingDestination` + `listedCount`, `duplicates` |
| `Data/Sources/FileServer/BackupDeviceIdentity.swift` (mới) | Data | UUID trong Keychain, tạo lần đầu |
| `App/BackupCoordinator+Live.swift` | App | truyền device id vào runner |
| `Domain/Backup/BackupStatusText.swift` | Domain | trạng thái `Checking <connection> · N files` / `before the first copy` · `daily check` |
| `Features/Backup/BackupRunningScreen.swift` | Features | hàng `Already on <connection> · N` dưới Backed Up (khi N>0) → `BackupDuplicatesScreen` (tên ở máy → đường dẫn ở đích); sửa comment 5/5 → 6/6 |
| `Features/Backup/BackupFormSheet.swift:138` | Features | footer Destination: "Photos already in this folder — from another iPhone or copied earlier — are skipped." |
| Board: `PH_Backup`, `PH_BackupRunning`, `PH_BackupNew` + `IP_*`, `DI_*`, `DC_*` tương ứng | Design | sửa tại chỗ: một thẻ ở 1/6 sang trạng thái Checking; hàng Already on ở 6/6; footer ở 2/6. Đọc lại từ canvas trước khi sửa, publish, commit |
| `docs/.../FS-22-backup/03-data.md`, `05-…md`, `02-…md`, `04-acceptance-criteria.md` | Docs | cột mới, chữ theo tên connection, số board 1/6·6/6 trong bảng §5 của 02, cột "Chứng minh bằng" |
| `ShotDexTests/ServerUploadFakes.swift`, `BackupFakes.swift`, `BackupDuplicateTests*.swift` (mới), `BackupContentIndexTests.swift` (mới), `BackupStatusTextTests`, `BackupStoreTests` | Test | |

Không đổi protocol `RemoteFileClient` (walk dựng trên `entries`, đọc đoạn bằng `download`, tồn tại bằng `fileSize`).

## Luật chạy (Claude tự quyết, ghi vào 05)

- Quét cây + đọc sổ chung chỉ khi lượt có việc chép (sau `connect`, trước vòng chép). Không có gì mới thì không nối NAS chỉ để quét — "mỗi ngày một lần khi có lượt chạy" như 05 §3.
- File mình đẩy lên: ghi dòng đích ngay (sha, mtime nil, needsPublish) — AC-37 và AC-33 đều nhờ đây.
- Mtime nil trên dòng = chưa biết; lần quét kế điền mtime, giữ SHA nếu cỡ khớp.
- Đoạn sổ: ghi cuối lượt (kể cả Pause, nếu còn mạng); lỗi ghi → `needsPublish` giữ nguyên, lượt sau ghi. Không bao giờ sửa đoạn đã có.
- Tra trùng: ứng viên SHA khớp ở đường dẫn ≠ đích dự kiến → `fileSize` khớp → `duplicate`. Không khớp → xoá dòng, thử ứng viên khác → hết thì băm các file cùng cỡ chưa có SHA → vẫn không → đẩy.
- Part của extension mà nội dung đã có chỗ khác → `discardPart`, ghi `duplicate`.

## Thứ tự task — một AC một commit

| # | AC | Nội dung | Test |
|---|---|---|---|
| 1 | AC-37 | migration v35, `Outcome.duplicate`, store, tra bảng đích trong `copy`, `localName`; sửa 05/AC chữ tên connection | `BackupDuplicateTests.identicalItemsInOneLibraryCopyOnce`, `BackupStoreTests.duplicateCountsAsHandled` |
| 2 | AC-35 | kiểm tồn tại, xoá dòng cũ, đẩy lại | `.deletedOnNASIsSentAgain` |
| 3 | AC-34 | walker + quét lần đầu/hằng ngày + trạng thái Checking + chỉ băm file cùng cỡ | `.existingFilesCheckedBySizeFirst`, `BackupStatusTextTests.checkingDestination`, `.scanRepeatsAfterADay` |
| 4 | AC-33 | băm file NAS cùng cỡ đúng một lần, SHA vào sổ | `.sameSizeDifferentContentIsHashedOnce` |
| 5 | AC-31, AC-32 | device id, ghi/đọc đoạn sổ chung, `BackupContentIndex` | `.secondPhoneSkipsSameBytesUnderAnotherName`, `.matchesInAnotherFolderLayout`, `BackupContentIndexTests.*` |
| 6 | AC-38 | 55.000 dòng: đọc ≤ 5 s, tra ≤ 10 ms, 0 lần băm lại | `.fiftyFiveThousandLinesReadFast` |
| 7 | AC-36 | part trùng bị xoá | `BackupUploadExtensionTests.duplicatePartIsRemoved` |
| 8 | AC-39 | hàng Already on + màn danh sách + footer 2/6 + boards 4 thiết bị | `BackupStoreTests.duplicateEntries`, ui-drive `backup-duplicates.json`, design-parity PH/IP/DI/DC |

Sau mỗi commit: build, test liên quan, dòng Tiến độ intent. Cuối: full suite một lần, `/verify FS-22`.

## Rủi ro

- **Folder Files/iCloud làm đích:** băm file NAS = tải từ iCloud. Chấp nhận (chỉ khi cùng cỡ).
- **WebDAV `sha256` tải cả file về máy tạm** — dung lượng tạm 1 file, đúng luật "không quá 1 file".
- **SMB root share** trả share không cỡ: walker không bao giờ chạy từ gốc (folder đích luôn trong share).
- **Hai máy cùng lúc** chép cùng ảnh → có thể 2 bản (đã ghi ở 05 §6).
- **Bảng đích lớn** (cây 100k file): upsert trong một transaction, có index; quét ~ số folder lệnh PROPFIND/list.
- Concurrency: tất cả trong actor runner; GRDB đồng bộ như hiện tại.
- Agent chạy sau: `data-migration`, `swift-concurrency`, `design-parity`, `copy-consistency`.

## Chứng minh xong

- Test trên theo bảng; `-only-testing:ShotDexTests/BackupDuplicateTests` + Backup* xanh; full suite một lần cuối.
- Sim "Backup iPhone 17" (962EF073…): WebDAV local seed 2 job cùng folder (2 device id giả bằng 2 lượt với Keychain khác) → chụp 1/6 Checking, 6/6 Already on + danh sách, 2/6 footer. iPad + Duo qua design-parity.
- Cột "Chứng minh bằng" AC-31…39 điền tên test thật.
