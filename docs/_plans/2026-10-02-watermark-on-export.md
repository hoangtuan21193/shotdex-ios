# Kế hoạch — Đóng watermark lúc xuất (FS-05.04)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-05.04`](../02-functional-spec/FS-05-markup/04-watermark-on-export.md) — 15 AC |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 6 (đợt 2) |
| Phụ thuộc | [FS-03.07b](../02-functional-spec/FS-03-photo-editor/07b-export-to-files.md) / [plan](2026-10-02-export-to-files.md) — **task 15** chờ sheet Export (T2, T5, T15 của plan đó); **task 14** đi sau T1 của plan đó (cùng sửa sheet xuất server). Task 1–13 không chờ gì |
| Ngày | 2026-10-02 |
| Trạng thái | **approved 2026-10-03** — 16 task. Quyết định ở §7 (đã vào FS-05.04 cùng commit duyệt) |

## 1. Hiểu đúng chưa

Chữ ký đã lưu trong Markup (`SignaturePreset`) được đóng lên ảnh ở mọi lối xuất ra **file mới**: Resize (một ảnh và cả
mẻ), Share ở mọi lối của FS-08.06 kể cả kéo thả, sheet xuất ảnh server, và sheet Export ra Files / server của
FS-03.07b. Dấu là **cả cụm lớp** của preset dựng thành một khối, đặt theo cạnh ngắn (9 điểm neo, Margin, Size, Opacity),
ghép **cuối cùng ở kích thước xuất**, chỉ raster khung bao của khối, token thay theo từng ảnh. Bản gốc không bao giờ
mang dấu (Delete Originals / Replace Original tắt khi bật dấu); không bao giờ giao ảnh không dấu khi đã bật (ảnh không
đóng được dấu bị bỏ và nêu tên). Form xuất nhớ cấu hình + bật/tắt chung cho mọi form; Share theo Settings → **Watermark
When Sharing**, đổi một lần bằng một dòng của app trong share sheet. Không database, không extension, không video.

## 2. Đối chiếu AC ↔ code

**Đo trước khi viết bảng** (script tạm trên macOS 27.0.1, ImageIO/Core Image — cùng bộ mã hoá với simulator):

| Phép đo | Kết quả | Hệ quả |
|---|---|---|
| Gain map khi ghép dấu (spec §8 đòi đo lúc `/plan`): HEIC và JPEG có ISO gain map, headroom 3,99 | ghép kiểu thường (`CIImage(contentsOf:)` → ghép → mã hoá) **mất gain map** ở cả hai; ghép trên ảnh đọc với `.expandToHDR` rồi ghi kèm `CIImageRepresentationOption.hdrImage` **giữ** ISO gain map, headroom 3,99 | làm đúng spec: file có dấu là SDR (rẻ, trong ngân sách RAM). Đường giữ HDR có thật nhưng tốn thêm một lượt render HDR → `REVIEW_QUEUE.md`, không làm ở đây |
| JPEG 2048×1365, khung bao dấu 300×55 ở (1707…2007, 1269…1324), q 80 và 95: so pixel bản có dấu với bản không dấu | pixel đổi lan ra **tới 11 px ngoài khung bao**; **0 pixel** đổi ngoài khung bao nới ra lưới khối 16 px | AC-1 "mọi pixel ngoài khung bao trùng" **không đạt được** với JPEG như đang viết → ⚠️-2 |

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 Resize 2048 + W → dấu ở x=2007, y=1324, cao 55; ngoài khung bao trùng bản không dấu | ❌ (+⚠️-2 về cách đo — AC-1 đã viết lại lúc duyệt) | không lối xuất nào đọc `SignaturePresetStore` (chỉ editor: `PhotoEditorScreen.swift:351,761`, `PhotoEditorController.swift:2828`); Resize render `PhotoEditRecipe.identity` rồi `resize` rồi `write` `PhotoEditingService.swift:572-594`; raster lớp phủ hiện là **bitmap cỡ cả khung** `PhotoRenderService+Overlay.swift:161-178` (48MP ≈ 195 MB, FS-05.01 AC-38); preset không lưu tỉ lệ khung `PhotoOverlayModels.swift:495-507`; vị trí lớp chuẩn hoá theo khung, `maximumWidth` theo **bề rộng** `:166-169`, nét vẽ theo bề rộng canvas `PhotoRenderService+Drawing.swift:140` — đặt thẳng lên ảnh khác tỉ lệ sẽ tách logo khỏi credit | `WatermarkLayout` (kit, thuần) + raster chỉ khung bao + ghép sau `resize` trong đường Resize; preset ghi `sourceAspect` |
| AC-2 xem trước 320pt có dấu đúng chỗ (≤ 1pt), 4 thiết bị | ❌ | xem trước dựng `recipe: .identity` ở 2000px `CompressionController.swift:343-362`, không lớp nào vẽ lên; không có hàng Watermark, không có màn Watermark. Board **đã có** trên canvas editor (sau 2026-10-02): `PH31`/`IP22`/`IPP18`/`DI17`/`DIP17`/`DC18` `_Watermark`, `PH32_ResizeWatermark`, `PH37_ShareWatermark` | export board, rồi hàng + màn Watermark; xem trước dùng đúng bộ raster của bản xuất |
| AC-3 3 máy → `© Nguyen An · ILCE-7M4` / `… X-T5` / `… iPhone 17 Pro` (AC đã sửa lúc duyệt) | ⚠️-1 → code đúng | luật thay token theo từng ảnh đã có và đã test (`OverlayTokenResolver.swift:108-123`, `OverlayTokenResolverTests`; mẻ editor thay theo từng ảnh `EditorBatchSaver.swift:217-238`). Nhưng `{camera}` = `normalizedCameraModel` `OverlayTokenValues+Metadata.swift:15`, mà normalizer **bỏ tên hãng** và giữ nguyên mã model `CameraNormalizer.swift:45-55`, `MetadataComposer.swift:86`: Sony `ILCE-7M4` → `ILCE-7M4`, Fujifilm `X-T5` → `X-T5`. Spec §3 lại bảo dùng "cùng nguồn giá trị mà editor dùng" | **code đúng** (đã quyết): chuỗi kỳ vọng của AC-3 đã sửa thành `© Nguyen An · ILCE-7M4`, `… X-T5`, `… iPhone 17 Pro` — §7 |
| AC-4 Settings Credit + No Location → Share → Files: có dấu, không GPS, còn Make/Model | ❌ | ảnh tĩnh đi `CGImageDestinationCopyImageSource`, **không giải mã** `ShareExportPipeline.swift:134-155` → không có chỗ ghép; Settings chỉ có Metadata When Sharing `SettingsScreen.swift:495-507`, `SettingsKeys.swift:58` | mẫu "render rồi ghi metadata" đã có ở `ShareRAWRenderer.swift:19-39` + `MetadataRewriter.rewrite(_:metadataFrom:…)` `MetadataRewriter.swift:151-159` (đặt orientation = 1) → `ShareWatermarkRenderer` cùng khuôn; hàng Settings mới |
| AC-5 Settings Off → *Share With Watermark* → mở lại, dòng 2 *Watermark: Credit*, Settings vẫn Off | ❌ | khuôn dòng một lần đã có cho mức metadata: `ShareLevelRow` `ShareLevelRow.swift:7-44`, đóng → mở lại `PhotoShareSheet.swift:153-166` (lazy) và `:304-316` (gather); dòng 2 của đầu sheet `:178-190` | thêm `ShareWatermarkRow` + tham số watermark một lần cho `share(…)`/`gather(…)` |
| AC-6 ARW + RAF chưa đọc được + A, Settings Credit → không alert RAW; 2 JPEG có dấu; RAF bị bỏ, nêu tên trong modal; *RAW sent as JPEG* | ❌ | alert RAW hỏi khi `level != .all` `ShareBatchPlan.swift:69`, `PhotoShareSheet.swift:114-120`; RAW ở All đi nguyên byte `ShareExportPipeline.swift:113,137-139`; modal nêu tên ảnh bị bỏ **đã có** (`LazyShareBatch.Stage.leftOut` `LazyShareBatch.swift:26-27,176-181`) | watermark bật ⇒ RAW luôn `shareAsJPEG` + dấu, không hỏi; `ShareRAWRenderer.Failure.unreadable` rơi vào `leftOut` sẵn có |
| AC-7 MOV SHA-256 nguyên; A có dấu; *Videos aren't watermarked* | ❌ (vế MOV ✅) | MOV đi nguyên URL `ShareExportPipeline.swift:111-112`, test `ShareExportPipelineTests.videoGoesAsItIs`; ghi chú video hiện chỉ nói metadata `ShareBatchPlan.swift:50-58` | thêm ghi chú watermark vào đầu sheet + summary |
| AC-8 Resize 5 ảnh, bật dấu → Delete Originals tắt + mờ + dòng phụ; 5 bản gốc còn | ❌ | `deleteOriginals = true` mặc định `CompressionController.swift:48`, toggle luôn bật được `CompressionScreen.swift:324-344`, xoá `CompressionController.swift:383-395` | `deleteOriginals` hiệu lực = false khi watermark bật (model, test qua `ResizeOperations` giả) |
| AC-9 NAS 2 JPEG, đích Original Folder, W → Replace Original mờ + lý do; `<tên>_edited.jpg` có dấu; gốc giữ SHA | ❌ | `canReplaceOriginals` chỉ xét RAW/composed `ServerExportModel.swift:98-100`, footer lý do RAW `ServerExportSheet.swift:215-221`; render closure `ServerExportModel.swift:267-279` → `EditorBatchSaver.renderToFile` → `writeRender` `PhotoEditingService.swift:631-645`; tên `_edited` có sẵn | section Watermark dưới Format; `canReplaceOriginals` thêm điều kiện; ghép dấu trong `writeRender` |
| AC-10 1080×1920, khối tự nhiên 1200 px → thu đều còn 1016 ±1 | ❌ | — | luật thu đều trong `WatermarkLayout` |
| AC-11 ảnh đã dán Credit trong editor → chỉ một dấu; *1 photo already had this watermark* | ❌ | `applySignature` cấp id mới cho mỗi lớp, **không ghi preset nguồn** `PhotoEditorController.swift:2828-2843`; `PhotoOverlay` không có trường đó `PhotoOverlayModels.swift:134-207`; công thức đọc lại được qua `session.recalledRecipe` `PhotoEditingService.swift:260` (đường tải iCloud không có session `:532-543`) | lớp mang `signaturePresetID`; đọc công thức đã lưu cho cả hai đường |
| AC-12 cấu hình nhớ giữa Resize và sheet Export ra Files | ❌ | Resize không nhớ gì (FS-03.07 §1, đã ghi ngoại lệ watermark); sheet Export **chưa có** (FS-03.07b, `FileExport*Tests` chưa có) | store nhớ cấu hình (task 5); AC-12 đóng ở task 15, **sau** sheet của FS-03.07b |
| AC-13 preset Logo mất file → hàng `Off`, chip *Missing file* không chọn được | ❌ (lưu preset ✅) | `PhotoOverlayModelsTests.signaturePresetRoundTrips`; `OverlayImageStore.imageExists(id:)` có sẵn (kit `OverlayImageStore.swift:67`); font lùi có cờ `didSubstitute` `TextOverlayLayout.swift:79-85`; renderer lặng lẽ bỏ lớp ảnh mất file `PhotoRenderService+Overlay.swift:227-232` | `WatermarkAvailability` (Domain) dùng hai thứ đó |
| AC-14 HEIC 48MP, Resize Original + W → đỉnh RAM +≤ 40 MB, iPhone 17 26.5 | ❌ | raster cả khung `PhotoRenderService+Overlay.swift:165-178` | raster khung bao; khung bao > 8 MP thì vẽ theo dải (Size 25% trên 8064 px rộng ≈ 49 MB một bitmap, §4) |
| AC-15 10 ảnh, 4 chỉ trên iCloud, Settings Credit → modal tải 4 gốc; 10 file có dấu đúng cỡ gốc | ❌ (vế tải ✅) | share mở ngay rồi tải trong modal `LazyShareBatch.swift:131-152`; reader ghi resource đủ cỡ (`.fullSizePhoto`/`.photo`, có mạng) `ShareExportPipeline+PhotoKit.swift:59-68`; test `CompressionPreparationTests.copiesReadThePreparedOriginals`, `LazyShareItemTests.viewerSharesPreparedOriginal` | chỉ thêm dấu vào bước ghi; test khoá "ghép trên bản đủ cỡ" |

**Tổng:** ✅ 0 trọn vẹn (vế đã đạt nằm trong AC-7, AC-13, AC-15 — test có sẵn, không viết lại) · ⚠️ 1 (AC-3) + 1 AC đo
không được như viết (AC-1) · ❌ 13 · ❓ 0. Cả hai ⚠️ đã quyết 2026-10-03 (§7).

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `OverlayTokenResolver` + `OverlayTokenValues(metadata:)` + `LibraryQueries.metadata(assetId:)` (cách `EditorBatchSaver.renderReady` `:217-227` làm) | token theo từng ảnh ở mọi lối |
| `TextOverlayLayout.contentSize`/`transform`/`drawText`/`drawImage`, `ShapeOverlayLayout`, `drawDrawingLayer` + `drawingBands` (`PhotoRenderService+Drawing.swift:126-165`) | vẽ khối dấu — **cùng** hàm vẽ với editor, chỉ đổi phép biến đổi và bitmap đích |
| `OverlayImageCache` (khoá, 8 ảnh) `PhotoRenderService+Overlay.swift:13-49` | ảnh logo, dùng chung với editor |
| `ShareRAWRenderer` + `MetadataRewriter.rewrite(_:metadataFrom:to:level:)` | render → ghi metadata của file nguồn theo mức (spec §5) |
| `ShareBatchPlan`, `ShareLevelRow`, `ShareHeaderItem`, `PhotoShareSheet.headerNote` | dòng hai của đầu sheet, dòng một lần |
| `LazyShareBatch` (modal, `leftOut` nêu tên), `OriginalPreparation` (FS-02.06) | ảnh iCloud và ảnh bị bỏ — không modal mới |
| `ResizeOperations` (seam), `CompressionGallery` (carousel 250pt, pill `i / N`), chip Size 48pt + `CompressionChoiceStyle`, `EditorValueSlider` | màn Watermark và test Resize không cần thư viện |
| `CompressionPresetStore` (UserDefaults JSON) | khuôn của `WatermarkSettingsStore` |
| `LossyArray` (`ShotDexKit/Models/LossyDecoding.swift`) | `SignaturePresetStore.reload` hôm nay giải mã cả mảng một lần `SignaturePresetStore.swift:25-30`: một preset hỏng là mất **hết** — đổi sang lossy khi thêm trường (luật độ bền của CLAUDE.md) |
| `MetadataFixture` (sinh JPEG/HEIC có EXIF Sony `ILCE-7M4` + GPS), `RAWFixtures` (ARW CC0 ở `~/Library/Caches/ShotDexFixtures/raw`), đo footprint của `PhotoDrawingModelsTests`/`FocusStackExportTests` | fixture và đo RAM. Không ảnh có mặt người |

## 4. Chỗ nào trong code

| Tầng | File | Đổi |
|---|---|---|
| Kit | `ShotDexKit/Models/PhotoOverlayModels.swift` | `SignaturePreset.sourceAspect: Double?` (thiếu = 3:2); `PhotoOverlay.signaturePresetID: UUID?` (chỉ ghi khi có, decode tuỳ chọn như mọi khoá) |
| Kit | `ShotDexKit/Models/WatermarkStamp.swift` (mới) | `WatermarkAnchor` (9 điểm), `WatermarkPlacement {anchor, margin, size, opacity}` có dải/bước của §3, `WatermarkStamp {layers đã thay token, sourceAspect, placement}` — `Sendable`, `public` |
| Kit | `ShotDexKit/Editing/WatermarkLayout.swift` (mới, thuần) | khung ảo theo `sourceAspect` → khung bao từng lớp (bỏ kính lúp) → khối; đặt theo neo/Margin/Size theo **cạnh ngắn**; thu đều khi rộng hơn ảnh − 2 Margin; neo tâm bỏ Margin; px ↔ phần cạnh ngắn cho stepper |
| Kit | `ShotDexKit/Render/PhotoRenderService+Watermark.swift` (mới) | `watermarkLayer(_:extent:) -> CIImage?` raster **chỉ khung bao** (dải khi > 8 MP), `applyWatermark(_:to:)` ghép cuối cùng |
| Kit | `ShotDexKit/Render/PhotoRenderService.swift` | `write`/`estimatedEncodedByteCount` không đổi chữ ký; `PhotoExportOptions.watermark: WatermarkStamp?` để Resize truyền qua một chỗ |
| Domain | `Domain/Watermark/WatermarkPlan.swift` (mới) | theo từng ảnh: đóng / bỏ vì đã có lớp từ cùng preset / bỏ vì token rỗng hết; đếm và chữ summary/đầu sheet (*1 photo already had this watermark*, *Videos aren't watermarked*, *RAW sent as JPEG*, tên ảnh không dấu) |
| Domain | `Domain/Watermark/WatermarkAvailability.swift` (mới) | preset bị xoá → `Off`; mất file ảnh → *Missing file*, không chọn; font lùi → *Unavailable*, chọn được; chưa có preset → `None` |
| Data | `Data/Sources/WatermarkSettingsStore.swift` (mới) | `@Observable`, UserDefaults JSON: cấu hình nhớ + bật/tắt (chung các form) + `sharingPresetID` (Settings). Không database (spec §6, BD-02) |
| Data | `Data/Sources/SignaturePresetStore.swift` | decode lossy; `sourceAspect` khi lưu |
| Data | `Data/Sources/ShareWatermarkRenderer.swift` (mới) | file nguồn (ảnh hoặc RAW) → giải mã đứng thẳng → ghép dấu → JPEG/HEIC 95% (HEIC ở No Metadata → JPEG, PNG/TIFF giữ) → `MetadataRewriter.rewrite(metadataFrom:)` |
| Data | `Data/Sources/ShareExportPipeline.swift` | `watermark: WatermarkStamp?` + `tokens: (ShareSource) -> OverlayTokenValues` + `stampedPresetIDs`; bật dấu thì ảnh và RAW (mọi mức) qua `ShareWatermarkRenderer`, video không đổi |
| Data | `Data/Sources/PhotoEditingService.swift` | `compress` ghép dấu sau `resize`; `writeRender(…, watermark:)`; `recipeOnFile(for:)` đọc công thức đã lưu (resource `.adjustmentData`) cho đường đã tải iCloud |
| Domain | `Domain/Metadata/ShareBatchPlan.swift` | `watermarkName`, `watermarkRow` (With/Without), ghi chú watermark nối " · " với ghi chú sẵn có; bật dấu thì `asksAboutRAW = false` |
| Core | `Core/Utils/SettingsKeys.swift` | `watermark.export`, `watermark.sharing` |
| Features | `Features/Watermark/WatermarkScreen.swift` + `WatermarkModel.swift` (mới, `/new-screen Watermark D`) | màn toàn màn tầng D, Done; iPhone xếp dọc (xem trước 320pt), iPad/Duo trong hai cột (cột 320pt), Duo ngoài 382pt |
| Features | `Features/Editing/CompressionScreen.swift`, `CompressionController.swift` | hàng Watermark 44pt giữa Metadata và Delete Originals; vẽ dấu lên xem trước 320 và trang carousel 250; Delete Originals tắt + mờ |
| Features | `Features/Editing/PhotoEditorScreen.swift:758-767`, `PhotoEditorController.swift:2828-2843` | Save as Preset ghi `sourceAspect`; dán preset ghi `signaturePresetID` |
| Features | `Features/Shared/PhotoShareSheet.swift`, `ShareLevelRow.swift` (+ `ShareWatermarkRow`), `LazyShareBatch.swift`, `PhotoDragItem.swift`, `App/OriginalDownloadModel.swift` | watermark Settings mặc định, dòng một lần, đầu sheet; gộp đoạn ghi chú lặp `PhotoShareSheet.swift:290-300` vào `headerNote` khi thêm dòng watermark |
| Features | 7 lối gọi share (`AssetActionsCoordinator:235`, `LibraryScreen:417`, `PhotoDetailScreen:1226,1290`, `AlbumDetailScreen:485`, `OnThisDayScreen:351`, `SmartAlbumDetailScreen:474`, `PhotoEditorScreen:525`) + `ServerPhotoCommands:173`, `ServerExportSheet:50` | truyền ngữ cảnh watermark (store, preset, token) từ `AppDependencies` |
| Features | `Features/ServerImport/ServerExportSheet.swift`, `ServerExportModel.swift` | section Watermark dưới Format; Replace Original mờ + lý do; render closure ghép dấu |
| Features | `Features/Settings/SettingsScreen.swift:495-507`, `SettingsRowLabel.swift` | picker **Watermark When Sharing** (`Off` / tên preset) trong section Sharing; mục tìm kiếm + số vàng của `SettingsSearchTests` |
| Features | sheet Export của FS-03.07b (chưa có) | hàng Watermark, section riêng dưới Format (task 15) |
| App | `App/AppDependencies.swift` | dựng `WatermarkSettingsStore` |
| Chữ | `Localizable.xcstrings` | Watermark, Add Watermark, Position/Margin/Size/Opacity, *Originals are kept…*, *Watermarked copies are saved as new files.*, *Watermark: %@*, *Share With/Without Watermark*, *Videos aren't watermarked*, *RAW sent as JPEG*, *%d photo already had this watermark* (số nhiều), *Missing file*, *Unavailable*, *No watermarks yet* + câu hướng dẫn, *Position, bottom right* … |
| Test | `WatermarkLayoutTests`, `WatermarkRenderTests`, `WatermarkPlanTests`, `WatermarkAvailabilityTests`, `WatermarkSettingsStoreTests`, `ShareWatermarkTests` (pipeline + plan), `ResizeWatermarkTests` (qua `ResizeOperations`), `ServerExportWatermarkTests`, `WatermarkMemoryTests`; sửa `PhotoOverlayModelsTests`, `ShareBatchPlanTests`, `SettingsSearchTests` | |
| Docs | FS-05.04 (cột chứng minh, §8 kết quả đo gain map), FS-05.03 §8 (preset mang tỉ lệ khung; lớp dán mang id preset), FS-08.06 §4 (dòng thứ ba của app), FS-03.07 §4 (hàng Watermark), FS-08 bảng hàng Settings | |

Logic đặt ở kit (hình học + raster, thuần) và Domain (quyết định theo ảnh, chữ); View chỉ đọc model. Không đụng
`photo_metadata`, không migration. Không đụng extension nào (spec §2).

## 5. Thứ tự task (một AC = một commit)

Không AC nào ✅ trọn vẹn nên không có task "chỉ viết test khoá"; vế đã đạt của AC-7/13/15 đã có test (cột Bằng chứng).
Thứ tự: nền móng nằm trong AC đầu tiên cần nó; Resize → Share → server → Export ra Files; AC-3 đã có quyết định
(⚠️-1, code đúng). **Task 15 chờ sheet Export của FS-03.07b** — mọi task khác không phụ thuộc nó.

| # | Task | AC | Test |
|---|---|---|---|
| 1 | Nền: `WatermarkStamp`/`WatermarkLayout`/raster khung bao (kit), `sourceAspect` khi Save as Preset, `SignaturePresetStore` lossy, `WatermarkSettingsStore` (chưa có UI), `compress` ghép dấu sau `resize`; controller nhận cấu hình W từ store | AC-1 | `WatermarkLayoutTests.bottomRightAt2048` (2007/1324/55 ±1, thuần), `WatermarkRenderTests.outsideTheBoxIsUntouched` (6000×4000 → 2048: bản render trước mã hoá **trùng tuyệt đối** ngoài khung bao; file JPEG trùng ngoài khung bao nới lưới 16 px — theo ⚠️-2), `.onlyTheBoxIsRasterized`, `PhotoOverlayModelsTests.signaturePresetCarriesAspect`, `.oneBadPresetKeepsTheRest` |
| 2 | Thu đều khi khối rộng hơn ảnh − 2 Margin; neo giữa cạnh và neo tâm | AC-10 | `WatermarkLayoutTests.shrinksToFitPortrait` (1016 ±1, tỉ lệ giữ), `.centreIgnoresMargin`, `.edgeAnchorsCentreTheOtherAxis`; `WatermarkRenderTests.noLayerIsClipped` |
| 3 | Token theo từng ảnh trong mẻ Resize; token rỗng hết → ảnh đi không dấu, nêu tên trong summary | AC-3 (`{camera}` không hãng, ⚠️-1) | `ResizeWatermarkTests.tokensPerPhoto` (3 fixture Sony/Fujifilm/iPhone, đọc chữ đã thay từ `WatermarkStamp`), `WatermarkPlanTests.allTokensEmptyIsNamed` |
| 4 | Lớp dán mang `signaturePresetID`; ảnh đã có lớp từ cùng preset không bị đóng thêm (đọc `recalledRecipe` hoặc resource `.adjustmentData` ở đường đã tải); summary ghi số | AC-11 | `WatermarkPlanTests.samePresetIsNotStampedTwice`, `.otherPresetStillStamps`, `ResizeWatermarkTests.alreadyStampedIsCounted`; editor test `applySignatureRecordsPreset` |
| 5 | **Board đã có** — export `PH31`/`IP22`/`IPP18`/`DI17`/`DIP17`/`DC18` `_Watermark` + `PH32_ResizeWatermark` vào `build/design/editor/project/`, không vẽ → hàng Watermark 44pt + màn Watermark (`/new-screen`) + vẽ dấu lên xem trước 320 và carousel 250, cùng bộ raster; nhớ cấu hình + bật/tắt | AC-2 | `WatermarkModelTests.previewCentreMatchesExport` (≤ 1pt, tính từ `WatermarkLayout` ở cỡ xem trước), `WatermarkSettingsStoreTests.remembersAcrossForms`; ui-drive dump trên iPhone 17 26.5 + 18.6, iPad, Duo trong, Duo ngoài (`Tools/ui-drive` + `Tools/sim-shot`, không MCP trên Duo); **`design-parity`** từng board |
| 6 | Bật dấu → Delete Originals tắt, mờ, dòng phụ; tắt dấu → trả lại lựa chọn trước | AC-8 | `ResizeWatermarkTests.watermarkKeepsOriginals` (`ResizeOperations` giả: 5 bản tạo, 0 xoá); ảnh form + `design-parity` board Resize |
| 7 | Preset bị xoá → `Off`; mất file ảnh → chip *Missing file* không chọn được; font lùi → *Unavailable*; chưa có preset → hàng mờ `None` + màn rỗng | AC-13 | `WatermarkAvailabilityTests.*` (store giả, xoá file thật trong thư mục tạm); ảnh màn Watermark có chip mất file, `design-parity` board rỗng |
| 8 | Đo RAM: raster khung bao theo dải khi > 8 MP; test footprint trên sim làm chốt hồi quy; đo máy thật | AC-14 | `WatermarkMemoryTests.stampAt48MPAddsUnder40MB` (HEIC 8064×6048 sinh lúc chạy, Size 4% và 25%); **iPhone 17 26.5 thật**: Resize Original có/không dấu, `footprint` — biên bản vào `/verify` |
| 9 | Settings → **Watermark When Sharing**; pipeline Share ghép dấu (`ShareWatermarkRenderer`, render rồi metadata theo mức) ở Position/Margin/Size/Opacity đã nhớ của các form, preset từ Settings (❓-A); đầu sheet *Watermark: Credit*; mọi lối Share của FS-08.06 §2 gồm ảnh server (`gather`) và kéo thả | AC-4 | `ShareWatermarkTests.noLocationWithWatermark` (JPEG có dấu ở dưới-phải, không nhóm GPS, Make `SONY`, Model `ILCE-7M4`), `.dragFollowsSettings`, `.serverShareFollowsSettings`, `ShareBatchPlanTests.watermarkNote`; `SettingsSearchTests` cập nhật số |
| 10 | Dòng *Share With/Without Watermark* (thứ ba, sau hai dòng mức); chọn → đóng, mở lại một lần; Settings không đổi; chưa có preset thì không có dòng lẫn ghi chú; *Share With Watermark* khi Settings Off dùng preset dùng lần cuối ở form, chưa có thì preset mới nhất (❓-C); board `PH37_ShareWatermark` | AC-5 | `ShareBatchPlanTests.watermarkRowFlipsSettings`, `.noPresetNoRow`, `WatermarkSettingsStoreTests.shareWithUsesLastFormPresetElseNewest`, `LazyShareItemTests.watermarkRowPreparesNothing`; ui-drive share sheet 26.5 + 18.6, iPhone + Duo ngoài |
| 11 | Bật dấu → RAW thành JPEG đủ cỡ có dấu, **không** alert; RAW không đọc được bị bỏ và nêu tên trong modal `leftOut`; *RAW sent as JPEG* | AC-6 | `ShareWatermarkTests.rawBecomesStampedJPEG` (ARW CC0, bỏ qua nếu thiếu fixture), `.unreadableRAWIsLeftOutByName` (RAF hỏng tự tạo — chưa có máy 26.5 nào không đọc được), `ShareBatchPlanTests.watermarkNeverAsksAboutRAW` |
| 12 | Ghi chú *Videos aren't watermarked* ở đầu sheet và summary; MOV nguyên byte | AC-7 | `ShareBatchPlanTests.videosArentWatermarked`, `ShareWatermarkTests.movieKeepsItsBytes` (SHA-256) |
| 13 | iCloud: dấu ghép trên bản gốc đã tải, không bao giờ trên bản xem trước | AC-15 | `ShareWatermarkTests.iCloudOriginalsAreStampedAtFullSize` (`FakeOriginalFetcher` kịch bản 4/10, kiểm cỡ pixel từng file); ảnh modal trên sim |
| 14 | Sheet xuất ảnh server: section Watermark dưới Format, Replace Original mờ + lý do, render ghép dấu, đích Share của sheet dùng bản render đã theo hàng Watermark của sheet — không đóng thêm theo Settings, không dòng With/Without (❓-B) | AC-9 | `ServerExportWatermarkTests.replaceIsOffAndOriginalsKeepTheirHash` (`RemoteFileAccess` giả: 2 gốc giữ SHA, `<tên>_edited.jpg` có dấu), `.shareDestinationIsNotStampedTwice`; ảnh sheet trên iPhone + iPad; một lượt SMB server test cục bộ |
| 15 | **Chờ FS-03.07b** ([plan](2026-10-02-export-to-files.md) T2 sheet, T5 seam `FileExportJob.stamp: ExportStamping` cài `nil`, T15 đích connection). Cấp `ExportStamping` thật (bọc `applyWatermark`, token + "đã có dấu" theo từng ảnh, ném lỗi = ảnh bị bỏ và nêu tên); hàng Watermark 44pt ở section riêng ngay dưới Format (spec §4, chỗ plan kia chừa sẵn); cùng cấu hình nhớ; **Unmodified Original ẩn hàng** (bản gốc, spec §2), bật/tắt đã nhớ giữ nguyên cho lần Current Version sau; đích connection (= "upload bản render") đi cùng đường | AC-12 | `WatermarkSettingsStoreTests.resizeThenExportSheetSeeTheSame` (Credit, trên-trái, 5%, 60%, bật); ui-drive Resize → Save → sheet Export; `design-parity` board sheet Export của FS-03.07b |
| 16 | Đóng: `copy-consistency` (Watermark ↔ Presets/Sign trong editor), ảnh mọi màn mọi thiết bị, cột chứng minh FS-05.04, cập nhật FS-05.03 §8 / FS-08.06 §4 / FS-03.07 §4, `/verify FS-05.04`, full suite **một lần** | tất cả | |

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Thêm trường bắt buộc vào `SignaturePreset` (Codable tổng hợp) làm `reload` trả `[]` — mất mọi chữ ký | cao nếu sơ ý | trường **tuỳ chọn** + decode lossy (task 1). App chưa phát hành nên không migration (CLAUDE.md), nhưng decode khoan dung vẫn giữ |
| Bitmap khung bao ở Size 25% trên ảnh 48MP ≈ 8064×1512×4 ≈ 49 MB > ngân sách 40 MB | trung bình | vẽ theo dải khi > 8 MP, mỗi dải một `CGImage` ghép lại (như `drawingBands`); `WatermarkMemoryTests` đo cả 4% và 25% |
| Share có dấu phải giải mã + mã hoá cả ảnh (đường không dấu chỉ chép, `CopyImageSource`) → đỉnh RAM của Share tăng tới mức Resize | chắc chắn | chấp nhận: app chính, không phải extension; mẻ tuần tự một ảnh một lúc (NF-02). AC-14 đo trên Resize nơi gốc so sánh đã giải mã |
| Gain map HDR và depth mất khi ghép (đo ở §2) | chắc chắn | đúng spec §8: file có dấu là SDR. `MetadataRewriter.rewrite(metadataFrom:)` có thể chép thẻ XMP `hdrgm:` vào file SDR → kiểm trên sim rằng Photos không coi file là HDR; còn thẻ thì bỏ nhánh `hdrgm` trong bảng xoá. Đường giữ HDR (đã đo được) → `REVIEW_QUEUE.md` |
| Lớp dán từ preset dựa vào `signaturePresetID` mới: ảnh dán **trước** khi có trường này không được nhận ra (AC-11 sẽ đóng thêm một dấu) | thấp (app chưa phát hành) | chấp nhận, không đoán theo nội dung lớp |
| "Đã có dấu" cần công thức đã lưu: đường đã tải iCloud của Resize/Share không mở session | trung bình | đọc resource `.adjustmentData` (vài KB, `isNetworkAccessAllowed`) và giải mã bằng bộ decode của `PhotoEditingService`; chỉ ShotDex mới viết định dạng đó — ảnh sửa bằng app khác coi như chưa có dấu |
| Concurrency: raster và Core Text chạy ngoài main (pipeline Share không cô lập; renderer là actor); `OverlayImageCache` đã có khoá | thấp | `WatermarkStamp` là `Sendable` giá trị; không giữ `PhotoOverlay` có ảnh decode trong model `@MainActor`; `swift-concurrency` review |
| PhotoKit: đường Resize một cặp RAW+JPEG chọn RAW (`preferredSource(for: nil)` `PhotoEditingService.swift:63-73`) với công thức identity | ngoài AC | không đổi ở đây; ghi `REVIEW_QUEUE.md` nếu đo thấy mất bản sửa |
| Token của ảnh server luôn rỗng (editor mở ảnh server với `metadata: nil`, `EditorBatchSaver.swift:207`) — dấu `© Nguyen An · {camera}` trên NAS ra `© Nguyen An` | chắc chắn | đúng luật "cùng nguồn với editor"; AC-9 không kiểm chữ. Đọc EXIF file server cho token → `REVIEW_QUEUE.md` |
| Duo trong 669pt: màn Watermark hai cột, cột 320pt cuộn dọc; Duo ngoài 382pt sau rail 84 | trung bình | board DI/DC trước; `device-layout` + `duo-ux-review`; chụp bằng `Tools/sim-shot` |
| iOS 26 vs trước: hàng Settings, sheet server và dòng share sheet giống nhau hai nhánh; Resize/màn Watermark là tầng D tự vẽ | thấp | `ios26-parity` (dump 26.5 vs 18.6) ở task 5, 9, 10, 14 |
| FS-03.07b chưa có sheet Export | chắc chắn | task 15 đứng cuối, không task nào khác chờ; nếu FS-03.07b đổi chỗ đặt section thì chỉ task 15 đổi |
| **Hai phiên cùng sửa** `ServerExportSheet`/`ServerExportModel`/`EditorBatchSaver.renderToFile` (FS-03.07b T1 thêm hàng Size ở đó) | cao | task 14 làm **sau** khi T1 của FS-03.07b đã commit, rebase lên nó; stage đường dẫn cụ thể, `git commit -- <paths>`, không stash/checkout (memory "Two agents, one checkout") |
| Tên "Presets"/"Sign"/"Rename Signature" trong editor vs "Watermark" ở lối xuất (spec §8) | chắc chắn | `copy-consistency` ở task 16; không đổi chữ editor trong spec này |

**Agent ở giai đoạn Deploy:** `design-parity` (mỗi board, task 5/6/7/15), `device-layout`, `iphone-ux-review`,
`ipad-ux-review`, `duo-ux-review` (màn Watermark + Resize), `ios26-parity`, `memory-leak` (raster, cache logo, task 8),
`swift-concurrency` (pipeline Share, renderer), `photokit-guard` (đọc `.adjustmentData`, tải iCloud), `extension-boundary`
(kit thêm `public`, không SwiftUI/GRDB; không extension nào gọi đường dấu), `copy-consistency`, `localization`
(số nhiều, px/%), `a11y-voiceover` (lưới Position *"Position, bottom right"*, stepper px, chip *Missing file*),
`hig-components` (hàng Settings, sheet server), `design-reviewer`, `test-coverage`, `ux-reviewer` (ảnh bị bỏ không im
lặng), `challenger` (§8).

## 7. Quyết định (người dùng duyệt 2026-10-03)

Người dùng chấp nhận mọi đề nghị của plan; mọi dòng dưới đây đã vào FS-05.04 trong cùng commit duyệt.

| # | Chỗ | Quyết định | Đổi trong spec / plan |
|---|---|---|---|
| ⚠️-1 | AC-3 chờ `Sony ILCE-7M4`, `Fujifilm X-T5`; code (và luật §3 "cùng nguồn giá trị mà editor dùng") cho `{camera}` = model chuẩn hoá không có hãng | **code đúng**: `{camera}` giữ là model không hãng; muốn hãng thì token `{make}` riêng của FS-05.02 | FS-05.04 §3 ghi luật, AC-3 = `© Nguyen An · ILCE-7M4` / `… X-T5` / `… iPhone 17 Pro`; task 3 |
| ⚠️-2 | AC-1 "mọi pixel ngoài khung bao trùng" không đạt với JPEG (đổi tới 11 px ngoài khung, 0 px ngoài khung nới ra lưới 16 px) | **sửa tài liệu**: trùng tuyệt đối trên bản render trước khi mã hoá; trong file, mọi pixel ngoài khung bao nới ra lưới khối 16 px trùng bản Resize không dấu | AC-1 viết lại; task 1 (`WatermarkRenderTests.outsideTheBoxIsUntouched` kiểm cả hai vế) |
| ❓-A | Share đặt dấu ở đâu (Settings chỉ lưu tên preset) | Share dùng **chung** Position/Margin/Size/Opacity đã nhớ của các form; preset lấy từ Settings | FS-05.04 §4 thêm dòng; task 9 |
| ❓-B | đích Share… của sheet xuất ảnh server | dùng bản render đã theo hàng Watermark **của sheet**: không đóng thêm theo Settings, không có dòng With/Without | FS-05.04 §4 thêm dòng; task 14 |
| ❓-C | *Share With Watermark* khi Settings Off dùng preset nào | preset dùng lần cuối ở một form; chưa dùng lần nào thì preset **mới nhất** | FS-05.04 §4 thêm câu; task 10 |
| — | board canvas | **đã có**: `PH31`/`IP22`/`IPP18`/`DI17`/`DIP17`/`DC18` `_Watermark`, `PH32_ResizeWatermark`, `PH37_ShareWatermark` — task 5 không vẽ, chỉ export | FS-05.04 §6 ghi tên board; task 5, 10 |

Quyết định kỹ thuật plan tự chốt: màn Watermark mở bằng `fullScreenCover` (Done, không Back) từ cả Resize lẫn sheet;
khung ảo theo `sourceAspect` để giữ chữ xuống dòng như lúc lưu rồi co cả khối (spec: "không xuống dòng"); file có dấu là
SDR; phát hiện "đã có dấu" chỉ qua `signaturePresetID`.

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| — chưa chạy | |

## 9. Cách chứng minh là xong

- **Test (sim, iPhone 17 26.5 theo `id=`):** các test ở §5; full suite một lần ở task 16.
- **Đo máy thật:** AC-14 trên iPhone 17 26.5 (spec đòi). Nên thử thêm một ảnh HDR thật của iPhone qua Share có dấu
  để xác nhận Photos hiện nó là SDR (gain map Apple, không phải ISO như phép đo macOS).
- **Đo trên sim:** AC-1…AC-13, AC-15 (iCloud bằng `FakeOriginalFetcher` kịch bản; ảnh chỉ trên iCloud thật thì
  `/verify` ghi rõ là chưa đo), AC-9 với SMB server cục bộ, AC-6 với RAF hỏng tự tạo.
- **Màn hình phải chụp:** Resize một ảnh và cả mẻ có dấu (iPhone, iPad, Duo trong, Duo ngoài — Duo qua
  `Tools/ui-drive` + `Tools/sim-shot`); màn Watermark (bật, tắt, rỗng, chip mất file) ở 4 thiết bị; Settings hàng
  Watermark When Sharing (26.5 + 18.6); share sheet có dòng thứ ba và dòng hai *Watermark: Credit* (26.5 + 18.6, iPhone
  + Duo ngoài); sheet xuất server với section Watermark và Replace Original mờ; sheet Export của FS-03.07b có hàng
  Watermark. Mỗi màn có board → `design-parity` qua `Tools/design-board compare`.
- **Design canvas:** board đã có trên canvas editor — `PH31`/`IP22`/`IPP18`/`DI17`/`DIP17`/`DC18` `_Watermark`,
  `PH32_ResizeWatermark`, `PH37_ShareWatermark`; export `project/` trước task 5. Màn Watermark rỗng và chip *Missing
  file* không có board riêng — so bằng ảnh với `_Watermark`. Canvas Video Studio không đổi.
- **Tài liệu phải cập nhật:** FS-05.04 (cột chứng minh, §8 kết quả đo gain map; AC-1/AC-3 và §3/§4/§6 đã sửa lúc duyệt),
  FS-05.03 §8, FS-08.06 §4, FS-03.07 §4, bảng hàng của FS-08 §Sharing and Export.
- Dòng `Tiến độ` của intent đã ghi lúc duyệt 2026-10-03; task đầu tiên ghi `**đang làm**` theo `docs/PROCESS.md` §2.
