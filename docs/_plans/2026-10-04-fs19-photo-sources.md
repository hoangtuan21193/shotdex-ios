# Kế hoạch — Nguồn ảnh: thư mục, ổ ngoài và server (FS-19)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19`](../02-functional-spec/FS-19-photo-sources/README.md) — **68 AC + AC-73** ([06](../02-functional-spec/FS-19-photo-sources/06-acceptance-criteria.md)) + 7 test bắt buộc ở [05 §8](../02-functional-spec/FS-19-photo-sources/05-data.md); AC-69…AC-72 thêm vào 06 cùng task (A1, A2, E13, E14) |
| Intent | [2026-10-04-macos-app](../_intents/2026-10-04-macos-app.md) · [2026-10-04-ipad-mac-style](../_intents/2026-10-04-ipad-mac-style.md) |
| Quyết định | [DECISIONS](../../.planboard/macos-app/DECISIONS.md) D1, D3–D7, D16 · [SPEC-DECISIONS](../../.planboard/macos-app/SPEC-DECISIONS.md) mục FS-19 + "Schema FS-19" + "Planboard mac-ipad-v2" · [mac-ipad-v2](../../.planboard/mac-ipad-v2/DECISIONS.md) — **không mở lại** |
| Bảng AC ↔ code | [`2026-10-04-fs19-photo-sources-ac-table.md`](2026-10-04-fs19-photo-sources-ac-table.md) — **0 ✅ trọn · 13 ⚠️ · 55 ❌ · 1 ❓** |
| Board | iPhone `PH_Sources` · `PH_AddSource` · `PH_SettingsSources` · `PH_ServerList/Form/Browser` · `PH_Hidden` · `PH_DeleteCopies` · `PH_DeletePermanent`; Duo `DI_*` / `DC_*` cùng tên; iPad `IP_AddSource` · `IP_SourceIndexing` · `IP_Settings` · `IP_Server*` · `IP_Hidden` · `IP_DeleteCopies` · `IP_DeletePermanent`; Mac `MAC_*` ([docs/design](../design/README.md)) |
| Ngày | 2026-10-04 |
| Trạng thái | **đã duyệt 2026-10-04** (planboard mac-ipad-v2). 77 task = 77 commit (4 khoá + 73 AC) |

## 1. Hiểu đúng chưa

Một thư viện gộp ba loại nguồn trên mọi thiết bị: Photos, thư mục/ổ (bookmark security-scoped), server
SMB/SFTP/WebDAV được index. Một **ảnh** là một id (ảnh Photos giữ `localIdentifier` làm id; ảnh mới từ file/NAS nhận
UUID) với nhiều **bản sao**; hai bản giống hệt (hash đầy đủ của **phần dữ liệu ảnh**) là một ảnh, đếm một lần, chung
sao/cờ/keyword/recipe. Thứ người dùng nhập nằm ở bảng riêng theo id ảnh **và** ở sidecar `.xmp` cạnh mọi bản file
online; file ảnh không bao giờ bị ghi. Xoá đi đúng nơi (Recently Deleted / Thùng rác / ẩn với NAS / xoá hẳn sau hộp
đỏ), chỉ đụng bản sao của nguồn đang xem. Ảnh mất bản sao cuối là mồ côi 30 ngày.

Code hôm nay: **không có dòng nào** của nguồn, bản sao, hash nội dung, sidecar, theo dõi file, Thùng rác, mục Hidden
của ShotDex hay album của app. Mọi bảng khoá theo `localIdentifier`; `IndexPipeline` là actor PhotoKit thuần
(`Domain/Indexing/IndexPipeline.swift:46`, `:1001`). Cái dùng lại được nhiều: client server + đọc dải + thang
thumbnail (FS-15/17), `ExifReader.readExif(fromImageAt:)`, `MetadataComposer` thuần, luật ghép RAW+JPEG của server,
mẫu luồng `requestData` của `ExifReader`, bảng quy đổi Lightroom, kiểm chỗ trống, dọn tmp lúc mở app.

Vì vậy plan này là **nền dữ liệu trước** (khối A), rồi đọc thư mục (B), sidecar (C), server (D), xoá/ẩn/trùng/album/
thống kê (E), màn hình iPhone/Duo/iPad (F). App chưa phát hành: migration chỉ **thêm** (CLAUDE.md), không cờ phiên bản.

## 2. Phép đo trước khi code (spec 01 §4 đòi số từ spike)

| # | Đo | Ở đâu | Lái cái gì |
|---|---|---|---|
| M1 | file/giây của lượt đọc đầu (liệt kê + EXIF + preview nhúng + hash nhanh) trên: bộ nhớ trong iPhone 17, SSD USB-C trên iPad, NAS gigabit qua SMB | máy thật, 2.000 CR3 + 2.000 JPG fixture (CC0, không mặt người) | banner có hứa số hay chỉ "Estimating time…"; `readConcurrency` của nguồn |
| M2 | hash nhanh vs hash đầy đủ 26.107 RAW trên SSD/HDD (Mac khi có target FS-18; tạm iPad + SSD) | máy thật | bảng ước lượng 02 §1 |
| M3 | đỉnh RAM khi băm luồng một RAW 50 MB của Photos theo K2 (TIFF cần đọc ngẫu nhiên) | iPhone thật, Instruments | trần bộ đệm trong K2; extension không bao giờ chạy đường này |

**Chốt (board Q10): bỏ qua — M1, M2, M3 chưa đo (cần máy thật).** Thay bằng: M1 → banner theo `IndexEstimate` (chờ 200
file, không hứa số trước — A8), `readConcurrency` của nguồn lấy mặc định của `IndexPipeline`; M2 → bảng 02 §1 giữ là
ước lượng, ghi "chưa đo"; M3 → trần đệm bảo thủ trong A8, đỉnh RAM đo trên simulator như `FileExportMemoryTests`, quá
trần thì giữ hash nhanh.

## 3. Đã chốt (planboard mac-ipad-v2)

Duyệt 2026-10-04, một vòng. Bảng chi tiết các phương án: `.planboard/mac-ipad-plans/plan.json` (bảng cũ). Mỗi dòng:
lựa chọn — id trên board.

**Kiến trúc**

- **K1** — b: actor mới `SourceIndexPipeline` cho thư mục + server; `IndexPipeline` giữ PhotoKit, chỉ thêm bước giữ bảng
  Bản sao; tách chung nhịp (`readConcurrency`/`interBatchPause`/thermal), `MetadataComposer`, `ExifReader.parse` — **A1**.
- **K2** — a: parser v1 JPEG (từ SOS), ISOBMFF (HEIC, CR3), TIFF-family (DNG, ARW, NEF, TIFF); định dạng khác băm cả
  file; tên `sdx-image-sha256` + version — **A2**.
- **K3** — b: đọc bằng `CGImageMetadata`, ghi bằng bộ vá văn bản thuần Domain (chỉ `xmp:Rating`, `dc:subject`,
  `dc:title`, `dc:description`, namespace ShotDex), file tạm + `replaceItemAt` — **A4**.
- **K4** — a: `photo_user_marks` + `photo_user_keyword`; `pending_photo_rating` giữ vai hộp thư đi; luật ưu tiên một chỗ
  ở `PhotoMarksStore.ratingCondition` — **A3**.
- **K5** — a: `photo_recipes` là bản làm việc cho mọi ảnh; Done trên bản Photos ghi thêm adjustment data; adjustment
  data mới hơn `updatedAt` thì lấy nó — **A3**.
- **K6** — a: `EXISTS` bản sao thấy được qua chỉ mục `copies(photoId, online)`, một hàm SQL dùng chung; cổng đo 55k
  trước khi đóng E7 — **A5**.
- **K7** — b: thư mục cache tự chứa + `cache.sqlite`; trần 2/5/10/25/50 GB (iOS 5, Mac 25) — **A6**.

**Câu hỏi ⚠️** (số Q của plan này → id trên board)

- **Q1** (AC-5) — tài liệu đúng; một `IndexEstimate` cho banner Photos lẫn nguồn — **A8**.
- **Q2** (AC-47, AC-37) — tài liệu đúng; `RemoteThumbnailCache` gộp vào `PreviewCache`, thư mục cũ xoá ở lần mở đầu — **A6**.
- **Q3** (AC-51, AC-67) — tài liệu đúng: giữ 30 ngày; FS-01.12 AC-9 sửa cùng A3 — **A9**.
- **Q4** (AC-66) — sửa AC: widget + Recents; mọi chỗ lưu id đi qua `PhotoAliasResolver` — **A10**.
- **Q5** (AC-33) — 03 §2 đúng, sửa AC-33: trần = byte thang thumbnail + 3 × 64 KB — **A10**.
- **Q6** (AC-39) — tài liệu đúng: bỏ Import to Library, Save to Photos dùng `PhotoKitAssetCreator`; giữ bảng
  `server_downloads`, không ghi thêm — **A9**.
- **Q7** (AC-56) — code đúng: giữ "Delete N from This Device", sửa AC, thêm câu "They stay in ShotDex from NAS Home." — **A7**.
- **Q8** (AC-40) — tài liệu đúng: hộp ShotDex đếm theo đích, tên Move/Delete/Hide; toàn Photos chỉ hộp hệ thống — **A7**.
  Kèm theo (08c Q3, **A7**): huỷ hộp hệ thống của Photos chỉ giữ lại phần Photos — FS-19.04 §2 sửa ở E3.
- **Q9** (AC-59) — **khác đề xuất**: hai lệnh riêng **Hide in Photos** · **Hide in ShotDex Only** trên ảnh có bản Photos
  và bản file/NAS; "Hide" trơn chỉ khi ảnh nằm ở một nơi. FS-19.04 §3 và AC-73 đã sửa khi duyệt; task E15 — **Q1**.
- **Q10** (AC-44) — tài liệu đúng: khoá Duplicates thêm nguồn; Exact của ảnh chỉ-Photos giữ dHash — **A9**.
- **Q11** (AC-60) — tài liệu đúng; câu hộp Merge đổi theo loại ảnh giữ — **A9**.
- **Q12** (AC-61) — tài liệu đúng; New Album theo nguồn — **A9**.
- **Phép đo M1–M3 và kiểm trên máy thật** — bỏ qua, ghi "chưa đo / chưa kiểm (cần máy thật)" — **Q10**.

## 4. Đổi so với bản nháp

- **E15 mới** (Q9 → board Q1): hai lệnh Hide, AC-73. Tổng 76 → 77 task.
- **L2, E3** (A7): huỷ hộp hệ thống không còn là "không gì chạy" mà "chỉ phần Photos ở lại"; test đổi tên
  `photosCancelKeepsPhotosPart`; E3 sửa FS-19.04 §2 + AC-41 cùng commit.
- **F4** (Q10): bỏ máy thật; gập Duo bằng tay trong Simulator.app + `Tools/sim-shot … cover`.
- **M1–M3** (Q10): không đo — thay thế ghi ở §2.
- **AC-69…72, AC-33, AC-56, AC-66**: sửa 06 cùng commit của task (A1, A2, E13, E14, D1, D7, A7), không gom vào một
  commit duyệt.

## 5. Thứ tự task

Một AC = một task = một commit (`feat(FS-19): AC-n …`). L = khoá phần ✅; W = ⚠️ không phụ thuộc nền; A–F = ❌ và
⚠️ còn lại theo phụ thuộc (dòng ⚠️ đánh dấu ⚠️, làm theo chốt ở §3). Test là tên đề xuất trong 06; test mới
viết trước, đỏ, rồi code (task sửa lỗi bật `SHOTDEX_FREEZE_TESTS=1`).

### Khối L — khoá phần đã đúng

| # | Task | AC | Test |
|---|---|---|---|
| L1 | auth bị từ chối dừng lô, không hộp mật khẩu | AC-36 (phần ✅) | `ServerSourceIndexTests.passwordRejectedNoPrompts` (nửa client) |
| L2 | Cancel hộp hệ thống → phần Photos không đổi | AC-41 (phần ✅) | ✅ đã có: `RejectedDeletionCancelTests.cancelChangesNothing` — không viết test trùng; `MixedDeletionTests` ra đời ở E3 |
| L3 | asset Photos không đọc sao trong file | AC-52 (phần ✅) | `SidecarReaderTests.cameraRatingFilesOnly` (nửa Photos) |
| L4 | Clear Local Metadata Index giữ sao/cờ | AC-31 (phần ✅) | ✅ đã có: `PhotoMarksStoreTests.clearIndexKeepsMarks` — không viết test trùng; `SidecarSettingTests` ra đời ở C13 |

### Khối W — ⚠️ không cần nền

| # | Task | AC | Test |
|---|---|---|---|
| W1 ⚠️ | `PreviewCache` (K7) ở Application Support, `isExcludedFromBackup`, trần 2/5/10/25/50 GB (iOS 5); `RemoteThumbnailCache` chuyển vào; NF-02 + FS-08 (bỏ pane Server Thumbnails) | AC-47 | `PreviewCacheTests.locationAndDefaults` |
| W2 ⚠️ | bỏ preview mở lâu nhất trước, thumbnail sau | AC-37 | `PreviewCacheTests.evictsPreviewsBeforeThumbnails` |
| W3 ⚠️ | `IndexEstimate` (Domain): cửa sổ 200 file, làm tròn phút, "about 1 h 20 min left"; banner Photos dùng chung theo Q1 | AC-5 | `IndexEstimateTests.waitsFor200ThenRoundsToMinutes` |

### Khối A — nền dữ liệu (chỉ iOS, DB trong bộ nhớ)

| # | Task | AC | Test |
|---|---|---|---|
| A1 | migration `v30-photoSources`: **mọi** bảng 05 §3 (`photos`, `photo_copies` UNIQUE(sourceId, relPathKey) không FK cascade, `sources`, `content_hashes` UNIQUE(algo, fullHash) partial + index fastHash, `photo_aliases`, `photo_recipes`, `photo_user_marks` + `photo_user_keyword` (K4), `pending_sidecar`, `shotdex_albums` + thành viên) + khoá lại `duplicate_groups`/`duplicate_scan_state` có `sourceId`; backfill Ảnh + Bản sao kind `photos` từ hợp `assetId` của **mọi** bảng; `IndexPipeline` thêm/bỏ bản sao kind `photos` thay vì xoá dòng; BD-02 sửa | AC-69 (mới) | `PhotoSourcesMigrationTests.backfillsUnionOfIds` (05 §8.1, `migrate(upTo: "v29-creationDrafts")` như `DatabaseTests.swift:93`) |
| A2 | Clear Local Metadata Index giữ mọi bảng FS-19 (`MetadataStore.deleteAll`, `MetadataStore.swift:372-385`) | AC-70 (mới) | `…userDataSurvivesReindexAndClear` (05 §8.2) |
| A3 ⚠️ | `OrphanRetention` (Domain, đồng hồ tiêm): mồ côi đặt/xoá dấu, dọn > 30 ngày lúc mở app trừ 3 lịch sử; thay `UserMarkRemovalPolicy` + nối `AppDependencies.swift:349-357`; `.limited` không mồ côi; FS-01.12 AC-9 sửa | AC-67 | `OrphanRetentionTests.purgeKeepsHistories` (05 §8.4) |
| A4 | `ContentHasher` (K2) thuần Domain, nguồn byte trừu tượng (file, dải server, luồng Photos) | AC-22 | `PhotoIdentityTests.embeddedMetadataKeepsHash` |
| A5 | hash nhanh (kích thước phần ảnh + 3 × 64 KB) vs đầy đủ; gộp chỉ khi đầy đủ trùng | AC-48 | `PhotoIdentityTests.fastHashNeverMergesAlone` |
| A6 | `PhotoMergePlan` (Domain) + `PhotoIdentityStore.merge` một transaction: một giá trị theo giờ đổi, tập hợp hợp lại, dấu chờ trỏ id thắng, bí danh | AC-65 | `PhotoMergeTests.collisionsInEverySatelliteTable` (05 §8.3) |
| A7 ❓ | `PhotoAliasResolver`: widget snapshot writer + Recents (+ chỗ khác ở Q4) đi qua bí danh; bộ nạp thumbnail file cho widget từ `PreviewCache` (EX-02 sửa) | AC-66 | `PhotoAliasTests.loserIdResolves` |
| A8 | `PhotosContentHashPass`: luồng `requestData` (mẫu `ExifReader.swift:426-650`), băm rồi bỏ, luật mạng index, không file tạm | AC-49 | `PhotosHashTests.streamsWithoutDiskGrowth` |

### Khối B — nguồn thư mục

| # | Task | AC | Test |
|---|---|---|---|
| B1 | `FolderEnumeration`: `enumerator` với `skipsPackageDescendants` + `skipsHiddenFiles`, `.xmp` thành sidecar, loại theo `CGImageSourceCopyTypeIdentifiers` | AC-4 | `FolderEnumerationTests.skipsPackagesAndDotFiles` |
| B2 | `SourceOverlap` từ chối lồng/chứa | AC-45 | `SourceOverlapTests.refusesNestedAndContaining` |
| B3 | `SourceStore` + `FolderSourceReader` (bookmark security-scoped đọc + ghi, mẫu `ExportFolderStore.swift:83-98`) + `SourceIndexPipeline` (K1): liệt kê → EXIF/preview nhúng/hash nhanh → bản sao + dòng metadata từ bản chính; `PairingRule` dời từ `ServerFolderListing.swift:90-125`; BD-03 sửa | AC-1 | `FolderSourceIndexTests.pairsAndNeverWrites` |
| B4 | đổi Include Subfolders → chỉ đọc phần chênh | AC-3 | `…subfoldersToggleReadsOnlyDelta` |
| B5 | Pause/Resume, điểm chạy tiếp ở bảng Nguồn | AC-6 | `…resumeAfterRelaunch` |
| B6 | ảnh nhiều bản: một ô, đếm một lần ở All và mỗi nguồn (hàm hiển thị K6 vào `LibraryQueries`, `StatisticsQueries`, `SmartAlbumSQLBuilder`); FS-07 sửa | AC-18 | `PhotoIdentityTests.identicalCopiesAreOnePhoto` (05 §8.6) |
| B7 | đổi tên → cùng id bản sao | AC-20 | `…renameKeepsIdentity` (05 §8.5) |
| B8 | chuyển nguồn → cùng ảnh | AC-21 | `…moveAcrossSourcesKeepsData` |
| B9 | ghi đè khi bản khác giữ ảnh cũ → tách | AC-64 | `…overwrittenCopySplits` |
| B10 ⚠️ | file quay lại trong 30 ngày → cùng id, dữ liệu đủ | AC-51 | `OrphanRetentionTests.thirtyDays` |
| B11 | chỗ giữ chỗ cloud: không tải, không đếm, glyph | AC-15 | `CloudPlaceholderTests.neverDownloadsNeverCounts` |
| B12 | hết chỗ → dừng preview, metadata chạy tiếp | AC-17 | `PreviewCacheTests.diskFullStopsPreviewsOnly` |
| B13 | Hide Its Photos | AC-46 | `SourceAvailabilityTests.hideOnDisconnect` |
| B14 | rút ổ giữa lượt đọc | AC-10 | `…unplugMidIndexKeepsRead` |
| B15 | cắm lại → chạy tiếp ≤ 5 s | AC-11 | `…replugResumes` |
| B16 | bookmark hỏng → Needs access, ảnh ở lại | AC-13 | `SourceBookmarkTests.staleBookmarkKeepsPhotos` |
| B17 | Grant Access → khớp lại bằng hash | AC-14 | `…regrantRematchesByHash` |

### Khối C — sidecar

| # | Task | AC | Test |
|---|---|---|---|
| C1 | `SidecarReader` (Lightroom: sao, −1 Reject, `dc:subject`); lọc keyword đọc cả gương Photos lẫn `photo_user_keyword` | AC-23 | `SidecarReaderTests.lightroomRatingsRejectsKeywords` |
| C2 | XMP nhúng; sidecar thắng | AC-24 | `…sidecarBeatsEmbedded` |
| C3 | sao máy ảnh trong file với ảnh file (FS-01.12 §7 sửa) | AC-52 | `…cameraRatingFilesOnly` |
| C4 | bộ vá XMP (K3) | AC-25 | `SidecarWriterTests.preservesForeignTags` |
| C5 | `SidecarWriter`: trễ 1 s, tmp + replace, mọi bản online; FS-01.12 §3 + NF-03 §2b sửa | AC-19 | `…writesEveryOnlineCopyNeverTheImage` |
| C6 | tắt ghép → `<tên>.JPG.xmp` | AC-2 | `FolderSourceIndexTests.pairingOffSeparateSidecar` |
| C7 | dấu sidecar (ngày + hash), đọc lại trước khi ghi | AC-26 | `SidecarConflictTests.rereadsBeforeWrite` |
| C8 | cùng trường: đổi sau thắng | AC-27 | `…sameFieldLastWriterWins` |
| C9 | hai bản khác sidecar → mới hơn thắng, ghi bản kia | AC-28 | `…copiesDisagreeNewestWins` |
| C10 | Reject/Pick/favorite/recipe vào vùng ShotDex | AC-54 | `SidecarWriterTests.rejectPickFavoriteRecipe` |
| C11 | dấu chờ cho bản offline | AC-29 | `PendingSidecarTests.offlineCopyMarkedSurvivesClear` |
| C12 | cắm lại → ghi giá trị hiện hành 1 lần | AC-30 | `…writesCurrentValueOnReconnect` |
| C13 | công tắc sidecar tắt | AC-31 | `SidecarSettingTests.offKeepsMarksInDatabaseOnly` |
| C14 | ổ chỉ đọc → dấu chờ + dòng báo | AC-32 | `PendingSidecarTests.readOnlyVolume` |
| C15 | Import Lightroom Edits qua `LightroomMapping` (FS-03.14b sửa) | AC-53 | `LightroomImportTests.onlyOnCommand` |

### Khối D — server là nguồn

| # | Task | AC | Test |
|---|---|---|---|
| D1 ⚠️ | `ServerSourceReader` trên `RemoteFileClient` + `AsyncGate` (`ServerBrowseSession.swift:5-24`), thang thumbnail `RemoteThumbnailer`, hash nhanh bằng `readRange`; trần byte theo Q5 | AC-33 | `ServerSourceIndexTests.rangeReadsOnly` (SMB cục bộ) |
| D2 | Rescan so size + `modified` | AC-38 | `…rescanReadsOnlyNew` |
| D3 | chỉ so lúc mở app / server về / Rescan | AC-55 | `…noTimedRescan` |
| D4 | hàng nguồn "Password rejected" + Edit Connection… | AC-36 | `…passwordRejectedNoPrompts` |
| D5 | server không với tới | AC-35 | `SourceAvailabilityTests.serverUnreachable` + ảnh chụp |
| D6 | viewer thư viện tải bản gốc vào tmp, xoá khi rời (tái dùng `ServerPhotoCommands`, `TemporaryWorkspace`, `DeviceSpaceCheck`) | AC-34 | `ServerOriginalTests.tempDeletedOnClose` |
| D7 ⚠️ | upload vào folder nguồn → bản sao ngay; câu hộp theo Q7 | AC-56 | `UploadIntoSourceTests.uploadedFileIsACopy` |
| D8 ⚠️ | Add as Source trong form; bỏ Import to Library, thêm Save to Photos; FS-15/FS-17 + FS-21 §1/§4 dòng FS-17 sửa | AC-39 | `ShotDexUITests/scripts/source-server-iphone.json` |

### Khối E — xoá, ẩn, trùng, album, thống kê

| # | Task | AC | Test |
|---|---|---|---|
| E1 ⚠️ | `MixedDeletionPlan` (Domain): đếm theo đích, câu, tên Move/Delete/Hide; một `DeletionService` thay 12 chỗ gọi `metadataStore.deleteAssets` rải ở Features (`LibraryModel.swift:1412`, `AlbumsModel.swift:1085`, `DuplicatesModel.swift:675`, …) và đường bỏ qua hook `PhotoEditingService.swift:656-665`; FS-01.12b sửa | AC-40 | `MixedDeletionPlanTests.messageCountsByDestination` |
| E2 | toàn NAS → Hide | AC-43 | `…allServerIsHide` |
| E3 ⚠️ | thư mục/NAS chạy trước, Photos sau qua hộp hệ thống; Cancel ở đó → chỉ phần Photos ở lại (08c §6, A7); FS-19.04 §2 + AC-41 sửa | AC-41 | `MixedDeletionTests.photosCancelKeepsPhotosPart` |
| E4 | Thùng rác kèm cặp + `.xmp` (`FileManager.trashItem`) | AC-42 | `…trashCarriesPairAndSidecar` |
| E5 | chỉ bản của nguồn đang xem; danh sách tick ở All Photos | AC-57 | `MultiCopyDeletionTests.onlyViewedSourceThenChecklist` |
| E6 | nơi không Thùng rác → hộp đỏ thứ hai; FS-06.06b sửa | AC-58 | `ShotDexUITests/scripts/source-permanent-delete-ipad.json` |
| E7 | ẩn = mọi bản ẩn; cổng đo K6 ở 55k | AC-68 | `HiddenCopyTests.hiddenOnlyWhenEveryCopyHidden` |
| E8 ⚠️ | mục Hidden trong Collections (gồm ảnh ẩn bằng mọi lệnh Hide, FS-19.04 §3); FS-06.01 sửa | AC-59 | `ShotDexUITests/scripts/hidden-section-iphone.json` |
| E9 ⚠️ | Duplicates theo nguồn, Exact cùng nguồn = hash nội dung | AC-44 | `DuplicateSourceScopeTests.groupsStayInOneSource` (05 §8.7) |
| E10 ⚠️ | Merge ảnh file: sao, cờ, keyword | AC-60 | `FileMergeTests.ratingFlagKeywordOnly` |
| E11 ⚠️ | album ShotDex, New Album theo nguồn | AC-61 | `ShotDexAlbumTests.spansSources` |
| E12 | thứ tự mở bản sao + `PhotoEditOrigin.fileCopy`, tự lưu recipe (D16, K5) | AC-50 | `CopyOrderTests.internalPhotosExternalServerCloud` |
| E13 | Statistics popup Source | AC-71 (mới) | `StatisticsSourceTests.countsOncePerSource` |
| E14 | Duplicates popup Source | AC-72 (mới) | `DuplicateSourceScopeTests.sourcePopupFilters` |
| E15 | **Hide in Photos · Hide in ShotDex Only** (board Q1): `HideCommandPlan` (Domain) chọn lệnh theo bản sao của lựa chọn; Hide in Photos = `PHAssetChangeRequest.isHidden` (đường hôm nay, `PhotoDetailScreen.swift:3153`) + cờ ẩn mọi bản file/NAS; Hide in ShotDex Only = cờ ẩn mọi bản sao, kể cả bản Photos; ⋯ Viewer, menu nhấn giữ, ⋯ chọn nhiều cùng chữ; sau E7, E8 | AC-73 (mới) | `HideCommandPlanTests.mixedPhotoOffersBothCommands`, `HiddenCopyTests.shotDexOnlyLeavesPhotosUntouched` |

### Khối F — màn hình

| # | Task | AC | Test / chứng minh | Chờ |
|---|---|---|---|---|
| F1 | iPhone Settings › Sources + Add Folder or Drive (board `PH_SettingsSources`, `PH_AddSource`, `PH_Sources`); FS-08 "Photo Library" → Sources (+ FS-21 §4 dòng FS-08.01) | AC-62 | `source-folder-iphone.json` | — |
| F2 | lượt so lệch khi về trước mặt | AC-9 | `source-foreground-diff-ipad.json` | — |
| F3 | Stop trên iPad, hàng nguồn | AC-7 | `source-stop-ipad.json` | **FS-21** sidebar |
| F4 | Duo màn ngoài thấy nguồn (`DC_Sources`) | AC-63 | gập tay trong Simulator.app + `Tools/sim-shot … cover`; máy thật bỏ (Q10) | — |
| F5 | mở chỗ giữ chỗ → tải 1 file | AC-16 | ảnh chụp tay | — |
| F6 | viewer ảnh offline: Edit/Export/Share mờ + câu | AC-12 | ảnh iOS; ảnh Mac | **FS-18** cho nửa Mac |
| F7 | `FolderWatchSettle` (đứng yên 2 s) thuần Domain; adapter FSEvents | AC-8 | `FolderWatchTests.newFilesAppearAfterSettle` | **FS-18** cho adapter + chứng minh |

**Tổng:** 4 (L) + 3 (W) + 8 (A) + 17 (B) + 15 (C) + 8 (D) + 15 (E) + 7 (F) = **77 task**.

## 6. Phụ thuộc giữa các plan

- **FS-19 đi đầu.** Plan khác chờ:
  - **FS-20** (nhập thẻ) chờ A1 (Nguồn, Bản sao, Hash), A4–A5 (bộ băm), B3 (ảnh nhập vào nguồn thư mục).
  - **FS-01.08c** Compare độc lập, trừ phần "trộn nguồn → một hộp" và cờ ảnh file: chờ E1–E6 và A1.
  - **FS-21** iPad: nhóm Sources ở sidebar dùng `SourceStore`/trạng thái nguồn (A1, B13–B17); FS-19 **F3 chờ FS-21**.
  - **FS-18** Mac: dùng lại toàn bộ Domain/Data của FS-19; FS-19 **F6 (nửa Mac), F7 (adapter)** và ảnh chụp tay Mac của
    AC-1, AC-10–AC-14 chờ target Mac.
- Code Domain/Data của FS-19 **không import UIKit** (FS-18 05 §1 dùng chung Domain + Data cho Mac); bookmark tạo với
  tuỳ chọn khác nhau theo nền tảng gói trong `FolderSourceReader`.

## 7. Tài liệu sửa theo (cùng commit với task)

| Tài liệu | Task |
|---|---|
| FS-19 README dòng 28 (board đã có) | **đã sửa** trong lượt plan này |
| FS-19.06: AC-69…72 mới; AC-33 (Q5), AC-56 (Q7), AC-66 (Q4) | A1, A2, E13, E14 · D1, D7, A7 |
| FS-19.04 §3 + AC-73 (board Q1) | **đã sửa** khi duyệt |
| FS-19.04 §2 + AC-41 (huỷ hộp Photos chỉ giữ phần Photos — A7) | E3 |
| BD-02 (mọi dòng §2 của [FS-18 07](../02-functional-spec/FS-18-mac-app/07-spec-deltas.md)) | A1, A3, A6 |
| BD-03 | B3, D1, A8 |
| FS-01.12 AC-9 · §3/§4/§7 | A3 · C5, C3 |
| EX-02 | A7 |
| NF-02 (cache) · NF-03 §2b | W1 · C5 |
| FS-01.12b, FS-06.06b, FS-06.01 | E1 · E6, E10 · E8, E11 |
| FS-07 / 07.01 §2 (popup Source, đếm một lần) | B6, E13 |
| FS-08 README, 02 + FS-21 §4 dòng FS-08.01 | F1, W1 |
| FS-15, FS-17 + FS-21 §1 dòng FS-17, §4 dòng FS-17·FS-15 | D8 |
| FS-03.14b | C15 |
| FS-09 (thư viện trống 3 cách) | **không** ở plan này — FS-21/FS-18 sở hữu màn trống |

## 8. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Dữ liệu:** `eraseDatabaseOnSchemaChange = true` ở DEBUG (`AppDatabase.swift:39`) xoá cả sao/cờ trên máy dev mỗi lần sửa `v30` khi đang làm | cao | chốt hình `v30` ở A1 rồi mới cài lên máy có dữ liệu; mọi bảng sau thêm bằng migration mới, không sửa `v30` |
| **Dữ liệu:** đường lùi migration | thấp | `v30` chỉ **tạo** bảng + backfill, không đổi bảng cũ → lùi = bỏ bảng mới; test `migrate(upTo:)` trên dữ liệu `v29` |
| **Dữ liệu / PhotoKit:** dưới `.limited` walk đầy **xoá** dòng metadata của ảnh không chia sẻ (`IndexPipeline.swift:550-560`); ảnh ẩn trong Photos cũng biến khỏi fetch | cao | bản sao `photos` không mồ côi dưới `.limited`; ảnh **ẩn trong Photos** sẽ mồ côi và bị dọn sau 30 ngày → A3 phải phân biệt (PhotoKit không cho biết) — ghi vào test, hỏi `photokit-guard` trước A3 |
| **Một khái niệm nhiều đường:** 12 chỗ xoá gọi thẳng `metadataStore.deleteAssets`, một đường xoá bỏ qua `onAssetsDeleted` | chắc | E1 gom về `DeletionService`; `component-consistency` quét lại sau E6 |
| **Hiệu năng 55k:** điều kiện hiển thị thêm subquery vào lưới, Statistics, tìm | vừa | K6 + cổng `perf-profiler` ở E7; chỉ mục `copies(photoId, online)`, `photos(orphanedAt)` partial |
| **Bộ nhớ:** băm TIFF/DNG của Photos cần đọc ngẫu nhiên → đệm cả file | vừa | M3 chưa đo (cần máy thật, Q10) — đo đỉnh RAM trên simulator; trần đệm, quá trần thì bỏ qua (giữ hash nhanh). Widget/Share **không** chạy index hay hash (trần extension) — `extension-boundary` kiểm A7 |
| **Concurrency:** hai actor index cùng ghi DB; phiên SMB không chạy song song; `start/stopAccessingSecurityScopedResource` lệch cặp | vừa | K1b + `AsyncGate`; truy cập scoped bọc trong một kiểu có `deinit`; `swift-concurrency` sau B3, D1 |
| **Cloud:** đọc nguồn thư mục qua `NSFileCoordinator` sẽ tải file cloud (`FilesFolderClient.swift:5-9`) | cao nếu tái dùng nhầm | B11: kiểm `ubiquitousItemDownloadingStatus` trước mọi lần mở file |
| **Mạng:** băm ảnh Photos chỉ-iCloud là tải trọn từng ảnh | chắc | A8 theo luật mạng index (`AppDependencies.swift:256-259`), nhường viewer (`IndexInteractionGate`) |
| **Thiết bị:** Duo 669pt cho Settings › Sources, banner đọc nguồn; cover 466 với dải 84 | vừa | F1, F4 qua `device-layout` + `sim-shot` |
| **Privacy manifest:** đọc ngày sửa file (`contentModificationDate`) là API required-reason | chắc | `privacy-manifest` sau B3 (lý do C617.1) |

## 9. Cách chứng minh là xong

- **Test:** mọi tên ở cột Test §5; `/test` từng lớp mỗi task; cả bộ một lần khi xong khối F (luật "full suite once per
  intent"). Server: máy SMB cục bộ như FS-15. Fixture RAW CC0 ở `~/Library/Caches/ShotDexFixtures/raw`, **không mặt người**.
- **Màn hình** (`/screens`, iOS 26.5 + 18.6): `PH_Sources`, `PH_AddSource`, `PH_SettingsSources`, `PH_ServerList`,
  `PH_ServerForm`, `PH_ServerBrowser`, `PH_Hidden`, `PH_DeleteCopies`, `PH_DeletePermanent`; cùng bộ `DI_*` (Duo trong),
  `DC_*` (Duo ngoài, `sim-shot … cover`); iPad `IP_AddSource`, `IP_SourceIndexing`, `IP_Settings`, `IP_Server*`,
  `IP_Hidden`, `IP_DeleteCopies`, `IP_DeletePermanent` (phần không cần sidebar FS-21). `design-parity` mỗi board.
- **Agent ở giai đoạn Deploy:** `data-migration` (A1, A3, A6, E9, E11) · `photokit-guard` (A1, A3, A8, E1–E4, E15) ·
  `swift-concurrency` (B3, D1, C5) · `memory-leak` (A8, W1, C5) · `extension-boundary` (A7) · `perf-profiler` (B6, E7) ·
  `device-layout` + `design-parity` (F1–F4, E6, E8) · `ios26-parity` (F1, E8) · `copy-consistency` (E1–E2, D7, E8, E15) ·
  `ux-reviewer` (E1–E6) · `a11y-voiceover` (trạng thái nguồn) · `privacy-manifest` (B3) · `localization` (mọi chuỗi mới).
- **Tiến độ intent:** coordinator ghi dòng `Tiến độ` của hai intent (plan này không sửa intent).

## 10. Tái dùng — không viết lần hai

`ExifReader.readExif(fromImageAt:)`/`parse`/`exif(fromPartial:)` · `MetadataComposer` + `AssetInfo` (mẫu
`ServerExifExport.swift:13-48`) · luật ghép `ServerFolderListing.contents` · `RemoteFileClient.readRange`/`entries`,
`EmbeddedPreview`, `RemoteThumbnailer` · `AsyncGate`/`ServerBrowseSession` · `KeychainPasswordStore` ·
`FileChecksum.sha256` · mẫu luồng `streamExif` · `PanoramaXMP`/`CGImageSourceCopyMetadataAtIndex` · `LightroomXMPReader` +
`LightroomMapping` · `LossyArray` cho recipe · `TemporaryWorkspace.sweepOrphans` · `DeviceSpaceCheck` + `DiskSpace` ·
`PhotoMarksStore.ratingCondition` (mở rộng, không viết bản thứ hai) · `RejectedDeleter.Outcome` · `DuplicateGrouper` +
cổng "Keep at least one" · gia hạn bookmark của `ExportFolderStore` · nhịp index (`readConcurrency`, `interBatchPause`,
`IndexInteractionGate`) · `TransferRateEstimate`/`IndexThroughput` → một `IndexEstimate`.
