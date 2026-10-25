# Kế hoạch — FS-19.07 Ảnh Photos đã có trên server chưa

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.07`](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md) · AC + spike: [`07b`](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md) |
| Intent | [2026-10-24-smart-album-on-nas](../_intents/2026-10-24-smart-album-on-nas.md) |
| Ngày | 2026-10-25 |
| Trạng thái | đang làm — duyệt 2026-10-25; T0 (`b36d7a09`), T1 (`f95b0163`), T2 (`12c4bbfc`), T3 (`0c241bea`), T4 (`721e9947`), T5 (`470ec043`), T6 xong |

## 1. Hiểu đúng chưa

Mỗi mục Photos phải biết chắc có bản **giống hệt từng byte** (SHA-256 cả file) trên một folder của nguồn server hay chưa,
cho **từng file gốc** — ảnh, RAW, video Live Photo, video, và bản sửa nếu có. SHA của file Backup đã chép dùng lại; phần
còn lại chỉ băm khi hai bên **trùng cỡ**, nên ít tải iCloud, ít đọc NAS. Kiểm không dựa vào gộp ảnh FS-19. Đợt 1 cho người
dùng xoá được an toàn (chạy khi mở app, smart album có Folder, cổng xoá ở ba lối chính); đợt 2 thêm chạy nền, ghép Live
Photo, dấu lưới, Photo Info, các lối xoá còn lại.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-74 Folder | ❌ | `SmartAlbumSQLBuilder.swift:100-108` chỉ so `sourceId`; `SmartAlbumQuery.swift:298` không có folder | trường folder tuỳ chọn; clause đọc bảng hash theo file + tiền tố `relativePathKey` |
| AC-75 cả nguồn, không gộp | ❌ | clause hiện dựa `photo_copies` sau gộp; Photos ↔ server không bao giờ gộp (`IdentityMergePass.swift:27`) | clause mới không cần gộp |
| AC-76 rename | ✅ phía server | `ServerSourceIndexer.swift:101-106` nối bằng hash nhanh + cỡ | test khoá |
| AC-77, 78, 99 đủ file gốc (cả bản sửa) | ❌ | một hash mỗi bản sao (`AppDatabase+PhotoSources.swift:79-86`); JPEG đi kèm ở `pairedPath` không băm; bản sửa là tài nguyên riêng (`PhotoKitOriginalExporter.swift:22-24`) | bảng hash theo file |
| AC-79 không giống từng byte | ✅ theo thiết kế mới | SHA-256 cả file — khác byte là khác | test |
| AC-80 chưa kiểm | ❌ | "is not" = `NOT(…)` gồm cả mục chưa kiểm | clause đọc trạng thái |
| AC-81 làm tiếp | ⚠️ nửa | dòng NULL chọn lại (`ContentHashStore.swift:29-38`) nhưng `ORDER BY c.id`, mục hỏng chặn hàng | lần thử/lỗi, mới nhất trước |
| AC-82 file tạm | ❌ | `PhotosContentHashPass.swift:47-50` gom vào `Data` | `writeData(for:toFile:)` (có ở `ShareExportPipeline+PhotoKit.swift:68`) + băm luồng `FileChecksum.sha256` (`RemoteFileClient.swift:142-158`) |
| AC-83 chỗ trống | ❌ | 2 GB nằm trong `BackupRunner.swift:127-128, 330` | helper dùng chung |
| AC-84, AC-101 lọc theo cỡ | ❌ | cỡ bản gốc có sẵn: `photo_metadata.fileSize` (`AppDatabase.swift:75`), từng tài nguyên `OriginalFetcher.swift:153`; cỡ file NAS có trong listing | ứng viên theo cỡ hai phía |
| AC-85 Backup ghi sẵn | ❌ | file tạm giữa `BackupRunner.swift:333-334`; SHA đã tính ở :346; `UploadIntoSource.swift:49-56` không ghi hash | ghi hash file vào bảng mới trong transaction :401 |
| AC-100 lấy lại SHA Backup | ❌ | sổ có `(itemKey, resourceKey, sourceStamp, sha256, remotePath)` (`AppDatabase+Backup.swift:41-56`), chưa ai đọc cho việc này | gieo hash phía Photos từ sổ khi dấu nguồn khớp |
| AC-86, 94, 97 mạng | ❌ | server không có cổng (`ServerSourceRefresh.swift:64-77`); cổng Backup `BackupCoordinator+Live.swift:50-54`; không tra job theo connection | cổng mới, khắt nhất |
| AC-87 quét lại | ⚠️ | một lần mỗi lần chạy app (`ServerSourceRefresh.swift:31-33`), test `noTimedRescan` (`ServerSourceIndexTests.swift:108`) khoá điều đó; spec (người dùng) nói mỗi lần về trước mặt | theo spec, sửa test; nối `serverReachable` |
| AC-88, 89, 95, 102, 103, 104 cổng xoá | ❌ | ~15 lối xoá không hội tụ (`LibraryModel.swift:1455`, `SmartAlbumDetailModel.swift:135`, `UploadedToServerScreen.swift:231`…); `fileSize(at:)` mọi giao thức (`RemoteFileClient.swift:15`), mất = nil, không với tới = throw; chưa có stat ngày sửa | cổng một hàm; thêm ngày sửa vào stat |
| AC-98 bản NAS không bị ẩn | ⚠️ | `DeletionService.swift` ẩn bản `kind == "server"` trong cùng lượt; clause loại `isHidden = 1` (`SmartAlbumSQLBuilder.swift:103`) | cổng chỉ nhắm bản Photos |
| AC-90 câu Recently Deleted | ⚠️ nửa | có ở Free Up Space (`UploadedToServerScreen.swift:62`), không ở hộp chung (`MixedDeletionPlan.swift:100-130`) | thêm |
| AC-92 `.limited` | ❌ | banner có (`SmartAlbumDetailScreen.swift:227`), câu chưa có | thêm |
| AC-93 board | ❌ | chưa vẽ; picker tái dùng `ServerBrowserModel` `chooseFolder` (`ServerBrowserModel.swift:49`) | T0 |
| AC-91, 96, 105, 106 | đợt 2 | `MetadataPanel.swift:177-199`; `PairingRule.swift:33-53` chỉ RAW+JPEG; `BackupBackgroundService.swift:91` ép sạc khi 0 job; ghi sidecar sau gộp `IdentityMergePass.swift:12-15` | đợt 2 |
| S1–S4 | ❓ | cần máy thật | T13 |

Lỗi nhặt được: chip Source hiện UUID (`SmartAlbumRule+Display.swift:171-181`) — sửa ở T8 vì AC-74 cần tên; glyph cũ không
cập nhật sau upload của Backup (`ServerUploadIndex` chỉ `insert` từ `ServerUploadModel.swift:359`) — `REVIEW_QUEUE.md`,
hết ở đợt 2.

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `FileChecksum.sha256` (luồng 1 MB) | mọi SHA-256 mới, cả video |
| sổ Backup `sha256` theo tài nguyên | hash phía Photos không cần tải |
| `photo_metadata.fileSize`, cỡ tài nguyên qua PhotoKit | lọc ứng viên |
| `photo_copies.relativePathKey` | tiền tố folder |
| `ServerBrowserModel` `chooseFolder` + `FolderPickerRoute` | dòng Folder |
| `BackupSettings`, `NetworkMonitor`, `PowerMonitor`, `DiskSpace` | cổng mạng, chỗ trống |
| `RemoteFileClient.fileSize(at:)`, `entries(in:)` | kiểm lại trước khi xoá |
| `SourceDeletionFlow`, `MixedDeletionPlan` | hộp xoá, alert sau lượt |
| `InMemoryRemoteFileClient`, `FakeBackupSource`, `PhotosHashTests` | test |

## 4. File đổi (đợt 1)

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Data | `AppDatabase+PhotoSources.swift` (migration kế) | bảng **hash theo file**: bản sao · vai trò (ảnh, RAW, JPEG đi kèm, video Live Photo, video, bản sửa ảnh, bản sửa video) · cỡ · ngày sửa · SHA-256 · lần thử · lỗi cuối · nguồn hash (Backup / băm) | sửa |
| Data | `Data/Sources/FileServer/ConnectionLock.swift` | một lệnh một lúc mỗi connection, Backup ưu tiên | mới |
| Data | `PhotosContentHashPass.swift`, `ContentHashStore.swift` | gieo từ sổ Backup, ứng viên theo cỡ, file tạm, mới nhất trước, mục hỏng không chặn | sửa |
| Data | `ServerSourceIndexer.swift`, `ServerSourceRefresh.swift` | băm trọn ứng viên theo cỡ (cả file đi kèm), quét mỗi lần về trước mặt, `serverReachable` | sửa |
| Data | `BackupRunner.swift`, `BackupStore.swift` | ghi hash file vào bảng mới cho bản sao server | sửa |
| Data | `OnServerPresenceQueries.swift` | đủ file gốc trên nguồn + folder; đã kiểm chưa; tiến độ | mới |
| Domain | `Domain/OnServer/OnServerSchedule.swift` | cổng chạy (khắt nhất), lý do chờ | mới |
| Domain | `Domain/OnServer/ServerCopyVerification.swift` | kết quả kiểm lại: xoá được / mất / đổi / không với tới | mới |
| Data | `Data/Sources/PhotoDeletionGate.swift` | cổng xoá một hàm | mới |
| Data | `OnServerHashService.swift` | chạy pass khi app ở trước mặt | mới |
| Core / Data | `SmartAlbumQuery.swift`, `SmartAlbumRule+Display.swift`, `SmartAlbumSQLBuilder.swift` | folder, chip có tên, clause mới | sửa |
| Features | `SmartAlbumRuleRow.swift`, `SmartAlbumDetailScreen.swift`, `SmartAlbumConditionsBar.swift` | dòng Folder, dòng tiến độ | sửa |
| Features | `SmartAlbumDetailModel.swift`, `UploadedToServerScreen.swift`, `LibraryModel.swift` | xoá qua cổng | sửa |
| Design | `docs/design/{iphone,ipad,duo}/project/*SmartAlbumEditor*`, `*SmartAlbum*`, `*DeleteCopies*` | dòng Folder, tiến độ, alert | sửa |

## 5. Thứ tự task

Một task = một commit, test đi kèm. Đợt 1 dùng được ngay sau T14.

**Đợt 1**

| # | Task | AC | Test |
|---|---|---|---|
| T0 | Vẽ board 3 thiết bị (sáng + tối), publish 3 canvas | AC-93 (nền) | `Tools/design-board render` |
| T1 | Khoá một-lệnh-một-lúc mỗi connection; Backup, Upload, index dùng chung (màn duyệt folder không chờ khoá — người dùng đang chờ) | nền cho AC-84/85 | `ConnectionLockTests.backupFirst`, `.yieldsBetweenFiles`, `.oneCallAtATimePerConnection`, `.cancelledWaiterSkipsWork` |
| T2 | Khoá rename server bằng test | AC-76 | `ServerSourceIndexTests.renameKeepsIdentity` |
| T3 | Bảng hash theo file + gieo từ sổ Backup | AC-100 | `PhotosHashTests.seedsFromBackupLedger` |
| T4 | Backup ghi hash cho bản sao server — làm bằng cách lượt quét nguồn đọc sổ Backup + sổ chung theo đường dẫn + cỡ (Backup đã ghi SHA sau khi đọc lại; không thêm lần ghi nào trong `BackupRunner`, phủ cả file máy khác) | AC-85 | `BackupRunnerTests.recordsServerCopyHash` |
| T5 | Server: ứng viên theo cỡ, băm trọn ra file tạm, nhớ theo đường dẫn + cỡ + ngày | AC-84 | `ServerSourceIndexTests.fullHashOnlySizeCandidates` |
| T6 | Photos: chỉ ứng viên theo cỡ, file tạm, mới nhất trước, mục hỏng không chặn, chờ chỗ trống | AC-81, 82, 83, 101 | `PhotosHashTests.*` |
| T7 | Truy vấn đủ file gốc (cả bản sửa), không cần gộp | AC-75, 77, 78, 79, 99 | `OnServerRuleTests.*` |
| T8 | Source có Folder + chưa kiểm + chip có tên + dòng Folder | AC-74, 80, 93 | `OnServerRuleTests.folderScope`, `.uncheckedInNeither` + `design-board compare` |
| T9 | Cổng chạy khắt nhất + chạy khi về trước mặt | AC-86, 94, 97 | `OnServerScheduleTests.*` |
| T10 | Quét lại mỗi lần về trước mặt, nối `serverReachable`, sửa `noTimedRescan` | AC-87 (album) | `ServerSourceIndexTests.rescanOnForeground` |
| T11 | Dòng tiến độ + câu `.limited` | AC-80 (dòng), 92 | `OnServerProgressTests` + ảnh |
| T12 | Cổng xoá (một hàm) ở smart album, Free Up Space, Library; kiểm cỡ + ngày, tìm lại file dời; Delete Anyway; không ẩn bản NAS; câu Recently Deleted; test chặn lời gọi xoá mới | AC-88, 89, 90, 95, 98, 102, 103, 104 | `PhotoDeletionGateTests.*` |
| T13 | Build spike S1, S2, S4 có log; người dùng chạy; ghi số | S1, S2, S4 | số đo |
| T14 | `/verify` đợt 1, `/screens`, `design-parity` | đợt 1 | — |

**Đợt 2** (sau S3)

| # | Task | AC | Test |
|---|---|---|---|
| T15 | Spike S3 + tác vụ nền riêng (không qua `scheduleProcessing` của Backup) | AC-105, S3 | test giả lập tác vụ |
| T16 | Ghép Live Photo trên nguồn thư mục/server | AC-96 | `ServerSourceIndexTests.pairsLivePhoto`, `FolderSourceIndexTests.pairsLivePhoto` |
| T17 | Gộp Photos ↔ server để hiển thị, không ghi sidecar | AC-106 | `PhotoIdentityMergeTests.checkMergeWritesNoSidecar` |
| T18 | Glyph lưới theo hiện trạng | AC-87 (glyph) | `OnServerIndexTests.glyphFollowsCopies` |
| T19 | Photo Info On Server | AC-91 | ảnh 3 thiết bị |
| T20 | Nối cổng vào mọi lối xoá còn lại | N2 | `PhotoDeletionGateTests.everyEntryPointRoutes` |
| T21 | `/verify` cả FS-19.07, `Tools/gate` | tất cả | — |

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Đợt 1 chỉ cổng ở 3 lối: xoá từ Duplicates, Cull, Album thường chưa được kiểm lại | chắc chắn tới đợt 2 | ba lối là đường người dùng dùng để giải phóng iCloud; T12 có test chặn lời gọi xoá mới; T20 làm nốt |
| File bị app khác ghi metadata coi là "chưa có" — người dùng thấy ít ảnh hơn mong đợi | vừa | đúng ý: không xoá nhầm; ghi trong spec §2 |
| Không hàng đợi chung mỗi connection (SMB không an toàn song song) | vừa | T1 trước mọi task gọi server; `swift-concurrency` duyệt |
| Bộ nhớ: video 4K | cao nếu không đổi | file tạm + băm luồng; S4 |
| Sổ Backup sai dấu nguồn → dùng SHA cũ | thấp | chỉ gieo khi dấu nguồn khớp; lúc xoá vẫn hỏi NAS |
| Migration bảng mới | thấp | bảng thêm; app chưa release; `data-migration` |
| Truy vấn đủ file trên 55.000 mục | vừa | một truy vấn có index trên SHA; ≤ 3 s (NF-01); `perf-profiler` |
| Hook build bị khoá khi phiên khác test cùng `build/sim` | đã gặp | chờ; không nhân bản DerivedData |

## 7. Phản biện (`challenger`, 2026-10-25)

| Phản đối | Trả lời / thay đổi |
|---|---|
| Ảnh đã sửa: NAS chỉ có bản gốc, xoá là mất bản sửa — đường mất dữ liệu duy nhất bị sót | **Nhận.** Bản sửa là một file gốc bắt buộc (spec §3, AC-99); người dùng chọn |
| T2 cũ tải lại mọi bản gốc iCloud trong khi sổ Backup đã có SHA từng tài nguyên | **Nhận.** Hash đổi sang SHA-256 cả file, gieo từ sổ (AC-100); người dùng chọn |
| Backup ghi hash xếp quá muộn, mà với người dùng này là chỗ tiết kiệm chính | **Nhận.** Lên T4, trước băm server |
| An toàn bị buộc vào gộp ảnh (gộp xoá dòng của bên thua, ghi sidecar lên mọi bản) | **Nhận.** Truy vấn đọc thẳng bảng hash (AC-75 tắt gộp); gộp sang đợt 2, cấm ghi sidecar (AC-106) |
| Xoá bản Photos có thể ẩn luôn bản NAS → ảnh biến mất khỏi ShotDex | **Nhận.** AC-98; cổng chỉ nhắm bản Photos |
| Gom 15 lối xoá là điều kiện tiên quyết nặng; NAS tắt thì chặn cả việc xoá ảnh Reject | **Nhận một phần.** Giữ N2 (mọi lối) nhưng đợt 1 chỉ 3 lối + test chặn lời gọi mới; chỉ mục *dựa vào server* bị kiểm; có Delete Anyway (người dùng chọn) |
| Chỉ so cỡ lúc xoá — không thấy file bị ghi đè cùng cỡ | **Nhận.** Thêm ngày sửa; file dời thì tìm lại bằng hash nhanh + cỡ (AC-102, 103); hỏng âm thầm ngoài phạm vi |
| Ghép Live Photo và đổi nghĩa glyph không cần cho việc xoá an toàn | **Nhận về thứ tự**, không bỏ: sang đợt 2 (người dùng đã chọn làm, giờ chọn chia đợt) |
| Ngân sách chạy nền chưa đo, không xong 20.000 mục một đêm | **Nhận.** Đợt 1 chạy khi mở app; nền ở đợt 2 sau S3 |
| Khoá một-lệnh-một-lúc đụng 3 runner | **Nhận.** Commit riêng T1, duyệt trước khi task khác xây lên |

Người dùng hỏi thêm (2026-10-25): file NAS không do ShotDex chép — xử lý bằng lọc theo cỡ hai phía (AC-84, AC-101); file
hash do script ghi sẵn để sau.

## 8. Cách chứng minh là xong

- Test: mọi tên ở §5; cột "Chứng minh bằng" của 07b đổi từ `⚠️ chưa có` sang tên thật theo từng commit.
- Màn hình (đợt 1): editor có dòng Folder; album ở các trạng thái đang kiểm, chờ Wi‑Fi, chờ chỗ, không với tới, xong;
  alert sau xoá; alert Delete Anyway — iPhone 26.5 + 18.6, iPad, Duo trong + ngoài; `design-parity` từng board.
- Tài liệu: 07/07b theo code; BD-02 (bảng mới); FS-19.02 §1b; FS-19.03 §3; FS-22.05.
- Agent ở Deploy: `data-migration`, `swift-concurrency`, `photokit-guard`, `memory-leak`, `perf-profiler`, `ux-reviewer`
  (luồng xoá), `device-layout`, `ios26-parity`, `design-parity`.
