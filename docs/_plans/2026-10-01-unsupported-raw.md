# Kế hoạch — RAW iOS chưa đọc được (FS-03.04b)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-03.04b`](../02-functional-spec/FS-03-photo-editor/04b-unsupported-raw.md) — 18 AC · dòng thêm ở [FS-01.05 §3](../02-functional-spec/FS-01-library/05-filtering-and-sorting.md) và [FS-01.01b §6](../02-functional-spec/FS-01-library/01b-grid-engine-and-gestures.md) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 2 |
| Ngày | 2026-10-01 |
| Trạng thái | **đã duyệt 2026-10-01** — 21 task (3 đo + 18 AC). Quyết định ở §9 |

## 1. Hiểu đúng chưa

Hôm nay một RAW mà iOS chưa giải được chỉ lộ ra **sau khi** editor đã tải cả file: một câu chung "This RAW format
can't be decoded on this device.", không tên máy, không lối ra. Cặp RAW+JPEG cũng hỏng theo vì nguồn mặc định là
RAW, và chọn RAW trong menu Source thì lỗi bị nuốt.

Việc cần làm: **phán quyết theo máy × bản build iOS** (khớp danh sách bộ giải → thử một file có sẵn trên máy →
"chưa biết" nếu chỉ có trên iCloud), lưu ở bảng vệ tinh mới. Từ đó: glyph trên tile và trong viewer, mục lọc
*Unsupported RAW*, thông báo có tên máy + phiên bản iOS + việc cần làm hiện **trước** khi tải gì, action sheet
*Edit which version?* cho mọi cặp, và Collage / Video Studio / Combine hỏi trước khi dùng bản xem trước nhúng.
Không đánh dấu nhầm máy đọc được — "không biết" không bao giờ thành "chưa hỗ trợ".

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 NEF `NIKON Z 6_2` khớp "Nikon Z 6 2" → đọc được, 0 dấu | ❌ | không có phán quyết nào; chỉ có `CIRAWFilter(imageURL:) == nil` lúc mở (`ShotDexKit/Render/PhotoRenderService.swift:164-166`). Khoá so tên đã có sẵn: `CameraNormalizer.lookupKey` (`Domain/Normalize/CameraNormalizer.swift:57-59`) bỏ khoảng trắng, `-`, `_` → "z62" khớp hai phía | bộ so tên thuần + bảng `raw_decoder_verdicts` + bước 1 của lượt xét. **Phụ thuộc đo M1** |
| AC-2 8 ARW không khớp + bộ giải rỗng → 8 tile có glyph, VO "RAW not supported by iOS" | ❌ | hàng glyph `applyStatusBadges` (`Features/Shared/PhotoGridCollectionView.swift:2247-2290`) chỉ đọc `PHAsset`; nhãn VO ghép ở `updateAccessibilityLabel` `:2309-2318`. Mẫu tái dùng: `ServerUploadIndex` (set id + `version`, nạp một lần, đưa qua environment — `:28`, `:195`, `:586-596`, `:1009`) | bước 2 (thử file có sẵn) + `UnsupportedRAWIndex` + glyph + VO. **Chờ glyph vào DESIGN.md §8** (người dùng sửa) |
| AC-3 Edit → hai câu có "Sony ILCE-7M5" + "iOS 27.0", editor không mở; editor nhiều ảnh → thông báo + Skip khi tới ảnh đó | ❌ | editor luôn mở rồi mới hỏng: nút Edit `Features/Library/PhotoDetailScreen.swift:617-628` → `PhotoEditorController.load` `:641-685` → `EditorLoadFailure.other(localizedDescription)` (`Domain/Editing/EditorLoadFailure.swift:36`), câu chung `ShotDexKit/Models/PhotoEditingModels.swift:1652`. Editor nhiều ảnh dùng cùng `load` theo ảnh đang chọn trong filmstrip | `UnsupportedRAWMessage` (Domain, thuần) + case `.unsupportedRAW` của `EditorLoadFailure` + cổng chặn ở Photo Detail trước `editorTarget`; ở editor nhiều ảnh: thông báo khi tới ảnh đó + **Skip** sang ảnh kế (Q7) |
| AC-4 phán quyết đã có + chỉ trên iCloud → ≤ 1 s, 0 byte, không spinner | ❌ | `beginSession` gọi `requestContentEditingInput` với `isNetworkAccessAllowed = true` (`Data/Sources/PhotoEditingService.swift:208`, `:631-650`) — tải trước khi biết gì; spinner bật ở `PhotoEditorController.swift:820` | cổng AC-3 đọc index + phán quyết, không đụng PhotoKit ngoài `assetResources`. Test: cổng không gọi session. Sim không có iCloud → phần "0 byte" chỉ chứng minh được trên máy thật |
| AC-5 cặp, máy chưa đọc được → sheet có Edit RAW mờ + lý do; mở JPEG; Source có RAW mờ; không có White Balance | ❌ (một phần ✅) | ✅ nhóm RAW (WB, NR, Sharpening) chỉ hiện khi `isRAWSource` (`Domain/Editing/EditorAdjustmentCatalog.swift:228-240`). ❌ không có sheet; nguồn mặc định là RAW (`PhotoEditingService.swift:71`); menu Source không mờ gì và nuốt lỗi bằng `try?` (`Features/Editing/PhotoEditorScreen.swift:2554-2569`) | `EditSourceChoice` (Domain, thuần: cặp? RAW dùng được? lý do) + `confirmationDialog` ở Photo Detail + mở editor với nguồn đã chọn + menu Source mờ + bỏ `try?` |
| AC-6 Make/Model rỗng → câu nói ".ARW"; tile **không** có dấu | ❌ | — (câu chung như AC-3) | nhánh "không tên máy" của `UnsupportedRAWMessage`; lượt xét bỏ qua dòng không có máy |
| AC-7 DNG hỏng → "can't read this DNG file" + Share Original · OK | ❌ | `EditorLoadFailureAlert` chỉ có OK / Open Settings (`PhotoEditorScreen.swift:3707-3733`) | nhánh DNG của message + nút thứ hai |
| AC-8 Share Original → đúng file DNG, cùng số byte; Settings ≠ All → alert RAW FS-08.06, Share as JPEG mờ | ❌ | `PhotoShareSheet.gather` lấy data qua `imageData(for:)` và có thể bỏ vị trí (`Features/Shared/PhotoShareSheet.swift:15-30`) — không phải "nguyên byte resource" | ghi resource RAW bằng `PHAssetResourceManager.writeData` (cùng cách `PhotoEditingService.write(resource:to:)` `:729`, `PhotoKitOriginalExporter.swift:45`) rồi share URL; Settings ≠ All Metadata → alert RAW của FS-08.06 với Share as JPEG mờ + *iOS can't read this RAW yet* (Q4). Dùng `ShareBatchPlan` của FS-08.06 task 15 nếu đã có, không thì dựng nhánh mờ ở đó |
| AC-9 ImageIO không đọc nổi thuộc tính → vẫn thông báo RAW | ❌ | `inspectSource` ném `.cannotDecode` **trước** khi xét `typeHint` (`PhotoRenderService.swift:144-150`) | kit: thuộc tính hỏng mà `typeHint`/đuôi file là RAW → `.unsupportedRAW` |
| AC-10 máy "chưa biết", editor hỏng 1 ảnh → 6 tile có dấu, không mở lại app | ❌ | `load()` chỉ đặt `loadFailure` (`PhotoEditorController.swift:677-681`), không ghi đi đâu | lỗi RAW ở editor ghi phán quyết nguồn `editor` (chỉ khi máy đang "chưa biết") + `UnsupportedRAWIndex.reload()` |
| AC-11 ghi ở 27.0, lên 27.1 đọc được → xét lại, 0 dấu | ❌ | — | lượt xét lúc mở app so build hiện tại (`ProcessInfo` / `kern.osversion`) với dòng đã lưu; build mới → xét lại từ bước 1 |
| AC-12 3 ARW không khớp, cả 3 chỉ iCloud → "chưa biết", 0 byte, 0 dấu | ❌ | — | bước 3; thử file chỉ với `isNetworkAccessAllowed = false` (mẫu: `ExifReader.swift:674`, `PhotoLibraryService.swift:677`) |
| AC-13 menu con → *Unsupported RAW* → Library còn 8, album còn 4 | ❌ | `PhotoMediaSubtype` 8 case, mỗi case có `bit` + `sqlTest` (`Core/Models/PhotoMediaSubtype.swift:9-44`); SQL ghép ở `LibraryQueries.swift:397-402`; menu dựng từ `allCases` (`Features/Shared/PhotoFilterMenu.swift:75`); chip ở `FilterTokenBar.swift:280`. **Menu này dùng chung với màn album**, nơi `AlbumFilterPredicate` hỏi Photos bằng bit (`Domain/Filtering/AlbumFilter.swift:57-64`) | case `unsupportedRAW` không có bit: `sqlTest` = đuôi RAW **và** `EXISTS` trong bảng phán quyết của build hiện tại; album: danh sách id từ index cắt theo tập id của album, như Panoramas ghép (Q3) |
| AC-14 Resize 2 JPEG + 1 RAW hỏng + 1 cặp hỏng → 3 bản mới (cặp từ JPEG), 1 dòng lỗi mang câu AC-3 | ❌ (vòng chung ✅) | vòng chạy bắt lỗi từng ảnh và chạy tiếp (`Features/Editing/CompressionController.swift:195-216`); `compress` ném ở `loadSource` trước khi render nên không tạo asset (`PhotoEditingService.swift:487-492`). Chỗ lệch: câu là `localizedDescription` chung; ảnh **đầu** hỏng thì `load()` báo lỗi cả màn (`:117-139`); cặp chọn RAW (`PhotoEditingService.swift:71`) và hỏng thay vì dùng JPEG | test khoá vòng chạy; RAW của cặp hỏng → dùng JPEG của cặp (Q6); câu đổi theo task AC-3; preview lấy ảnh đọc được đầu tiên |
| AC-15 Collage 4 ảnh, 1 RAW hỏng → hỏi; Convert / Skip / Cancel | ❌ | Collage lấy pixel qua `requestDetailImage` của PhotoKit, không hỏi gì (`Features/Collage/CollageEditorModel.swift:196-222`, `ingest` `:229-236`) — RAW hỏng **âm thầm** thành bản xem trước. Lối vào: `presentCollage` ở 3 màn (`LibraryScreen.swift:353-356`, `AlbumDetailScreen.swift:389`, `SmartAlbumDetailScreen.swift:420`) + Creations + khay/picker trong Collage | `UnsupportedRAWGate.partition` (Domain, thuần) + một modifier hỏi dùng chung |
| AC-16 cặp máy đọc được, Edit 2 lần → lần nào cũng hỏi; đổi sang JPEG mang bản sửa, bỏ 5 thông số RAW | ❌ | code **nhớ** nguồn: `preferredSource(for:)` lấy `sourceFilename` / `source` của recipe đã lưu (`PhotoEditingService.swift:61-72`) | bỏ nhớ nguồn: lần nào cũng hỏi; chọn JPEG khi recipe đang trên RAW → giữ recipe, xoá `.rawTemperature`, `.rawTint`, `.rawSharpness`, `.rawLuminanceNoise`, `.rawColorNoise` (`EditorAdjustmentCatalog.swift:228-240`) (Q1) |
| AC-17 chạm glyph viewer → thẻ có máy, "iOS 27.0", câu preview; vùng chạm ≥ 44pt | ❌ | dòng tiêu đề bảng thông tin có sẵn chỗ cho glyph (iCloud stall/ring, `PhotoDetailScreen.swift:973-991`) nhưng cả bảng là **một Button** mở sheet Info (`:960-963`); nhãn định dạng dùng danh sách đuôi riêng 8 mục (`:1052-1061`) | glyph + thẻ; xem Q2 về danh sách đuôi |
| AC-18 Video Studio 5 ảnh, 2 RAW hỏng, Skip → 3 clip | ❌ | ảnh vào timeline không qua giải mã nào (`VideoStudioService.loadSources` `:61-110`, `VideoStudioModel.appendMedia` `:1097-1105`) | cùng cổng AC-15 ở `presentVideoStudio` (4 màn) và picker trong Video Studio |
| *§2 "cùng bảng đuôi"* | ❌ | **ba** danh sách đuôi RAW: `FileTypeBadge` 25 đuôi (`Core/Models/LibraryGridItem.swift:40-43`), `formatBadge` 8 đuôi so `hasSuffix` không dấu chấm (`PhotoDetailScreen.swift:1052-1061`), `SmartAlbumQuery .raw` 19 đuôi — có `fff`, thiếu `crw dcr kdc mef raw rwl srw` (`Core/Models/SmartAlbumQuery.swift:204-206`) | một bảng: `FileTypeBadge.rawExtensions` + `FFF`; viewer, smart album và luật RAW-only dùng nó (Q2) — trong task 2 |

Mọi AC đã đọc tới file. Những gì **chưa đo được** nằm ở task M1–M3 và đổi được kết luận của AC-1, AC-12,
AC-15, AC-18 — xem §4.

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `ServerUploadIndex` (`Features/ServerUpload/ServerUploadIndex.swift`) + cách grid đọc nó qua environment | `UnsupportedRAWIndex`: set id + `version`, nạp một lần, không hỏi DB từng ô (NF-01) |
| `CameraNormalizer.lookupKey` / `normalizeModel` | bộ so tên với `CIRAWFilter.supportedCameraModels` |
| `FileTypeBadge.text(forExtension:)` | quy tắc RAW-only (một bảng đuôi) |
| `LibraryModel.startPlaceLookup()` (`LibraryModel.swift:596-614`) — lượt chạy sau khi index yên | chỗ gọi lượt xét phán quyết |
| `AppDependencies.backfillMediaSubtypes()` (`:314-337`) — lượt nền lúc mở app | lượt xét lúc mở app / đổi build |
| `AlbumFilterPredicate.identifierPredicate` (cắt 500 id) | nhánh album của mục lọc (Q3) |
| `PhotoEditingService.write(resource:to:)`, `PhotoKitOriginalExporter` | thử file trên máy (tắt mạng) và Share Original |
| `EditorLoadFailure` + `EditorLoadFailureAlert` | thêm case, không đẻ alert thứ hai |
| `PhotoMediaSubtype.sqlTest` (tiền lệ Panoramas hỏi thêm `isPanorama`) | `sqlTest` của Unsupported RAW |
| `EditorAdjustmentCatalog` ẩn nhóm RAW khi nguồn không phải RAW | AC-5 phần White Balance — không sửa |

## 4. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Domain | `Domain/Editing/RAWDecoderVerdict.swift` (mới) | so tên máy ↔ danh sách; hàm quyết định 3 bậc (khớp → thử file → chưa biết) dạng thuần, nhận kết quả thử qua tham số; luật "editor đè chưa biết", "đọc được thì không đổi vì một file hỏng" |
| Domain | `Domain/Editing/UnsupportedRAWMessage.swift` (mới) | ba câu (có máy / chỉ đuôi / DNG) + câu thẻ viewer + câu hỏi Collage (số nhiều qua String Catalog) |
| Domain | `Domain/Editing/EditSourceChoice.swift` (mới) | cặp hay RAW-only, mục nào mờ, lý do — từ danh sách resource đã rút gọn; mang recipe sang nguồn kia (bỏ 5 thông số RAW khi sang JPEG) |
| Domain | `Domain/Editing/UnsupportedRAWGate.swift` (mới) | chia lượt thêm thành đọc được / không đọc được + cỡ nhỏ nhất |
| Domain | `Domain/Editing/RAWDecoderVerdict.swift` | bậc 2 thử tối đa **hai** file có sẵn của cùng máy trước khi ghi "chưa đọc được" (Q5) |
| Domain | `Domain/Editing/EditorLoadFailure.swift` | case `.unsupportedRAW(UnsupportedRAWMessage)`, `offersShareOriginal` |
| Core | `Core/Models/LibraryGridItem.swift` | `FileTypeBadge.rawExtensions` công khai + `fff`, là nguồn duy nhất (Q2) |
| Core | `Core/Models/SmartAlbumQuery.swift` | `.raw` dùng `FileTypeBadge.rawExtensions` (Q2) |
| Core | `Core/Models/PhotoMediaSubtype.swift` | case `unsupportedRAW` (không bit; `sqlTest` riêng) |
| Data | `Data/Database/AppDatabase.swift` | migration `v26-rawDecoderVerdicts` (số lấy theo số trống kế tiếp **lúc commit** — plan khác đang chạy song song) |
| Data | `Data/Database/RAWVerdictStore.swift` (mới) | đọc/ghi phán quyết; id ảnh RAW-only của máy "chưa đọc được" cho build hiện tại (một truy vấn, join theo máy) |
| Data | `Data/Sources/RAWDecoderProbe.swift` (mới) | bọc `CIRAWFilter.supportedCameraModels` + thử một file (chép tạm, tắt mạng); protocol để test giả |
| Data | `Data/Sources/RAWVerdictPass.swift` (mới) | lượt xét: máy RAW chưa có phán quyết cho build này → 3 bậc |
| Data | `Data/Sources/UnsupportedRAWIndex.swift` (mới) | `@MainActor @Observable`, set id + `version` |
| Data | `Data/Database/LibraryQueries.swift` | `sqlTest` mới cần tham số build |
| Kit | `ShotDexKit/Render/PhotoRenderService.swift` | `inspectSource`: thuộc tính hỏng + gợi ý RAW → `.unsupportedRAW` (AC-9). Không đổi public API |
| App | `App/AppDependencies.swift`, `App/ShotDexApp.swift` | dựng store/pass/index, chạy lượt xét lúc mở app, đưa index vào environment |
| Features | `Features/Shared/PhotoGridCollectionView.swift` | glyph + nhãn VO |
| Features | `Features/Library/PhotoDetailScreen.swift` | cổng trước editor, action sheet, glyph + thẻ, `formatBadge` dùng `FileTypeBadge` |
| Features | `Features/Editing/PhotoEditorController.swift`, `PhotoEditorScreen.swift` | nhận nguồn đã chọn; ghi phán quyết khi hỏng; menu Source mờ + bỏ `try?`; alert có Share Original; editor nhiều ảnh: thông báo + Skip (Q7) |
| Data | `Data/Sources/PhotoEditingService.swift` | `preferredSource` bỏ nhớ nguồn (Q1); `compress` của cặp có RAW hỏng → JPEG (Q6) |
| Features | `Features/Editing/CompressionController.swift` | preview lấy ảnh đọc được đầu tiên |
| Features | `Features/Library/LibraryModel.swift` | gọi lượt xét sau index |
| Features | `Features/Shared/PhotoFilterMenu.swift`, `Domain/Filtering/AlbumFilter.swift` | mục lọc; nhánh album bằng danh sách id (Q3) |
| Features | `Features/Collage/*`, `Features/VideoStudio/*`, `LibraryScreen`, `AlbumDetailScreen`, `SmartAlbumDetailScreen`, `OnThisDayScreen`, `PhotoListScreen`, `CreationsScreen` | cổng hỏi trước khi thêm |
| Test | `RAWDecoderVerdictTests`, `RAWVerdictStoreTests`, `RAWVerdictPassTests` (probe giả), `UnsupportedRAWMessageTests`, `EditSourceChoiceTests`, `UnsupportedRAWGateTests`, `FileTypeBadgeTests`, `PhotoRenderServiceInspectTests` (fixture cắt cụt), `CompressionRAWPairTests`, mở rộng `EditorLoadFailureTests`, `AlbumFilterTests`, `DatabaseTests`, `SmartAlbumTests` (bảng đuôi chung) | |
| UI test | `ShotDexUITests/scripts/unsupported-raw-*.json` | route `ui-drive` cho từng state |
| Docs | FS-03.04b (cột chứng minh), BD-02 §3 (dòng bảng mới), FS-03.07 (Resize: cặp dùng JPEG), FS-06.08 (smart album RAW dùng bảng đuôi chung), FS-06.09 (Unsupported RAW trong menu album), FS-03.04 §2 nếu đổi | |

Logic phán quyết, câu chữ, lựa chọn nguồn và chia lượt thêm đều ở Domain, thuần, test được. View chỉ đọc kết quả.

## 5. Thứ tự task

Mặc định ✅ → ❌ (không còn ⚠️ sau khi duyệt); AC-16 cần sheet của AC-5 nên đi ngay sau AC-5. Mỗi task một commit,
`/build` sau mỗi commit, task đụng UI thêm `/screens`.

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| M1 | **Đo bộ giải trên sim**: `CIRAWFilter.supportedCameraModels` trên iPhone 17 iOS 26.5 và 27.0 (chọn sim bằng `id=`), và iOS 18.6: số mục, tên của Z 6_2 / ILCE-7M4, diff 26.5↔27.0. Với một file của máy **không** có trong danh sách: `CIRAWFilter(imageURL:)` trả nil hay trả object mà `outputImage` nil; `CGImageSourceCopyPropertiesAtIndex` còn đọc được Make/Model không | (AC-1, AC-2, AC-9, AC-12) | ghi số đo vào FS-03.04b §2; không commit code |
| M2 | **Fixture**: một RAW-only của máy có trong 27.0 mà **không** có trong 26.5 (từ diff M1) — nguồn CC0, **không mặt người** (kiểm bằng Vision trước); một DNG bộ giải trả rỗng; một RAW cắt cụt cho AC-9. Tải file cần người dùng cho phép (tên, nguồn, cỡ) | (AC-2, AC-7, AC-9) | fixture vào `ShotDexTests/Fixtures/RAW/`; commit riêng |
| M3 | **Đo PhotoKit**: tạo cặp RAW+JPEG trên sim theo cả hai thứ tự resource (`.photo` JPEG + `.alternatePhoto` RAW và ngược lại) → `ExifReader.photoResource` ghi tên file nào; `requestImage` trả gì cho RAW-only hỏng (bản xem trước nhúng? cỡ bao nhiêu?) trên 3 hãng | (AC-1, AC-5, AC-15, AC-18) | ghi vào FS-03.04b §7; nếu cặp trông như RAW-only → dừng, hỏi lại trước task AC-1 |
| 1 | khoá vòng Resize: lỗi từng ảnh, chạy tiếp, không asset; preview lấy ảnh đọc được đầu tiên; **cặp có RAW không đọc được → dùng JPEG của cặp** (Q6) | AC-14 | test vòng chạy với service giả; `CompressionRAWPairTests.unreadablePairUsesJPEG`; câu "đúng câu AC-3" xanh ở task 5 |
| 2 | bảng `raw_decoder_verdicts` + `RAWVerdictStore` + bộ so tên + bước 1 của lượt xét + **một bảng đuôi** `FileTypeBadge.rawExtensions` + `FFF`, viewer `formatBadge` và smart album `.raw` chuyển sang nó (Q2) | AC-1 | `RAWDecoderVerdictTests` (bảng tên đo ở M1), `RAWVerdictStoreTests` in-memory GRDB, migration test, `FileTypeBadgeTests.oneListEverywhere` |
| 3 | bước 3: chỉ iCloud → "chưa biết", không mở mạng | AC-12 | `RAWVerdictPassTests` với probe giả đếm lần gọi có mạng = 0 |
| 4 | bước 2 (thử file trên máy; hỏng thì thử **file thứ hai** trước khi ghi "chưa đọc được", Q5) + `UnsupportedRAWIndex` + glyph + VO | AC-2 | pass test (probe giả hỏng → 8 id; file 1 hỏng + file 2 đọc được → "đọc được", 0 id); ui-drive dump nhãn VO; ảnh tile 4 thiết bị. **Chờ DESIGN.md §8** |
| 5 | `UnsupportedRAWMessage` + `EditorLoadFailure.unsupportedRAW` + cổng ở Photo Detail; editor nhiều ảnh: thông báo khi tới ảnh đó + **Skip** (Q7) | AC-3 | `UnsupportedRAWMessageTests`, `EditorLoadFailureTests`, `MultiPhotoEditSkipTests` (Skip sang ảnh kế, ảnh khác lưu được); ảnh alert một ảnh và nhiều ảnh |
| 6 | cổng không tải: quyết từ index + phán quyết, không `beginSession` | AC-4 | test cổng không gọi session; máy thật cho phần 0 byte |
| 7 | kit: thuộc tính hỏng + RAW → `.unsupportedRAW` | AC-9 | `PhotoRenderServiceInspectTests` trên fixture cắt cụt (M2) |
| 8 | máy không tên: câu theo đuôi; lượt xét bỏ qua | AC-6 | message test + pass test (0 id) |
| 9 | câu DNG + nút Share Original | AC-7 | message test; ảnh alert |
| 10 | Share Original gửi nguyên byte resource; Settings ≠ All Metadata → alert RAW FS-08.06, Share as JPEG mờ + lý do (Q4) | AC-8 | so số byte file share với `PHAssetResource` trên sim (fixture M2); `ShareBatchPlanTests.unreadableRAWDimsShareAsJPEG`; ảnh alert |
| 11 | lỗi ở editor đè "chưa biết" + index reload | AC-10 | pass test luật đè; ui-drive: mở → lỗi → về lưới, đếm glyph |
| 12 | đổi build → xét lại lúc mở app | AC-11 | store test với hai build giả |
| 13 | action sheet *Edit which version?*, mở đúng nguồn, Source mờ, bỏ `try?` | AC-5 | `EditSourceChoiceTests`; ảnh sheet iPhone + popover iPad + Duo |
| 14 | hỏi lại mỗi lần Edit; RAW → JPEG mang recipe, bỏ 5 thông số nhóm RAW (Q1) | AC-16 | `EditSourceChoiceTests.switchingToJPEGDropsRAWOnlyKinds`; ui-drive hai lần Edit |
| 15 | glyph + thẻ trong viewer, vùng chạm ≥ 44pt | AC-17 | dump frame ≥ 44pt; ảnh 4 thiết bị |
| 16 | mục lọc *Unsupported RAW* + SQL + chip, ở Library và màn album (danh sách id, Q3) | AC-13 | `LibraryQueries` test in-memory (8 / 3 / 5 ảnh), `AlbumFilterTests.unsupportedRAWByIdentifiers` (album 4 + 2 → 4) |
| 17 | cổng hỏi ở Collage (lối vào + khay/picker) | AC-15 | `UnsupportedRAWGateTests`; ui-drive ba nhánh; đếm asset trước Save |
| 18 | cổng hỏi ở Video Studio (lối vào + picker) | AC-18 | gate test; ui-drive Skip → 3 clip |

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Đánh dấu nhầm** máy đọc được (tệ hơn không dấu): một file hỏng riêng lẻ ở bước 2 làm cả máy thành "chưa đọc được" | vừa | bước 2 thử file thứ hai trước khi ghi (Q5); chỉ bước 2 và editor được ghi "chưa đọc được", bước 1 chỉ ghi "đọc được" |
| **Migration**: bảng mới `raw_decoder_verdicts`; plan song song (burst, sao/cờ) cũng thêm migration | cao (trùng số) | đặt số lúc commit, sau `main` mới nhất. Đường lùi: bảng là **kết quả quét**, drop là mất một lượt xét, dựng lại ở lần mở app kế tiếp. Không thêm cột vào `photo_metadata` (BD-02 §1) |
| **Hiệu năng ở 55k**: lượt xét quét đuôi RAW bằng `LIKE` trên `originalFilename` | thấp | lượt xét ngoài indexer, chạy sau khi index yên; `SELECT DISTINCT máy` một lần quét; mỗi máy không khớp thử tối đa vài file, mỗi file chép một lần. Grid đọc set id, không hỏi DB từng ô. `perf-profiler` đo |
| **PhotoKit**: thử file phải tắt mạng; `assetResources` lúc bấm Edit; thứ tự resource của cặp | vừa | M3 đo trước; mọi request trong lượt xét `isNetworkAccessAllowed = false`; `photokit-guard` duyệt |
| **Kit boundary**: `inspectSource` đổi hành vi | thấp | không đổi chữ ký public; `extension-boundary` kiểm; extension không giải RAW (EX-05 §1) |
| **Concurrency**: lượt xét chạy nền, ghi DB, cập nhật index `@MainActor` | vừa | cùng mẫu `ServerUploadIndex.reload`; `swift-concurrency` duyệt |
| **Duo / iPad**: action sheet là popover trên iPad cần neo; thẻ viewer trên Duo trong 669pt và cover 466×678 | vừa | `device-layout` + `duo-ux-review` |
| **Đụng plan song song**: FS-02.06 thêm glyph iCloud cùng dòng tiêu đề bảng thông tin; FS-08.06 hỏi riêng tư khi share RAW; FS-02.06 đổi Share thành sheet mở ngay + modal | cao | xếp glyph cùng một hàng với FS-02.06; Share Original đi qua alert RAW của FS-08.06 (Q4) rồi qua đường Share chung của FS-02.06 |
| Share Original mang nguyên GPS (ImageIO không ghi RAW) | chắc chắn | Settings = All Metadata: nguyên byte. Khác All: alert FS-08.06, chỉ còn Share RAW with Location · Skip (Q4) |
| Mang recipe từ RAW sang JPEG: thông số khác ngoài nhóm RAW có thể trông khác trên JPEG (đã qua xử lý của máy) | chắc chắn | chấp nhận — người dùng chốt mang sang; test chỉ khoá 5 thông số bị bỏ |
| Không có fixture RAW "hỏng" thật nếu diff 26.5↔27.0 rỗng | vừa | rơi về DNG nén lạ / file cắt cụt + probe giả trong test; AC-2/AC-3 trên sim khi đó chỉ chứng minh qua probe giả — báo lại trước khi làm |

## 7. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 8. Cách chứng minh là xong

- **Test**: các file ở §4, chạy `/test <Class>` theo từng task; full suite một lần khi xong cả intent.
- **Màn hình** (`/screens`, `Tools/ui-drive`, `Tools/sim-shot` cho Duo và iPad ngang): tile có glyph · viewer có
  glyph + thẻ · alert có máy / không máy / DNG · action sheet (cặp đọc được, cặp hỏng) · menu Source mờ · menu lọc
  + chip · Resize danh sách lỗi · Collage hỏi · Video Studio hỏi. Mỗi cái trên iPhone 17 (26.5 và 27.0), iOS 18.6,
  iPad (dọc + ngang), Duo trong + ngoài. Không có nhánh `#available` riêng trong phần này, nhưng chrome viewer
  khác nhau giữa 26 và trước 26 nên vẫn chụp cả hai.
- **Tài liệu**: cột "Chứng minh bằng" của FS-03.04b; BD-02 §3 (dòng bảng phán quyết); FS-03.07 (Resize, cặp dùng
  JPEG); FS-06.08 và FS-06.09 (bảng đuôi chung, mục lọc ở album); DESIGN.md §8 glyph (người dùng sửa); dòng Tiến độ
  của intent theo `docs/PROCESS.md` §2. Đã sửa lúc duyệt 2026-10-01: FS-03.04b §2, §3, §4, §7, AC-3/8/13/14/16;
  FS-01.05 §3.
- **Agent ở Deploy**: `data-migration`, `photokit-guard`, `perf-profiler`, `extension-boundary`,
  `swift-concurrency`, `device-layout`, `duo-ux-review`, `a11y-voiceover`, `localization`, `copy-consistency`,
  `hig-components` (action sheet/popover), `ios26-parity`.

## 9. Quyết định (người dùng duyệt 2026-10-01)

| # | Dòng | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| Q1 | AC-16 | hỏi mỗi lần; cặp đã sửa trên RAW mà chọn Edit JPEG → **mang bản sửa sang, bỏ 5 thông số nhóm RAW** | spec §3 + AC-16; task 14 |
| Q2 | §2 | **một** bảng đuôi: `FileTypeBadge` + `FFF`, dùng cho viewer, smart album và luật RAW-only | spec §2; task 2 |
| Q3 | AC-13 | *Unsupported RAW* có cả ở menu lọc màn album, lọc bằng danh sách id | spec §3 + AC-13, FS-01.05 §3; task 16 |
| Q4 | AC-8 × FS-08.06 | Share Original khi Settings ≠ All Metadata đi qua alert RAW của FS-08.06, **Share as JPEG mờ** kèm *iOS can't read this RAW yet*; còn Share RAW with Location · Skip | spec §3 + AC-8; task 10 |
| Q5 | §2 | hỏng thì thử **file có sẵn thứ hai** trước khi ghi "chưa đọc được" | spec §2; task 4 |
| Q6 | ngoài AC | Resize cặp có RAW không đọc được → **dùng JPEG** | spec §4 + AC-14; task 1 |
| Q7 | ngoài AC | editor nhiều ảnh có RAW không đọc được → **thông báo khi tới ảnh đó, kèm Skip** | spec §4 + AC-3; task 5 |
| Q8 | §4 | Combine, Edit in ShotDex, ảnh file server → **để đợt sau** | spec §4 đánh dấu đợt sau; một dòng ở `REVIEW_QUEUE.md` |

Dòng Tiến độ của intent đã ghi 2026-10-01.
