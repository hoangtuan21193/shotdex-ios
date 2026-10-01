# Kế hoạch — Statistics: Insights, bộ gieo 6 biểu đồ, điều kiện "trong tháng" (FS-07)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-07`](../02-functional-spec/FS-07-statistics/README.md) — [01 dashboard](../02-functional-spec/FS-07-statistics/01-dashboard.md) · [02 insights](../02-functional-spec/FS-07-statistics/02-insights.md) · [03 AC](../02-functional-spec/FS-07-statistics/03-acceptance-criteria.md) (18 AC) · điều kiện *trong tháng* ở [FS-01.05 §4](../02-functional-spec/FS-01-library/05-filtering-and-sorting.md) và [FS-06.08 §2](../02-functional-spec/FS-06-collections/08-smart-albums.md) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md), mục 5 |
| Ngày | 2026-10-01 |
| Trạng thái | **đã duyệt 2026-10-01** — 17 task = 17 commit (task 17 bắt đầu bằng phép đo `.limited` trên máy thật) + AC-13 đo tay, không commit. Quyết định ở §6 |

> Dòng `Tiến độ` của intent đã ghi lúc duyệt 2026-10-01. Lưu ý: intent ghi FS-07 có 15 AC, spec hiện có **18**.

## 1. Hiểu đúng chưa

Tab Statistics hôm nay là dashboard biểu đồ người dùng tự dựng, lần đầu gieo 2 biểu đồ. Spec này thêm:
(1) **thẻ Insights** trên đầu màn — tối đa 3 câu khẳng định về thư viện của chính người dùng (tiêu cự tương đương,
cặp body + lens, tỉ lệ chụp chậm, tháng bận nhất), số đếm trong SQL, luật chọn câu là **hàm thuần ở Domain**, câu là
mẫu trọn vẹn trong String Catalog có plural; chạm câu → Library lọc sẵn; ẩn được, bật lại ở Settings;
(2) **bộ gieo 6 biểu đồ** — cần thêm một trục X mới (**cặp thân máy + ống**) và một phép đo mới (**tỉ lệ chụp chậm hơn
1/tiêu cự tương đương**); (3) điều kiện **"trong tháng"** cho bộ lọc Library (`FilterCriteria`) và smart album
(`RuleOperator`). Không cột, không bảng mới; tính trên máy; ≤ 500 ms ở 55k ảnh.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 0 dòng → "No Indexed Photos", không Insights, không biểu đồ | ✅ (phần dashboard) | `StatisticsScreen.swift:131-136` — `totalPhotos == 0` (đếm mọi dòng, `StatisticsModel.swift:64`) thay cả màn bằng `ContentUnavailableView`, kể cả khi đã gieo biểu đồ | không sửa code; khoá bằng route `ui-drive` trên sim thư viện rỗng. Phần "không có thẻ Insights" khoá lại ở task 6 (trạng thái thẻ là hàm thuần, test `.noIndexedPhotos`) |
| AC-2 49 ảnh có máy + 200 screenshot + 30 video → 0 câu, "…— 49 so far." | ❌ | không có Insights; `slowShutterShare`/`summary` không lọc `mediaType` (`StatisticsQueries.swift:147-163, 262-279`) | `StatisticsQueries.insightInputs()` mới (chỉ `mediaType = 1`) + trạng thái thẻ + dòng dưới ngưỡng |
| AC-3 iPhone 13 Pro 850 @26 / 150 @77 → "85%… 26mm equivalent", lọc 25,5–26,5 | ❌ | dữ liệu đã có: `equivalentFocalLength` ưu tiên `FocalLenIn35mmFilm` (`EquivalentFocalLength.swift` `resolve`), cột có chỉ mục (`AppDatabase.swift:85-89`) | nhánh tiêu cự của `InsightSelector` + `GROUP BY ROUND(equivalentFocalLength)`; mm qua `MetadataFormatter.focalLength` ("26mm", Q6) |
| AC-4 X-T5 23 mm → nêu 35 mm, 75% trên 400, biến thể nêu mẫu số | ❌ | crop + quy đổi đã ghi vào dòng (`MetadataStore.swift:551-569`) | luật 90% mẫu số + biến thể câu |
| AC-5 ba cặp (380 / 220 / 400), mô-đun iPhone không gộp | ❌ | `normalizedLensModel` giữ tên mô-đun riêng; không có truy vấn nhóm theo **hai** cột | truy vấn cặp; dữ liệu AC đã sửa (Q5): EOS R6 đứng đầu 40%, gộp mô-đun thì iPhone thành 60% nên test bắt được lỗi gộp |
| AC-6 18% chụp chậm, không mũi tên, không trait nút; 4% → không câu | ❌ | luật đã có ở `slowShutterShare` `StatisticsQueries.swift:262-279` (`shutterSpeedSeconds > 1.0 / equivalentFocalLength`) nhưng trả `%` của mọi loại media và không trả số đếm | đếm `(slow, total)` chỉ ảnh tĩnh; hàng câu không chạm được |
| AC-7 luật chọn thuần: 3 câu, đúng thứ tự, tháng bị bỏ, lặp lại giống hệt | ❌ | không có `Domain/Statistics/` | `InsightSelector.select(_:)` thuần + test |
| AC-8 plural 1/2, 99,6% → "99%", không từ cấm | ❌ | catalog đã có mẫu plural thủ công (`Localizable.xcstrings:353-374` "%lld item"); test chuỗi en có tiền lệ (`PhotoDropImportTests.swift:46-70`) | `InsightCopy` + mục catalog + test quét từ cấm |
| AC-9 chạm câu tiêu cự → Library lọc 25,5–26,5, lưới 850 | ❌ | đường drill có sẵn: `AppNavigation.openLibrary(with:)` `AppNavigation.swift:104-107` → `RootTabView.swift:265-269, 361-365` gán `libraryModel.criteria`; `FilterCriteria.focalRange` + `.equivalent` (`FilterCriteria.swift:131-132`, SQL `LibraryQueries.swift:376-379`) | câu mang `FilterCriteria`; route `ui-drive` |
| AC-10 180/200 máy chưa biết cảm biến → không câu tiêu cự, chân thẻ, chạm mở Unknown Cameras | ❌ | màn có sẵn `CameraDatabaseScreen.swift:39`, link chỉ trong Settings `SettingsScreen.swift:790-793`; `SettingsNavigation` tạo mới mỗi lần mở (`SettingsScreen.swift:61`) → **không có đường mở thẳng từ tab khác** | đếm `focalLength NOT NULL AND equivalentFocalLength IS NULL`; thêm yêu cầu mở Settings tới một mục vào `AppNavigation` |
| AC-11 cài mới → Insights + đúng 6 biểu đồ theo thứ tự; máy cũ → thêm 4 vào cuối, một lần | ❌ | `ChartSpec.defaultSpecs()` gieo **2** (`ChartSpec.swift:73-78`); test khoá 2 (`ChartDashboardTests.swift:87-97`); không có trục **cặp** (`ChartSpec.swift:154-170`) và phép đo **tỉ lệ chụp chậm** (`ChartSpec.swift:302-309`); cờ đã gieo `stats.didSeedCharts` (`SettingsKeys.swift:60`, `StatisticsModel.swift:41-54, 85`) | gieo 6; cờ mới `stats.didSeedCharts.v2`: máy có cờ cũ mà chưa có v2 → thêm #3–#6 vào cuối bảng một lần, rồi ghi v2 (Q1) |
| AC-12 bố cục 1/2/3 cột, Duo ≥ 120pt biểu đồ đầu, cả hai nhánh iOS | ❌ | công thức cột dùng lại được: `StatisticsScreen.swift:99-126` (`minimumCardWidth` 320, kẹp 2…3, `horizontalSizeClass == .regular`) | `InsightsCard` dùng cùng `columnCount`; route `ui-drive` + `Tools/sim-shot` |
| AC-13 55k dòng ≤ 500 ms, ≤ 500 dòng/truy vấn | ❌ (đo tay) | các cột nhóm đều có chỉ mục trừ cặp hai cột (`AppDatabase.swift:85-89`) | ghi thời lượng lượt Insights vào log health; đo trong `/verify` |
| AC-14 `.limited` 312 ảnh → câu + "Based on 312…" + Manage | ❌ (đo trước) | `presentLimitedLibraryPicker()` có sẵn (`LibraryScreen.swift:503-505`). Lượt index tăng dần dựa vào `PHPersistentChange.deleted` (`IndexPipeline.swift:696-716`); chưa biết thu hẹp quyền có được báo là "xoá" không — chỉ lượt quét đầy đủ mới dọn dòng thừa (`IndexPipeline.swift:524-533`). Nếu dòng thừa còn, "312" sai | để cuối; task 17 **bắt đầu bằng phép đo trên máy thật** (`photokit-guard`), rồi mới viết code (người dùng chốt) |
| AC-15 xoá cả 6 → "No Charts" + Insights; mở lại không gieo lại | ✅ (phần biểu đồ) | Delete trong menu thẻ `ChartCard.swift:222-225` → `StatisticsModel.deleteChart` `:105-110`; cờ chặn gieo lại `StatisticsModel.swift:47-54`; "No Charts" `StatisticsScreen.swift:137-142` | test store (gieo → xoá hết → đọc lại 0) + `ui-drive`. Khi thẻ Insights vào (task 6), nhánh "No Charts" phải **giữ** thẻ phía trên — ghi vào task 6 |
| AC-16 Hide Insights → ẩn, nhớ; Settings → Display → Statistics → Show Insights | ❌ | không có gì cho Insights; mục `.display` trong code mang tên **"Thumbnail Metadata"** (`SettingsSection.swift:29`, section `SettingsScreen.swift:666-685`) | đổi tên mục thành **Display**, hai nhóm "Thumbnail Metadata" (giữ nguyên) và "Statistics" (Show Insights) (Q2) |
| AC-17 tháng bận nhất 1.240 → Library *trong tháng* đếm 1.240 | ❌ | `FilterCriteria` không có trường ngày (`FilterCriteria.swift:112-163`; chú thích `ChartSpec.swift:261-262`). Gom tháng hiện có theo **UTC**: `strftime('%Y-%m', creationDate, 'unixepoch')` (`StatisticsQueries.swift:243, 586`) | mọi phép gom thời gian sang `'unixepoch','localtime'` — Insights **và** biểu đồ (Q3); thêm `captureMonth` + chip |
| AC-18 smart album *trong tháng* Aug → 1.240, Jul → 280 | ❌ | toán tử ngày `[.on, .inLastDays, .before, .after, .inRange]` (`SmartAlbumQuery.swift:123`); SQL ngày `SmartAlbumSQLBuilder.swift:102-130`; ô nhập `SmartAlbumRuleRow.swift:184-207`; chip `SmartAlbumConditionsBar.swift:178-190, 245-255` | `RuleOperator.inMonth` + bộ chọn tháng/năm |

Ghi chú phân loại: AC-1 và AC-15 ✅ vì code hôm nay đã làm đúng phần không dính Insights; mệnh đề về thẻ Insights
trong hai AC được khoá lại ở task 6 (thẻ chưa tồn tại thì không có gì để khoá).

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `StatisticsQueries` — `slowShutterShare` (luật chụp chậm), `cameraMonthlyTrend` (dạng SQL gom tháng), `usage(groupedBy:)` | dạng truy vấn Insights; **không** gọi thẳng vì chúng không lọc `mediaType` và không trả số đếm. `summary()`, `focalLengthHistogram()` vẫn không có UI gọi — không thuộc AC, để nguyên |
| `ChartSpec` / `ChartDimension.drillCriteria(key:)` / `bins` (`ChartSpec.swift:219-296`) | trục cặp mới cắm vào cùng khuôn; drill cặp = `cameraBodies` + `lenses` |
| `FocalAngleBucket` (`FilterCriteria.swift:29-48`, mốc `range`) | nhóm tiêu cự của câu Insights (Q4) — cùng mốc với bộ lọc Library nên chạm câu ra đúng tập ảnh; SQL Insights đọc mốc từ đây, không chép số |
| `AppNavigation.openLibrary(with:)` + `pendingLibraryFilter` | mọi câu chạm được |
| `StatisticsScreen.columnCount(forWidth:)`, `cardSpacing`, `floatingChromeSpacer`, `bottomClearance` | bố cục thẻ Insights; không hằng số mới |
| Kiểu thẻ `ChartCard` (bo `AppTheme.Radius.lg` 16, nền `.secondarySystemGroupedBackground`, `.padding()`) | `InsightsCard` — DESIGN.md:64, :94 |
| Lối `.on` trong `SmartAlbumSQLBuilder.swift:104-113` (lịch hiện hành, nửa mở `[start, end)`) | `.inMonth` dùng `calendar.dateInterval(of: .month, …)` |
| `DateRangePickerSheet` (`monthSymbols` `:213`) | tên tháng cho bộ chọn tháng/năm |
| `photoLibrary.presentLimitedLibraryPicker()` | nút Manage (AC-14) |
| `SettingsNavigation.pendingScrollTarget` + `revealPendingRow` (`SettingsScreen.swift:291-309`) | mở Settings tới Unknown Cameras (AC-10) — chỉ cần nguồn yêu cầu từ ngoài Settings |
| Mục plural thủ công trong `Localizable.xcstrings` + cách test ở `PhotoDropImportTests` | AC-8 |
| `LibraryModel.isIndexing` (`LibraryModel.swift:121`) | chân thẻ "Updating as your library is indexed." |

## 4. File đổi và tầng

| File | Đụng gì | Mới / sửa | Tầng |
|---|---|---|---|
| `ShotDex/Domain/Statistics/InsightInputs.swift` | các số đã gom (đếm ảnh có máy, tiêu cự theo mm + theo dải, đếm máy chưa biết cảm biến, top-2 cặp + mẫu số, chụp chậm `(slow,total)`, đếm theo tháng) | mới | Domain |
| `ShotDex/Domain/Statistics/InsightSelector.swift` | ngưỡng §2, thứ tự §3, tối đa 3, hoà điểm, luật tiêu cự §5 (giá trị → dải → gộp dải kề), luật 90% mẫu số, trạng thái thẻ (`noIndexedPhotos` / `belowThreshold(n)` / `insights` + chân thẻ) | mới | Domain |
| `ShotDex/Domain/Statistics/InsightCopy.swift` | dựng câu từ `Insight` (định dạng %, tháng, mm), luật 99% | mới | Domain |
| `ShotDex/Data/Database/StatisticsQueries+Insights.swift` | `insightInputs() throws -> InsightInputs` — ≤ 7 truy vấn gom nhóm trong **một** `read` | mới | Data |
| `ShotDex/Data/Database/StatisticsQueries.swift` | trục cặp và phép đo chụp chậm trong `categoricalData`/`scalar`/`temporalData`; mọi `strftime` gom thời gian thêm `'localtime'` (Q3) | sửa | Data |
| `ShotDex/Core/Models/ChartSpec.swift` | `ChartDimension.cameraLensPair`, `MetricAggregation.slowShutterShare` (không cần trường), `defaultSpecs()` 6 mục | sửa | Core |
| `ShotDex/Core/Models/FilterCriteria.swift` | `captureMonth: CaptureMonth?` (năm + tháng), `isEmpty`, `activeConditionCount`, decode khoan dung | sửa | Core |
| `ShotDex/Core/Models/SmartAlbumQuery.swift` | `RuleOperator.inMonth` (sau `.on`), `isValid`; `migrating` ánh xạ `captureMonth` | sửa | Core |
| `ShotDex/Data/Database/SmartAlbumSQLBuilder.swift`, `LibraryQueries.swift:324-461` | mệnh đề *trong tháng* `creationDate >= ? AND creationDate < ?` | sửa | Data |
| `ShotDex/Features/Statistics/InsightsCard.swift` | thẻ, hàng câu (icon + câu + chevron nếu chạm được), menu Hide Insights, chân thẻ, trạng thái lỗi + Try Again | mới | Features |
| `ShotDex/Features/Statistics/StatisticsModel.swift` | tải Insights song song, không chặn biểu đồ; huỷ lượt cũ; gieo theo cờ v2 (máy cũ thêm 4 biểu đồ vào cuối) | sửa | Features |
| `ShotDex/Features/Statistics/StatisticsScreen.swift` | đặt thẻ trên cả hai nhánh (`columns`, `rows`), giữ thẻ trong "No Charts"; edit mode: thẻ là hàng không kéo, không xoá | sửa | Features |
| `ShotDex/Features/Statistics/ChartEditorSheet.swift:70, 199` | phép đo chụp chậm không hỏi "Of" | sửa | Features |
| `ShotDex/Features/Library/FilterTokenBar.swift:161` | chip `Aug 2026` | sửa | Features |
| `ShotDex/Features/Albums/SmartAlbumRuleRow.swift:184-207`, `SmartAlbumConditionsBar.swift:178-255` | ô chọn tháng + năm, chip | sửa | Features |
| `ShotDex/App/AppNavigation.swift` | `openSettings(at: SettingsRowLabel)`; `SettingsScreen` đọc yêu cầu khi mở | sửa | App |
| `ShotDex/Features/Settings/SettingsScreen.swift`, `SettingsRowLabel.swift`, `SettingsSearchIndex.swift`, `SettingsSection.swift` | mục `.display` đổi tên **Display**; nhóm "Thumbnail Metadata" + nhóm "Statistics" có Show Insights; có trong tìm kiếm Settings (Q2) | sửa | Features |
| `ShotDex/Core/Utils/SettingsKeys.swift` | `showsInsights` (mặc định `true`); `didSeedCharts.v2` | sửa | Core |
| `ShotDex/Resources/Localizable.xcstrings` | mọi mẫu câu, biến thể plural en | sửa | Resources |
| `ShotDexTests/StatisticsInsightsTests.swift` | AC-2…8, AC-10, AC-17 (phần SQL) | mới | Test |
| `ShotDexTests/ChartDashboardTests.swift` | bộ gieo 6, trục cặp, phép đo chụp chậm, allowlist, xoá hết không gieo lại | sửa | Test |
| `ShotDexTests/SmartAlbumMonthRuleTests.swift` | AC-18 + chip `FilterCriteria.captureMonth` | mới | Test |
| `Tools/stats-fixtures` | sinh JPEG nhỏ một màu (không mặt người) có EXIF Model/LensModel/FocalLength/FocalLenIn35mmFilm/ExposureTime/DateTimeOriginal theo kịch bản AC, rồi `simctl addmedia` | mới | Tool |
| `ShotDexUITests/scripts/statistics-*.json` | route cho AC-1, 9, 11, 12, 15, 16, 17 | mới | UI driver |

Không cột, không bảng, không migration. Không đụng ShotDexKit hay extension. Logic chọn câu không nằm trong View.

**Thiết kế cụ thể đề xuất (không phải câu hỏi, nói để duyệt luôn):**
- Trục cặp: `GROUP BY normalizedCameraModel, normalizedLensModel`, cả hai khác rỗng; nhãn `"EOS R6 · RF 85mm F1.2 L USM"`; `drillKey` mã hoá hai phần bằng JSON `["EOS R6","RF 85mm…"]` (tên ống có thể chứa mọi ký tự, nên không dùng ký tự ngăn). Test allowlist mở rộng cho trục hai cột.
- Phép đo chụp chậm: `100.0 * AVG(CASE WHEN shutterSpeedSeconds > 1.0/equivalentFocalLength THEN 1 ELSE 0 END)` với chặn `shutterSpeedSeconds IS NOT NULL AND equivalentFocalLength > 0`; hợp lệ cho `kpi`, `bar`, `line` (donut chỉ đếm). Định dạng "18%".
- "Trong tháng" lưu `number` = một thời điểm **giữa tháng** (ngày 15, 12:00 lịch địa phương), biên dịch bằng `dateInterval(of: .month)` — đổi múi giờ ±14 h vẫn rơi đúng tháng.
- Lọc của câu tiêu cự: `25,5 … 26,5 − 0,0001`, cùng cách nắn mốc với `ChartSpec.swift:232-235`, để ảnh đúng 26,5 mm (SQLite `ROUND` → 27) không bị đếm ở câu này mà lọt vào bộ lọc.
- Trung vị số ảnh theo tháng khi số tháng chẵn = trung bình hai giá trị giữa (AC-17: 310).

## 5. Thứ tự task

Một AC = một task = một commit `feat(FS-07): AC-n …`, build sau mỗi commit, `/screens` khi đụng UI. Thứ tự theo luật
✅ → ❌; AC-11 (bộ gieo) lên sớm vì không phụ thuộc gì; AC-16 cần thẻ Insights (task 6), AC-17 dùng lại mệnh đề tháng
của AC-18 (task 12), nên hai task đó đi sau.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Khoá màn rỗng; viết `Tools/stats-fixtures` + route `statistics-empty.json` | AC-1 ✅ | `ui-drive` trên sim xoá trắng (thư viện 0 ảnh) — ảnh chụp "No Indexed Photos" |
| 2 | Khoá xoá-hết-không-gieo-lại | AC-15 ✅ | `ChartDashboardTests.deletingEverySeededChartLeavesNone` (store) + `statistics-delete-all.json` + mở lại app |
| 3 | Bộ gieo 6: trục cặp, phép đo chụp chậm, `defaultSpecs()`, editor; cờ v2 — máy đã gieo bộ cũ thêm #3–#6 vào cuối, một lần (Q1) | AC-11 | sửa `seedDefaultsAreTopCameraAndTotal` → `seedDefaultsAreTheSixFromFS07`; `existingInstallAppendsFourMissingOnce` (cờ cũ → +4 cuối bảng; xoá rồi mở lại → không mọc); `cameraLensPairGroupsAndDrills`; `slowShutterShareMetric`; allowlist |
| 4 | `InsightSelector` thuần: ngưỡng, thứ tự, tối đa 3, hoà điểm, ổn định; nhóm tiêu cự = `FocalAngleBucket` (Q4) | AC-7 | `StatisticsInsightsTests.selectorKeepsFixedOrderAndDropsFourth`, `…isDeterministic`, ca biên ngưỡng (49/50, 19,9/20%, 4,9/5%, 1,99×/2× trung vị), ca nhóm góc nhìn §5.2–5.3, mốc 19,999 / 20 / 34,999 / 35 |
| 5 | `InsightCopy` + mục catalog plural; mm qua `MetadataFormatter` ("26mm", Q6) | AC-8 | `copyUsesPluralVariants`, `percentNeverRoundsUpToHundred`, `noTemplateContainsBannedWords` (quét mọi mẫu × số 1, 2), `focalUsesAppFormatter` |
| 6 | `insightInputs()` + `InsightsCard` + `StatisticsModel` tải song song + trạng thái thẻ (rỗng, dưới ngưỡng, đang index, lỗi + Try Again); thẻ giữ trong "No Charts"; khoá luôn mệnh đề Insights của AC-1 và AC-15 | AC-2 | in-memory GRDB: 49 + 200 không EXIF + 30 video → `belowThreshold(49)`; `cardStateForEmptyLibraryIsHidden`; log thời lượng lượt; ảnh chụp 5 trạng thái |
| 7 | Câu tiêu cự, iPhone theo mô-đun; nhánh nhóm góc nhìn lọc đúng nhóm của bộ lọc Library | AC-3 | `focalSentenceUsesEquivalentValue` (850/150, "26mm"), `angleGroupSentenceCountEqualsFilterCount` (mốc 19,999 / 20 / 34,999 / 35) |
| 8 | Biến thể mẫu số + X-T5 | AC-4 | `focalSentenceNamesEquivalentAndDenominator` |
| 9 | Chân thẻ máy chưa biết cảm biến + `openSettings(at: .unknownCameras)` | AC-10 | `unknownSensorSuppressesFocalSentence`; route chạm chân thẻ |
| 10 | Câu cặp | AC-5 (dữ liệu 380 / 220 / 400, Q5) | `pairSentenceKeepsPhoneModulesApart` |
| 11 | Câu chụp chậm, không chạm được | AC-6 | `slowShutterSentenceAt18Percent`, `noSlowShutterSentenceBelowFivePercent`; dump `ui-drive`: không trait nút |
| 12 | `RuleOperator.inMonth` cho smart album | AC-18 | `SmartAlbumMonthRuleTests` (Aug 1.240 / Jul 280; ảnh 23:30 ngày cuối tháng giờ địa phương; decode rule lạ vẫn lossy) |
| 13 | Chạm câu tiêu cự → Library | AC-9 | `statistics-focal-drill.json`: chip tiêu cự tương đương bật, lưới 850 |
| 14 | Bố cục thẻ 1/2/3 cột, Duo ≥ 120pt | AC-12 | `statistics-layout.json` trên iPhone 26.5 + 18.6, iPad 13" ngang, iPad 11" dọc, Duo trong; `Tools/sim-shot` cho iPad/Duo; dump đo khung biểu đồ đầu |
| 15 | Tháng bận nhất + `FilterCriteria.captureMonth` + chip; **mọi** gom thời gian (Insights + biểu đồ) sang giờ địa phương (Q3) | AC-17 | `busiestMonthSentenceAndFilterAgree` (SQL đếm = `LibraryQueries.count(matching:)`), `monthGroupingUsesLocalTime` (ảnh 23:30 ngày 31/8 ở UTC+7 → tháng 8 ở cả câu, biểu đồ và bộ lọc); `statistics-month-drill.json` |
| 16 | Hide Insights / Show Insights; đổi tên mục Settings → **Display** với nhóm Thumbnail Metadata + Statistics (Q2) | AC-16 | `statistics-hide-insights.json` + mở lại app + bật lại; ảnh Settings → Display ở bố cục hẹp và cột mục |
| 17 | `.limited`: **bước 0 đo trên máy thật** (thu hẹp quyền có để lại dòng thừa không, `photokit-guard`); rồi chân thẻ "Based on N…" + Manage | AC-14 | máy thật; nếu dòng thừa còn thì thêm việc dọn vào task này hoặc mở intent riêng |
| — | Đo 55k (không commit) | AC-13 | `/verify`: bản in-memory 55k theo đúng thành phần AC-13 + log trên máy thật 55k; ghi số vào báo cáo verify |

## 6. Quyết định (người dùng duyệt 2026-10-01)

| # | Câu hỏi | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| Q1 | AC-11, máy đã có cờ `stats.didSeedCharts` | **cờ lên v2**, máy cũ được thêm 4 biểu đồ còn thiếu vào cuối, một lần | FS-07.01 §3, AC-11, README §4; task 3 |
| Q2 | AC-16, "Settings → Display" | mục "Thumbnail Metadata" đổi tên **Display**, hai nhóm: Thumbnail Metadata và Statistics (Show Insights) | FS-07.02 §6, AC-16; FS-08.01/08.03 ở task 16 |
| Q3 | AC-17, UTC hay giờ địa phương | **giờ địa phương ở mọi chỗ** gom tháng (Insights, biểu đồ, bộ lọc, smart album) | FS-07.01 §5; task 15 |
| Q4 | dải tiêu cự của câu | **nhóm góc nhìn của bộ lọc Library** (`FocalAngleBucket`), để chạm câu ra đúng tập ảnh | FS-07.02 §5, README §4; task 4, 7 |
| Q5 | AC-5 dữ liệu mâu thuẫn | **sửa dữ liệu**: 380 mô-đun chính / 220 mô-đun kia / 400 EOS R6 → EOS R6 đứng đầu 40% | AC-5; task 10 |
| Q6 | "26 mm" hay "26mm" | **"26mm"** qua `MetadataFormatter` của app; sửa ví dụ và AC | FS-07.02 §2, §4, §5, AC-3/4/14; task 5, 7 |
| — | AC-14 `.limited` dòng thừa | **đo trên máy thật** ở đầu task 17 | task 17 |

**Ghi chú, không chặn** (để `/verify` không bỏ sót):
- AC-11 "(3 chuỗi thân máy)" với dữ liệu AC-3 chỉ có một thân máy → biểu đồ đường vẽ **1** đường. Hiểu là *cấu hình*
  `seriesSplit = cameraBody, topN = 3` (khoá bằng unit test), không phải 3 đường trên ảnh chụp.
- Spec có trạng thái **không có AC**: đang index, lỗi truy vấn + Try Again, nhánh nhóm và gộp nhóm (§5.2–5.3), hoà
  điểm, biến thể mẫu số cho câu cặp/chụp chậm (§4 chỉ nói chung). Làm trong task 4/6 kèm unit test; `/verify` sẽ
  báo chúng là "có test, không có AC".

## 7. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **55k, lần mở đầu** chạy 6 biểu đồ gieo + Insights; `binnedData` kéo **mọi dòng** về Swift (`StatisticsQueries.swift:510-519`) cho biểu đồ "Equivalent Focal Length" | trung bình | Insights chạy `Task.detached` riêng, không chờ biểu đồ; mọi gom nhóm Insights trong SQL, ≤ vài trăm dòng/truy vấn; `DatabasePool` đọc song song (`AppDatabase.swift:22`). Đo tay ở `/verify` (AC-13); vượt 500 ms → intent mới, không tối ưu đoán |
| Cặp hai cột không có chỉ mục ghép | thấp | `GROUP BY` một lượt quét 55k; đo trong AC-13 trước khi nghĩ tới chỉ mục (chỉ mục = migration) |
| Plural / localization: câu ghép mảnh, `%` tự định dạng, tháng tự viết | trung bình | mẫu trọn vẹn trong catalog, `FormatStyle` cho %, tháng, mm; test AC-8 quét mọi mẫu; agent `localization` sau task 5 |
| Ngân sách chữ: tiếng Đức dài hơn 30%, cỡ accessibility | trung bình | câu xuống dòng, không `lineLimit`; ảnh chụp AX5 ở task 14 |
| iPad 2–3 cột: thẻ Insights ngoài vòng chia cột nhưng câu bên trong chia cột theo cùng `columnCount` | thấp | dùng đúng hàm `StatisticsScreen.columnCount(forWidth:)`, không công thức thứ hai |
| Duo trong 669pt: thẻ đẩy biểu đồ đầu ra khỏi màn | trung bình | AC-12 đo ≥ 120pt bằng dump; ở cỡ chữ lớn nếu trượt thì hỏi lại, không tự rút câu |
| Duo ngoài 466pt hẹp, 1 cột | thấp | chụp trong task 14 (spec liệt kê Duo ngoài ở ràng buộc dù AC-12 không) |
| `.limited`: dòng metadata của ảnh ngoài tập được cấp còn sót → số "Based on N" sai | **chưa biết** | task 17 sau khi `photokit-guard` đo trên máy thật |
| Đổi gom tháng sang `localtime` (Q3) làm "Photos per Month" lệch so với trước | thấp | app chưa release — không migration, không hỏi (CLAUDE.md) |
| Cờ gieo v2 thêm 4 biểu đồ cho máy đã có bảng: người dùng từng tự dựng biểu đồ trùng tên | thấp | chỉ thêm, không đụng biểu đồ có sẵn; trùng nội dung thì người dùng xoá — lần mở sau không mọc lại |
| Đổi tên mục Settings → Display: tìm kiếm Settings và đường mở thẳng (`SettingsNavigation`) theo tên cũ | thấp | `SettingsSearchIndex` có cả hai từ khoá; test tìm "Thumbnail" vẫn ra mục Display |
| `RuleOperator.inMonth` là raw value mới trong JSON smart album | thấp | decode đã lossy (`LossyRule`, `SmartAlbumQuery.swift:380-386`); không migration |
| Dữ liệu UI: 1.000–2.140 ảnh EXIF giả trên sim | trung bình | `Tools/stats-fixtures` sinh ảnh một màu (không mặt người, theo memory); mỗi kịch bản một sim xoá trắng; iOS 26.5 cấp quyền bằng erase + addmedia + một chạm Allow Full Access; chọn sim bằng `id=` (hai sim tên "iPhone 17") |
| Concurrency: lượt Insights cũ về sau lượt mới (mở tab liên tục) | thấp | giữ `Task` và huỷ khi `load()` lại; `swift-concurrency` review |
| Hai nhánh iOS 26 / trước 26 khác chrome | thấp | thẻ nằm trong cùng `List`/`ScrollView` có sẵn spacer; `ios26-parity` diff dump 26.5 vs 18.6 |

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 9. Cách chứng minh là xong

- **Test** (`/test`): `StatisticsInsightsTests` (AC-2…8, 10, 17 phần SQL), `ChartDashboardTests` (AC-11, AC-15, trục và
  phép đo mới), `SmartAlbumMonthRuleTests` (AC-18). Full suite một lần cuối intent (`Tools/gate`).
- **Màn hình phải chụp** (`/screens statistics`), cả iOS 26.5 và 18.6:
  - iPhone 402×874: rỗng (AC-1), dưới ngưỡng, đang index, lỗi, 3 câu, 6 biểu đồ gieo (AC-11), xoá hết (AC-15), ẩn/hiện (AC-16), chạm tiêu cự → Library (AC-9), chạm tháng → Library (AC-17), smart album *trong tháng* (AC-18), chân thẻ cảm biến → Unknown Cameras (AC-10), AX5.
  - iPad 13" ngang (3 cột câu), iPad 11" dọc (2 cột), Duo trong 951×669 (2 cột, đo ≥ 120pt), Duo ngoài 466×678 — qua `Tools/sim-shot`.
  - Máy thật: `.limited` (AC-14), đo 55k (AC-13).
- **Tài liệu phải cập nhật** cùng commit task tương ứng: cột "Chứng minh bằng" của `FS-07.03` (từng AC); `DESIGN.md`
  §component (thêm `InsightsCard`, :192) và đoạn Dashboard Statistics (:223 — thẻ trên cùng, không chia vòng tròn);
  `FS-08.03 §2` + `FS-08.01 §3` (mục Display gồm Thumbnail Metadata + Statistics, Q2) — task 16; dòng `Tiến độ` của
  intent sau mỗi commit task. Đã sửa lúc duyệt 2026-10-01: FS-07.01 §3 (cờ v2) và §5 (giờ địa phương), FS-07.02
  §2, §4, §5, §6 ("26mm", nhóm góc nhìn, Display → Statistics), FS-07.03 AC-3/4/5/11/14/16, FS-07 README §4.

## 10. Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `swift-concurrency` | `Task.detached` thứ hai trong `StatisticsModel`, huỷ lượt cũ, áp kết quả trên main actor |
| `photokit-guard` | `.limited` (AC-14): dòng thừa sau khi thu hẹp quyền, nút Manage |
| `device-layout` | thẻ Insights trên iPhone, iPad hai hướng, Duo trong/ngoài (AC-12) |
| `ios26-parity` | thẻ trong cả nhánh `List` lẫn cột, chrome 26 vs trước 26 |
| `perf-profiler` | lần mở đầu ở 55k: 6 biểu đồ + Insights (AC-13) |
| `localization` | mẫu câu, plural, %, tháng, mm (AC-8) |
| `a11y-voiceover` | mỗi câu một phần tử, trait nút chỉ khi chạm được (AC-6), cỡ accessibility |

Không cần `data-migration` (không lược đồ mới; raw value mới đi qua decode lossy), `extension-boundary` (không đụng
kit/extension), `memory-leak` (không cache mới).
