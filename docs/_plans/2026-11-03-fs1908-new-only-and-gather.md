# Kế hoạch — FS-19.08 §6c Chạy lại chỉ ảnh mới · tự gom

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.08 §6c`](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC: [`08b`](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) (AC-159…173) |
| Intent | [2026-11-03-common-photos-new-only-and-sync](../_intents/2026-11-03-common-photos-new-only-and-sync.md) |
| Commit spec | `463a5021` (intent `43c24873`) |
| Ngày | 2026-11-03 |
| Trạng thái | đang làm — G1 xong (loop: [FS1908_GATHER_LOOP.md](FS1908_GATHER_LOOP.md)) |

## 1. Hiểu đúng chưa

Hai người có ảnh chung giữa `Tuấn/` và `Vợ/` trên NAS. Họ đã gom phần chung vào `Shared/` một lần. Muốn gom tiếp thì
hôm nay phải quét lại từ đầu, và băm lại mọi file cùng cỡ ở folder không phải nguồn. Sau việc này:

- Quét lại cùng **bộ** (connection + folder nguồn + folder chung) thì chỉ đọc byte của file mới hoặc đổi. Danh sách chỉ
  hiện ảnh chung mới, cộng ảnh đã gom mà bản ở Shared đã mất.
- Bộ bật **Keep gathering** thì helper Mac chạy lại kiểu đó mỗi 15 phút, chỉ khi cắm điện và mạng không tính tiền.
  - Copy: tự chép.
  - Move: chỉ báo "ready to move", người dùng bấm mới dời.
  - Lượt tự gom trong một ngày gộp thành một lượt Activity.
- Mục **Gathering** đầu cửa sổ Activity liệt kê các bộ đang tự gom.

## 2. Đối chiếu AC ↔ code

Đã đọc: `CommonPhotosScanModel.swift`, `CommonPhotosScanner.swift`, `CommonPhotosVerifier.swift`,
`CommonPhotosRunner.swift`, `CommonPhotosStore.swift`, `AppDatabase+CommonPhotos.swift`, `MacCommonPhotosSheet.swift`,
`MacCommonPhotosRuns.swift`, `MacActivityWindow.swift`, `LongRunningJob.swift`, `MacAgent.swift`, `MacAgentLink.swift`,
`OnServerSchedule.swift`.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-159 | ❌ một phần | `CommonPhotosScanModel.swift:305-337` `knownHashes` chỉ đọc `copy_files` của **nguồn**. `CommonPhotosVerifier.swift:73` chỉ dùng SHA đã có cho folder đầu (`file.folder == 0`). Không chỗ nào lưu SHA băm lúc quét. Khoá ngày chụp không được nhớ (`Scanner.swift:36`, model không truyền `known`, `:262`) | G1: bảng SHA đã đọc; verifier ghi vào; mọi folder dùng lại SHA nếu đường dẫn + cỡ + ngày sửa trùng |
| AC-160 | ❌ | quét không biết lượt trước (`ScanModel:62-70`, chỉ giữ trong bộ nhớ); lượt không có khoá bộ (`common_photo_runs`, v46) | G2: cột `setKey`; Domain `CommonPhotosIncremental` lọc nhóm có bản mới/đổi so với mục của lượt xong gần nhất (`common_photo_items.sources` có path, size, modifiedAt) |
| AC-161 | ❌ | như AC-160; bước cỡ (`Matcher.swift:41`) đã loại ảnh chỉ ở một folder | G2: test khoá lại (X chỉ ở A không vào; lần sau B có thì vào) |
| AC-162 | ❌ | — | G2: file cùng đường dẫn mà cỡ hay ngày sửa khác là "đổi", băm lại; đặt tên ` (2)` theo `Runner.swift:309` có sẵn |
| AC-163 | ❌ | folder chung chỉ được liệt kê lúc **chạy** (`Runner.swift:196-197`), không lúc quét | G3: quét liệt kê thêm folder chung; ảnh đã gom mà đích mất thì vào lại danh sách |
| AC-164 | ❌ | sheet không biết lượt trước (`MacCommonPhotosSheet.swift`); Activity chỉ có Show Log / Remove (`MacActivityWindow.swift:255-268`, `LongRunningJob.swift:145-160`) | G4: Run Again (hàng Activity + cửa sổ log); câu "Last gathered…"; nút Scan Everything; board trước |
| AC-165 | ❌ | helper chỉ có timer 30 phút cho On Server (`MacAgent.swift:23`, `:71-73`); không có bộ tự gom | G5 (bảng bộ + lượt tự gom) + G6 (Copy tự chạy, gộp ngày) + G9 (helper gọi mỗi 15 phút) |
| AC-166 | ❌ | — | G5: lượt không có ảnh thì không tạo lượt, chỉ cập nhật `checkedAt` |
| AC-167 | ❌ một phần | điều kiện có ở `OnServerSchedule.wait` (`OnServerSchedule.swift:33-40`) và `NetworkMonitor` / `PowerMonitor`, nhưng gắn theo luật job Backup; Common Photos không dùng | G5: luật riêng cho tự gom (bắt buộc cắm điện + mạng không tính tiền), dùng lại `OnServerSchedule.Wait` và chữ có sẵn |
| AC-168 | ✅ phần khoá | runner dùng client có khoá kết nối (`MacDependencies.swift:139`, `LockedRemoteFileClient`); Backup ưu tiên (`ConnectionLockTests.backupFirst`) | G5: viết test khoá lại cho lượt tự gom |
| AC-169 | ❌ | không có thông báo nào trên Mac (không có `UNUserNotificationCenter` trong ShotDexMac); lượt không có trạng thái "sẵn sàng dời" | G7: trạng thái `ready`, thông báo + xin quyền khi bật tự gom cho bộ Move, hàng Activity "Ready to move N", nút Move N…; board trước |
| AC-170 | ✅ phần Resume | `CommonPhotosRunner.run` bỏ qua mục đã xong (`Runner.swift:177-224`); `canResume` (`CommonPhotosRun.swift:53`) | G8: lượt tự gom dở được lượt sau chạy tiếp, không chép lại ảnh 1; ghi "isn't reachable" |
| AC-171 | ❌ | — | G5: folder nguồn/chung không còn thì bộ dừng, ghi lý do, không thử lại |
| AC-172 | ❌ | — | G5 (dữ liệu) + G9 (Run Now · Stop Gathering ở Activity) |
| AC-173 | ❌ | mỗi lượt một hàng, một CSV tên theo giờ phút (`CommonPhotosLog.swift:101-107`); giữ 20 lượt (`CommonPhotosStore.swift:50`) | G6: lượt tự gom theo ngày (`auto`, `day`); CSV `… auto.csv` ghi lại sau mỗi lượt; ngày đóng mới tính vào 20 |

### 2a. Tái dùng

- `CommonPhotosVerifier` (mẫu 3 đoạn, SHA cả file, tham số `knownHashes`): thêm nguồn SHA đã nhớ; bỏ giới hạn
  `folder == 0` **chỉ cho lượt quét Copy** (`trustsCache`). Move giữ luật cũ, vì Move xoá các bản ngoài folder đầu
  chỉ sau khi hỏi lại cỡ + ngày sửa, không SHA (sửa khi làm G1).
- `CommonPhotosScanner.captureKeys(known:)`: tham số đã có, chỉ cần truyền khoá đã nhớ.
- `CommonPhotosRunner` (copy/move/skip/resume/CSV/undo): lượt tự gom là lượt thường, có thêm cột. Không viết runner thứ hai.
- `OnServerSchedule.Wait` (`.charging`, `.wifi`, `.unreachable`) và chữ của nó (`OnServerProgressLine.text(for:)`).
- `NetworkMonitor`, `PowerMonitor` (như `OnServerCheck.live`).
- `ConnectionLock` + `LockedRemoteFileClient`: Backup đi trước.
- `ServerTreeListing.list` để liệt kê folder chung.
- Activity: `LongRunningJob` / `MacActivityRow` để thêm hàng; Gathering là một nhóm hàng mới, không phải cửa sổ mới.

### 2b. Claude tự quyết (kỹ thuật)

- **Khoá bộ** `setKey` = `connectionId|<folder nguồn đã chuẩn hoá, sắp xếp>|<folder chung>`, dùng
  `ServerUploadPath.normalizedFolder`.
- **"Mới hay đổi"** so với **mọi mục của mọi lượt xong của bộ**, không chỉ lượt gần nhất. Lượt gần nhất có thể chỉ có 3
  ảnh, còn 300 ảnh cũ nằm ở lượt đầu. Cách làm: hợp các `sources` (path, size, modifiedAt) của mục Copied/Moved/Skipped
  trong các lượt của bộ còn giữ. Lượt đã bị đẩy ra khỏi 20 thì ảnh của nó coi như mới, nhưng SHA vẫn nhớ nên không đọc
  lại byte, và Copy gặp bản ở đích thì Skipped. Đúng, chỉ chậm hơn.
- **Lượt tự gom và app cùng chạy**: claim hôm nay chỉ trong một process (`Runner.swift:155-175`). Thêm **claim trong
  DB**: cột `claimedBy` (pid + boot) và `claimedAt` trên `common_photo_runs`, hết hạn sau 2 phút không cập nhật. App và
  helper đều xin claim trước khi chạy một lượt hay một bộ.
- **Helper sống**: `hasWork` (`MacAgent.swift:107`) thêm "có bộ tự gom bật". Timer 15 phút riêng, không gộp với
  relist 30 phút của On Server.
- **Thông báo Mac**: `UNUserNotificationCenter`. Xin quyền lúc người dùng bật Keep gathering cho một bộ **Move**, không xin
  lúc mở app. Bị từ chối thì vẫn có hàng "Ready to move" trong Activity.
- **Gộp ngày**: `day` = `yyyy-MM-dd` giờ máy lúc lượt tự gom bắt đầu. Lượt đang dở qua nửa đêm thì vẫn ghi vào ngày nó
  bắt đầu.
- **Bảng SHA đã đọc** giữ theo connection + đường dẫn chính xác (khác hoa thường là khác file, như `knownHashes` hôm nay).
  Liệt kê thấy file không còn thì xoá dòng. Không có giới hạn số dòng: một dòng ~150 B, 270k dòng ~40 MB thì chấp nhận
  được. Clear Local Metadata Index không xoá bảng này, vì nó là dữ liệu dẫn xuất của server chứ không phải index.

## 3. File đổi

| File | Tầng | Việc |
|---|---|---|
| `ShotDex/Data/Database/AppDatabase+CommonPhotos.swift` | Data | v52 `common_photo_scan_hashes`; cột `setKey`, `auto`, `day`, `claimedBy`, `claimedAt` trên `common_photo_runs`; v53 `common_photo_watches` |
| `ShotDex/Data/Database/CommonPhotosStore.swift` | Data | đọc/ghi SHA đã đọc; lượt xong của một bộ; bộ tự gom; claim DB; giữ 20 với ngày đóng |
| `ShotDex/Core/Models/CommonPhotosRun.swift` | Core | `setKey`, `isAuto`, `day`, trạng thái `ready` |
| `ShotDex/Domain/CommonPhotos/CommonPhotosIncremental.swift` (mới) | Domain | lọc nhóm mới/đổi/đích mất — thuần, test được |
| `ShotDex/Domain/CommonPhotos/CommonPhotosSetKey.swift` (mới) | Domain | khoá bộ |
| `ShotDex/Domain/CommonPhotos/CommonPhotosVerifier.swift` | Domain | báo SHA vừa băm cho người gọi; bỏ `folder == 0` |
| `ShotDex/Data/Sources/FileServer/CommonPhotos/CommonPhotosScanModel.swift` | Data | SHA + khoá ngày chụp đã nhớ; liệt kê folder chung; chế độ chỉ ảnh mới / Scan Everything |
| `ShotDex/Data/Sources/FileServer/CommonPhotos/CommonPhotosGatherPass.swift` (mới) | Data | một lượt tự gom của một bộ: điều kiện → quét chỉ ảnh mới → Copy chạy / Move `ready` → dừng khi mất folder |
| `ShotDex/Domain/CommonPhotos/CommonPhotosRunner.swift` | Domain | lượt theo ngày (thêm mục vào lượt đang mở của ngày), CSV `auto` |
| `ShotDex/Domain/CommonPhotos/CommonPhotosLog.swift` | Domain | tên CSV ngày `… auto.csv` |
| `ShotDex/Domain/Activity/LongRunningJob.swift` | Domain | Kind/hành động: Run Again, Move N…, Run Now, Stop Gathering; nhóm Gathering |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift` | Features | câu "Last gathered…", ô Keep gathering, Scan Everything |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosRunWindow.swift` | Features | Run Again; trạng thái `ready` + Move N… |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosRuns.swift` | Features | Run Again mở sheet đúng bộ; claim DB |
| `ShotDexMac/Activity/MacActivityWindow.swift` | Features | mục Gathering đầu cửa sổ |
| `ShotDexMac/Agent/MacAgent.swift`, `MacAgentLink.swift` | Mac | timer 15 phút; `hasWork` có bộ tự gom |
| `ShotDexMac/Servers/CommonPhotos/MacGatherNotifier.swift` (mới) | Mac | thông báo "ready to move", xin quyền |
| `docs/design/mac/project/MAC_CommonPhotos.dc.html`, `MAC_CommonPhotosRun.dc.html`, `MAC_Activity.dc.html` | design | tweak `again`, trạng thái `readyToMove`, mục Gathering |
| Test: `CommonPhotosIncrementalTests` (mới), `CommonPhotosGatherTests` (mới), `CommonPhotosMatcherTests`, `CommonPhotosRunnerTests`, `CommonPhotosStoreTests`, `CommonPhotosJobTests`, `CommonPhotosSMBTests` | test | xem §6 |

File mới dưới `ShotDexMac/` cần chạy `Tools/mac-membership`.

## 4. Thứ tự task (một task một commit)

| Task | Làm | AC | Test |
|---|---|---|---|
| G1 | v52 bảng SHA đã đọc; verifier ghi; mọi folder dùng lại; khoá ngày chụp đã nhớ | AC-159 | `CommonPhotosIncrementalTests.rescanReadsNothing` (client giả: 0 `sha256`/range/download) |
| G2 | `setKey`; Domain lọc ảnh mới/đổi; quét chỉ ảnh mới khi bộ đã có lượt xong | AC-160, 161, 162 | `onlyNewPhotos`, `newInOneFolderWaits`, `changedFileIsNew` |
| G3 | quét liệt kê folder chung; đích mất → vào lại | AC-163 | `goneFromSharedComesBack`, `presentInSharedNotRead` |
| G4 | **board `MAC_CommonPhotos` tweak `again`** → sheet: câu Last gathered, Scan Everything; Run Again ở Activity + log | AC-164 | `CommonPhotosJobTests.runAgainAction`; ảnh Mac sáng/tối |
| G5 | v53 bộ tự gom; `CommonPhotosGatherPass` (điều kiện, khoá, không ảnh → không lượt, mất folder → dừng); Stop Gathering ở dữ liệu | AC-166, 167, 168, 171, 172 | `CommonPhotosGatherTests.*` |
| G6 | lượt tự gom Copy chạy luôn, gộp theo ngày, CSV ngày, giữ 20 tính ngày đóng | AC-165, 173 | `copiesWithoutTheApp`, `oneRunPerDay` |
| G7 | **board `MAC_CommonPhotosRun` trạng thái `readyToMove`** → Move: `ready` + thông báo + Move N… | AC-169 | `moveWaitsForTheUser`; ảnh Mac |
| G8 | lượt tự gom dở chạy tiếp ở lượt sau; "isn't reachable" | AC-170 | `resumesNextPass`; e2e SMB ảo: ngắt server giữa lượt |
| G9 | **board `MAC_Activity` mục Gathering** → helper timer 15 phút, `hasWork`, claim DB app↔helper; Run Now · Stop Gathering | AC-165 (thật), 172 (UI) | `claimAcrossProcesses` (hai store trên một DB file); chạy helper thật với SMB ảo, `log show` |
| G10 | `/verify`: e2e SMB ảo cả vòng (Copy tự gom 2 lượt, Move ready), ảnh, cập nhật 08b/intent | tất cả | — |

## 5. Rủi ro

| Rủi ro | Cách giữ |
|---|---|
| App và helper cùng chạy một bộ, hai bản Copy chép trùng hoặc Move xoá hai lần | claim trong DB có hạn (2b); test hai store trên một file DB; Move vẫn hỏi lại cỡ + ngày sửa trước khi xoá |
| SHA đã nhớ sai khi file bị ghi đè mà giữ nguyên cỡ + ngày sửa | đã ghi ở §10 spec; Copy đọc lại SHA ở đích, Move kiểm đích bằng SHA trước khi xoá nguồn → không mất ảnh |
| Liệt kê 2 × 50k file + folder chung mỗi 15 phút làm NAS bận | đo ở G10 trên SMB ảo với 20k file; quá 2 phút một lượt thì giãn chu kỳ (spec §10) |
| Helper không thoát được nữa, ăn pin | chỉ chạy khi cắm điện; `hasWork` chỉ thêm khi có bộ đang bật |
| Undo một lượt ngày đang được tự gom thêm mục | lượt ngày đang có undo thì tự gom bỏ qua tới khi undo xong (claim DB) |
| Quyền thông báo bị từ chối | hàng Activity "Ready to move" vẫn có; không bao giờ tự Move |
| Migration v52/v53 trên DB có dữ liệu | chỉ thêm bảng/cột; app chưa phát hành (không cần đường lùi) |
| Duo/iPhone/iPad | không đụng (chỉ Mac) |

Agent ở giai đoạn Deploy: `data-migration` (G1, G5, G6), `swift-concurrency` (G5, G9: helper, timer, claim),
`ux-reviewer` (G4, G7: Run Again, ready to move), `hig-components` (thông báo, Activity), `perf-profiler` (G1/G2:
lọc trên 50k), `memory-leak` (timer trong helper).

## 6. Cách chứng minh là xong

- Mỗi AC một test có tên trong 08b. Client giả `InMemoryRemoteFileClient` đếm `sha256Paths`, `rangeReadPaths`,
  `downloadCount` để chứng minh "không đọc byte".
- e2e trên SMB ảo `127.0.0.1:4450` (ảnh phong cảnh): lượt đầu Copy, thêm 3 ảnh, lượt tự gom chép 3; xoá 1 ở Shared,
  lượt sau chép lại; bộ Move báo ready.
- Ảnh Mac sáng + tối (`-ShotDexAppearance`, demo library) của: sheet `again`, cửa sổ log `readyToMove`, Activity
  Gathering; so với board.
- Cập nhật 08b (cột Chứng minh bằng), dòng Tiến độ của intent, `docs/design` (3 board, publish canvas Mac).
