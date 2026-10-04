# FS-19 — Bảng đối chiếu AC ↔ code

Thuộc [kế hoạch FS-19](2026-10-04-fs19-photo-sources.md). Đường dẫn tính từ `ShotDex/` trừ khi ghi khác. "Task" trỏ số ở
§5 của kế hoạch. **Tổng: 0 ✅ trọn · 13 ⚠️ · 55 ❌ · 1 ❓** (68 AC + AC-73 của planboard mac-ipad-v2 Q1); 4 AC ❌ có một phần ✅ được khoá test trước (L1–L4);
đề xuất thêm AC-69…AC-72 (cuối bảng).

Nền chung cho mọi dòng ❌ dưới đây (khỏi chép lại):
- **Không có khái niệm nguồn, bản sao, hash nội dung, sidecar:** grep `photo_copies|PhotoCopy|orphan|FSEventStream|trashItem|
  skipsPackageDescendants|ubiquitousItemDownloadingStatus|isExcludedFromBackup` = 0 dòng trong app (trừ `orphan` ở
  `WidgetShared/PhotoWidgetSettings.swift`, nghĩa khác). Mọi bảng khoá theo `assetId` = `PHAsset.localIdentifier`
  (`Data/Database/AppDatabase.swift:42-661`, `Core/Models/PhotoMetadata.swift:16`).
- **Index chỉ biết PhotoKit:** `actor IndexPipeline` (`Domain/Indexing/IndexPipeline.swift:46`) nhận `[PHAsset]`
  (`:1001`), fetch `PHAsset.fetchAssets` (`:430`, `:647-653`), không protocol nguồn nào.
- **Đọc file lẻ đã có và tái dùng được:** `ExifReader.readExif(fromImageAt:)` (`Data/Sources/ExifReader.swift:722-732`),
  `parse(properties:source:)` (`:742-768`), đọc phần đầu file `exif(fromPartial:)` (`:705-718`); `MetadataComposer.compose`
  thuần với `AssetInfo` (`Domain/Indexing/MetadataComposer.swift:57-87`) — mẫu dựng không cần PHAsset có sẵn ở
  `ServerExifExport.swift:13-48`. Thiếu: `RawExif` không mang ngày chụp/GPS/kích thước (PhotoKit cấp các trường này).

## Thư mục và ổ (01, 01b)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 2.118 ảnh, ghép cặp, 0 byte đổi | ❌ | không có nguồn thư mục; ghép cặp có cho server, thuần Domain: `Domain/ServerImport/ServerFolderListing.swift:90-125` (RAW + {jpg, jpeg, heic, heif} cùng tên gốc, `:80`, nhãn `ServerPhoto.badge` `:34-38`) | B3; **tái dùng** luật ghép (dời ra `Domain/Sources/PairingRule`, server và thư mục cùng gọi). Ảnh chụp tay Mac → FS-18 |
| AC-2 tắt ghép → 4.118; `DSC0001.JPG.xmp` | ❌ | như trên + không có sidecar (grep `xmp` chỉ ra preset Lightroom, `Domain/Editing/LookExchange/LightroomXMPReader.swift:21`) | C6 |
| AC-3 bật thư mục con → +150, 0 đọc lại | ❌ | không client nào liệt kê đệ quy (`SMBFileClient.swift:203`, `FilesFolderClient.swift:137` một tầng) | B4 |
| AC-4 bỏ gói Photos Library và file `.` | ❌ | không có `FileManager.enumerator`; `.skipsHiddenFiles` chỉ ở widget/LookInbox (`App/Widgets/PhotoWidgetSnapshotWriter.swift:65`) | B1 |
| AC-5 "Estimating time…" tới file 200, "about 3 min left" | ⚠️ | ETA của index Photos là `IndexThroughput` (`Features/Library/LibraryModel.swift:7-50`, `:1076-1098`): trung bình **cả lượt**, có số ngay sau 1 s, chữ "About M min left" (`:37-48`), không có "Estimating time…"; `TransferRateEstimate` (`Domain/Shared/TransferRateEstimate.swift:6-34`) cửa sổ 30 s theo byte, chỉ Export dùng | **Câu hỏi Q1**. W3 |
| AC-6 Pause, tắt app, Resume → đọc đúng 2.572 | ❌ | pipeline không đọc lại cursor để chạy tiếp (chỉ diff `needsReindex` `IndexPipeline.swift:325-340`; cursor chỉ `BackgroundIndexService.swift:140` đọc); không có Pause cho người dùng (chỉ chờ tự động `:178-248`) | B5 — điểm chạy tiếp lưu ở bảng Nguồn |
| AC-7 iPad Stop → banner đi cùng khung hình; hàng nguồn "1,240 of 3,812 read" + Continue | ❌ | chỉ có Cancel (`Features/Library/LibraryScreen.swift:1068-1070`, `Features/Settings/SettingsScreen.swift:731`) | F3 — **chờ FS-21** (hàng nguồn ở sidebar iPad) |
| AC-8 Mac, 12 JPG mới ≤ 10 s, file chép dở không thành ảnh hỏng | ❌ | không có theo dõi file (grep FSEvents/DispatchSource/NSFilePresenter/NSMetadataQuery = 0) | F7 — luật "đứng yên 2 s" thuần Domain làm ở FS-19, adapter FSEvents + chứng minh **chờ FS-18** |
| AC-9 iPad về trước mặt → +12, 0 đọc lại | ❌ | không có lượt so lệch cho thư mục | F2 |
| AC-10 rút T7 giữa lượt đọc → giữ 1.240, nguồn sau chạy tiếp | ❌ | — | B14 (logic + test iOS); ảnh Mac → FS-18 |
| AC-11 cắm lại ≤ 5 s, đọc từ 1.241 | ❌ | — | B15 |
| AC-12 ảnh offline: preview cache, Edit/Export/Share mờ + câu | ❌ | — | F6 (viewer iOS); ảnh chụp tay Mac → FS-18 |
| AC-13 bookmark hết hạn → Needs access, ảnh ở lại | ❌ | chưa có nguồn; client Files của FS-17 **bỏ qua** `isStale` (`Data/Sources/FileServer/FilesFolderClient.swift:26-27`), bookmark tạo **không** `.withSecurityScope` (`Features/ServerImport/OnCloudScreen.swift:185`); mẫu gia hạn đúng có ở `Data/Sources/FileExport/ExportFolderStore.swift:83-98` | B16 — tái dùng mẫu của `ExportFolderStore`, không mẫu của `FilesFolderClient` |
| AC-14 Grant Access → cùng id, ★ giữ | ❌ | — | B17 |
| AC-15 iCloud Drive 40 chỗ giữ chỗ → 0 byte tải | ❌ | không kiểm `ubiquitousItemDownloadingStatus`; `FilesFolderClient` đọc qua `NSFileCoordinator` — thứ **tải** file cloud về (`FilesFolderClient.swift:5-9`, `:69-86`) | B11 — **không** đọc nguồn thư mục qua `FilesFolderClient` |
| AC-16 mở chỗ giữ chỗ → tải 1 file, tiến độ + Cancel | ❌ | — | F5 (ảnh chụp tay) |
| AC-17 ổ cache đầy → metadata đủ, 0 preview, dòng báo | ❌ | — | B12 |
| AC-45 thư mục nằm trong/chứa nguồn → từ chối | ❌ | — | B2 (`SourceOverlap`, thuần) |
| AC-46 Hide Its Photos → lưới −26.057, 50 ở lại | ❌ | — | B13 |
| AC-47 cache ở Application Support, loại khỏi backup, 25 GB Mac / 5 GB iPad | ⚠️ | cache thumbnail server ở **Caches**/`ServerThumbnails` (`Data/Sources/FileServer/RemoteThumbnailCache.swift:53-56`), trần **500 MB** (`:47`), không cờ backup; một cache riêng của FS-17 (`App/AppDependencies.swift:438`) | **Câu hỏi Q2**. W1 |

## Danh tính và sidecar (02)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-18 50 file giống hệt ở 2 nguồn → +50, "2 copies", Statistics +50 | ❌ | Statistics đếm thẳng `photo_metadata` (`Data/Database/StatisticsQueries.swift:30-35`), không bộ lọc nguồn | B6 (+ test 05 §8.6) |
| AC-48 hash nhanh trùng không bao giờ gộp | ❌ | hash duy nhất trong app là SHA-256 cả file (`Domain/ServerUpload/RemoteFileClient.swift:140-158`) và dHash (`Data/Sources/PerceptualHashReader.swift:16-46`) | A5 |
| AC-49 băm ảnh Photos: tải 1 lần, đĩa ± 1 MB | ❌ | không hash dữ liệu `PHAssetResource`; mẫu luồng có sẵn: `ExifReader.streamExif` (`ExifReader.swift:426-650`, `requestData` `:484`) | A8 — tái dùng mẫu luồng + watchdog |
| AC-50 thứ tự mở bản sao; Photos có Done, T7 "Edited · Saved" | ❌ | `PhotoEditOrigin` chỉ `.asset` / `.serverFile` (`Features/Editing/PhotoEditOrigin.swift:11-12`); phiên server **không nhớ recipe** (`Data/Sources/PhotoEditingService.swift:216-245`) | E12 + K5 |
| AC-19 ★4 → `.xmp` ở mọi bản online ≤ 2 s; ảnh không đổi | ❌ | — | C5 (+ NF-03 §2b) |
| AC-20 đổi tên → cùng id, ★4 | ❌ | — | B7 (+ test 05 §8.5) |
| AC-21 chuyển sang T7 → ★ và recipe giữ | ❌ | — | B8 |
| AC-22 XMP nhúng vào JPEG → hash không đổi | ❌ | — | A4 (bộ băm theo định dạng, K2) |
| AC-51 mồ côi 30 ngày, Put Back về cùng id | ⚠️ | dấu bị gỡ **ngay**: `UserMarkRemovalPolicy` (`Domain/Marks/UserMarkRemovalPolicy.swift:12-29`) nối ở `App/AppDependencies.swift:349-357` → `PhotoMarksStore.deleteMarks` (`Data/Database/PhotoMarksStore.swift:210-220`); FS-01.12 AC-9 hiện nói thế | **Câu hỏi Q3**. B10 |
| AC-64 file bị ghi đè khi bản khác giữ ảnh cũ → tách | ❌ | — | B9 |
| AC-65 gộp va chạm ở mọi bảng vệ tinh | ❌ | có sẵn dấu thời gian cho luật "đổi sau thắng": `photo_flag.flaggedAt`, `pending_photo_rating.ratedAt` (`AppDatabase.swift:602-613`); favorite Photos không có giờ đổi | A6 (+ test 05 §8.3) |
| AC-66 widget và smart album trỏ id thua | ❓ | widget lưu id ở nhiều chỗ (`WidgetShared/PhotoWidgetSettings.swift:54-58`, `:695-712`; `WidgetShared/OnThisDaySnapshot.swift:14-19`; `WidgetShared/WidgetPhotoCatalog.swift:11-24`), ảnh render bằng PhotoKit trong app (`App/Widgets/WidgetImageRenderer.swift:36-64`); **smart album không lưu id nào** (`Core/Models/SmartAlbumQuery.swift:293-327`) — nửa "smart album" của AC không có đối tượng. Chỗ khác lưu id: Recents (`Data/Sources/RecentActivityStore.swift:19-49`), `PanoramaSaveRecord` (`Core/Utils/PanoramaSaveRecord.swift:17-31`), bộ đếm tên file (`Data/Sources/PhotoOutputFilenameIndexStore.swift:46`) | **Câu hỏi Q4**. A7 |
| AC-23 sidecar Lightroom: ★≥3 → 45, Rejected → 30, "Kyoto" → 80 | ❌ | không đọc sidecar; lọc keyword chỉ đọc gương Photos `photo_keyword` (`Data/Database/SmartAlbumSQLBuilder.swift:167-179`, `:262-271`) | C1 |
| AC-24 sidecar thắng XMP nhúng | ❌ | XMP nhúng chỉ đọc cờ panorama (`ExifReader.swift:766`, `ShotDexKit/Render/Panorama/PanoramaXMP.swift:41`) | C2 — tái dùng `CGImageSourceCopyMetadataAtIndex` |
| AC-52 sao máy ảnh: file ★3, asset Photos ★0 | ❌ (một phần ✅) | ✅ asset Photos không đọc sao trong file: `parse` không đọc Rating (`ExifReader.swift:742-768`), sao chỉ từ `PHAsset.rating` (`Data/Sources/PHAsset+StarRating.swift:8-13`); ❌ `MakerNoteParser` chỉ đọc số shutter (`Domain/Metadata/MakerNoteParser.swift:24`) | L3 khoá nửa Photos; C3 |
| AC-53 Import Lightroom Edits chỉ khi bấm | ❌ | bảng quy đổi có sẵn: `Domain/Editing/LookExchange/LightroomMapping.swift`, `LightroomXMPReader.swift:21` (đọc preset) | C15 — tái dùng, không viết bảng thứ hai |
| AC-25 thêm "deer" → mọi thẻ khác giống từng byte | ❌ | — | C4 (K3) |
| AC-26 đọc lại sidecar trước khi ghi | ❌ | — | C7 |
| AC-54 X/U/favorite/recipe vào sidecar, iPad đọc ra như nhau | ❌ | — | C10 |
| AC-27 cùng trường: bên đổi sau thắng | ❌ | — | C8 |
| AC-28 hai sidecar khác nhau lúc index → mới hơn thắng | ❌ | — | C9 |
| AC-29 bản offline → dấu chờ, sống qua Clear | ❌ | — | C11 |
| AC-30 cắm lại → ghi giá trị hiện hành 1 lần | ❌ | — | C12 |
| AC-31 sidecar tắt → 0 `.xmp`, lọc ra 10, Clear vẫn 10 | ❌ (một phần ✅) | ✅ Clear giữ sao/cờ: `MetadataStore.deleteAll` chỉ xoá metadata + gương (`Data/Database/MetadataStore.swift:372-385`, chú thích `:377`) | L4 khoá; C13 |
| AC-32 ổ chỉ đọc → 3 dấu chờ + dòng báo | ❌ | — | C14 |

## Server (03)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-33 NAS 1.102 RAW: byte tải ≤ 1.102 × (256 KB + 3 × 64 KB) | ⚠️ | đọc dải có ở cả 4 client (`SMBFileClient.swift:216-237`, `SFTPFileClient.swift:205-229`, `WebDAVFileClient.swift:141-158`, `FilesFolderClient.swift:185-195`); thang thumbnail `RemoteThumbnailer.swift:61-91`: 256 KB rồi **1 MB với mọi RAW**, RAF tới 8 MB, file thường ≤ 25 MB tải **cả file**. Spec tự mâu thuẫn: 03 §2 cho "tối đa 1 MB với RAW khác", AC đặt trần 448 KB | **Câu hỏi Q5**. D1 |
| AC-34 mở ARW 48 MB → preview ngay, bản gốc vào tmp, rời viewer → tmp rỗng | ❌ | tái dùng được: tmp `ShotDexServerEdit-*` + xoá khi đóng công cụ (`Features/ServerImport/ServerPhotoCommands.swift:92-95`, `:211-216`), dọn lúc mở app (`Core/Utils/TemporaryWorkspace.swift:19-64`), kiểm chỗ `DeviceSpaceCheck.shortfall` (`Domain/ServerImport/ServerEditFetch.swift:53-63`); viewer lớn của FS-17 **không** tải bản gốc (`Features/ServerImport/ServerBrowserScreen.swift:1049-1060`) | D6 |
| AC-35 server tắt → "Not reachable", thumbnail cache, câu viewer | ❌ | — | D5 |
| AC-36 mật khẩu đổi → "Password rejected", 0 hộp hỏi | ❌ (một phần ✅) | ✅ `RemoteFileError.authenticationFailed` dừng lô (`Domain/ServerUpload/RemoteFileClient.swift:90`, `:106`), không có hộp mật khẩu tự bật (`ServerBrowserScreen.swift:165-172`, `Features/ServerUpload/ServerSignIn.swift:25-41`); ❌ trạng thái trên hàng nguồn | L1 khoá; D4 |
| AC-37 cache 5 GB: bỏ preview trước thumbnail, không pane server riêng | ⚠️ | cache server riêng, LRU theo ngày sửa file, một loại (`RemoteThumbnailCache.swift:106-124`, `:149-151`) | **Câu hỏi Q2**. W2 |
| AC-38 Rescan → +5, 0 đọc lại | ❌ | `entries(in:)` có size + `modified` (`Domain/ServerImport/ServerFolderListing.swift:6-12`) — đủ để so | D2 |
| AC-55 2 giờ không bấm → 0 lệnh liệt kê | ❌ | — | D3 |
| AC-39 iPhone: nguồn NAS · 1,102; không Import to Library; Save to Photos | ⚠️ | Import to Library có ở mọi thiết bị: `Features/Shared/PhotoCommand.swift:42`, `ServerBrowserScreen.swift:433-434`, sheet `Features/ServerImport/ServerDownloadSheet.swift:60`; đường tạo asset `Data/Sources/FileServer/PhotoKitAssetCreator.swift:9-38`; không có "Save to Photos" cho server | **Câu hỏi Q6**. D8 |
| AC-56 upload 20 ảnh → "2 copies"; câu "They stay in ShotDex from NAS Home." | ⚠️ | không có chữ "Free Up Space"; lệnh là "Delete N from This Device" (`Features/ServerUpload/ServerUploadSheet.swift:325`, tiêu đề `:89`, lời `:69`; `UploadedToServerScreen.swift:69-86`); upload ghi `server_uploads` theo assetId sau kiểm SHA-256 (`Domain/ServerUpload/ServerUploadSession.swift:248-283`) | **Câu hỏi Q7**. D7 |

## Xoá, ẩn, trùng, album, thống kê (04, 05)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-40 hộp "Move 120 rejected photos?" đếm theo nơi đến | ⚠️ | mọi lệnh xoá là `PHAssetChangeRequest.deleteAssets` (`Data/Sources/PhotoLibraryService.swift:967-981`), hộp hệ thống là xác nhận duy nhất (`Data/Sources/RejectedDeleter.swift:4-5`); tên "Delete N Rejected…" (`Domain/Marks/MarkCopy.swift:152-153`) | **Câu hỏi Q8**. E1 |
| AC-41 Cancel ở hộp Photos → 0 file đi | ❌ (một phần ✅) | ✅ `.userCancelled` → `.cancelled`, không đổi gì (`RejectedDeleter.swift:24-25`) | L2 khoá; E3 |
| AC-42 84 vào Thùng rác kèm JPEG cặp + `.xmp`; 6 ẩn | ❌ | grep `trashItem` = 0 | E4 |
| AC-43 toàn NAS → "Hide 6 photos?" | ❌ | — | E2 |
| AC-57 xoá trong nguồn T7 chỉ đụng bản T7; All Photos có danh sách tick | ❌ | — | E5 |
| AC-58 ổ không Thùng rác → hộp đỏ thứ hai | ❌ | — | E6 |
| AC-59 mục Hidden, Unhide | ⚠️ | "Hide" hôm nay là ẩn **của Photos** (`Data/Sources/PhotoLibraryService+Assets.swift:35-43`; hộp "Hide this photo?" … "moves to the Hidden album in Photos" `Features/Library/PhotoDetailScreen.swift:3153-3167`; toast `App/AssetActionsCoordinator.swift:126-142`); Collections không có mục Hidden (`Features/Albums/AlbumsModel.swift:333-348`) | đã chốt (mac-ipad-v2 Q1): hai lệnh Hide in Photos · Hide in ShotDex Only → AC-73. E8 |
| AC-73 Hide in Photos · Hide in ShotDex Only trên ảnh có bản Photos + bản NAS | ❌ | một lệnh Hide, chỉ ẩn trong Photos (`PhotoDetailScreen.swift:3153-3167`, `PhotoLibraryService+Assets.swift:35-43`) | E15 |
| AC-67 mồ côi 31 ngày: gỡ hết trừ 3 lịch sử | ⚠️ | như AC-51: gỡ ngay, không đếm ngày; lịch sử upload/tải về sống lâu hơn ảnh đã đúng (`server_uploads`/`server_downloads` không khoá ngoại tới ảnh, `AppDatabase.swift:463-503`) | **Câu hỏi Q3**. A3 (+ test 05 §8.4) |
| AC-68 ảnh ẩn khi và chỉ khi mọi bản sao ẩn | ❌ | — | E7 |
| AC-44 Exact "2 identical copies … both on T7"; không nhóm gồm bản NAS | ⚠️ | `duplicate_groups` khoá (strictness, assetId), `duplicate_scan_state` theo strictness (`AppDatabase.swift:258-274`, ghi `Data/Database/PerceptualHashStore.swift:161-180`); Exact = dHash trùng, không phải hash nội dung (`Domain/Duplicates/DuplicateGrouper.swift:27-38`, `:90`) | **Câu hỏi Q10**. E9 (+ test 05 §8.7) |
| AC-60 Merge ảnh file: chỉ sao, cờ, keyword | ⚠️ | Merge cho mọi ảnh nhận favorite + vị trí + ngày sớm nhất qua PhotoKit (`Features/Duplicates/DuplicatesModel.swift:572-606`, câu hộp `Features/Duplicates/DuplicatesScreen.swift:364`) | **Câu hỏi Q11**. E10 |
| AC-61 album ShotDex 5 ảnh, hàng album Photos mờ | ⚠️ | album chỉ PhotoKit: `AddToCollectionSheet.swift:124-139` → `PhotoLibraryService.swift:1088-1110`; không bảng album của app | **Câu hỏi Q12**. E11 |

## iPhone và Duo

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-62 iPhone: Settings › Sources → thêm "Kyoto" → 300 ảnh, ★4 → `.xmp` | ❌ | Settings có trang "Photo Library" (`Features/Settings/SettingsSection.swift:100`, `SettingsScreen.swift:560-615`), không có Sources | F1 (+ FS-08 "Photo Library" → Sources) |
| AC-63 Duo gập → màn ngoài thấy nguồn và 300 ảnh | ❌ | — | F4 (gập tay trong Simulator.app; máy thật bỏ — mac-ipad-v2 Q10) |

## Đề xuất AC mới (thêm vào 06 cùng commit của task: A1 → AC-69, A2 → AC-70, E13 → AC-71, E14 → AC-72)

| AC | Cho · Khi · Thì | Vì sao | Chứng minh đề xuất |
|---|---|---|---|
| AC-69 | DB ở `v29` có 300 dòng `photo_metadata`, 40 cờ + 12 sao chờ của ảnh **không** có dòng metadata (`.limited`), 3 dòng `server_uploads` · chạy migration FS-19 · bảng Ảnh = hợp mọi id (≥ 340 + id của upload), mỗi ảnh 1 bản sao kind `photos` cùng id; 0 dòng vệ tinh đổi khoá | 05 §8 test 1 chưa có AC | `PhotoSourcesMigrationTests.backfillsUnionOfIds` |
| AC-70 | ảnh file ★4, cờ, keyword, recipe, ẩn 1 bản sao, trong album ShotDex · index lại toàn bộ, rồi Clear Local Metadata Index · mọi giá trị còn; Ảnh, Bản sao (id, cột ẩn), Hash, Nguồn, bí danh còn | 05 §8 test 2 + 05 §7 | `PhotoSourcesMigrationTests.userDataSurvivesReindexAndClear` |
| AC-71 | ảnh A có bản ở T7 và NAS, ảnh B chỉ Photos · Statistics popup Source: All / T7 / NAS · All đếm 2, T7 1, NAS 1; chú thích "Each photo counted once across sources" | README FS-19 dòng 208 hẹn thêm ở `/plan` | `StatisticsSourceTests.countsOncePerSource` |
| AC-72 | nhóm trùng ở T7 và ở Photos · Duplicates popup Source = T7 · chỉ nhóm của T7 | như trên | `DuplicateSourceScopeTests.sourcePopupFilters` |
