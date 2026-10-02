# Kế hoạch — Caption và keyword (FS-02.07)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-02.07`](../02-functional-spec/FS-02-photo-detail/07-caption-and-keywords.md) — 16 AC |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 14 (và mục 9 cho đường "updated" dùng chung với [FS-01.12](../02-functional-spec/FS-01-library/12-rating-and-flags.md)) |
| Ngày | 2026-10-02 |
| Trạng thái | **approved 2026-10-03** — 22 task = 22 commit: 5 phép đo trên simulator iOS 27.0 (task 1–5) đi trước mọi dòng code, 1 phép đo máy thật đi cùng AC-15 (task 21). Quyết định ở §8 |

> Dòng `Tiến độ` của intent đã ghi lúc duyệt 2026-10-03. Task đầu tiên ghi `**đang làm**` theo `docs/PROCESS.md` §2.

## 1. Hiểu đúng chưa

Trên **iOS 27** (API mới: `PHAsset.extendedMetadata` → `caption` / `keywords` / `originalFilename`;
`PHAssetChangeRequest.caption`, `addKeyword(_:)` / `removeKeyword(_:)`; `PHFetchOptions.prefetchAssetExtendedMetadata`
— đọc header SDK 27.1): sửa caption và keyword của **một** ảnh ngay trong Info (section đầu, trên Location, ghi ngay
không có Save), và của **cả mẻ** từ ⋯ của chế độ chọn (sheet *Caption & Keywords*, Apply = **một** lần ghi Photos,
banner có Undo 4 s ghi ngược đúng phần đã đổi, chế độ chọn giữ nguyên). Photos là nguồn thật; app giữ **hai bảng gương**
(keyword, caption) để lọc — không cột nào trong `photo_metadata`. Gương dựng bằng **lượt đọc đầy** (trang 1.000 id, tải
sẵn, tiếp tục được, nhường) và giữ tươi bằng tập **"updated" của lịch sử thay đổi** kể cả khi ngày sửa không đổi
(đường này **FS-01.12 dựng**, xem §7). Lọc: trường **Keyword** (has / doesn't have / has any / has no keywords) và
**Caption** (contains / doesn't contain) trong bộ dựng điều kiện; tìm: `keyword:` / `từ khoá:`, một từ trùng đúng tên
keyword thành chip, chữ tự do khớp thêm caption + keyword. Dưới iOS 27 **ẩn hết**, Info giữ dòng *Keywords* IPTC chỉ đọc
như hôm nay.

## 2. Phép đo trước (spec §10) — làm đầu tiên

Hôm nay **không có một dòng code iOS 27 nào** (`grep extendedMetadata` = 0, `#available(iOS 27` = 0), nên mọi câu ở §10
còn mở. Sim có sẵn: `iPhone 17` iOS 27.0 (`D905D15D-…`, đang boot), iPad Pro 13" M5 27.0, Duo 27.0 (memory
`iphone-duo-ios27`). Cách đo: một bộ `CaptionKeywordProbeTests` chạy trong test bundle (host là app, nên PhotoKit
thật), **tự bỏ qua** khi chưa có quyền hoặc OS < 27 — không bao giờ chạy trong `Tools/gate`. Quyền ảnh trên sim 27 phải
cấp bằng một chạm *Allow Full Access* qua `Tools/ui-drive` (memory `sim-photo-permission-ios26`). Ảnh thử sinh bằng
ImageIO (nhiễu, **không mặt người**), nạp bằng `xcrun simctl addmedia`. Kết quả ghi vào spec §10 trong cùng commit.

| # | Câu hỏi (spec §10) | Cách đo trên sim | Quyết định nó lái |
|---|---|---|---|
| M1 | Sửa caption/keyword có vào tập `updatedLocalIdentifiers`, có đổi `modificationDate` không | probe: lấy token → ghi caption + 1 keyword cho A từ app → `fetchPersistentChanges` + so `modificationDate` trước/sau. Nửa "sửa trong app Photos": `ui-drive` thêm bước mở `com.apple.mobileslideshow` (cần một tham số `app` cho driver) — nếu Info của Photos trên sim 27 không cho sửa keyword thì ❓-3 | không vào "updated" → Info là lưới duy nhất + rủi ro §7 hàng 1; **đổi ngày sửa** → bắt buộc task "đóng dấu ngày sửa" (§7 hàng 2) |
| M2 | Photos có tự nhập IPTC Keywords/Caption khi thêm file | `addmedia` một JPEG có `IPTC Keywords = [Lightroom, test]` + `Caption-Abstract` (sinh bằng `MetadataFixture`), đọc `extendedMetadata` | ghi một câu vào spec §8 ("ảnh Lightroom lọc được ngay" hay "chỉ hiện ở Info") — không đổi code |
| M3 | Ghi thuộc tính cho 1.000 asset: có hộp thoại hệ thống không, bao lâu | `addmedia` 1.000 JPEG nhiễu 64×64; một `performChanges` thêm 1 keyword cho cả 1.000; đo thời gian, chụp màn trong lúc ghi (`Tools/sim-shot`) | ngưỡng modal (spec §5 "trên 1 giây"); > 10 s → chia lô 1.000 (spec §12 hàng 3) |
| M4 | Asset thư viện chia sẻ có từ chối sửa thuộc tính không | sim **không có** iCloud Shared Library — chỉ đo được `canPerformEditOperation(.properties)` = true cho ảnh của mình và ghi được | phần "từ chối" là ❓-2 (máy thật). AC-13 chứng minh bằng writer giả |
| M5 | Photos có giới hạn độ dài caption, keyword không | probe ghi caption 1 / 2.000 / 20.000 ký tự, keyword 1 / 255 / 2.000 ký tự, đọc lại so từng ký tự; thêm keyword rỗng / chỉ khoảng trắng | có trần → ô nhập chặn ở trần (quyết định kỹ thuật, không có đường lỗi); không trần → không chặn |
| M7 | (thêm, mồi cho AC-15) `prefetchAssetExtendedMetadata` có áp cho `fetchAssets(withLocalIdentifiers:options:)` không | 1.000 asset: thời gian đọc `.extendedMetadata` từng asset với / không tải sẵn (lười ≈ ms/asset, tải sẵn ≈ µs) | cách chia trang của lượt đọc đầy (§5 task 8): theo id từ database, hay phải theo `PHFetchResult` |
| M6 | Lượt đọc đầy 55k: tổng thời gian, bộ nhớ đỉnh | **máy thật** 55k — task 21 | ngân sách AC-15; > 60 s thì chạy sau lượt EXIF |

## 3. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 gõ caption trong Info → Photos có chuỗi; mở lại thấy; bàn phím không che ở 4 máy | ❌ | Info = `MetadataPanel` (`Features/Library/MetadataPanel.swift:9`), section đầu là Location `:55-59`; trình bày ở `PhotoDetailScreen.swift:356-362` với `[.medium, .large]`. Không có đọc/ghi `extendedMetadata` ở đâu cả | section `CaptionKeywordSection` (iOS 27) trên Location; `InfoCaptionKeywordModel` đọc sống + ghi qua `PhotoPropertyWriting`; gương cập nhật **sau khi** Photos xong |
| AC-2 xoá hết caption, rời ô → caption rỗng, bảng caption không còn dòng, placeholder | ❌ | như AC-1 | ghi `caption = nil` (header: nil/rỗng = xoá); store xoá dòng |
| AC-3 gõ `sun` → `Sunset 40` đứng đầu; `sunset, beach` + Return → đúng `Sunset`, `beach` | ❌ | có `AutocompleteTokenField` (`Features/Shared/AutocompleteTokenField.swift:8-80`): 8 gợi ý, nhưng `localizedCaseInsensitiveContains` (không bỏ dấu), không số đếm, không tách phẩy | logic ra Domain (`KeywordInput`: tách phẩy, trim, bỏ rỗng; `KeywordSpelling`: cách viết đã có theo khoá hoa-thường); gợi ý từ store, xếp theo số ảnh; ô token dùng chung cho §4 và §5 |
| AC-4 30 ảnh, thêm `Hoi An` + `2026 trip`, Apply → 1 lần ghi, không trùng, banner, chọn còn 30 | ❌ | ⋯ ở `SelectionBarViews.swift:205-276` (Add to Collection `:247`, Duplicate `:263`); thứ tự `PhotoCommand.albumSelectionMenu` `PhotoCommand.swift:59`; mẫu một `performChanges` cho cả mẻ `PhotoLibraryService+Assets.swift:17-24`; banner Undo 4 s có sẵn `App/AppBanner.swift:20-24, 59-67`, host ở `RootTabView.swift:237, 333` | `PhotoCommand.captionKeywords` (`tag`) sau Add to Collection; `CaptionKeywordBatchPlan` (Domain) → `PhotoPropertyWriting.apply(plan)` một khối; banner qua `AppBannerModel`; modal *Updating N photos…* khi ghi > 1 s |
| AC-5 Undo trong 4 s → gỡ `Hoi An` khỏi đúng 18 ảnh, `2026 trip` khỏi 30, 1 lần ghi | ❌ | — | `CaptionKeywordBatchPlan.inverse` (thuần): chỉ phần đã đổi, caption cũ từng ảnh |
| AC-6 `Sunset` ×5 + `sunset` ×2 → một dòng `7 of 30`, gỡ → 0 biến thể | ❌ | — | gom theo khoá hoa-thường trong plan; gỡ mọi cách viết thật trên từng ảnh |
| AC-7 3 caption khác nhau, không đụng ô → *Multiple Captions*, 30 caption giữ nguyên | ❌ | — | plan có `captionEdit: .untouched / .set / .clear`; `.untouched` không sinh ghi caption nào |
| AC-8 smart album *Keyword has Sunset* = 40, *has no keywords* = 150, chân sheet = lưới | ❌ | `RuleField` `Core/Models/SmartAlbumQuery.swift:30-114`; `isValid` `:256` đòi chữ cho kiểu text; `SmartAlbumSQLBuilder.clause` `Data/Database/SmartAlbumSQLBuilder.swift:47` chỉ biết cột `photo_metadata`; đếm chân sheet `RuleBuilderSections.swift` (`matchCount`) | `RuleFieldKind.keyword` + 4 toán tử (2 không cần giá trị); mệnh đề `assetId [NOT] IN (SELECT … FROM photo_keyword …)`; `caption` là kiểu text trên bảng caption |
| AC-9 `keyword:"golden hour"` → chip, 9 ảnh; `85mm` → chip tiêu cự như cũ | ❌ (vế 2 ✅) | tách từ theo khoảng trắng/phẩy `SearchIntentParser.swift:157`, không có cú pháp `trường:` hay ngoặc kép; tên lấy từ `FilterSuggestionCatalog` (`FilterSuggestionCache.swift:6-23`, không có keyword) qua `nameRules` `SearchIntentParser+Names.swift:28`; chữ tự do `LibraryQueries.swift:437-447`. Vế 2 đã khoá: `SearchIntentParserTests.swift:136`, `SearchParserTests.swift:23` | tiền xử lý `keyword:`/`từ khoá:` có ngoặc kép trước khi tách từ; `catalog.keywords`; khớp **đúng** tên → rule keyword; chữ tự do thêm caption + keyword. Xem ⚠️-1 về phần chữ thừa |
| AC-10 thêm `Sunset` cho B trong Photos → lượt tăng dần kế tiếp lọc ra B; 0 lần đọc file B | ❌ | `runFromPersistentChanges` gom `updated` (`IndexPipeline.swift:847-857`, `:695`) nhưng `needsReindex` bỏ qua id có ngày sửa không đổi (`:316-330`, `:740`); tập `updated` không ra khỏi hàm | **phụ thuộc FS-01.12**: đường "updated dù ngày sửa không đổi" (§7). Task này chỉ tiêu thụ nó: đọc lại metadata mở rộng cho tập đó, 0 lần `ExifReader` |
| AC-11 index lại toàn bộ (nâng phiên bản) → gương vẫn 2 keyword + 1 caption | ❌ (cơ chế ✅) | bảng chưa có; nhưng lượt index ghi bằng `upsert` (`MetadataStore.swift:32-49`) — không xoá dòng nên không kéo khoá ngoại; full reindex không xoá dòng nào (`IndexPipeline.swift:418`, xoá chỉ khi `!fullReindex` `:527`) | migration mới (số kế tiếp lúc commit — hôm nay là `v27`, FS-01.12 cũng lấy một số) + `PhotoKeywordStore`; **không** khoá ngoại tới `photo_metadata`; test khoá |
| AC-12 50 ảnh (20 chỉ iCloud), mất mạng, Apply `trip` → 50/50, 0 tải bản gốc, 0 mạng | ❌ | — | writer chỉ đụng `PHAssetChangeRequest` (không resource, không `requestImage`). Rủi ro thật nằm ở **lượt index sau đó** nếu ngày sửa đổi (M1) — §7 hàng 2 |
| AC-13 30 ảnh, 4 từ chối → 26 có `trip`, banner *4 photos can't be changed.* | ❌ | — | `canPerformEditOperation(.properties)` lọc trước khi ghi; cả mẻ bị từ chối → alert; lỗi ghi → alert *Try Again* (NF-04) |
| AC-14 iOS 26.5: Info không ô caption, *Keywords* IPTC `Lightroom, test`; ⋯ và menu trường không có mục mới | ✅ | dòng IPTC `AssetMetadataReader.swift:481`, mảng nối bằng `", "` ở `stringify` `:902-908`; ⋯ và `RuleField.selectableCases` (`SmartAlbumQuery.swift:111`) hôm nay không có gì để ẩn | khoá ngay (task 6): tách `rightsSection` thuần để test; thêm cổng `ExtendedMetadataSupport.isAvailable` (một chỗ cho mọi `#available(iOS 27)`) mà các task sau bắt buộc dùng, mỗi task tự thêm assert "ẩn khi false" |
| AC-15 55k, gương rỗng → ≤ 55 fetch, 0 hỏi lười; thời gian + RAM đỉnh trong ngân sách | ❌ | — | lượt đọc đầy (task 8) + đo máy thật (task 21) |
| AC-16 `.limited`, 10 ảnh chia sẻ; `Private` chỉ ở ảnh không chia sẻ → không gợi ý | ❌ (nền ✅) | dưới `.limited`, `fetchAssets` chỉ trả ảnh đã chia sẻ, và lượt walk xoá dòng không thấy (`IndexPipeline.swift:527-531`) nên `photo_metadata` chỉ có ảnh chia sẻ | gương theo `photo_metadata`: xoá cùng lúc, gợi ý và lọc **JOIN** `photo_metadata` nên dòng gương mồ côi không bao giờ lộ |

**Tổng:** ✅ 1 (AC-14) + vế 2 của AC-9 · ❌ 15 · ⚠️ code–spec 1 (⚠️-1, nằm trong AC-9 — đã quyết 2026-10-03: spec đúng, sửa code ở task 19).

## 4. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `AppBannerModel.show(_:actionTitle:action:)` 4 s khi có nút (`App/AppBanner.swift:20-24, 59`), host ở mọi màn lưới + viewer | banner *Added 2 keywords to 30 photos* · Undo; *4 photos can't be changed.* |
| `PhotoLibraryService+Assets` — một `performChanges` cho cả mẻ (`:17-24`) | `PhotoLibraryService+Properties.swift` cùng mẫu |
| `PhotoCommand` (`Features/Shared/PhotoCommand.swift`) — tên + icon một chỗ | `.captionKeywords` "Caption & Keywords…" / `tag` |
| `SelectionBarModel` closures ⋯ (`App/SelectionBarModel.swift:66-70`) | `onCaptionKeywords` — Library, Album, Smart Album; On This Day không gán |
| `AutocompleteTokenField` | **không** dùng nguyên: cần số đếm, bỏ dấu, phẩy. Ô mới `KeywordTokenField` gọi Domain; ô cũ giữ cho smart album (ghi vào `REVIEW_QUEUE.md` nếu muốn hợp nhất) |
| `PlaceSearchText.normalized` (`Domain/Places/PlaceSearchText.swift`) — gấp hoa thường + dấu + dấu câu | khoá khớp (`foldKey`) của keyword và caption: spec §7 nói "cùng cách cột địa điểm" |
| `SmartAlbumSQLBuilder` + `LossyRule` (lossy decode) | hai trường mới; album hỏng một điều kiện không thành "cả thư viện" |
| `FilterSuggestionCache` (catalog bất biến, làm mới có chủ đích) | `catalog.keywords` (tên + số ảnh) cho parser + gợi ý; làm mới sau mỗi lần ghi và sau lượt đọc |
| `PlaceIndexPass` (actor, chạy sau lượt index, tiếp tục được) + `IndexInteractionGate` | khuôn cho `ExtendedMetadataMirrorPass`; nhường khi tương tác (NF-01 luật 5) |
| `OriginalDownloadModal` (thẻ giữa màn, khoá chạm) | dáng thẻ cho modal *Updating 5,000 photos…* — biến thể không Cancel |
| `MetadataFixture` (`ShotDexTests/MetadataFixture.swift`) | JPEG có IPTC Keywords/Caption cho M2 + AC-14 |
| `AssetActionsCoordinator.perform` + alert *Couldn't Update Photos* | đường lỗi; thêm biến thể có *Try Again* |

## 5. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Domain | `Domain/Metadata/KeywordInput.swift` (mới) | tách phẩy, trim, bỏ rỗng; `caseKey` (chỉ hoa-thường) và `foldKey` (= `PlaceSearchText.normalized`); chọn cách viết đã có theo `caseKey` |
| Domain | `Domain/Metadata/CaptionKeywordBatchPlan.swift` (mới) | từ (trạng thái từng ảnh, thêm, gỡ theo `caseKey`, `captionEdit`) → thay đổi từng asset; `inverse`; nhãn banner (`added N keywords` / `updated N photos`) + số bị từ chối; dòng *On These Photos* (`12 of 30`) |
| Domain | `Domain/Indexing/ExtendedMetadataMirrorPass.swift` (mới) | actor: lượt đọc đầy (trang 1.000 id từ database, tiếp tục theo con trỏ), lượt đọc lại theo tập id (AC-10), dọn dòng không còn; mỗi trang **fetch + commit không `await` ở giữa** (§7 concurrency) |
| Domain | `Domain/Filtering/SearchIntentParser.swift`, `+Names.swift` | `keyword:` / `từ khoá:` (gấp → `tu khoa:`) có ngoặc kép; tra keyword **đúng tên** sau place/body/lens/brand đúng tên, trước khớp một phần |
| Core | `Core/Models/SmartAlbumQuery.swift`, `Features/Albums/SmartAlbumConditionsBar.swift` | `RuleField.keyword`, `.caption`; `RuleFieldKind.keyword`; toán tử `hasKeyword`, `lacksKeyword`, `hasAnyKeyword`, `hasNoKeywords`; `isValid` cho toán tử không giá trị; `selectableCases` theo `ExtendedMetadataSupport`; chip `keyword: Sunset`, `no keywords`, `caption contains "wedding"` |
| Core | `Core/Utils/ExtendedMetadataSupport.swift` (mới) | `isAvailable` (= `#available(iOS 27, *)`, ghi đè được trong test) — cổng duy nhất |
| Data | `Data/Database/AppDatabase.swift` | migration số kế tiếp: `photo_keyword(assetId, keyword, caseKey, foldKey, PK(assetId, keyword))` + index `caseKey`, `foldKey`, `assetId`; `photo_caption(assetId PK, caption, foldKey)`; `extended_metadata_state(id, cursorAssetId, completedAt, osBuild)`. Không khoá ngoại |
| Data | `Data/Database/PhotoKeywordStore.swift` (mới) | thay gương của một tập asset (một transaction), xoá theo id, đếm theo `caseKey` (JOIN `photo_metadata`), trạng thái lượt đọc |
| Data | `Data/Database/MetadataStore.swift` `deleteAssets` `:120`, `deleteAll` `:284` | xoá dòng gương **cùng transaction**; Clear index xoá cả gương + trạng thái (gương dựng lại từ Photos, khác bảng sao/cờ) |
| Data | `Data/Database/SmartAlbumSQLBuilder.swift`, `LibraryQueries.swift:437` | mệnh đề keyword/caption; chữ tự do thêm caption + keyword |
| Data | `Data/Database/FilterSuggestionCache.swift` | `keywords: [KeywordCount]` |
| Data | `Data/Sources/SearchService.swift:99, 141` | chữ thừa khớp cùng tập cột với chữ tự do (máy, ống, tên file, caption, keyword) thay vì `filename contains` (⚠️-1) |
| Features | `Features/Statistics/ChartEditorSheet.swift:116` | điều kiện biểu đồ có Keyword/Caption qua `RuleBuilderSections` (❓-1); không code riêng nếu `selectableCases` đủ |
| Data | `Data/Sources/PhotoLibraryService+Properties.swift` (mới) | `protocol PhotoPropertyWriting` + bản PhotoKit `@available(iOS 27)`: lọc `canPerformEditOperation(.properties)`, một `performChanges`, đọc lại `modificationDate` sau khi xong |
| Data | `Data/Sources/ExtendedMetadataReader.swift` (mới) | `protocol ExtendedMetadataReading` + bản PhotoKit: fetch theo id với `prefetchAssetExtendedMetadata = true`; giả trong test đếm số fetch / số truy cập lười |
| Features | `Features/Library/MetadataPanel.swift` | section caption + keyword trên Location (iOS 27) |
| Features | `Features/Library/CaptionKeywords/` (mới): `InfoCaptionKeywordModel`, `CaptionKeywordSection`, `CaptionKeywordSheet`, `CaptionKeywordSheetModel`, `KeywordTokenField` | UI §4, §5; logic ở model + Domain |
| Features | `Features/Shared/PhotoCommand.swift`, `Features/Library/SelectionBarViews.swift:247`, `App/SelectionBarModel.swift`, `LibraryScreen`, `AlbumDetailScreen`, `SmartAlbumDetailScreen` | mục ⋯ sau Add to Collection; ẩn dưới 27 |
| Features | `Features/Albums/SmartAlbumRuleRow.swift:104, 330` | trình sửa cho kiểu keyword (ô gợi ý có số, toán tử không giá trị thì không có ô) |
| Features | `Features/Library/LibraryModel.swift:599` | chạy `ExtendedMetadataMirrorPass` sau lượt index như `startPlaceLookup`; làm mới catalog khi có việc |
| Chữ | `Localizable.xcstrings` | *Add a Caption*, *Add Keyword*, *Caption & Keywords*, *Multiple Captions*, *Clear Captions*, *On These Photos*, `%lld of %lld`, banner số nhiều, *Updating %lld photos…*, *%lld photos can't be changed.*, VO *keyword* / *Remove* / *unchanged* / *will be removed* |
| Test | `KeywordInputTests`, `CaptionKeywordBatchPlanTests`, `PhotoKeywordStoreTests`, `ExtendedMetadataMirrorPassTests`, `CaptionKeywordSheetModelTests`, `InfoCaptionKeywordModelTests`, `SmartAlbumKeywordRuleTests`, mở rộng `SearchIntentParserTests`, `SearchServiceTests`, `ChartDashboardTests`, `DatabaseTests`, `AssetMetadataReaderTests`; `CaptionKeywordProbeTests` (đo, tự bỏ qua) | |
| Docs | FS-02.07 (§8 hai khoá, §10 số đo, cột chứng minh), BD-02 §3 (hai bảng gương + trạng thái), FS-06.08 §2 (trường mới), FS-01.03 (`keyword:`), DESIGN.md §8 (`tag`), NF-01 nếu thêm pass | |

## 6. Thứ tự task (một AC = một task = một commit)

Mọi task UI: build → `/screens` (iPhone 17 27.0, iPad Pro 13" 27.0, Duo trong + ngoài 27.0 qua `Tools/sim-shot`,
và iPhone 26.5 cho nhánh ẩn) → **`design-parity` trên board tương ứng** của canvas editor — board **đã có**: section Info
`PH29`/`IP20`/`IPP16`/`DI15`/`DIP15`/`DC16` `_InfoKeywords`, sheet hàng loạt `PH30`/`IP21`/`IPP17`/`DI16`/`DIP16`/`DC17`
`_BulkKeywords`. Export `project/` của canvas vào `build/design/editor/project/` trước task UI đầu tiên (task 9).

| # | Task | AC | Test / bằng chứng |
|---|---|---|---|
| 1 | **Đo M1** + khung `CaptionKeywordProbeTests` (tự bỏ qua; ui-drive cấp quyền) | (AC-10, AC-12) | số đo vào spec §10 câu 1 |
| 2 | **Đo M2** (`addmedia` JPEG IPTC) | (AC-14, §8) | spec §10 câu 2 |
| 3 | **Đo M3** + **M7** (1.000 asset: thời gian ghi, hộp thoại, tải sẵn theo id) | (AC-4, AC-15) | spec §10 câu 3; ngưỡng modal + cách chia trang chốt ở đây |
| 4 | **Đo M5** (độ dài) | (AC-1, AC-3) | spec §10 câu 5 |
| 5 | **Đo M4** phần làm được trên sim; phần "từ chối" ghi ❓-2 | (AC-13) | spec §10 câu 4 |
| 6 | **Khoá AC-14** (✅): tách `rightsSection` thuần, test IPTC `[Lightroom, test]` → `Lightroom, test`; thêm `ExtendedMetadataSupport` | AC-14 | `AssetMetadataReaderTests.iptcKeywordsJoin`; ảnh Info trên iPhone 26.5. Từ đây mọi task UI thêm assert "ẩn khi `isAvailable == false`" |
| 7 | Bảng gương + `PhotoKeywordStore`; xoá cùng `deleteAssets`/Clear index; full reindex không đụng | AC-11 | `PhotoKeywordStoreTests.fullReindexKeepsMirror` (upsert lại cả dòng `photo_metadata` + nâng `indexerVersion`), `.deleteAssetsTakesMirror`, migration test trong `DatabaseTests` |
| 8 | Lượt đọc đầy `ExtendedMetadataMirrorPass` (trang 1.000 id, tải sẵn, con trỏ, nhường, dọn dòng thừa) + đếm gợi ý JOIN `photo_metadata` | AC-16 | `ExtendedMetadataMirrorPassTests.limitedSeesOnlyShared` (nguồn giả 10 ảnh), `.pagesOf1000`, `.resumesFromCursor`; `PhotoKeywordStoreTests.suggestionsIgnoreOrphans`; ảnh gợi ý dưới `.limited` trên sim |
| 9 | Info: caption (đọc sống, sửa gương nếu lệch, ghi khi rời ô / Done) + `PhotoPropertyWriting` | AC-1 | `InfoCaptionKeywordModelTests.writesThenMirrors` (writer giả: gương chỉ đổi sau khi writer xong), `.liveReadRepairsMirror`; ui-drive gõ → đóng → mở lại, 4 máy, bàn phím không che (dump frame ô so với bàn phím) |
| 10 | Info: xoá caption | AC-2 | `InfoCaptionKeywordModelTests.emptyClears` (writer nhận `nil`, store 0 dòng); ảnh placeholder |
| 11 | Info: keyword — ô token, gợi ý 8 có số, phẩy, cách viết sẵn có, capsule × + VO *Remove* | AC-3 | `KeywordInputTests.commaSplits`, `.reusesExistingCase`, `.diacriticsStayDistinct`; `PhotoKeywordStoreTests.suggestionsRankByCount`; ui-drive `sun` → dump hàng đầu `Sunset, 40` |
| 12 | Sheet *Caption & Keywords…* + mục ⋯ (`tag`, sau Add to Collection, Library/Album/Smart Album) + Apply một khối + banner + chọn giữ nguyên + modal > 1 s (ngưỡng theo M3) + DESIGN.md §8 | AC-4 | `CaptionKeywordBatchPlanTests.addTwoToThirty` (0 trùng), `CaptionKeywordSheetModelTests.applyIsOneWrite` (writer giả đếm `performChanges` = 1), ảnh sheet 4 máy + banner |
| 13 | Undo ghi ngược đúng phần đã đổi | AC-5 | `CaptionKeywordBatchPlanTests.inverseRemovesOnlyAdded` (18 / 30), `.inverseRestoresCaptions`; 1 lần ghi |
| 14 | *On These Photos*: gom theo hoa-thường, ⊖ xoay hai trạng thái, VO | AC-6 | `CaptionKeywordBatchPlanTests.removeFoldsCase` (5 + 2 → 0) |
| 15 | Caption hàng loạt: *Multiple Captions*, Clear Captions, không đụng = không ghi | AC-7 | `CaptionKeywordBatchPlanTests.untouchedCaptionWritesNothing` (so từng ký tự 30 caption) |
| 16 | Ảnh chỉ iCloud, mất mạng | AC-12 | `CaptionKeywordSheetModelTests.neverFetchesOriginals` (`OriginalFetching` giả = 0 lần); nếu M1 nói ngày sửa đổi: `.stampsModificationDate` + `IndexDiffTests` không đọc lại asset vừa ghi. Đầu-cuối thật → ❓-4 |
| 17 | Từ chối một phần / cả mẻ / lỗi ghi + *Try Again* | AC-13 | `CaptionKeywordSheetModelTests.partialRefusal` (26 / 4, banner), `.allRefusedAlerts`, `.failureLeavesMirror` |
| 18 | Trường Keyword + Caption trong bộ dựng điều kiện — Advanced Search, smart album **và điều kiện biểu đồ Statistics** (cùng `RuleBuilderSections`, cùng SQL, ❓-1); chip | AC-8 | `SmartAlbumKeywordRuleTests` (40 / 150 trên GRDB trong bộ nhớ, đếm chân sheet = lưới), `SmartAlbumRuleDecodingTests` cho toán tử mới, `ChartDashboardTests.keywordConditionFiltersChart` (biểu đồ đếm có điều kiện *Keyword has Sunset* = 40, qua `StatisticsQueries.filterAndScope`); ảnh trình sửa trên Duo trong + trình sửa biểu đồ có trường Keyword/Caption |
| 19 | Tìm: `keyword:` / `từ khoá:` / ngoặc kép, chip theo tên đúng, chữ tự do + caption/keyword; **chữ thừa** khi parser hiểu một phần câu khớp cùng tập cột với chữ tự do, không còn `filename contains` (`SearchService.swift:99, 141`, ⚠️-1) | AC-9 | `SearchIntentParserTests.keywordPrefixQuoted`, `.exactKeywordBecomesChip`, `.85mmStaysFocal` với vocabulary có keyword; `DatabaseTests.searchTextMatchesCaption`; `SearchServiceTests.leftoverWordsMatchCaption` (`fukuoka wedding` → chip địa điểm + ảnh có caption *wedding*) |
| 20 | Giữ tươi qua tập "updated" — **chờ đường của FS-01.12** | AC-10 | `ExtendedMetadataMirrorPassTests.updatedIdsRereadWithoutExif` (tập giả {B}, ngày sửa không đổi, `ExifReader` giả = 0); sim: sửa trong Photos (theo M1) |
| 21 | **Đo M6 máy thật** + log thời gian / RAM đỉnh của lượt đọc đầy; nếu > 60 s dời ra sau lượt EXIF | AC-15 | `ExtendedMetadataMirrorPassTests.fetchCountIsPages` (55k id giả → 55 fetch, 0 lười); số máy thật vào spec §10 câu 6 |
| 22 | Chữ, ảnh mọi máy, cột chứng minh FS-02.07, BD-02 §3, FS-06.08 §2, FS-01.03, `/verify FS-02.07` + full suite một lần | tất cả | |

Task 1–5 không gắn AC riêng: chúng là cổng mà spec §10 tự đòi "phải đo trước `/plan`". Task 7–8 (nền dữ liệu) đi
trước UI vì AC-1 đã phải "sửa gương". Task 20 nằm cuối vì phụ thuộc FS-01.12; không task nào khác chờ nó.

## 7. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Phụ thuộc FS-01.12**: đường đọc lại tập `updated` dù ngày sửa không đổi | chắc chắn | FS-01.12 sở hữu (sao iOS 27 cần đúng đường này, spec §12 hàng 4 cấm dựng lượt thứ hai). Thứ cần từ nó: sau mỗi lượt tăng dần, `IndexPipeline` giao ra `{inserted ∪ updated, deleted}` kể cả id bị `needsReindex` bỏ qua (`IndexPipeline.swift:740`), **và** cờ "lịch sử hết hạn / vừa đi walk đầy" để gương chạy lượt đọc đầy. Chỉ task 20 chờ; nếu FS-01.12 dựng khác tên, task 20 theo tên đó |
| **Ghi keyword làm đổi `modificationDate`** (M1) → lượt index kế tiếp đọc lại EXIF cả mẻ 5.000 ảnh, ảnh chỉ iCloud thì **kéo bản gốc qua mạng** khi mạng được phép — phá AC-12 | vừa | nếu M1 nói có: writer đọc lại `modificationDate` sau `performChanges` và ghi vào `photo_metadata` **cùng transaction** với gương → `needsReindex` thấy không đổi. Sửa từ app Photos vẫn kéo một lần đọc lại (chấp nhận, như sửa ảnh). FS-01.12 gặp cùng câu hỏi với sao — làm một hàm dùng chung |
| Lịch sử thay đổi không báo sửa keyword (M1) | thấp–vừa | Info đọc sống + sửa gương (AC-1); thêm lượt đọc lại theo trang khi mở app chỉ nếu số đo M6 cho phép — hỏi lại trước khi làm |
| **Concurrency**: trang của lượt đọc đầy đọc giá trị cũ rồi commit **sau** khi người dùng vừa ghi → gương lùi | vừa | một actor duy nhất ghi gương; mỗi trang fetch (đồng bộ) + commit trong cùng một lượt actor, không `await` ở giữa; cập nhật sau khi người dùng ghi đi qua cùng actor. `swift-concurrency` duyệt |
| **Migration đụng nhau** với FS-01.12 (cả hai lấy `v27`), cùng sửa `MetadataStore.deleteAssets`, `RuleField`, `RuleBuilderSections`, ⋯ chọn, Info | cao | lấy số kế tiếp lúc commit; commit nhỏ, `git commit -- <paths>`, không stash/checkout (memory `two-agents-shared-checkout`); ai sửa `deleteAssets` sau thì rebase lên bản kia |
| Mệnh đề `assetId IN (SELECT …)` mơ hồ nếu truy vấn ngoài có JOIN bảng khác cũng có `assetId` | thấp | test mỗi đường gọi `SmartAlbumSQLBuilder` (lưới, đếm, `StatisticsQueries.filterAndScope` `:389`) |
| Gợi ý mỗi phím trên 55k ảnh × vài keyword | vừa | đếm theo `caseKey` một lần vào `FilterSuggestionCache` (danh sách + số), lọc trong bộ nhớ mỗi phím; làm mới sau ghi. `perf-profiler` |
| Lượt đọc đầy 55k (M6): thời gian, RAM; prefetch theo id có thể không hiệu lực (M7) | vừa | trang 1.000, `autoreleasepool` mỗi trang, nhường qua `IndexInteractionGate`, tiếp tục theo con trỏ; M7 sai thì chia trang theo `PHFetchResult` có `fetchLimit` |
| Ghi rất lớn bị hệ thống hỏi hoặc > 10 s (M3) | thấp | chia lô 1.000 (spec §12); Undo phủ các lô đã ghi |
| **Duo trong 669pt** + bàn phím: ô gõ và gợi ý; Apply bị đẩy khỏi thanh trên; Duo ngoài: Cancel/Apply dưới rail 84pt | vừa | sheet `[.medium, .large]`, gợi ý cuộn dưới ô, `scrollDismissesKeyboard`; `duo-ux-review` + `device-layout` |
| Banner (bottom inset 120, `RootTabView.swift:237`) đè khay chọn của `SelectionOverlay` khi chế độ chọn giữ nguyên | vừa | đo frame bằng `ui-drive dump`; nâng inset khi overlay đang hiện nếu chồng |
| Sim 27 không cho cấp quyền ảnh bằng `simctl` | cao | một chạm *Allow Full Access* qua ui-drive; kẹt thì erase + addmedia (memory) |
| Ảnh thử có mặt người | — | chỉ ảnh sinh bằng ImageIO |

## 8. Quyết định (người dùng duyệt 2026-10-03)

Người dùng chấp nhận mọi đề nghị của plan.

| # | Chỗ | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| ⚠️-1 | spec §7 "chữ tự do khớp thêm caption và keyword" vs code: chữ thừa khi parser hiểu một phần câu thành rule `filename contains` (`SearchService.swift:99, 141`) | **spec đúng** — chữ thừa khớp cùng tập cột với chữ tự do (máy, ống, tên file, caption, keyword), chip vẫn hiện | FS-02.07 §7 nêu rõ luật chữ thừa + ví dụ `fukuoka wedding`; task 19 sửa `SearchService` |
| ❓-1 | trình sửa biểu đồ Statistics dùng chung `RuleBuilderSections` (`ChartEditorSheet.swift:116`), spec chỉ nêu Advanced Search và Smart Album | **hiện** Keyword và Caption ở cả điều kiện biểu đồ: cùng bộ dựng, cùng SQL (`StatisticsQueries.swift:389`) | FS-02.07 §3, §7 thêm điều kiện biểu đồ Statistics; task 18 |
| ❓-2 | M4: sim không có iCloud Shared Library | AC-13 chứng minh bằng writer giả; máy thật có Shared Library thì xác nhận, không có thì spec §6 hàng 2 ghi "chưa đo" | task 5, 17; `/verify` |
| ❓-3 | M1 nửa "sửa trong app Photos" | thử driver mở `com.apple.mobileslideshow` trên sim 27; không được thì người dùng sửa tay một ảnh (sim hoặc máy thật) rồi app đo; AC-10 có test giả từ trước | task 1, 20 |
| ❓-4 | AC-12 cần ảnh chỉ có trên iCloud, sim không có | `OriginalFetching` giả (0 lần) + kiểm writer không đụng resource; đầu-cuối thật đi cùng M6 trên máy 55k | task 16, 21 |

**Quyết định kỹ thuật đã tự chốt** (không cần duyệt, ghi để thấy):
- **Hai khoá**, không phải một như chữ của spec §8: `caseKey` (chỉ gấp hoa-thường) để chọn cách viết, gom dòng §5 và gom
  gợi ý — vì §4 nói `Đà Lạt` và `Da Lat` là hai keyword; `foldKey` (hoa-thường + dấu, = `PlaceSearchText.normalized`) để
  khớp gợi ý, lọc và tìm — vì §4/§7 nói khớp không phân biệt dấu. Sửa chữ §8 ở task 22.
- Gương **đi theo** `photo_metadata` (xoá cùng transaction, Clear index xoá cả gương rồi dựng lại) — khác bảng sao/cờ của
  FS-01.12, vì gương là bản sao của Photos, còn sao/cờ là dữ liệu chỉ app có.
- Lượt đọc đầy chia trang bằng id lấy từ database (55k → 55 fetch có tải sẵn), không theo `PHFetchResult` — trừ khi M7 nói tải sẵn không áp cho fetch theo id.
- Keyword đúng tên xếp **sau** place/thân máy/ống/hãng đúng tên và **trước** mọi khớp một phần — đúng tên luôn thắng.
- Có trần độ dài (M5) thì ô nhập chặn ở trần, không có đường lỗi.

## 9. Phản biện

(điền sau khi chạy `challenger` trên plan này)

## 10. Cách chứng minh là xong

- **Test:** mọi test ở §6; `CaptionKeywordProbeTests` chỉ chạy tay trên sim 27 (tự bỏ qua ở `Tools/gate`); full suite
  một lần ở task 22 (memory `full-suite-once-per-intent`).
- **Đo:** M1–M5, M7 trên `iPhone 17` iOS 27.0 (task 1–5); M6 + đầu-cuối AC-12 trên máy thật 55k (task 21); phần
  từ chối của M4 trên máy có Shared Library nếu có (❓-2).
- **Ảnh phải chụp** (27.0: iPhone 17, iPad Pro 13", Duo trong 951×669 có bàn phím, Duo ngoài 466×678; 26.5: iPhone 17
  cho nhánh ẩn): Info với caption rỗng / có chữ / đang gõ + gợi ý; capsule keyword; ⋯ có và không có mục mới; sheet
  với *Multiple Captions*, dòng `7 of 30` thường và gạch đỏ; banner + Undo trên khay chọn; modal *Updating…*; banner từ
  chối; trình sửa điều kiện Keyword (4 toán tử) và Caption; chip tìm `keyword: golden hour`. Mỗi màn có board: `design-parity`.
- **Tài liệu:** cột "Chứng minh bằng" FS-02.07; spec §8 (hai khoá, kết quả M2) và §10 (số đo); BD-02 §3 (hai bảng gương
  + bảng trạng thái, luật "gương đi theo `photo_metadata`"); FS-06.08 §2; FS-01.03 (cú pháp `keyword:`); DESIGN.md §8
  (Caption & Keywords = `tag`).
- **Agent ở Deploy:**
  - `photokit-guard` — `performChanges` thuộc tính, `canPerformEditOperation(.properties)`, `.limited`, tải sẵn metadata mở rộng, lịch sử thay đổi;
  - `data-migration` — migration mới, không khoá ngoại, xoá cùng transaction, Clear index;
  - `swift-concurrency` — actor gương, thứ tự trang ↔ ghi của người dùng, `Task` sau ghi;
  - `perf-profiler` + `memory-leak` — lượt đọc đầy 55k, gợi ý mỗi phím, catalog;
  - `device-layout` + `duo-ux-review` — Info và sheet trên Duo trong có bàn phím, Duo ngoài với rail;
  - `ios26-parity` — 27.0 hiện, 26.5 ẩn hết, Info IPTC như cũ;
  - `a11y-voiceover` — capsule *Sunset, keyword* + *Remove*, dòng *on 12 of 30 photos, unchanged / will be removed*;
  - `copy-consistency` + `localization` — số nhiều của banner, *Multiple Captions*, `từ khoá:`;
  - `design-parity` — từng board; `challenger` trước khi duyệt plan.
