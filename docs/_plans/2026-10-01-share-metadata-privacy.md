# Kế hoạch — Metadata khi chia sẻ và xuất (FS-08.06)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-08.06`](../02-functional-spec/FS-08-settings/06-share-metadata-privacy.md) — 22 AC (AC-22 thêm khi duyệt) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 3 · [NF-03 §3](../04-non-functional-design/NF-03-privacy-and-security.md) |
| Ngày | 2026-10-01 |
| Trạng thái | **đã duyệt 2026-10-01** — 24 task (22 của bản nháp + task 6 cho ❓-2 + task 19 cho AC-22). Quyết định ở §7; còn một cổng đo (HEIC No Metadata, task 2) và mẫu RAW (❓-5) |

## 1. Hiểu đúng chưa

Một cài đặt ba mức (**All Metadata** · **No Location** · **No Metadata**) thay công tắc Include Location, làm mặc
định cho mọi lối ra: Share (mọi màn), Share ảnh server, đích Share của sheet xuất server, Save Copy, Paste Edits,
Resize, kéo sang app khác. Share đổi mức cho một lần bằng hai dòng hành động của app trong share sheet, phụ đề nói
mức đang áp. File ảnh được **ghi lại không giải mã** (chỉ thay bộ metadata); ghi lại lỗi thì **không bao giờ** giao
nguyên bản — RAW: mẻ share hỏi một lần, kéo thả thì render JPEG; ảnh khác: bỏ khỏi mẻ và nêu tên. Video luôn đi
nguyên bản và app nói rõ. Share sheet mở ngay (luật FS-02.06 §9): gom từng ảnh ra file tạm **sau khi chọn đích**,
tải iCloud rồi ghi lại trong cùng một modal có Cancel, xoá sạch khi share sheet đóng. Asset đã bị xoá vị trí thì
GPS của file cũng bị bỏ, kể cả ở All Metadata. Kéo ảnh đã chỉnh giao bản đã chỉnh, như Share. Riêng **Save Changes** không bao giờ đổi ngày hay vị trí của asset — code hôm
nay xoá cả hai, đây là lỗi mất dữ liệu nên làm **đầu tiên**.

## 2. Đối chiếu AC ↔ code

Sau khi duyệt không còn dòng ⚠️: các câu ở §7 đã có quyết định, cột Việc ghi theo quyết định đó. Chỗ code làm
ngược mà spec đã phán là lỗi (AC-17) ghi ❌.

**Đo trước khi viết bảng** (script tạm trên macOS 27.0, ImageIO, ảnh 512×384 nhiễu, Display P3, GPS + TIFF + EXIF +
IPTC + MakerApple + orientation 6):

| Cách ghi lại | JPEG | HEIC |
|---|---|---|
| `CGImageDestinationAddImageFromSource` (cách `stripLocation` đang dùng) | **mã hoá lại**: 239 679 → 184 634 byte, pixel giải mã **khác**; GPS đi; XMP `photoshop:City` **còn** | mã hoá lại: 161 917 → 108 260 byte, pixel khác; `photoshop:City` còn |
| `CGImageDestinationCopyImageSource` + metadata đã sửa, mức No Location | pixel **trùng**, GPS đi, City đi, Make/Rating/Artist/Copyright còn | pixel **trùng**, như JPEG |
| `CopyImageSource`, mức No Metadata (metadata mới chỉ còn orientation/Artist/Copyright, `MergeMetadata=false`, `ShouldExcludeGPS`, `ShouldExcludeXMP`) | pixel trùng, ICC còn, orientation 6 còn; EXIF, GPS, MakerApple **đi**; IPTC chỉ còn Byline + Copyright | pixel trùng, ICC còn; GPS, MakerApple đi — nhưng **`DateTimeOriginal` và IPTC City/StarRating vẫn còn** |

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 No Location từ lưới: không GPS, còn Make/ISO/ngày, pixel trùng | ❌ | `PhotoShareSheet.swift:26` gọi `stripLocation` (`:42-79`) → `AddImageFromSource` `:74` **mã hoá lại** (đo ở trên); IPTC City chỉ bị null trong dictionary `:61` nên còn trong XMP; ghi lỗi thì `?? data` `:26` **giao nguyên bản có GPS**; test `thePictureItselfIsUntouched` chỉ so kích thước nên không bắt được; `garbageInGivesNothingBack` khoá đúng hành vi rò | `MetadataRewriter` không giải mã (`CopyImageSource`) + ghi lỗi thì không bao giờ rơi về bản gốc (Q1) |
| AC-2 Share Without Metadata: bỏ EXIF/GPS/ngày/MakerNote, giữ orientation/ICC/Artist/Copyright; Settings không đổi | ❌ | không có mức No Metadata, không có dòng hành động (`present` `:95` truyền `applicationActivities: nil`); HEIC: `CopyImageSource` để sót ngày chụp + City (đo ở trên) | mức No Metadata trong `MetadataRewriter`; HEIC còn sót hay không quyết sau phép đo task 2 (cổng, ❓-1); dòng hành động ở task AC-7/AC-20 |
| AC-3 All Metadata → SHA-256 trùng file gốc | ✅ (ảnh chưa sửa) | `:26` truyền nguyên `data` khi bật vị trí; `requestImageDataAndOrientation` `:108-119` trả byte của bản hiện hành | test khoá qua seam (task 3); vế 2 của AC-3 (asset đã Remove Location → bỏ GPS của file kể cả ở All, ❓-2) là ❌: `PhotoLibraryService+Assets.swift:95` chỉ sửa `asset.location`, file vẫn mang GPS cũ — làm ở task 6 |
| AC-4 JPEG Lightroom: GPS trong EXIF + XMP, IPTC City, Rating 4 | ❌ | `stripLocation` null `IPTCCity` trong dictionary nhưng XMP `photoshop:City` sống sót (đo); không đụng `Iptc4xmpCore:Location`/`photoshop:State`/`Country` trong XMP | xoá theo đường dẫn XMP trong `MetadataRewriter` + test trên JPEG có XMP |
| AC-5 Photo Detail share giống lưới | ❌ | `PhotoDetailScreen.swift:1123-1136` tự gọi `requestImageDataAndOrientation` với `isNetworkAccessAllowed = false` `:1125`, **bỏ qua cài đặt vị trí** (rò toạ độ hôm nay), ảnh chỉ trên iCloud ra *Unable to Share* | đi chung pipeline **ngay** (Q2); ảnh chỉ trên iCloud tạm giữ *Unable to Share* tới khi FS-02.06 task 14 thay bằng sheet mở ngay + modal |
| AC-6 MOV + ảnh A, No Location: phụ đề *Videos keep their metadata*; MOV nguyên byte | ❌ | MOV đi nguyên URL `:24`, `:121-130` (đúng); ảnh bị gỡ (đúng một phần); không có phụ đề | phụ đề qua `UIActivityItemSource` |
| AC-7 phụ đề *Location removed*; đúng hai dòng của app | ❌ | không có `UIActivity`/`UIActivityItemSource`/`LPLinkMetadata` nào trong `ShotDex/` | `ShareMetadataActivity` + nguồn item có metadata xem trước |
| AC-8 Live Photo → 1 item, ảnh tĩnh không GPS | ✅ | `gather` rẽ theo `mediaType` `:23`; Live Photo là `.image` → chỉ ảnh tĩnh `:25-26` | test khoá qua seam (task 3) |
| AC-9 2 ARW + A: một alert, Skip → 1 file | ❌ | không phân biệt RAW; ARW qua `stripLocation` ra `nil` (ImageIO không ghi RAW) → `?? data` **giao ARW có GPS** | `ShareBatchPlan` (Domain) đếm RAW + alert |
| AC-10 20 ảnh: 0 GPS; đỉnh RAM không tăng theo số ảnh | ❌ | `gather` giữ cả mẻ `Data` trong `items` `:21-29`; `imageData` tải cả file vào RAM | gom từng ảnh ra file tạm (`PHAssetResourceManager.writeData`), nguồn ghi bằng URL |
| AC-11 Cancel lúc gom: không share sheet, thư mục tạm rỗng | ❌ | nút Share chỉ có spinner `SelectionBarViews.swift:68-69`, `LibraryScreen.swift:399-408`; `gather` không kiểm huỷ; không có thư mục tạm | huỷ + dọn trong pipeline; Cancel nằm trong **modal giữa màn của FS-02.06** (task 10 của plan FS-02.06) — share sheet mở ngay, gom sau khi chọn đích |
| AC-12 Save Copy No Location: file không GPS, vị trí asset rỗng, ngày giữ, Make/Model còn | ❌ | công tắc hai mức `PhotoEditorScreen.swift:3597,3608`; tắt thì `renderer.write` ghi `[:]` (`PhotoRenderService.swift:709`) và `saveCopy` bỏ cả ngày lẫn vị trí (`PhotoEditingService.swift:363-366`) | `MetadataLevel` vào kit `write`; ngày/vị trí asset theo mức; picker 3 mức chỉ trong section Save Copy (Q3) |
| AC-13 NAS RAF + JPG, No Location, Skip → JPG không GPS; RAF không đi; dọn tạm | ❌ (JPG ✅) | `ServerPhotoHandoff.shareFiles` `ServerPhotoCommands.swift:27-38`: JPG gỡ được (test `shareHandsOriginalAndCleansUp`); RAF `stripLocation` ra nil → `return fetched.url` `:34` **giao RAF có GPS**; dọn: `closeTool` → `discardCopies` `:209-214` | cùng alert RAW + `MetadataRewriter` |
| AC-14 Save to ShotDex 40 HEIC: < 120 MB, SHA-256 trùng | ✅ | `ShareViewController.swift:73-76` từng file một; `:84-99` `addResource(with:.photo, fileURL:)`, không đụng metadata; `loadFileRepresentation` chép ra file `:104-123`, không giữ `Data` | không sửa code; đo trên simulator (task 4). Bản chép tạm `:113-116` không bao giờ bị xoá → `REVIEW_QUEUE.md`, ngoài AC |
| AC-15 Share as JPEG: 3 file, 0 GPS, còn Make | ❌ | — | render RAW đủ cỡ bằng `PhotoEditingService.writeRender` `:554-569` + lọc metadata theo mức |
| AC-16 Share RAW with Location: 2 ARW nguyên byte + A không GPS | ❌ | — | nhánh của alert |
| AC-17 Save Changes: không lựa chọn metadata; ngày + vị trí asset giữ nguyên | ❌ (code làm ngược — spec §4 đã phán là lỗi) | `commit` `PhotoEditingService.swift:765-778` gán `creationDate = nil`, `location = nil` khi tắt Include Metadata `:773-776`; file render cũng mất EXIF `:457-462`; Live Photo `:426-438`; batch `EditorBatchSaver.swift:146-153`; sheet áp công tắc cho Save Changes `PhotoEditorScreen.swift:3664-3670`, footer `:3618` hứa xoá | **task 1**; AC đọc lại thành "Save Changes bỏ qua picker", footer nói Save Changes giữ mọi thứ (Q3) |
| AC-18 Resize + Paste Edits mở ở No Location; asset mới không GPS | ❌ | `CompressionController.swift:26` `includeMetadata = true` cứng, toggle `CompressionScreen.swift:297-317`; Paste Edits `EditorBatchSaver.swift:310,322`; `createFlatAsset` `PhotoEditingService.swift:780-805` bỏ cả ngày lẫn vị trí | segmented 3 mức + picker 3 mức, đọc mặc định Settings |
| AC-19 kéo A sang Files, No Location | ❌ | `PhotoDragItem.swift:99-123` ghi resource `.photo` nguyên byte, không đọc cài đặt | qua cùng pipeline với Share: ảnh đã chỉnh kéo ra **bản đã chỉnh** (❓-3) |
| AC-20 *Share With Location* → mở lại, phụ đề *All metadata*, Settings không đổi | ❌ | — | activity đóng → gom lại → `present` lại |
| AC-21 kéo ARW, No Location → JPEG đủ cỡ, không alert | ❌ | `PhotoDragItem.swift:30-37` đăng ký đúng kiểu ARW | đăng ký `public.jpeg` + render khi mặc định ≠ All |

| AC-22 *(thêm khi duyệt)* đích Share của sheet xuất server, No Location → bản render không GPS, còn Make/Model | ❌ | `ServerExportModel.swift:273` render với `includeMetadata: true` và `ServerExportSheet.swift:43` đưa thẳng file đó vào share sheet, nên ảnh mang toạ độ dù Settings = No Location | render theo `MetadataLevel` của Settings + hai dòng hành động như share thường (❓-4) |

**Tổng:** ✅ 3 (AC-3 vế 1, AC-8, AC-14) · ❌ 19.

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `PhotoShareSheet.present` (`:84-106`, neo popover iPad, `onFinished`) | giữ một chỗ trình chiếu; thêm `applicationActivities` + nguồn item chỉ cho share ảnh — share LUT/CSV/look (`EditorToolPanels.swift:177`, `LibraryScreen.swift:632`, `ServerBrowserScreen.swift:657`) không có dòng mức |
| `TemporaryWorkspace` (`Core/Utils/TemporaryWorkspace.swift`) — tiền tố + quét lúc mở app | tiền tố mới `ShotDexShare-` cho thư mục gom |
| `PhotoEditingService.writeRender` `:554-569` (render đủ cỡ ra file) | RAW → JPEG cho Share as JPEG và kéo RAW |
| `PhotoRenderService.write` (kit) `:683-718` | nhận `MetadataLevel` thay `Bool` |
| `ServerFolderListing.isRAW(_:)` `Domain/ServerImport/ServerFolderListing.swift:82` | nhận diện RAW ảnh server; RAW của asset theo `PHAssetResource.uniformTypeIdentifier` (`.rawImage`), như `PhotoEditingService.sourceOptions` `:653-733` |
| `ServerPhotoHandoff.shareFiles` + `ServerEditHandoffTests` | giữ hình dạng; đổi `includesLocation: Bool` → `MetadataLevel` |
| `ShareLocationStrippingTests` | chuyển thành `MetadataRewriterTests`; sửa `thePictureItselfIsUntouched` thành so pixel, xoá `garbageInGivesNothingBack` (khoá đúng hành vi rò) |
| `FocusStackExportTests` (đo footprint khi process yên) | mẫu đo đỉnh RAM cho AC-10 |
| FS-02.06 §9: share sheet mở ngay + modal giữa màn *Downloading from iCloud · % · MB* + Cancel | AC-11 dùng chung modal đó; ghi lại metadata chạy trong cùng pha modal, sau khi tải |

## 4. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Kit | `ShotDexKit/Models/MetadataLevel.swift` (mới) | `public enum MetadataLevel: String { all, noLocation, none }` + `filteredProperties(_:)` thuần cho đường render (dictionary ImageIO). Ở kit vì `PhotoRenderService.write` cần nó; chỉ ImageIO, không SwiftUI/GRDB |
| Kit | `ShotDexKit/Render/PhotoRenderService.swift`, `ShotDexKit/Models/PhotoEditingModels.swift` | `write(…, metadata:)`, `PhotoExportOptions.metadata`, ước lượng cỡ theo mức |
| Domain | `Domain/Metadata/MetadataRewriter.swift` (mới) | ghi lại file **không giải mã** (`CGImageDestinationCopyImageSource` + `CGImageMetadata` đã sửa) từ URL sang URL; bảng đường dẫn XMP/IPTC cần xoá; trả lỗi `unsupportedType` cho RAW thay vì trả bản gốc |
| Domain | `Domain/Metadata/ShareBatchPlan.swift` (mới) | từ danh sách item (ảnh/RAW/video) + mức → cần alert RAW không, đếm, chữ phụ đề, hai dòng hành động nào |
| Domain | `Domain/Metadata/AssetMetadataCarryOver.swift` (mới) | ngày/vị trí asset mới theo lối ra + mức; Save Changes luôn "không đụng"; asset không còn vị trí → bỏ GPS file ở mọi mức |
| Data | `Data/Sources/ShareExportPipeline.swift` (mới) | gom từng asset ra `ShotDexShare-<uuid>/` (resource → file, `MetadataRewriter`, RAW → render), kiểm huỷ, dọn; seam `ShareAssetReader` (PhotoKit thật + giả trong test) |
| Data | `Data/Sources/PhotoEditingService.swift` | `commit` bỏ tham số metadata; `saveChanges` luôn ghi đủ metadata; `saveCopy`/`compress`/`createFlatAsset` theo `MetadataLevel` |
| Core | `Core/Utils/SettingsKeys.swift` | `shareMetadataLevel` thay `shareIncludesLocation`; đọc khoá cũ một lần (false → No Location) rồi xoá |
| Features | `Features/Shared/PhotoShareSheet.swift` | nguồn item lười của FS-02.06 gọi pipeline khi đích xin; `present` nhận dòng hành động + nguồn item; `ShareMetadataActivity` (UIActivity) |
| Features | `Features/Shared/PhotoDragItem.swift` | qua pipeline một ảnh, **bản đã chỉnh** (resource hiện hành như Share); RAW khi mặc định ≠ All → JPEG |
| Features | `Features/Library/PhotoDetailScreen.swift` `:1111-1155` | share qua pipeline ngay (Q2) |
| Features | `Features/ServerImport/ServerExportModel.swift:273`, `ServerExportSheet.swift:43` | đích Share render theo `MetadataLevel` (AC-22) |
| Features | `LibraryScreen`, `AlbumDetailScreen`, `SmartAlbumDetailScreen`, `OnThisDayScreen`, `App/AssetActionsCoordinator.swift` | alert RAW, Cancel (theo FS-02.06) |
| Features | `Features/ServerImport/ServerPhotoCommands.swift` | `shareFiles(level:)`, RAF qua alert |
| Features | `Features/Editing/PhotoEditorScreen.swift` (sheet Save `:3585-3690`), `PhotoEditorController.swift:3244-3285`, `EditorBatchSaver.swift`, `CompressionController.swift`, `CompressionScreen.swift:297-317` | `MetadataLevel` thay `Bool`; picker/segmented 3 mức |
| Features | `Features/Settings/SettingsScreen.swift:19,487-495`, `SettingsRowLabel.swift:69,127,162` | picker **Metadata When Sharing**, footer mới |
| Chữ | `Localizable.xcstrings` | 3 tên mức, 3 phụ đề, *Videos keep their metadata*, alert RAW (số nhiều), 3 dòng hành động |
| Test | `MetadataRewriterTests`, `MetadataLevelTests`, `ShareBatchPlanTests`, `AssetMetadataCarryOverTests`, `ShareExportPipelineTests`, `SettingsMetadataLevelMigrationTests`, `MetadataFixture` (sinh JPEG/HEIC/PNG có GPS + XMP + IPTC + MakerApple bằng ImageIO, không ảnh người); sửa `ServerEditHandoffTests`, `LargeImageRenderTests` | |
| Docs | FS-08.06 (cột chứng minh, §8 vị trí thật của hai dòng, kết quả đo HEIC/gain map), NF-03 §3 nếu HEIC No Metadata đổi cách, DESIGN nếu thêm mẫu alert. Đã sửa lúc duyệt 2026-10-01: FS-08.06 §2–§5, §7 (AC-3, 11, 17, 19, 22), §8; NF-03 §3 | |

`ShotDexShare` (extension) **không đổi** — spec §2 giữ nguyên byte.

## 5. Thứ tự task (một AC = một commit)

| # | Task | AC | Test |
|---|---|---|---|
| 1 | **Save Changes không bao giờ đổi ngày/vị trí** (lỗi mất dữ liệu): `commit` bỏ nhánh xoá `:773-776`; `saveChanges` + Live Photo + batch Save Changes ghi đủ metadata; footer `:3618` bỏ câu "clears the Photos date/location" | AC-17 (phần dữ liệu) | `AssetMetadataCarryOverTests.saveChangesNeverTouchesDateOrLocation`; ảnh sim trước/sau Save Changes với Include Metadata tắt |
| 2 | **Đo trước** trên simulator iOS 26.5 + 18.6: ma trận `CopyImageSource` × JPEG/HEIC/PNG/TIFF × No Location/No Metadata; HEIC còn sót ngày/City không; gain map HDR + depth sống sót không (spec §8) — cổng cho task 5, 10 | (AC-1, AC-2) | `MetadataRewriteProbeTests` — số ghi vào spec §8 |
| 3 | Seam `ShareAssetReader` + khoá hành vi đã đúng (không đổi hành vi) | AC-3, AC-8 | `ShareExportPipelineTests.allMetadataIsByteIdentical`, `.livePhotoSharesOneStill` |
| 4 | Đo extension, không sửa code: 40 HEIC 48MP qua Files → Save to ShotDex trên sim, `footprint` của process extension, SHA-256 so với `DCIM` của sim | AC-14 | biên bản trong `/verify` |
| 5 | `MetadataLevel` (kit) + `MetadataRewriter` No Location không giải mã (`CopyImageSource`); **không bao giờ rơi về bản gốc**, ảnh ghi lỗi bị bỏ + nêu tên; Settings 3 mức + đọc khoá cũ; `gather` dùng nó | AC-1 (Q1) | `MetadataRewriterTests.noLocation*` (so pixel), `.failedRewriteNeverReturnsOriginal`, `SettingsMetadataLevelMigrationTests` |
| 6 | Asset không còn vị trí mà file có GPS → bỏ GPS ở mọi mức, kể cả All Metadata | AC-3 vế 2 (❓-2) | `ShareExportPipelineTests.removedLocationDropsFileGPSAtAll`; Remove Location trên sim rồi Save to Files |
| 7 | Xoá vị trí trong XMP/IPTC (GPS lặp, City/State/Country/Sublocation, `Iptc4xmpCore:Location`) | AC-4 | `MetadataRewriterTests.lightroomXMP` (JPEG có XMP sinh bằng `CGImageMetadata`) |
| 8 | Photo Detail share qua pipeline **ngay**, không chờ FS-02.06; ảnh chỉ trên iCloud tạm giữ *Unable to Share* tới FS-02.06 task 14 | AC-5 (Q2) | `ShareExportPipelineTests.detailMatchesGrid`; ảnh viewer |
| 9 | Gom từng ảnh ra file tạm `ShotDexShare-`, nguồn ghi bằng URL, xoá khi sheet đóng | AC-10 | `ShareExportPipelineTests.twentyPhotosPeakIsFlat` (footprint 1 vs 20 ảnh 48MP sinh lúc chạy) |
| 10 | Gom sau khi chọn đích, huỷ bằng Cancel của modal FS-02.06 + dọn thư mục. Cần modal của FS-02.06 task 10 — ai làm trước dựng | AC-11 | `ShareExportPipelineTests.cancelLeavesNothing` (đích nhận 0 file); ảnh modal + Cancel |
| 11 | Mức No Metadata: giữ orientation, ICC, Artist, Copyright (EXIF/TIFF/IPTC/XMP). **Cổng:** HEIC làm theo kết quả đo task 2 — sạch thì làm luôn; còn sót ngày/City thì dừng, hỏi người dùng trước khi làm phần HEIC | AC-2 (phần file; ❓-1) | `MetadataRewriterTests.noMetadata*` JPEG + HEIC |
| 12 | Dòng hành động + phụ đề trong share sheet (`ShareMetadataActivity`, `UIActivityItemSource` + `LPLinkMetadata`); đo vị trí thật trên 26.5 và 18.6 | AC-7 | `ShareBatchPlanTests.rowsAndSubtitle`; ảnh share sheet iPhone 402pt + Duo ngoài |
| 13 | Chạm dòng → đóng, mở lại ngay ở mức mới (chưa gom gì); Settings không đổi | AC-20 (+ hoàn tất luồng AC-2) | `ShareBatchPlanTests.oneShotOverrideKeepsSettings`; ui-drive |
| 14 | Phụ đề *Videos keep their metadata* khi mẻ có video | AC-6 | `ShareBatchPlanTests.videoNote`; SHA MOV trong pipeline test |
| 15 | Nhận diện RAW + một alert cho cả mẻ, Skip; RAW iOS không đọc được → Share as JPEG mờ + lý do (cho Share Original của FS-03.04b) | AC-9 | `ShareBatchPlanTests.rawAlertOnce`, `.skipDropsRAW`, `.unreadableRAWDimsShareAsJPEG` |
| 16 | Share as JPEG (render đủ cỡ, lọc theo mức) | AC-15 | `ShareExportPipelineTests.rawAsJPEG` (cần mẫu RAW — ❓-5) |
| 17 | Share RAW with Location | AC-16 | `ShareExportPipelineTests.rawKeepsBytes` |
| 18 | Share từ server: `shareFiles(level:)`, RAF qua alert | AC-13 | sửa `ServerEditHandoffTests.shareHandsOriginalAndCleansUp` + `.rafNeverLeaves` |
| 19 | Đích Share của sheet xuất server: render theo `MetadataLevel` + hai dòng hành động | AC-22 | `ServerExportShareTests.noLocationRenderHasNoGPS`; ảnh sheet xuất + share sheet |
| 20 | Save Copy 3 mức: kit `write(metadata:)`, ngày giữ / vị trí theo mức; picker trong section Save Copy, footer "Save Changes keeps everything" | AC-12 (Q3) | `MetadataLevelTests.filteredProperties`, `AssetMetadataCarryOverTests.saveCopy*`; ảnh sheet Save |
| 21 | Resize segmented 3 mức + Paste Edits picker, mở theo Settings | AC-18 | `AssetMetadataCarryOverTests.flatAsset*`; ảnh Resize trên Duo ngoài 382pt |
| 22 | Kéo ảnh qua pipeline, ảnh đã chỉnh giao bản đã chỉnh | AC-19 (❓-3) | `ShareExportPipelineTests.dragUsesDefault`, `.dragSendsEditedVersion`; ui-drive Split View iPad |
| 23 | Kéo RAW → JPEG đủ cỡ khi mặc định ≠ All | AC-21 | `ShareExportPipelineTests.dragRAWBecomesJPEG` |
| 24 | Chữ ở 4 màn, ảnh mọi thiết bị, cột chứng minh FS-08.06, `/verify FS-08.06` + full suite một lần | tất cả | |

Task 2 không gắn AC riêng: nó là phép đo mà AC-1/AC-2 dựa vào (spec §8 tự đòi "thêm AC so gain map và depth
trước khi coi AC-1 là xanh") và là **cổng** cho phần HEIC của task 11. Task 1 làm trước mọi thứ vì là lỗi mất dữ
liệu, không phải tính năng. Task 6 (vế 2 của AC-3) đi ngay sau task 5 vì dùng `MetadataRewriter`. So với bản nháp:
thêm task 6 (❓-2) và task 19 (AC-22), các task sau dời số.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **HEIC No Metadata không sạch được nếu không giải mã**: `CopyImageSource` để sót `DateTimeOriginal`, IPTC City/Rating (đo macOS 27.0) | cao | cổng đo ở task 2 (người dùng chốt: quyết sau khi đo); còn sót thì hỏi người dùng trước phần HEIC của task 11 — không tự chọn mã hoá lại |
| Gain map HDR / depth Portrait mất khi ghi lại HEIC | vừa | task 2 đo; nếu mất thì thêm AC theo spec §8 |
| **Bộ nhớ mẻ 20**: hôm nay cả mẻ là `Data` trong RAM (20 × 48MP HEIC ≈ 200–500 MB) | chắc chắn (hiện trạng) | task 9: `writeData` ra file, `CGImageSourceCreateWithURL`, một ảnh một lúc; đo footprint 1 vs 20 |
| **Share sheet iOS 26 vs 18**: dòng `UIActivity` `.action` có thể nằm dưới đáy danh sách; `LPLinkMetadata` không có trường phụ đề công khai (dòng dưới tiêu đề thường là kiểu file/cỡ) | cao | task 11 đo cả hai OS trước khi làm UI; không đặt được phụ đề thì đưa mức vào tiêu đề (*"3 Photos · Location removed"*) và báo lại spec |
| Mở lại share sheet sau khi activity đóng: phải đợi dismiss xong, iPad popover cần neo lại | vừa | `activityDidFinish` → `completionWithItemsHandler` → gom → `present`; test trên iPad |
| **RAW không ghi lại được bằng ImageIO** (22 kiểu ghi được, không có RAW/DNG) | chắc chắn | mọi đường đi qua `MetadataRewriter.unsupportedType` → alert (share) / JPEG (kéo); không còn `?? data` |
| **Kéo RAW → JPEG**: render đủ cỡ 61MP trong callback của `NSItemProvider`, không UI; RGBA8 của 61MP ≈ 244 MB + bộ giải RAW | cao | báo `Progress`; đo đỉnh trên sim (HDR plan đo nền `CIRAWFilter` ~400 MB trên Mac); vượt ngưỡng thì render theo dải như `PanoramaExporter.StripFeeder` |
| Ảnh đổi/xoá vị trí trong app: asset rỗng mà file vẫn GPS — All Metadata giao toạ độ người dùng tưởng đã xoá | vừa | bỏ GPS khi asset không còn vị trí (❓-2, task 6); đổi sang vị trí khác chưa có luật — All vẫn nguyên byte |
| Share sheet mở ngay với nguồn lười (FS-02.06): ghi lại metadata chạy trong callback của nguồn, sau khi đích xin | vừa | pipeline nhận URL đã tải, ghi lại ra file mới, trả URL; lỗi/huỷ trả qua modal; `swift-concurrency` duyệt |
| PhotoKit: `writeData` cho resource `.fullSizePhoto` (bản đã sửa) vs `.photo` (gốc), ảnh chỉ trên iCloud, quyền `.limited` | vừa | chọn resource giống `requestImageDataAndOrientation(.current)`; test trên ảnh đã sửa; `photokit-guard` |
| **Hai phiên cùng sửa** `PhotoShareSheet`, `PhotoDetailScreen` share (FS-02.06 iCloud, cùng intent), "Share Original" của FS-03.04b | cao | ai làm trước dựng pipeline / modal, phiên kia dùng lại; FS-03.04b task 10 dùng alert RAW của task 15 ở đây; commit nhỏ, `git commit -- <paths>`; không stash/checkout |
| Kit đổi `public` API (`write`, `PhotoExportOptions`) — extension Edit Action cũng link kit | thấp | `extension-boundary`; build cả 6 target |
| Chữ "Include Metadata" ở 3 màn + "Include Location" ở Settings → đổi tên ở 4 màn | chắc chắn | `copy-consistency` sau task 20 |
| Ảnh thử có mặt người | — | fixture sinh bằng ImageIO; mẫu thật (ARW, MOV) kiểm bằng Vision trước khi dùng |

## 7. Quyết định (người dùng duyệt 2026-10-01)

| # | Câu hỏi | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| Q1 | AC-1, cách ghi lại | **ghi lại không giải mã** (`CopyImageSource`); ghi lỗi thì không bao giờ giao bản gốc | spec §3 (đã nói); task 5 |
| Q2 | AC-5, Photo Detail | **đi chung pipeline ngay**, không chờ FS-02.06; iCloud tạm giữ *Unable to Share* tới FS-02.06 task 14 | task 8 |
| Q3 | AC-12 vs AC-17, sheet Save | picker 3 mức **chỉ trong section Save Copy**; footer nói Save Changes giữ mọi thứ; AC-17 đọc "Save Changes bỏ qua picker" | spec §2, §4, AC-17, NF-03 §3; task 1, 20 |
| ❓-1 | HEIC No Metadata còn sót ngày/City | **quyết sau phép đo task 2** — giữ làm cổng | task 11 có cổng |
| ❓-2 | asset đã xoá vị trí mà file còn GPS | **bỏ GPS khi asset không còn vị trí**, kể cả All Metadata | spec §3, §8, AC-3, NF-03 §3; task 6 |
| ❓-3 | kéo ảnh đã chỉnh | **giao bản đã chỉnh**, cùng pipeline với Share | spec §5, AC-19; task 22 |
| ❓-4 | đích Share của sheet xuất server | **thêm AC-22** | spec §7 AC-22; task 19 |
| ❓-6 | Share Original của FS-03.04b khi Settings ≠ All | qua alert RAW của spec này, **Share as JPEG mờ** kèm *iOS can't read this RAW yet* | spec §5; task 15 |
| — | luật Share mới của FS-02.06 | share sheet mở ngay; gom (tải + ghi lại) sau khi chọn đích, trong modal của FS-02.06 | spec §4, §5, AC-11; task 10, 13 |

**Còn mở:** ❓-5 — **mẫu RAW cho test** (AC-9, 13, 15, 16, 21): ImageIO không tạo được ARW/RAF, repo không có file
RAW. Cần một ARW + một RAF thật, không có người; tải file cần người dùng cho phép (tên, nguồn, cỡ). Dùng chung
fixture với FS-03.04b task M2 nếu được. Chưa có thì test đơn vị dùng UTI giả, `/verify` dùng file thật.

## 8. Phản biện

(điền sau khi chạy `challenger` trên plan này)

## 9. Cách chứng minh là xong

- **Test:** mọi test ở §5, sửa `ServerEditHandoffTests`, `LargeImageRenderTests`; full suite một lần ở task 24.
- **Đọc file nhận được:** Save to Files trên sim rồi đọc từ `File Provider Storage` của sim (`simctl get_app_container`)
  bằng `exiftool`-tương đương ImageIO + `shasum -a 256`; asset mới đọc từ `DCIM` của sim.
- **Ảnh phải chụp** (iPhone 26.5 + 18.6, iPad 13", Duo ngoài 466×678; Duo trong nếu mở được): Settings → Sharing
  (cả 3 mức); share sheet với hai dòng + phụ đề ở cả 3 mức và mẻ có video; alert RAW (1 và 2 file); tiến độ + Cancel
  lúc gom; sheet Save Edit; Resize segmented (Duo ngoài 382pt không cắt chữ); Paste Edits; kéo sang Files ở Split View iPad.
- **Tài liệu:** cột "Chứng minh bằng" FS-08.06; §8 FS-08.06 (vị trí thật của hai dòng, kết quả gain map/depth);
  NF-03 §3 nếu HEIC No Metadata đổi cách; FS-02.06 nếu dùng chung UI huỷ.
- **Agent ở Deploy:** `photokit-guard` (resource writes, Save Changes/Save Copy change request, iCloud, `.limited`),
  `memory-leak` (pipeline, kéo RAW → JPEG, extension), `swift-concurrency` (huỷ, Task trong `NSItemProvider`,
  callback `UIActivity`), `extension-boundary` (API `public` mới của kit, extension không đổi), `ios26-parity` (share
  sheet và dòng hành động 26.5 vs 18.6), `device-layout` (Settings, sheet Save, Resize trên Duo ngoài),
  `copy-consistency` (tên mức ở 4 màn, alert RAW).
