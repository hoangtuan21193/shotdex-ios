# ShotDex — Photo Metadata Explorer (iOS Native, Swift)

Ứng dụng iOS native bằng Swift/SwiftUI dành cho người đam mê nhiếp ảnh: duyệt toàn bộ thư viện ảnh, lọc ảnh theo thiết bị và thông số chụp, xem thống kê về camera body, lens và tiêu cự sử dụng nhiều nhất.

---

## 1. Mục tiêu sản phẩm

Dành cho người chụp bằng nhiều camera body và lens khác nhau, muốn trả lời:

- Tôi dùng camera body nào nhiều nhất?
- Tôi dùng lens nào nhiều nhất?
- Tôi thường chụp ở tiêu cự nào?
- Tôi thường chụp ở ISO, khẩu độ, tốc độ màn trập nào?
- Tôi chụp nhiều hơn bằng Full Frame, APS-C hay Micro Four Thirds?
- Quy đổi sang tiêu cự tương đương Full Frame, tôi thường chụp ở góc nhìn nào?

Không phải app chỉnh sửa ảnh. Trọng tâm: duyệt ảnh, đọc metadata, tìm kiếm/lọc, thống kê thói quen chụp, so sánh camera/lens/tiêu cự.

## 2. Nền tảng và công nghệ

- **SwiftUI** làm UI framework (UIKit khi cần perf/paging: grid `UICollectionView`, zoom viewer, detail pager `UIPageViewController`)
- **PhotoKit** cho photo library: `PHPhotoLibrary`, `PHAsset`, `PHCachingImageManager`, `PHPhotoLibraryChangeObserver`
- **ImageIO** đọc EXIF: `CGImageSourceCopyPropertiesAtIndex`, không decode ảnh
- **GRDB.swift** (SQLite) cho database — SQL aggregate cho filter và statistics
- **Swift Charts** cho màn hình thống kê (bar, histogram, donut qua SectorMark)
- **Observation framework** (`@Observable`) + environment injection cho state management / DI
- `UIScrollView` wrap trong `UIViewRepresentable` cho pinch-to-zoom trong photo detail
- `UIActivityViewController` / `ShareLink` cho share
- `.sheet` + `presentationDetents` cho modal sheet, `Menu` cho pull-down menu
- `UserDefaults` / `@AppStorage` cho settings
- **Swift Concurrency** (async/await, `TaskGroup`, actor) cho background work
- Font: San Francisco mặc định
- Haptics: `UIImpactFeedbackGenerator` / `.sensoryFeedback`

**Minimum deployment target: iOS 17** — cần cho Swift Charts, Observation framework, `presentationDetents`.

**Dependency bên thứ ba duy nhất: GRDB.swift** (qua Swift Package Manager). Mọi thứ khác dùng framework hệ thống. Không dùng SwiftData vì statistics cần aggregate SQL (GROUP BY, histogram bucket, percentile) — GRDB phù hợp hơn.

Không đọc lại metadata toàn thư viện mỗi lần mở app — có cơ chế index và cache metadata cục bộ (mục 6).

## 3. Ngôn ngữ thiết kế

Phong cách iOS thuần, lấy cảm hứng từ ứng dụng Photos mặc định, không sao chép trực tiếp.

- `NavigationStack`; các màn root tab KHÔNG có navigation title (tab bar phía dưới đã hiển thị tên tab), màn con (detail, Unknown Cameras…) vẫn có title riêng
- Swipe-back gesture mặc định của hệ thống
- Tab bar: thanh chrome nổi custom kiểu "Liquid Glass" lấy cảm hứng iOS 26 Music app — pill tab bar nổi + nút search hình tròn tách biệt, dựng bằng SwiftUI `ZStack` + `.ultraThinMaterial` (blur thật). Trên iOS 26+ dùng Liquid Glass API hệ thống nếu khả dụng
- 3 tab chính: Library, Collections, Statistics — custom tab chrome overlay trên `ZStack` chứa các `NavigationStack`. **Re-tap tab Library** (tab đang chọn) → grid nhảy về đáy (ảnh mới nhất): `AppNavigation.libraryRetapToken` (Int đơn điệu) bump từ cả hai đường tab bar (iOS 26 qua custom selection `Binding`, pre-26 qua `onReselect` của `LiquidGlassTabBar`); `LibraryScreen` bump counter local truyền làm `jumpToNewestToken` của `PhotoGridCollectionView` — collection view `setContentOffset` về đáy (O(1), content size là phép nhân hàng). Settings KHÔNG phải tab: mở qua nút gear (`gearshape`) ở góc trên trái của cả 3 tab, hiện dạng bottom sheet trượt từ dưới lên (native `.sheet`, `presentationDetents([.medium, .large])` — mở nửa màn, kéo lên gần full, grabber hiện, đóng bằng kéo xuống), giống panel metadata màn detail ảnh; sheet có `NavigationStack` riêng (push được Unknown Cameras)
- Search: nút tròn trong thanh chrome nổi phía dưới, KHÔNG nằm trong nav bar
- Filter/metadata panel: `.sheet` + `presentationDetents([.medium, .large])` + `presentationDragIndicator`
- Sort: `Menu` (pull-down kiểu iOS 14+)
- Settings và metadata panel: `List` style `.insetGrouped`
- Control: `Toggle`, `Picker`, `confirmationDialog`, `alert`, segmented `Picker`
- Màu semantic: `Color(.systemBackground)`, `.secondarySystemGroupedBackground`, `.label`, `.secondaryLabel` — tự thích nghi Light/Dark Mode
- Icon: SF Symbols
- Typography: San Francisco, hỗ trợ Dynamic Type
- Haptic feedback ở các thao tác quan trọng
- Accessibility: label/traits đầy đủ cho chrome custom (tab bar, glass buttons, album card), VoiceOver cho grid

Thiết kế cần: tối giản, nhiều không gian cho ảnh, ít màu trang trí, ưu tiên typography và hierarchy, cảm giác app hệ thống của Apple. Không dashboard kiểu web, không lạm dụng card, không button lớn nếu control hệ thống phù hợp hơn. **Ngoại lệ có chủ đích**: màn Statistics là dashboard chart tuỳ biến (§7.4) — nhưng dựng bằng control native (`List` insetGrouped, Swift Charts, EditButton kéo-sắp-xếp), card chart giữ ngôn ngữ hệ thống, không sa vào chrome kiểu web.

## 4. Kiến trúc và cấu trúc project

```
ShotDex/
├── App/
│   ├── ShotDexApp.swift            // @main, root
│   ├── HomeTabScaffold.swift       // ZStack 4 NavigationStack + glass chrome
│   ├── Glass/                      // LiquidGlassTabBar, GlassPanel, GlassIconButton
│   └── AppDependencies.swift       // DI container
├── Core/
│   ├── Models/                     // PhotoMetadata, LibraryGridItem (+PhotoGridDisplayable),
│   │   │                           // FilterCriteria, SortOption, SensorFormat, Stats models
│   └── Utils/FormatUtils.swift     // format shutter/aperture/focal/ISO/fileSize
├── Data/
│   ├── Database/
│   │   ├── AppDatabase.swift       // GRDB setup + migrations
│   │   ├── MetadataDAO.swift       // insert/update batch, index cursor
│   │   ├── LibraryQueryDAO.swift   // filter + search + sort queries
│   │   └── StatsDAO.swift          // aggregate queries
│   └── Sources/
│       ├── PhotoLibraryService.swift   // PhotoKit wrapper (fetch, thumbnail, change observer, favorite)
│       ├── ExifService.swift           // ImageIO EXIF reader
│       └── SensorDatabaseService.swift // load sensor_database.json
├── Domain/
│   ├── Normalize/
│   │   ├── CameraNormalizer.swift
│   │   └── LensNormalizer.swift    // gồm isZoom
│   ├── Filtering/SearchParser.swift    // query DSL cho search
│   ├── Grid/ChunkedLookupCache.swift   // PHAsset cache chunked + LRU cho grid
│   ├── Indexing/
│   │   ├── IndexPipeline.swift     // actor: batch, progress, cancel, resume
│   │   └── MetadataComposer.swift
│   ├── SensorLookup.swift
│   └── EquivalentFocalLength.swift
├── Features/
│   ├── Library/        // LibraryScreen, PhotoGridTile, MetadataLabel,
│   │                   // FilterSheet, FilterChipsBar, PhotoDetailScreen, MetadataPanel
│   ├── Albums/         // AlbumsScreen, AlbumDetailScreen
│   ├── Statistics/     // StatisticsScreen + chart views
│   ├── Settings/       // SettingsScreen, CameraDatabaseScreen (Unknown Cameras)
│   └── Onboarding/     // OnboardingScreen
└── Resources/
    └── sensor_database.json        // camera/sensor database bundle sẵn
```

Pattern:

- Feature layering: presentation (View + `@Observable` controller), domain (model + logic thuần), data (DAO + service)
- Repository/service layer cô lập PhotoKit, ImageIO, GRDB — không rò rỉ lên View
- `IndexPipeline` là `actor`, chạy background, publish progress qua `@Observable` state
- Domain logic (normalizer, search parser, equivalent focal, sensor lookup, metadata composer) là **pure Swift không phụ thuộc framework** — dễ unit test
- Kiến trúc dễ bảo trì, không khóa khả năng mở rộng (mục 14)

## 5. Database schema (GRDB)

Bảng `photo_metadata`:

```
assetId (TEXT PK — PHAsset.localIdentifier)
creationDate, modificationDate (INTEGER epoch)
mediaType                        -- PHAssetMediaType raw (1 = image, 2 = video); video rows có nhưng không EXIF
cameraManufacturer, cameraModel, normalizedCameraModel, normalizedCameraManufacturer
lensManufacturer, lensModel, normalizedLensModel
originalFilename (TEXT — từ PHAssetResource, dùng cho search theo filename)
iso (INTEGER), aperture (REAL)
shutterSpeedSeconds (REAL), shutterSpeedDisplay (TEXT)
focalLength (REAL), focalLengthIn35mm (REAL)
calculatedEquivalentFocalLength (REAL), equivalentFocalLength (REAL, denormalized cho query)
sensorFormat (TEXT), cropFactor (REAL)
width, height (INTEGER)          -- megapixels là computed property, KHÔNG lưu
fileSize (INTEGER)
latitude, longitude (REAL)
isFavorite (INTEGER)             -- sync từ PHAsset.isFavorite (PhotoKit là source of truth)
indexedAt (INTEGER)
exifStatus (TEXT: indexed / noExif / pendingRead / pendingICloud / error)
indexerVersion (INTEGER)         -- build của indexer đã ghi row (backfill khi thêm field mới)
```

Index trên: `normalizedCameraModel`, `normalizedLensModel`, `iso`, `aperture`, `shutterSpeedSeconds`, `focalLength`, `equivalentFocalLength`, `sensorFormat`, `creationDate`.

Bảng phụ: `custom_camera_mappings` (manual sensor mapping), `index_state` (con trỏ resume, last indexed time), `smart_albums` (saved rule query, migration `v3`), `stat_charts` (dashboard chart widget: `id` PK, `config` = JSON `ChartWidget`, `position`; migration `v4-statCharts`).

Favorite: đọc/ghi thẳng PhotoKit (`PHAsset.isFavorite`, toggle qua `PHAssetChangeRequest`); cột trong DB chỉ để query/filter nhanh, sync qua change observer.

## 6. Metadata Indexing (PhotoKit + ImageIO)

**Indexer version — backfill field mới lên row cũ**: mỗi row ghi `indexerVersion` = `PhotoMetadata.currentIndexerVersion` lúc viết. Khi build mới trích thêm data (field EXIF/PHAsset mới, đổi normalizer), bump hằng số này; `needsReindex` coi row có `indexerVersion` thấp hơn là **stale** và đọc lại kể cả khi `.indexed` và `modificationDate` không đổi. Row cũ do đó tự backfill ở **lần incremental run kế** (launch/background, resumable, thermal-aware — tái dùng nguyên pipeline), không cần full re-index thủ công, không cần backfill riêng cho từng field. Migration thêm cột default 0 nên mọi row có sẵn đều stale sau lần nâng cấp đầu. Lịch sử: 0 = pre-index (migration default), 1 = schema v1, 2 = thêm `fileSize`. (Đánh đổi: bump version đọc lại **toàn thư viện** — chi phí iCloud như index lần đầu; refinement khả dĩ nếu cần là tách version EXIF vs PHAsset-only để chỉ đọc lại phần đổi.)

Pipeline (mỗi run 2 pha):

0. **Fast pass (pha 1)**: duyệt toàn bộ fetchResult, asset chưa có row → ghi ngay row từ dữ kiện PHAsset thuần (ngày, kích thước, GPS, favorite; fileSize để nil, **không gọi XPC per-asset nào**), `exifStatus = pendingRead`, upsert theo batch 1000/transaction (`IndexPipeline.fastPassBatchSize`). Toàn thư viện có row trong vài giây → grid/sort/date dùng được ngay, EXIF fill dần ở pha 2. Không đè row đã tồn tại (kể cả khi full reindex — dữ liệu cũ hiển thị đến khi bị đọc lại đè lên)
1. **EXIF pass (pha 2)**: `PHAsset.fetchAssets` với `PHFetchOptions` (sort theo creationDate **descending — ảnh mới nhất index trước**), duyệt theo batch **200 ảnh**; trong batch đọc EXIF **song song tối đa 12 asset** (`TaskGroup`, `IndexPipeline.readConcurrency`) vì thời gian index bị chi phối bởi round-trip PhotoKit từng asset, không phải CPU. **Fan-out tự điều chỉnh theo nhiệt độ máy + Low Power Mode** (`IndexPipeline.readConcurrency(thermal:lowPowerMode:)`): nominal 12 / fair 6 / serious 3 / critical 2; LPM cap thêm tại mức fair (6), backoff nhiệt sâu hơn vẫn thắng. Target được **tính lại tại mỗi read completion** (không phải một lần mỗi batch): refill spawn `refillCount(inFlight:target:remaining:)` read mới — máy nóng lên giữa batch thì read xong không được thay (fan-out tự co về target, không kill task đang bay), máy nguội thì ramp lên lại; guard luôn spawn ≥1 khi không còn read nào đang bay để task group không bao giờ starve (bảo toàn invariant prefix liên tục/cursor). **Nghỉ giữa batches** (`interBatchPause(thermal:lowPowerMode:)`, duty cycle cho SoC): nominal 0s / fair 3s / serious+critical 10s, LPM ép tối thiểu 3s kể cả nominal; skip trước batch đầu tiên của run (máy mát start ngay), sleep theo tick 250ms nên cancel dính trong 1 tick, state sample lại mỗi lần nghỉ. Trạng thái nhiệt/LPM đọc qua closure inject được (`init(thermalState:isLowPowerMode:)`, mặc định `ProcessInfo`) — policy pure, unit-test được, không cần notification observer vì đã sample ở mọi suspension point. Đang **critical** thì `waitWhileThermalCritical()` (poll 1s, cùng dạng `waitWhileInteractionPaused`, thoát ngay khi cancel) ngừng spawn read mới cho tới khi máy nguội — run lâu đánh đổi tốc độ lấy nhiệt độ thay vì kéo máy tới critical. Kết quả gom lại đúng thứ tự batch; khi cancel giữa chừng chỉ lưu prefix liên tục để con trỏ resume không bao giờ trỏ quá một asset chưa đọc
2. Mỗi asset: đọc EXIF từ file gốc **không decode ảnh**, một đường streaming thống nhất cho cả local lẫn iCloud (`ExifService.readExif`):
   - `PHAssetResource.assetResources(for:)` gọi **đúng 1 lần/asset** (trong `IndexPipeline`), lấy resource truyền vào `ExifService` + original filename — không lặp XPC
   - **Đọc file size ở pha 2** (không phải fast pass): `resource.fileSize` (KVC) đọc trong `read()` **trên executor của actor pipeline, không phải main queue**, ghi vào cột `fileSize` để grid badge dùng lại mà không cần KVC per-cell lúc scroll. Với asset chỉ-ở-iCloud KVC vẫn có thể fault property set original-metadata, nhưng pha 2 đã stream từ file nên chi phí được khấu trừ. Row fast pass (`pendingRead`) vẫn để `fileSize` nil → badge file size chỉ hiện sau khi pha 2 đọc xong; ảnh index trước tính năng này (indexerVersion < 2) tự đọc lại ở incremental run kế qua cơ chế indexer version (trên). Photo Detail vẫn fetch lazy (một asset một lần) cho ảnh chưa index. Vẫn **không sort theo file size**
   - Screenshot (`mediaSubtypes.contains(.photoScreenshot)`) và **video** (`mediaType == video`) không có EXIF camera đọc được → bỏ qua hẳn bước đọc file, ghi thẳng `noExif` (`IndexPipeline.shouldSkipExifRead(mediaType:mediaSubtypes:)`, pure, có unit test). Video vẫn lấy fileSize/filename từ resource đầu tiên (không có photo resource riêng)
   - *Stream* file qua `PHAssetResourceManager.requestData`, cap 8 MB: thử **network off** trước (file local đọc từ disk); đọc local **thất bại vì bất kì lỗi gì** → thử tiếp **bản rendition local** (dưới đây) trước khi mới đụng mạng
   - **Fallback bản rendition local (quan trọng khi "Optimize iPhone Storage" bật)** `ExifService.readExifFromLocalDerivative`: khi original chỉ-ở-iCloud, `PHAssetResourceManager` đọc local thất bại vì file gốc không có trên máy — nhưng Photos vẫn giữ **bản downscaled trên thiết bị**, và bản này **giữ nguyên khối metadata EXIF/TIFF** (chỉ pixel bị thu nhỏ), đủ cho `parse`. Đọc byte bản đó bằng `PHImageManager.requestImageDataAndOrientation` với `isNetworkAccessAllowed = false` + `deliveryMode = .fastFormat` (**không** `.highQualityFormat` — mode đó đòi bản chất lượng cao chỉ-có-ở-iCloud nên trả nil local, ép đọc mạng vô ích; `.fastFormat` trả bất kỳ rendition local nào, khối EXIF vẫn nguyên) → **không kích hoạt tải iCloud** nên tránh luôn lỗi account-auth (`com.apple.accounts` Code=7) mà việc kéo original gây ra khi iCloud không phục vụ được. Parse bằng `CGImageSourceCreateWithData`. Chỉ khi **không có rendition local nào** (ảnh chưa mở / vừa sync) mới trả tín hiệu để rơi xuống đọc original qua mạng. Kết quả: đa số ảnh offloaded resolve local, cắt mạnh traffic iCloud
   - Cần mạng (không còn rendition local) → nếu được phép, stream lại với network on (byte đếm vào traffic monitor)
   - **Timeout là cửa sổ "no-progress" (stall), KHÔNG phải deadline tuyệt đối**: chỉ hủy khi trọn một cửa sổ trôi qua mà không có byte mới (local 10s, network **8s**). Trước đây iCloud original không tải được (0 B) chặn trọn 30s tuyệt đối mỗi asset → thư viện nhiều ảnh offloaded bị serialize 30s/ảnh, index rất chậm; nay bail sau ~8s. Original ở iCloud không tải được → `pendingICloud`, retry bằng nút thủ công / background task
   - **Giới hạn stream iCloud song song** (`ExifService.networkStreamLimiter`, `AsyncLimiter` limit **4**, static — cap toàn process gồm cả `indexSingle` của viewer): 12 reader của batch mà cùng stream iCloud thì chia băng thông tới mức từng read đói byte trọn cửa sổ stall 8s → stall **giả** trên mạng khỏe, nuôi breaker trip nhầm giữa run (triệu chứng: tốc độ giảm dần rồi hiện 0, cancel + retry lại chạy). Limit 4 còn nhằm **giảm churn request+cancel lên cloudphotod**: pattern requestData → parse header → cancel hàng trăm lần/phút làm daemon nghẹt tới mức ngừng phục vụ (0 byte) cho tới khi được nghỉ — quan sát thực tế trên device (chạy tốt → chết theo chu kỳ → nghỉ/restart là hồi). Chỉ ≤4 stream mạng chạy đồng thời (xếp hàng FIFO qua actor semaphore), read local không bị giới hạn; sau khi lấy slot re-check breaker (có thể đã trip trong lúc xếp hàng) và **chờ hết breather sau-stall** (dưới đây) — ngủ trong lúc giữ permit là chủ đích: bóp cả làn network cho daemon xả
   - **Circuit breaker mạng — sliding window + half-open** (`IndexTrafficMonitor`): khi iCloud không phục vụ được original (account error, sync chưa xong, link chết, daemon nghẹt), network read stall 0 byte. Tín hiệu trip là **cửa sổ trượt**: ≥`stallTripCount` (10) stall trong `stallTripThreshold` (12) read gần nhất → "trip", các iCloud read tiếp theo trả `pendingICloud` **tức thì** (không tốn cửa sổ stall/asset). **KHÔNG đếm liên tiếp** — iCloud nghẹt vẫn rỉ vài byte lẻ, một read may mắn không được phép "bảo lãnh" cả pipe chết: bản đếm-liên-tiếp không bao giờ trip ở trạng thái đó, run treo 0 KB/s vô hạn không pause không banner (bug thực tế). Link nghẽn nhưng còn sống (stall dưới tỉ lệ) không bao giờ trip. Ngoài trip, **mỗi stall còn mở một breather 2s** (`restDuration`, `networkRestRemaining`): read mạng mới chờ hết breather rồi mới request — daemon vừa đuối được nghỉ ngay từ stall đầu tiên thay vì bị đấm tiếp tới khi trip. Trip **không vĩnh viễn cho run**: sau cooldown breaker half-open — **đúng 1 probe** được thử (`shouldSkipNetworkRead()` là gate claim ngay trước khi stream, các read khác tiếp tục skip tới khi probe có kết luận; claim tự hết hạn sau 15s phòng probe không báo về — không claim ở check sớm vì read tự khóa mình); probe có byte → đóng hẳn, probe stall → re-trip (window clear mỗi lần trip để probe xây lịch sử mới). Trước đây cả 4 permit cùng probe: 1 cái re-trip, 3 cái còn lại đốt 8s stall window vô ích. **Cooldown cố định 30s, không backoff** (`init(cooldown:)` testable) — chủ đích: một probe fail chỉ tốn 1 cửa sổ stall 8s, còn bắt kịp iCloud ngay khi nó hồi quan trọng hơn. Trạng thái chết quan sát được trên device là **lỗi auth iCloud tầng OS** (`com.apple.accounts` Code=7 — cloudphotod treo im lặng mọi request, stall đúng cửa sổ 8s, không error trả về; cả run 0 byte từ read đầu tiên), có thể kéo dài nhiều phút; app sống chung bằng vòng probe/retry 30s. **Byte về trong lúc cooldown bị bỏ qua**: tới 6 read còn đang bay lúc trip, một cái nhả buffer muộn mà close breaker thì kỳ nghỉ vô nghĩa. Reset đầu mỗi run. Monitor cũng đếm **diagnostics**: `networkReadsStarted`/`networkReadsInFlight` (`beginNetworkRead`/`endNetworkRead` trong ExifService, sau khi lấy slot limiter), `stallCount`, `breakerCooldownRemaining` — nguồn cho dòng chẩn đoán trong UI index. **Log tập trung** (`IndexTrafficMonitor.healthLogger`, category **`index-health`**): run start, mỗi stall (số thứ tự, window x/y, filename, ms), breaker TRIPPED/RE-TRIPPED/CLOSED (kèm cooldown hiện hành), error domain+code khi network read trả lỗi thật (hiếm — treo là chủ đạo, nên error trả về là tín hiệu quý, ví dụ Code=7), health snapshot 10s/lần từ sampler (progress · speed/total · iCloudLine · thermalLine · allowNetwork), summary cuối run — `log stream --predicate 'category == "index-health"'` đọc được toàn bộ diễn biến một run suy thoái ở một chỗ. Log debug per-asset cũ của ExifService (streaming/success/needsNetwork per read) và `net sample` mỗi giây của sampler đã bỏ — chỉ còn read **failure** log per-asset
   - **Early-stop chỉ áp dụng cho đường network**: khi stream từ iCloud, parse tăng dần bằng `CGImageSourceCreateIncremental` mỗi chunk và hủy request ngay khi có metadata (thường 64–300 KB) để tiết kiệm băng thông. Đường local **không** parse từng chunk — file về từ disk trong mili-giây, nên gom hết buffer rồi parse **một lần** ở completion handler. Lý do: feed buffer HEIC dở dang vào `CGImageSourceCopyPropertiesAtIndex` khiến ImageIO cố init HEVC decoder trên mỗi chunk → lỗi lặp (`err -39`/`-12894`, `makeImagePlus ... initImage failed`) spam log và đốt CPU, làm index chậm — không chỉ riêng `PHPhotosError.networkAccessRequired`, vì Photos trả lỗi original-ở-iCloud với domain không ổn định giữa các version; file local hỏng thật thì lần thử mạng cũng fail → vẫn ra `error`. Buffer chỉ nằm trong RAM, không ghi file gốc xuống máy. Ảnh đã edit đọc resource `.photo` = file **gốc** → EXIF đúng nguồn, không tốn công render bản chỉnh sửa
   - Parse bằng `CGImageSourceCopyPropertiesAtIndex` (`kCGImageSourceShouldCache = false`) → đọc `{Exif}`, `{TIFF}`, `{ExifAux}` dictionary: ISO, FNumber, ExposureTime, FocalLength, FocalLenIn35mmFilm, LensModel, LensMake, Make, Model
   - Fallback hiếm: metadata nằm ngoài cap 8 MB của file local (layout container lạ) → `requestContentEditingInput` (`canHandleAdjustmentData = true` để nhận URL file gốc, không render; timeout 10s) + `CGImageSourceCreateWithURL` đọc tại chỗ
   - Không được dùng mạng hoặc stream thất bại → `exifStatus = pendingICloud`, retry sau
   - Chính sách mạng: Wi-Fi (đường mạng không "expensive" theo `NWPathMonitor`) luôn được phép; cellular chỉ khi bật toggle "Use Cellular Data for Indexing" trong Settings (mặc định tắt). Nút thủ công "Re-index Incomplete Photos" luôn được dùng mạng. Quyết định `allowNetwork` là **closure đánh giá lại mỗi batch**, không chốt một lần đầu run — run tự động lúc mở app thường chạy trước khi `NWPathMonitor` báo path đầu tiên (mặc định coi là expensive), chốt sớm sẽ khoá mạng cả run dù đang Wi-Fi; ngược lại user rời Wi-Fi giữa run thì batch kế tiếp ngừng stream
   - **Pause chỉ phần stream iCloud khi ở cellular chưa opt-in** (Wi-Fi → cellular giữa chừng, hoặc mở app sẵn trên cellular): đọc metadata local vẫn tiếp tục (không tốn data), chỉ ảnh iCloud-only phải chờ Wi-Fi. `IndexNetworkStatus.streamingPaused` (= `!allowsNetwork && connection == .cellular`) khiến `displayLine` hiện "Cellular · Paused — Wi-Fi needed", cập nhật sống theo sampler 1s. Khi run local-only kết thúc mà còn row `pendingICloud`/`error`, `LibraryController.indexStreamingPaused` (expensive + chưa bật cellular + `pendingICloudCount > 0`) giữ một card **"Indexing paused — waiting for Wi-Fi"** cố định (không spinner) kèm nút "Use Cellular" (bật toggle + resume ngay). **Auto-resume**: `NetworkStatusService` gọi callback `setPathChangeHandler` mỗi lần đổi path; khi chuyển từ paused → được phép (về Wi-Fi hoặc bật cellular) và còn việc dở thì tự `startReindexIncomplete()` — chỉ resume trên transition paused→allowed để không cướp run incremental đầu app
   - **iCloud không phục vụ được trên đường mạng được phép** (auth chết Code=7, router/route hỏng — cả Apple Photos cũng stall): **index không bao giờ đứng chết, tự retry vô hạn với backoff**. Trong run, breaker half-open tự probe (xem trên); run kết thúc mà còn row `pendingICloud`/`error` và mạng được phép → `LibraryController.scheduleAutoRetryIfNeeded` đặt lịch `reindexIncomplete` tự động sau **30s cố định, không backoff** (một lần thử fail rẻ — breaker trip trong ~12 read; bắt kịp iCloud ngay khi nó hồi quan trọng hơn); run bị user cancel → không schedule. `indexAutoRetryDate` (Date fire) drive UI: card **"iCloud not responding"** (icon `icloud.slash`) với **countdown sống** (`Text(timerInterval:)`), số ảnh chờ, nút **"Retry Now"** (`retryIncompleteNow` — hủy countdown chạy ngay; run đang chạy thì cancel trước rồi resume qua `pendingRetryAfterCancel`) và **"Use Cellular"**; empty state có nhánh tương ứng. Không còn banner chặn "iCloud not downloading over Wi-Fi" + cờ `indexNetworkStalled` + chip thu gọn như trước — lỗi giờ chỉ là trạng thái tạm giữa 2 lần retry. Task retry khi fire: đang `isIndexing` → thôi (run đó tự schedule tiếp lúc xong); mạng thành không-được-phép giữa countdown (rời Wi-Fi, chưa opt-in cellular) → **re-arm cùng delay** thay vì chết — không gọi `startReindexIncomplete` vì nó luôn stream (sẽ đốt cellular trái setting). Run mới start → hủy countdown đang treo. **Auto-resume theo path**: `handleNetworkChange` khi đổi path mà đang paused hoặc đang đếm ngược retry → hủy chờ, retry ngay (đổi mạng chính là tín hiệu iCloud có thể phục vụ lại) — vẫn chặn resume trên first-path-update của launch run healthy. Keep Screen Awake chỉ theo `isIndexing` thuần (giữa 2 retry không giữ màn sáng)
   - **Check path mạng trước khi hiện trạng thái index lúc mở app**: `runPipeline` `await networkStatus.awaitInitialPath()` (one-shot continuation resolve ở lần `pathUpdateHandler` đầu) rồi mới set `indexNetworkStatus`, nên indicator hiện đúng Wi-Fi/cellular từ frame đầu thay vì mặc định "expensive-until-first-update"
   - Index pipeline chỉ đọc EXIF tag chuẩn, **không** parse maker notes (giữ nhẹ, không cột shutter-count trong DB). MakerNote chỉ được parse **on-demand ở sheet Info của Photo Detail** (`MakerNoteParser`, xem §7.2) để lấy shutter count — không đụng đường index
3. Normalize camera và lens (mục 8)
4. Xác định sensor format từ sensor database + custom mappings
5. Tính full-frame equivalent focal length (mục 9)
6. Batch insert vào GRDB, cập nhật con trỏ resume
7. GPS: lấy từ `PHAsset.location`, không cần đọc GPS EXIF tag

Yêu cầu hiệu năng:

- Chạy trong actor / `Task.detached`, không block MainActor; run foreground chạy ở **`Task(priority: .utility)`** để parse/compose/ghi DB và XPC PhotoKit không tranh CPU với UI
- **Nhường băng thông cho photo viewer (`IndexInteractionGate`)**: các stream đọc iCloud của EXIF pass và download ảnh của viewer đi chung iCloud download daemon (`photod`) — không có gate, ảnh iCloud-only user vừa tap phải xếp sau hàng chục stream index (10–20 phút). Gate là refcount + mốc hoạt động (`OSAllocatedUnfairLock`, pure, có unit test): viewer giữ 1 count khi mở (`onAppear`/`onDisappear`), `touch()` khi đổi trang và mỗi tick progress download iCloud. Pipeline poll `shouldPauseIndexing` (250ms) tại đầu mỗi batch và trước mỗi lần spawn read thay thế trong `TaskGroup` — đang pause thì **ngừng spawn read mới**, các stream in-flight (≤12) tự cạn (early-stop header / stall watchdog 8s) rồi băng thông về tay viewer trong vài giây. Đóng viewer → resume tự động, con trỏ/batch không đổi (pause chỉ kéo dài batch, không bỏ dở). An toàn: **tự resume sau 90s không hoạt động** (`maxPauseDuration` — count bị leak không treo index; đang tải thì progress tick giữ pause sống), vòng chờ thoát ngay khi `cancel()`; đường nền `BGProcessingTask` (`allowNetwork: false`, không có viewer) không ảnh hưởng; `indexSingle` **miễn gate** — nó chính là nhu cầu tương tác của viewer
- Progress hiển thị trong UI (số ảnh đã index / tổng + phần trăm, `IndexProgress.percent`), cho phép cancel; chỗ hiển thị progress kèm chú thích "chỉ đọc metadata, không tải full ảnh nên không tốn bộ nhớ, app có thể lag đến khi index xong" — empty state và Settings hiện luôn, panel Library chỉ hiện khi mở rộng (xem dưới)
- **Progress là số cộng dồn (cumulative), không reset mỗi run**: `processed = baseline + newlyDone` với `baseline` = số row đã đọc xong (`indexed`/`noExif`) trước run (`MetadataDAO.completedCount()`), `newlyDone` = số ảnh đọc xong trong run này; `total` = tổng ảnh trong library (`PHAsset` count). Emit `baseline` ngay đầu run nên panel hiện đúng điểm bắt đầu tức thì, không nhảy từ 0 và không tụt lùi khi mở lại app (VD 100 ảnh đã index 3 → mở lại tiếp tục `4/100`, `5/100`, không phải "1/97 còn lại"). `fullReindex` bắt đầu từ 0 (đọc lại tất cả). Ảnh đã xong bị bỏ qua trong incremental không emit thêm (đã nằm trong `baseline`); ảnh đã-xong nhưng bị sửa (đọc lại) trừ khỏi `baseline` để `newlyDone` đếm lại không vượt `total`. `reindexIncomplete` cũng dùng cùng công thức cộng dồn theo tổng library, không hiện "N/số-retryable"
- Progress UI kèm dòng trạng thái mạng: loại kết nối đang dùng (Wi-Fi/Cellular/Wired/Offline theo `NWPathMonitor`), tốc độ download hiện tại và tổng dung lượng đã stream từ iCloud trong run (`IndexNetworkStatus.displayLine`, ví dụ "Wi-Fi · 1.2 MB/s · 45 MB"). Byte được đếm bởi `IndexTrafficMonitor` (mỗi chunk `PHAssetResourceManager` trả về khi stream, reset đầu mỗi run); `LibraryController` sample mỗi 1s, tốc độ = delta byte giữa hai lần sample. Tốc độ và dung lượng **ẩn khi bằng 0** (`displayLine` bỏ phần tương ứng): run local-only chỉ hiện tên kết nối (ví dụ "Wi-Fi"), chỉ số download chỉ xuất hiện khi thực sự có traffic từ iCloud
- **Tốc độ index + thời gian còn lại** (`IndexThroughput` trong `LibraryController`): trung bình `ảnh/phút` cộng dồn từ sample đầu tiên của run (baseline theo `indexRunStart`/`indexRunStartProcessed` để run incremental/resume chỉ đo phần việc thật, không tính đoạn skip-scan), ETA = `(total - processed) / tốc độ` format kiểu "2 hours remaining" / "1 hr 20 min remaining" / "45 min remaining" / "less than a minute remaining". Hiện ở panel Library mở rộng (dòng `ảnh/phút · … remaining`) và trên overlay dim khi Keep Screen Awake. `nil` đến khi ước lượng được (cần ≥1s và có ảnh đã xong trong run); reset mỗi run
- Resume sau khi đóng app (lưu con trỏ tiến độ trong database)
- **Index tiếp tục khi rời foreground** (`BackgroundIndexService`, identifier `tech.karabiner.shotdex.index`):
  - Mỗi run foreground giữ một background-task assertion (`UIApplication.beginBackgroundTask`) — user thoát app giữa chừng thì run vẫn chạy thêm ~30s; hết hạn thì cancel sạch (con trỏ đã lưu) và bàn giao cho `BGProcessingTask`
  - `BGProcessingTask` (đăng ký trong `ShotDexApp.init`, khai báo `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: processing` trong `Info.plist`) chạy tiếp khi app bị suspend/kill, vào lúc hệ thống thấy phù hợp (máy rảnh, pin ổn); mỗi lần tiếp tục đều rẻ nhờ incremental diff bỏ qua ảnh đã index. Run nền không dùng mạng (`allowNetwork: false`) — ảnh iCloud-only giữ `pendingICloud` chờ retry foreground. Chưa xong thì tự schedule lần kế
  - Khi app vào background mà còn việc dở (run đang chạy hoặc con trỏ còn trong DB) → submit `BGProcessingTaskRequest`
  - Lưu ý: `BGTaskScheduler` không chạy trên simulator; hệ thống tự quyết thời điểm chạy, không đảm bảo ngay lập tức
- Incremental: `PHPhotoLibraryChangeObserver` cho change notification; khi mở app diff theo `modificationDate` + `exifStatus` (`IndexPipeline.needsReindex`, pure, có unit test) — index ảnh mới/đã thay đổi, đồng thời tự re-enqueue row `error`/`pendingRead` (luôn) và `pendingICloud` (khi được phép dùng mạng) dù ảnh không đổi
- **Auto-index luôn chạy khi mở/quay lại foreground**, độc lập tab đang mở: trigger đặt ở `HomeTabScaffold` (root, luôn sống) qua `.task` lúc tạo controller + `.onChange(scenePhase == .active)`, không chỉ ở `LibraryScreen.task`. Trên iOS 26 `TabView`/`Tab` build nội dung tab lazy nên nếu app mở vào tab khác (Statistics/Albums) thì `LibraryScreen` chưa dựng → index sẽ không chạy nếu chỉ dựa vào `LibraryScreen`. `startIndexing`/`run()` idempotent (guard `isIndexing`/`isRunning`) nên gọi lặp an toàn
- Progress emit khi mỗi asset **bắt đầu đọc** lẫn khi **xong**, throttle 200ms (`BatchProgressState`, tối đa ~5 lần/s) — batch iCloud chậm (timeout 30s/ảnh) mà chỉ emit theo mốc số lượng thì counter đứng im hàng phút, user tưởng treo. `IndexProgress.activeItems` = danh sách `originalFilename` đang đọc **song song** (bắt đầu đọc append, xong remove, tối đa `readConcurrency` = 12) để dialog mở rộng thấy các ảnh đang lấy ngay cả khi số chưa nhích. Pha skip-scan của incremental pass **không** emit (số cộng dồn đã có sẵn `baseline` từ đầu run nên không cần đếm lại ảnh đã index), `activeItems` rỗng. Fast pass **không** emit progress (xong trong vài giây; emit sẽ làm progress bar nhảy 100% rồi reset về 0 khi EXIF pass bắt đầu) — trong lúc đó panel hiện "Indexing…" không số, đúng hành vi khi `indexProgress` còn nil
- Instrumentation: `OSSignposter` interval `fastPass` / `exifRead` / `dbWrite` (subsystem `tech.karabiner.shotdex`, category `index`) cho Instruments; cuối mỗi run `Logger` ghi 1 dòng tổng kết — số lượng theo outcome, thời gian chạy, assets/giây, avg ms/asset từng stage (resources / exif / compose / dbWrite) — để đo trước/sau khi tối ưu
- Panel progress ở Library hiển thị **ngay khi `isIndexing`**, kể cả lúc `indexProgress` còn nil (chưa có callback đầu tiên) — hiện "Indexing…" không số, giống row trong Settings; empty state cũng vậy
- Index indicator ở Library là **chip trên toolbar top-leading, ngay bên phải nút Settings** (`ToolbarItem(placement: .topBarLeading)` riêng, sau `SettingsDrawerButton`; iOS 26 chèn `ToolbarSpacer(.fixed)` giữa gear và chip để tách hẳn glass container — chip là control riêng, không dính tap target của gear). **Chip thu gọn**: spinner + "Indexing" + phần trăm (`IndexProgress.percent`), khi chưa có callback đầu (`indexProgress` nil) chỉ "Indexing"; label `.fixedSize` để không bị toolbar cắt chữ. iOS 26 dùng glass capsule của toolbar; pre-26 chip tự vẽ capsule `.ultraThinMaterial` + viền. **Tap chip → dropdown tự vẽ** (không dùng `.popover` hệ thống — nó double-blur và bị iOS ghim sát top): `overlay(alignment: .top)` trên `gridContent`, thả vào top safe area ngay **dưới nav bar** (không che nút toolbar), full-width (`padding(.horizontal, 12)` + card `maxWidth: .infinity`), **1 lớp material** `GlassPanel` duy nhất, transition `.move(edge: .top)`. Đóng khi: tap chip lần nữa (toggle), tap ảnh trên grid (`onTap`), scroll grid (`onUserScroll`), hoặc tap vào chính card. Tự reset `isIndexPanelExpanded = false` qua `onChange` khi hết mọi trạng thái index. Card `frame(maxWidth: 300)`: dòng đếm đầy đủ `processed/total (%)`, progress bar, dòng trạng thái mạng, **2 dòng diagnostics** (`IndexDiagnostics`, sampler 1s của LibraryController build từ `ProcessInfo.thermalState` + `isLowPowerModeEnabled` + counters của `IndexTrafficMonitor`): `Thermal: Fair · 6 readers` (trạng thái nhiệt + fan-out pipeline đang dùng; thêm ` · Low Power` khi Low Power Mode bật) và `iCloud: 4 in flight · 132 requested` (kèm `· N stalls` khi có; breaker đang cooldown thì thay bằng `iCloud paused · retry in 42s` — trip giữa run không còn câm), chú thích metadata, nút **Cancel** (không liệt kê danh sách file đang đọc). Tap card hoặc scrim popover → đóng (`isIndexPanelExpanded` về false qua binding). Đang multi-select thì ẩn chip (`!isSelecting`). **Trạng thái paused** (`indexStreamingPaused`, không đang index nhưng còn ảnh iCloud chờ Wi-Fi) → popover hiện `pausedIndexCard` — icon `wifi.slash`, "Indexing paused — waiting for Wi-Fi", số ảnh còn lại, nút "Use Cellular". **Trạng thái auto-retry** (`indexAutoRetryDate != nil`, giữa 2 lần tự retry vì iCloud không phục vụ — xem §6) → popover hiện `autoRetryCard` — icon `icloud.slash`, "iCloud not responding", countdown sống tới lần retry kế, nút "Retry Now" + "Use Cellular". Chip hiện khi `isIndexing || indexStreamingPaused || indexAutoRetryDate != nil`; thứ tự ưu tiên trong popover: indexing → auto-retry → paused. Empty state cũng có nhánh auto-retry + paused tương ứng
- Không load full-resolution image chỉ để đọc metadata (local đọc properties tại chỗ; iCloud chỉ stream header)
- Thumbnail grid: `PHCachingImageManager.requestImage` với `targetSize` khớp cell (scale cap 2x — 3x không phân biệt được ở cỡ cell, tốn 2.25x decode/memory), `deliveryMode = .opportunistic`, **`isNetworkAccessAllowed = false`** — scroll grid không bao giờ tải iCloud, chỉ dùng derivative local (Photos luôn cache sẵn cho mọi asset); bản nét full-quality (network on) chỉ tải ở detail view. Prewarm `startCachingImages` cho vùng scroll sắp tới: cân nhắc lại nếu profiling cho thấy cần (delivery `.opportunistic` + cache nội bộ của `PHCachingImageManager` đã đủ mượt). PHAsset cho tile grid resolve qua `ChunkedLookupCache` (Domain/Grid): chunk 400 id quanh index đang hiển thị, tối đa 5 chunk LRU (~2000 PHAsset trần) — grid không bao giờ giữ PHAsset cho toàn thư viện; clear khi nhận memory warning
- Grid scroll mượt với thư viện lớn 50.000–100.000 ảnh (`PHFetchResult` lazy sẵn + UICollectionView cell reuse + prefetch)

## 7. Các màn hình

Ứng dụng gồm 3 tab: Library, Collections, Statistics. Settings mở dạng bottom sheet trượt từ dưới lên (nút gear góc trên trái mọi tab).

### 7.1 Library

**Photo grid**

- View chung `PhotoGridCollectionView` (Features/Shared) dùng cho Library + Album Detail
- **Load toàn thư viện một lần, slim rows (kiểu Google Photos)**: Library KHÔNG phân trang — một query async trả toàn bộ thư viện đã filter/sort dưới dạng `LibraryGridItem` (projection: assetId, creationDate + các field overlay của tile; ~200 KB / 1k ảnh), collection view reuse cell nên memory phẳng dù cuộn tới đâu. `matchCount` = `items.count` (miễn phí, không cần query COUNT riêng). Full `PhotoMetadata` chỉ fetch on-demand theo assetId (detail viewer, Compare)
- **Nguồn của `items` — PhotoKit-first cho view mặc định (hiện ảnh tức thì kiểu app Photos/Metapho)**: khi KHÔNG có filter (`criteria.isEmpty`) và sort theo ngày (`SortOption.isDateSort`), `LibraryController.reload()` dựng list từ `PHFetchResult<PHAsset>` (mọi ảnh, theo creationDate), join mỗi asset với row DB đã index nếu có (để có overlay exposure) và dùng `LibraryGridItem(asset:)` (chỉ facts PhotoKit, exposure = nil → tile chỉ hiện thumbnail) cho ảnh chưa index. Nhờ vậy toàn bộ ảnh xuất hiện NGAY, không phải chờ `IndexPipeline`; index chạy nền chỉ để bơm overlay/filter/sort metric/statistics, và mỗi lần `reload()` (index xong, hoặc library thay đổi qua `libraryChangeToken`) overlay được điền dần. **Chống reload storm khi đang index**: streaming iCloud original làm PhotoKit bắn `photoLibraryDidChange` liên tục (có thể per asset) — không chặn thì mỗi change là một full reload (2× decode toàn bộ rows + 2× enumerate PHAsset) làm máy nóng và badge nháy. Hai lớp: (1) `PhotoLibraryService` debounce bump `libraryChangeToken` trailing-edge ≤1/s (fetchResult vẫn cập nhật ngay; bảo vệ luôn Albums/OnThisDay); (2) `LibraryScreen` gọi `LibraryController.handleLibraryChange()` — đang `isIndexing` thì chỉ set `pendingLibraryChange`, coalesce vào reload cuối run + một run incremental follow-up (mirror pattern `pendingRetryAfterCancel`); ngoài run thì reload + startIndexing như cũ. **Overlay ảnh index xong giữa run điền lazy khi scroll tới** (không refresh cả grid): cell thiếu toàn bộ field exposure hỏi `lazyMetadataProvider` (Library truyền `LibraryController.lazyBadgeItem` → `queryDAO.metadata(assetId:)` off-main; Album Detail để nil) khi được configure, kết quả chỉ update badge của đúng cell đó (guard assetId, cancel ở `prepareForReuse`, không bump version nào). Kết quả cache trong `GridBadgeCache` (@MainActor, Domain): `indexed`/`noExif`/không-có-row là final → cache; `pendingRead`/`pendingICloud`/`error` không cache để lần hiển thị sau retry; invalidate mỗi `applyLoadedRows`. Có filter bất kỳ hoặc sort metric → fallback về `LibraryQueryDAO.gridItems` (chỉ ảnh đã index) như trước. Enumerate `PHFetchResult` chạy off-main (materialize mọi asset). **First paint 2 pha**: enumerate toàn thư viện lớn vẫn mất vài giây, nên `reload()` fast path chạy pha 1 với `fetchLimit` 600 (lát newest/oldest theo sort, kèm DB overlay `LIMIT` tương ứng) để grid hiện gần như tức thì, rồi pha 2 enumerate full thay list — count đổi → `contentGeneration` bump → re-anchor đáy, liền mạch vì ảnh của lát pha 1 nằm đúng ở đáy; pha 2 lỗi giữ nguyên lát đã hiện (error banner chỉ khi grid trống). `refreshFilterOptions()` (3 query DISTINCT cho filter sheet) cũng chạy off-main để không chặn first paint lúc launch. Đây là pattern có sẵn của `AlbumDetailController` (`PhotoMetadata.placeholder(for:)`), nay port sang Library. Detail viewer: `metadata(for:)` fallback `placeholder(for:)` cho ảnh chưa index nên chrome favorite/share/info + Compare vẫn hoạt động
- **Video vào index + hiện mọi nơi**: mọi surface (Library grid, Albums, On This Day, detail viewer) VÀ `IndexPipeline` fetch cả photo lẫn video qua `PhotoLibraryService.browsableMediaPredicate` (`mediaType = image OR video`). Video được index thành row `photo_metadata` **không EXIF**: EXIF pass bỏ qua chúng (`IndexPipeline.shouldSkipExifRead(mediaType:mediaSubtypes:)` skip cả `.photoScreenshot` lẫn `mediaType == video`), ghi thẳng `noExif` với dữ kiện PHAsset (creationDate, kích thước, fileSize/filename từ resource đầu tiên, favorite). Vì là asset mới với indexer trước, incremental diff **tự chèn** ở run kế — không bump `indexerVersion`, không migration. Tile video hiện poster frame (`requestImage`) + badge play/duration; detail viewer phát video (§7.2). Video **đếm vào tổng** (KPI "Total Photos & Videos") và xuất hiện trong Statistics; vì không có metadata gear (camera/lens/exposure NULL), gear chart gom chúng vào bucket **"Unknown"** (footnote), và filter gear vẫn loại chúng ra (không có camera) — filter phi-gear (favorite, ngày) thì giữ
- **Grid engine = UICollectionView (`PhotoGridCollectionView`, UIViewRepresentable)** — Library + Album Detail. SwiftUI LazyVGrid không kham nổi feature set này ở scale toàn thư viện (100k+): bottom-anchor ép ước lượng tổng content height (mở app đen lâu, tile không render tới khi chạm — bug materialize của lazy container neo đáy), mọi đổi layout invalidate cả container (pinch lag), offset thô sau đổi cột trỏ sai vùng/vượt content (scroll bay xa, màn đen). UICollectionView + **flow layout** (`GridFlowLayout` — KHÔNG compositional: `UICollectionViewTransitionLayout` của pinch không hỗ trợ compositional, `startInteractiveTransition` trả layout đích không bọc → crash `setTransitionProgress`; grid vuông đều cột không cần compositional, pinned header flow có sẵn `sectionHeadersPinToVisibleBounds`): content size = phép nhân hàng (O(1)), neo đáy tức thì bằng `setContentOffset` sau `reloadData`. Contract với screens giữ nguyên DensityPhotoGrid cũ: mảng photos phẳng, callback flat-index (tap → pager index), `SwipeSelectEvent`. Cell `PhotoGridCell` thuần UIKit (UIImageView + gradient + metadata label + video badge + selection badge/border); header section = UICollectionViewCell đăng ký làm supplementary + `UIHostingConfiguration { GridSectionHeader }` (tái dùng capsule glass SwiftUI). **Prefetch thumbnail**: `UICollectionViewDataSourcePrefetching` → `PhotoLibraryService.startCachingThumbnails/stopCaching...` (bọc `PHCachingImageManager` — mảnh Metapho từng thiếu: ảnh sẵn sàng trước khi scroll tới). Display toggles (ISO/aperture/…) đọc qua snapshot `GridMetadataDisplayOptions` giữ trong Coordinator (cùng key @AppStorage của Settings), refresh khi `UserDefaults.didChangeNotification` rồi reconfigure cell hiển thị — không còn 5 lần đọc UserDefaults mỗi cell mỗi configure, và đổi toggle trong Settings áp dụng live.
- **Bottom-anchored kiểu app Photos** (chỉ Library, Album Detail vẫn top-anchored): kết quả "đầu" của sort nằm DƯỚI CÙNG (sort newest → ảnh mới nhất ở đáy), mở tab đứng sẵn ở đáy, cuộn lên xem ảnh cũ. SQL/ORDER BY giữ nguyên — controller đảo mảng một lần sau khi load (đảo ở Swift, không ở SQL, để giữ NULLS LAST = section "No Date" ở trên cùng). Đổi filter/sort (danh sách asset **đổi** thứ tự/thành phần) → `contentGeneration` bump = `contentVersion` → `reloadData` + re-anchor đáy; tab retap (`jumpToNewestToken`) → scroll về đáy. **Index run xong/bị cancel** thường trả **đúng danh sách cũ** (đường PhotoKit-first đã có sẵn mọi ảnh, index chỉ bơm overlay) → `reload()` so sánh assetId, thấy y hệt thì bump `contentRefreshGeneration` = `contentRefreshVersion` → grid **reconfigure cell hiển thị tại chỗ, GIỮ nguyên scroll** (KHÔNG re-anchor — nếu không, cancel index sẽ nhảy về đáy). Chỉ khi danh sách khác thật mới re-anchor. Album paging chỉ tăng count → reload GIỮ offset. Không còn `PhotoPrependEvent`/trigger 30 item — không có gì prepend nữa
- **Pinch đổi mật độ — interactive layout transition (mechanic Photos thật)**: dải cột liền **`GridDensity.columnRange` (1…8)**, API UIKit chuẩn `UICollectionViewTransitionLayout`. Pinch xác định hướng (spread = bớt cột/cell to, pinch vào = thêm cột), `startInteractiveTransition(to:)` sang layout ±1 cột; magnification (log-space, span 0.35) map vào `transitionProgress` — **cell to/nhỏ theo ngón tay, UIKit nội suy frame + contentOffset giữa hai layout** (không còn màn đen/bay xa — offset được nội suy, không stale). Progress chạm 1 → `finishInteractiveTransition` + re-arm baseline (một gesture dài bước được nhiều cột, mỗi segment đúng 1); thả tay giữa chừng: >0.4 finish, ngược lại cancel (spring về cũ); đảo chiều ngón → progress về 0 → cancel + cho segment ngược. **Segment phải serialize qua cờ `isSettling`**: từ finish/cancel tới completion callback của UIKit không được `startInteractiveTransition` mới — gọi giữa lúc settle làm hỏng state machine (UIKit trả layout đích trần → crash `setTransitionProgress`, đơ grid); movement trong cửa sổ settle chỉ re-baseline rồi bỏ qua. Sau mỗi commit: granularity đổi (day↔month tại 3↔4) → rebuild sections + `reloadData`; reconfigure visible cells xin thumbnail nét hơn; prefetch cache size cũ bị drop (`stopCachingAllThumbnails`). Math thuần ở `Domain/Grid/GridDensity` (`clamped`/`stepped`, có unit test). Mức cột persist `@AppStorage("grid.columns")` chung Library + Album Detail (sanitize `GridDensity.clamped`, legacy 9 → 8). Pinch disabled khi đang multi-select. Mức to nhất (1 cột) cell vẫn vuông — native aspect là follow-up.
- **Date section header** (chỉ khi sort theo ngày chụp; sort metric → grid phẳng): nhóm theo **ngày** ("Today"/"Yesterday"/"July 19, 2026") ở ≤3 cột, theo **tháng** ("July 2026") ở >3 cột; header pinned khi scroll (`sectionHeadersPinToVisibleBounds`, dạng **capsule chip glass** nhỏ lề trái — ultraThinMaterial + hairline stroke, không phủ full-width); ảnh không có ngày chụp → section "No Date" (khớp NULLS LAST: nằm cuối ở grid top-anchored như Album Detail, nằm trên cùng ở Library bottom-anchored vì mảng được đảo sau khi load). Grouping thuần một pass ở `Domain/Grid/PhotoGridSectionBuilder` (range flat-index như OnThisDay, có unit test) — swipe-select/tap/paging vẫn tính trên mảng phẳng.
- Mỗi thumbnail hiển thị 1 dòng metadata nhỏ overlay phần dưới ảnh, nền gradient nhẹ:
  - Mặc định: `ISO 400 · 85mm · f/1.8`
  - Tùy chọn bật/tắt từng field trong Settings: shutter speed, **megapixels** (`24.2 MP`, từ width×height đã lưu), **file size** (`12.4 MB`, từ cột `fileSize`) — vd đầy đủ `ISO 400 · 85mm · f/1.8 · 1/500s · 24.2 MP · 12.4 MB`. MP và file size mặc định tắt
  - **Ẩn khi cell hẹp hơn ~90pt** (mức cột dày)
- Thumbnail size theo cell width tính từ bounds collection view + số cột (2x scale cap — 3x không phân biệt được ở cỡ cell, đỡ 2.25x decode); khi cell to lên (pinch về ít cột) cell re-request bản resolution cao hơn (ngưỡng 1.4×), giữ ảnh cũ tới khi bản nét về. (On This Day vẫn dùng SwiftUI `PhotoGridTile` + `.measureWidth(into:)` — grid nhỏ 3 cột cố định)
- Metadata nhỏ nhưng dễ đọc, không làm rối ảnh, tự thích nghi Light/Dark Mode
- Chỉ hiển thị giá trị có thật — KHÔNG hiển thị placeholder kiểu `ISO -- · --mm · f/--`

**Navigation bar**

- Nav bar mỏng trong suốt, KHÔNG title (`navigationBarTitleDisplayMode(.inline)`, không set `navigationTitle`) — grid (`PhotoGridCollectionView`) `.ignoresSafeArea()` fill dưới nav bar nên ảnh scroll dưới các nút, không còn dải đen sau chrome; "transparent-at-top" như Album/Statistics. Banner limited-access + filter chips ghim qua `safeAreaInset(edge: .top)` (không nằm trong `VStack` để grid vẫn là root scroll view)
- Sort button (`Menu`)
- **Import button** (`square.and.arrow.down`, góc phải cùng của toolbar) mở màn Import từ thẻ/ổ ngoài (§7.7). **Không còn nút Filter nhanh cũ** — Advanced Search (§7.1) đảm nhận lọc ad-hoc; state `criteria` vẫn tồn tại cho drill-down từ Statistics + chips filter đang active
- Search KHÔNG nằm trong nav bar — nút search tròn trong thanh chrome nổi phía dưới
- Nút Select (checkmark) bật chế độ chọn nhiều ảnh (xem **Multi-select** bên dưới)

**Search**

- Tìm theo: filename, camera model, lens model, focal length, ISO, aperture, shutter speed, sensor format
- Ví dụ: `IMG_1234`, `Canon R6`, `RF 100-500`, `85mm`, `ISO 3200`
- Query DSL (`SearchParser`): tự nhận diện ISO, aperture (f/1.8), shutter (1/500), focal length (85mm), sensor format; còn lại match tự do vào camera/lens/filename; số trần (không đơn vị) được OR vào ISO/focal/tên thiết bị/filename
- `originalFilename` chỉ được ghi ở EXIF pass (fast pass không fetch resource); ảnh mới chỉ có placeholder row chưa match được theo filename cho tới khi EXIF pass chạy xong
- Autosuggest dựa trên danh sách camera/lens có trong database
- Chạy trên local database đã index, không quét lại file

**Advanced Search** (rule builder dùng chung với Smart Album)

- Trong màn search (SearchTab iOS 26 / SearchSheet pre-26) có row **"Advanced Search"** (`slider.horizontal.3`) mở `AdvancedSearchSheet` — cùng rule builder của editor smart album, nhưng áp làm **query tạm** lên grid thay vì lưu album.
- **Component dùng chung `RuleBuilderSections`** (`Features/Shared/`): section Match all/any + section Conditions (rows `SmartAlbumRuleRow` + Add Condition + delete + footer live match count). Cả `SmartAlbumEditorSheet` và `AdvancedSearchSheet` nhúng nó vào `List` của mình — sửa một chỗ, hai màn đồng bộ.
- **Loại trừ lẫn nhau với search/filter thường**: `LibraryController.advancedQuery: SmartAlbumQuery?`. Set nó thì clear `criteria` (và ngược lại — search text/filter thường clear `advancedQuery`) qua `didSet`, để grid chỉ có một nguồn. `reload()` ưu tiên: fast path PhotoKit (khi `criteria.isEmpty && advancedQuery == nil && sort.isDateSort`) → `gridItems(matching: advancedQuery)` khi advanced active → `gridItems(matching: criteria)`. `hasActiveQuery` gộp cả hai (dùng cho empty state + Clear).
- **Áp & hiển thị**: nút "Search" (disable khi không có rule hợp lệ) set `advancedQuery = validRules` rồi chuyển về tab Library. Khi active, thay `FilterChipsBar` bằng `AdvancedSearchBar` (chip `rule.displaySummary` + match count + **Edit** mở lại builder + **Clear**).
- **Save as Smart Album**: nút trong `AdvancedSearchSheet` mở `SmartAlbumEditorSheet(existing: nil, initialQuery:)` (init nhận `initialQuery` để seed rule từ search) — biến một lần search thành album lưu vĩnh viễn.

**Filter** (sheet native, medium/large detents, kết hợp nhiều điều kiện)

- **Camera Brand** và **Camera Body**: hai multi-select độc lập (không drill-down phân cấp)
- **Lens**: multi-select, danh sách phẳng (prime/zoom: logic `isZoom` có trong domain, chưa đưa lên UI filter)
- **ISO**: exact, range, nhóm nhanh (≤100, 101–400, 401–1600, 1601–6400, >6400)
- **Shutter Speed**: exact, range, nhóm nhanh (chậm hơn 1/30s, 1/30–1/125, 1/126–1/500, nhanh hơn 1/500s)
- **Aperture**: exact, range, nhóm nhanh (f/1.0–2.0, f/2.1–4.0, f/4.1–8.0, nhỏ hơn f/8)
- **Focal Length**: actual + full-frame equivalent, exact, range, nhóm nhanh theo góc nhìn:
  - Dưới 20mm equivalent: Ultra-wide
  - 20–34mm: Wide
  - 35–69mm: Standard
  - 70–134mm: Portrait / Short telephoto
  - 135–299mm: Telephoto
  - Từ 300mm: Super telephoto
- **Sensor Format**: multi-select — Full Frame, APS-H, APS-C, Micro Four Thirds, 1-inch, Compact, Medium Format, Smartphone, Unknown

**Filter state**

- Filter chips phía trên grid + nút Clear All + số lượng ảnh khớp
- Giữ nguyên filter khi mở ảnh rồi quay lại

**Sort**

- Date taken newest/oldest, ISO, focal length, FF equivalent focal length, aperture, shutter speed (KHÔNG có sort theo file size — dù `fileSize` đã được index, sort theo kích thước chưa mở, xem §6)
- Mọi ORDER BY kết thúc bằng tiebreaker `assetId` và dùng `NULLS LAST` cho creationDate — thứ tự total nên display order deterministic qua các lần reload (giá trị trùng hoặc NULL không làm xáo vị trí)

**Multi-select (chọn nhiều ảnh)**

- Vào chế độ chọn: nút checkmark trên nav bar, hoặc long-press một ảnh trong grid (ảnh đó được chọn luôn)
- Không giới hạn số lượng; tile được chọn hiển thị badge checkmark + viền accent (thứ tự chọn vẫn được giữ trong state — quyết định thứ tự pane khi Compare)
- **Swipe-to-select** (kiểu app Photos): trong chế độ chọn, vuốt ngón tay qua grid để chọn/bỏ chọn hàng loạt — 8pt đầu của drag quyết định hướng (ngang = chọn, dọc = nhường scroll); range tính theo **index** trong mảng ảnh phẳng giữa ô bắt đầu và ô dưới ngón tay, áp lên snapshot selection lúc bắt đầu drag nên kéo lùi tự hoàn tác; bắt đầu trên ô đã chọn → drag bỏ chọn range; scroll bị disable trong lúc drag active; chưa có edge auto-scroll (follow-up); pinch đổi mật độ cột bị tắt trong chế độ chọn để không xung đột gesture. Logic thuần (direction lock, range) nằm ở `Domain/Selection/SwipeSelectionEngine`, có unit test. Library + Album Detail: UIPanGestureRecognizer trong `PhotoGridCollectionView` (hit-test ô bằng `indexPathForItem(at:)`, chạy simultaneous với pan của scroll); On This Day: bản SwiftUI `SwipeToSelectModifier` (PreferenceKey thu frame ô + DragGesture trên named coordinate space)
- Vào chế độ chọn → **ẩn tab bar** và thay bằng cụm control nổi Liquid Glass (`SelectionBottomBar`) ở đáy, thế chỗ tab bar để không có gì nổi che ảnh (bug cũ: tray nổi che hàng ảnh cuối, không select được). Tab bar ẩn qua hai đường: iOS 26 dùng `.toolbar(.hidden, for: .tabBar)` cục bộ trên mỗi screen đang chọn; pre-26 dùng cờ `AppNavigation.hidesTabBar` để ẩn `LiquidGlassTabBar` trong scaffold. Grid nội `bottomInset` (On This Day: spacer đáy) nở bằng chiều cao cụm control đo được (`measureHeight`) khi đang chọn nên hàng cuối cuộn qua khỏi control → chọn được. **Bố cục**: **Share** chuyển LÊN toolbar top-leading khi đang chọn (thế chỗ nút Settings gear ở Library; các screen album đứng cạnh nút back hệ thống) — là toolbar Button native nên tự có Liquid Glass; đang gom ảnh thì thay glyph bằng `ProgressView`. Đáy còn lại (trái→phải): **chip Compare** glass rời + **panel ảnh** (`GlassPanel` **pill** bo tròn hết, corner = `selectionPanelCorner` 26 = nửa chiều cao) + nút **Delete** tròn (`GlassIconButton` tint đỏ); dưới cùng là dòng text đếm căn giữa. **Slot ảnh tròn đồng tâm với pill**: corner `selectionSlotCorner` = 26 − 8 (padding dọc panel) = 18 = nửa cạnh slot 36 → hình tròn lồng trong capsule. **Compare** là một `GlassPanel` **bo tròn hết** (cornerRadius lớn = capsule, giống chip indexing) riêng bên TRÁI panel, chữ `lineLimit(1)`/`fixedSize`, **luôn hiện** (khi feature có, tức `onCompare != nil`) ghim sát mép trái với **margin cân bằng** (khoảng cách tới viền màn hình = padding bar 16 = spacing 16 tới panel) — **không bay ra/thu vào nữa**. Chỉ **enable trong khoảng 2–4** ảnh (`compareEnabled`); ngoài khoảng đó (0–1 hoặc >4) `.disabled` + chữ `.tertiary` (xám mờ) để yêu cầu "2–4 ảnh" dễ hiểu chứ không biến mất. Chiều cao panel/chip ≈ nút Delete (slot 36 + padding). Khi chọn, Library ẩn nút Filter/Sort, On This Day ẩn nút calendar. **Panel ảnh** đứng cạnh Compare (bên phải nó), `Spacer` đẩy Delete sang mép phải; khi không có Compare (On This Day) panel **căn giữa** bằng `Spacer` hai bên. ≤4 ảnh → 4 slot cố định; slot có ảnh hiện thumbnail local **hình tròn** (kèm badge `xmark.circle.fill` nhỏ **tràn ra ngoài góc trên phải**, `offset(6,-6)`, chỉ che một sliver ảnh, làm gợi ý bỏ chọn), slot trống là **ô tròn viền dash** cùng shape thumbnail (corner 18 chung `selectionSlotCorner`) có icon `photo`; **>4 ảnh → panel GIỮ nguyên cửa sổ rộng đúng 4 slot** (không tràn full-width; Compare ẩn, panel vẫn căn giữa) và biến thành `ScrollView` ngang TẤT CẢ thumbnail đã chọn theo thứ tự chọn (không stack đè) — vì cửa sổ chỉ 4 slot nên ảnh thứ 5 đã tràn, `ScrollViewReader` tự cuộn (`withAnimation`) tới ảnh mới nhất (phải cùng, `anchor: .trailing`) **ngay mỗi lần thêm ảnh** (không phải đợi tích đủ chiều rộng), vừa để lộ rằng cuộn được. **Chạm thumbnail → bỏ chọn ảnh đó** (`onDeselect`; slot trống không phản hồi). **Dòng text đếm** giải thích giới hạn khi còn compare được: `canCompare` (onCompare != nil) → 0 ảnh "Select up to 4 to compare", 1–4 ảnh "N selected · up to 4 to compare", >4 ảnh chỉ "N selected"; không compare được (On This Day) → "Select Photos" / "N selected". **Share** (`PhotoShareSheet`, dùng chung với Photo Detail): gom item mọi ảnh chọn — ảnh → data, video → URL, **cho tải iCloud-only** (`isNetworkAccessAllowed = true`), rồi mở một `UIActivityViewController`. **Delete** (destructive, `deleteAssets`: hệ thống hiện dialog xác nhận, prune DB + state local, user hủy → giữ selection). On This Day là delete-only nên truyền `onCompare: nil` (Compare luôn ẩn, vẫn có Share). **Glass chrome**: `GlassIconButton` + `GlassPanel` dùng `.glassEffect` native trên iOS 26 (không stroke/shadow thủ công), fallback `.ultraThinMaterial` + viền pre-26 — nên Delete/capsule trông đúng Liquid Glass giống nút search/back chứ không mờ đục

**Compare (So sánh ảnh)**

- Mở từ chế độ chọn khi có 2–4 item (ảnh hoặc video); thứ tự pane = thứ tự chọn. Builder yêu cầu `PHAsset` tồn tại chứ **không** yêu cầu row metadata trong DB (`ComparePhoto.metadata` optional) — video không được index (pipeline chỉ index ảnh) nên nếu gate theo metadata thì chọn video sẽ ra mảng rỗng → fullScreenCover trống → màn hình đen
- Màn hình compare (fullscreen): 2–3 item xếp dọc, 4 item lưới 2x2; mỗi pane pinch-zoom/pan; sync zoom và sync pan bật/tắt độc lập kiểu Lightroom (offset chuẩn hóa theo content size nên ảnh khác tỷ lệ vẫn khớp vị trí tương đối)
- **Video pane**: branch theo `asset.mediaType` như Photo Detail — `AVPlayer` từ `requestPlayerItem(forVideo:)` (`isNetworkAccessAllowed = true`) render qua **`ZoomableVideoView`** (UIScrollView + `AVPlayerLayer`, cùng pattern `ZoomableImageView`) nên video **pinch-zoom/pan và tham gia sync** như ảnh; **không autoplay, mute mặc định** (2 video cạnh nhau không chọi tiếng); nút play/pause glass nhỏ ở góc dưới-phải mỗi pane (wrapper zoom thay control native AVKit), clip chạy hết tự tua về đầu; pause khi đóng compare
- 2 nút sync trên topbar là **capsule kiểu filter-chip** (icon + chữ ngắn: "🔍 Zoom" / "✥ Move"): bật = capsule đặc màu accent + chữ trắng (gesture mirror qua các pane), tắt = glass mờ + chữ trắng (pane độc lập); nền compare luôn đen nên chữ trắng cố định, không dùng `.label`
- Caption metadata mỗi pane (camera · focal · aperture · ISO); khi 4 item bỏ camera model cho gọn; item không có metadata row (video/ảnh chưa index) thì không có caption
- **Ảnh kéo eager lúc mở** (`requestDetailImage`, `targetSize` ~ screen×scale, `allowNetwork: true`): mỗi pane hiện ảnh ngay khi mở — iCloud giao derivative cỡ màn hình (nhanh), không phải file gốc. `.opportunistic` vẽ preview local trước nên pane không trắng trong lúc stream. Pane chỉ 1/2–1/4 màn hình nên derivative thừa nét

### 7.2 Photo Detail

- Fullscreen, swipe ngang chuyển ảnh trước/sau — **`UIPageViewController`** (`PhotoPager: UIViewControllerRepresentable`, transition `.scroll`) chứ KHÔNG dùng `TabView(.page)`: TabView dựng mọi page eager nên trước đây phải windowed ±2, mỗi lần đổi index lại remount page giữa lúc vuốt → giật/kẹt (cùng lý do grid bỏ SwiftUI qua UICollectionView). PageViewController dựng page **lazy** qua data source (`viewControllerBefore/After` → `PhotoPageHost` nhớ `index`), library cỡ nào cũng rẻ, paging native. `PhotoBrowsingSource` vẫn là protocol index-based (`photoCount`/`photoId(at:)`/`index(of:)`/`metadata(for:)`/`asset(for:)`) nên pager không ôm cả mảng metadata; Library fetch full `PhotoMetadata` on-demand từ DB theo assetId, Albums/On This Day trả từ mảng in-memory. `didFinishAnimating` ghi index về binding + `loadNextPageIfNeeded`. **Mở viewer theo identity (assetId), KHÔNG theo index vị trí bắt được từ grid**: các screen giữ `viewerTarget: PhotoViewerTarget?` (`{id, startIndex}`, `Identifiable`), tap set `viewerTarget = PhotoViewerTarget(id:, startIndex: controller.index(of: assetId))` — `startIndex` **resolve từ chính controller viewer dùng** (không tin index phẳng của grid), present qua `fullScreenCover(item:)`. Trước đây giữ `selectedPhotoIndex: Int` bắt lúc tap; sau khi xoá ảnh prune mảng thì index vị trí đó trỏ sang ảnh khác → **tap grid mở nhầm ảnh**. Dùng `item:` (không `.id` + `isPresented`): `startIndex` chốt một lần lúc mở, `id` cho identity (seed lại `@State currentIndex` mỗi ảnh khác). **Không** re-resolve `index(of:)` mỗi lần parent render — nếu re-resolve, xoá ảnh đang xem trong viewer khiến id biến mất → nội dung cover rỗng → **màn hình đen**; `item:` giữ cover ổn định để viewer tự quản index nội bộ
- Pinch-to-zoom + double-tap zoom (`UIScrollView` representable) cho ảnh; `ZoomableImageView.onZoomChange` báo zoom scale lên pager → (1) **tắt swipe-down-dismiss khi đang zoom** (vuốt lúc đó pan ảnh), (2) bubble tiếp lên `PhotoDetailScreen` (`PhotoPager.onZoomChange`) để **ẩn tạm toàn bộ chrome + info panel khi zoom** (scale > 1.01), zoom về 1x hiện lại; đổi trang reset zoom
- **Video**: `PhotoDetailPage` branch theo `asset.mediaType` — video dùng `VideoPlayer` (AVKit) với `AVPlayer` dựng từ `PHImageManager.requestPlayerItem(forVideo:)` (`isNetworkAccessAllowed = true`, phát được cả video iCloud), pause khi rời trang; ảnh vẫn đi đường `ZoomableImageView`. Control native (play/scrubber/mute/AirPlay) hiện đầy đủ; player được chừa `videoBottomInset` ở đáy (= chiều cao action bar đáy + safe-area bottom, đo qua `ChromeHeightKey`/`SafeAreaBottomKey`) nên thanh control nằm **trên** action bar, không đè. Inset đo được (0 lúc đầu) nên `PhotoPager.updateUIViewController` dựng lại **chỉ trang video hiện tại** khi inset về giá trị thật (`applyVideoInsetIfNeeded`, `PhotoPageHost.isVideo`); ảnh giữ full-bleed (inset 0) để zoom
- **Ảnh hiển thị = derivative cỡ màn hình, kéo eager** (`requestDetailImage`, `.opportunistic`, `targetSize` ~ screen×scale, `allowNetwork: true`) — CƠ CHẾ then chốt: iCloud lưu bản gốc **+ bộ derivative nhiều cỡ**; request cỡ màn hình (KHÔNG phải `PHImageManagerMaximumSize`) thì iCloud giao **bản derivative cỡ màn hình** (vài trăm KB, nhanh), KHÔNG phải file gốc 20–50MB — đúng cách Photos lấy ảnh xem nét-nhanh kể cả khi bản gốc đã offload. `.opportunistic` vẽ bản local low-res tức thì làm placeholder rồi thay bằng derivative sắc nét. `loadDisplayImage` gọi lúc page appear.
  - **Placeholder ba tầng, nét dần**: (1) `loadDisplayImage` fire `requestBestLocalImage` (`PhotoLibraryService`) NGAY khi page load — **độc lập callback mạng** (bản degraded của `.opportunistic` có thể không bao giờ tới khi daemon iCloud kẹt): `requestImage` (dựa **rendition**, không phải file gốc) với `isNetworkAccessAllowed = false` + `deliveryMode = .highQualityFormat` + `resizeMode = .exact` trả **rendition local cỡ thiết bị** mà "Optimize iPhone Storage" luôn giữ — sắc nét gần full-screen, không cần mạng. (Lưu ý phân biệt: `.highQualityFormat` trả nil local chỉ đúng với `requestImageDataAndOrientation` vốn đòi file gốc — xem `ExifService.readExifFromLocalDerivative`; `requestImage` làm việc trên rendition nên trả bản local tốt nhất.) Chỉ **nâng cấp** (thay khi pixel lớn hơn ảnh hiện tại và bản network final chưa về), không hạ cấp → (2) bản degraded cache (nếu tới) → (3) derivative iCloud sắc nét đè cuối. Đây là lý do viewer nét ngang app Photos ngay cả khi iCloud kẹt/offline. Request local-best cũng bị huỷ ở `onDisappear`
  - Trạng thái tải bubble lên `PhotoDetailScreen` qua `onDownloadStateChange(index, progress, isDownloading)`. Page preload off-screen (`UIPageViewController` dựng ±1) báo trạng thái TRƯỚC khi thành current, nên `PhotoDetailScreen` lưu theo index (`pageDownload`, prune quanh currentIndex) rồi hiển thị của trang hiện tại — nếu chỉ lọc `index == currentIndex` thì trang vừa swipe tới mà download đã stall sẽ không hiện ring/stall (report duy nhất của nó bắn lúc chưa current). `refreshCurrentPhoto` (đổi trang) re-apply state đã lưu của trang mới. Hiện **vòng tròn tiến độ kiểu iOS bọc quanh icon `icloud`** (`ICloudDownloadRing`) ở **góc trên-phải của info panel** — xác định (`Circle().trim` theo `progress`) khi có phần trăm, xoay vô định khi chưa có. Ring chỉ hiện khi thực sự stream iCloud; ảnh local giao thẳng bản non-degraded nên không hiện ring.
  - **Phát hiện stall iCloud**: download báo 0% trọn **15s** liên tục (`stallWindow`, one-shot task — mọi tick progress > 0, hoàn thành, hoặc đổi trang đều disarm) → ring thay bằng icon `exclamationmark.icloud` cam + dòng caption "iCloud isn't responding — check iCloud Photos in Settings or the Photos app." trong info panel. Không tự huỷ/re-request (request PhotoKit đang treo tự tiếp tục khi daemon sống lại); ảnh placeholder vẫn hiển thị bình thường. Lý do tồn tại: iCloud của máy có thể ngừng phục vụ download toàn cục (account-auth Code=7, Low Power/Low Data, sync paused — xem §6) — spinner vô hạn làm user tưởng app treo trong khi lỗi ở tầng thiết bị
- **Zoom → nâng lên bản GỐC** (`loadFullResolution`, `PHImageManagerMaximumSize`, `allowNetwork: true`): lần zoom đầu tiên (`ZoomableImageView.onZoomChange` scale > 1.01, cờ `didRequestFullResolution` chống gọi lại) mới kéo file gốc để soi pixel — chậm hơn (multi-MB) nhưng chỉ khi user chủ động zoom, có ring. `ZoomableImageView.updateUIView` gán lại `imageView.image` nên bản gốc thay vào liền không remount.
- **Huỷ request khi lật đi**: `onDisappear` huỷ cả request derivative (`requestId`) lẫn request bản gốc (`fullResRequestId`) qua `cancelImageRequest` — page hàng xóm preload (`UIPageViewController` dựng trước ±1 page) không giữ download giành băng thông của page đang xem (đây là nguyên nhân thật gây "tải cực lâu" trước kia, không phải cỡ ảnh).
- **Viewer tạm dừng index để download không bị chèn** (xem §6, `IndexInteractionGate`): `PhotoDetailScreen.onAppear` giữ gate / `onDisappear` nhả; `touch()` mỗi lần đổi trang + mỗi tick `onDownloadStateChange` của page đang hiển thị — EXIF pass ngừng spawn read iCloud mới trong suốt phiên xem, download tương tác (derivative lẫn bản gốc khi zoom) không phải xếp sau các stream index.
- **Fill metadata lúc appear (KHÔNG chờ tải ảnh, không tải lại)**: page appear → `onMetadataRefresh(index)` → `controller.refreshMetadataAfterDownload(assetId:)` → `IndexPipeline.indexSingle` đọc EXIF (stream chỉ ~KB header qua `PHAssetResourceManager`, đường riêng — KHÔNG phụ thuộc download ảnh full) + compose + upsert **một** row (không đụng con trỏ resume của batch pipeline; bỏ qua row đã `indexed`/`noExif`, không đọc được vẫn giữ nguyên `pendingICloud`), cập nhật `currentMetadata` cho info panel ngay. Vậy ảnh `pendingICloud`/placeholder được fill dần khi user xem, lần sau không cần tải lại
- Swipe-down-to-dismiss (ngưỡng velocity/khoảng cách, animation thu nhỏ) — `UIPanGestureRecognizer` trên view của pager, delegate chỉ cho begin khi **vuốt xuống dọc** (`velocity.y > 0 && |vy| > |vx|`) và **chưa zoom** nên vuốt ngang vẫn thuộc paging, `shouldRecognizeSimultaneouslyWith = false`
- **Swipe-up để mở full EXIF**: `UISwipeGestureRecognizer(.up)` trên view của pager (cùng delegate, chỉ begin khi chưa zoom) mở sheet `MetadataPanel` — giống hệt bấm nút Info
- **Status bar iOS hiện trong viewer**: bỏ `.statusBarHidden()`, thêm `.preferredColorScheme(.dark)` → clock/battery/Dynamic Island (Live Activities) hiện, chữ trắng trên nền đen
- **Chrome tách trên/dưới**: nút X (Close) góc **trên-trái**, **info panel nằm ngay bên phải nút Close (cùng hàng trên)** — tiết kiệm diện tích, không đè ảnh; các nút hành động (Favorite / Share / Info / **Delete**) gom thành **action bar ở đáy** (cả ảnh lẫn video). Toàn bộ chrome + info panel **ẩn khi zoom**. `ChromeHeightKey` giờ đo chiều cao **action bar đáy** (= `videoBottomInset` để control video nằm trên nó). Dòng đầu info panel hiện **ngày giờ chụp** (`creationDateValue`, `.dateTime.day().month().year().hour().minute()`) thay cho tên file (tên file không quan trọng); badge định dạng (RAW/HEIC/JPG) vẫn suy ra từ đuôi file
- **Xoá ảnh từ viewer**: nút Delete (`trash`) ở action bar gọi `PhotoBrowsingSource.deleteAsset(id:)` → `deleteAssets(ids:)` của controller → **PhotoKit hiện dialog xác nhận hệ thống** (app không tự dựng dialog: app bên thứ ba không thể ẩn/di dời dialog này). User hủy → không đổi gì. Xoá xong nguồn bị prune nên pager **re-seat** về cùng index đã clamp (`min(currentIndex, count-1)`) qua `reseatToken` (buộc dựng lại trang hiện tại dù index không đổi — vì `syncIfNeeded` chỉ re-seat khi `shown != index`) → hiện ảnh kế tiếp kiểu app Photos; hết ảnh thì `dismiss()`
- Share qua `UIActivityViewController`: ảnh share image data, video share URL từ `AVURLAsset` (`requestAVAsset(forVideo:)`); file chưa tải về máy (iCloud) → alert "Unable to Share"
- Favorite qua `PHAssetChangeRequest` (PhotoKit thật)
- Info panel hiện ở đáy (cả ảnh lẫn video, ẩn khi zoom): filename + badge định dạng (RAW/JPG/HEIC) + gear + exposure + file size
- **Nút Info (hoặc swipe-up) → sheet EXIF chia mục hữu ích** (`MetadataPanel`, sheet inset grouped list): đọc **live** khi mở sheet qua `AssetMetadataDump.load(for:)` (async, có thể chạm iCloud). Ảnh được **curate thành các mục dễ đọc**, phần còn lại gom vào **Other** (không mất dữ liệu — dedupe key đã dùng):
  - **Resolution**: pixel W×H, megapixels, DPI, orientation
  - **Camera**: Make, Model, Lens Make/Model, Lens (LensSpecification), Body/Lens Serial
  - **Exposure**: ISO, aperture, shutter speed, focal length + FF-equivalent, EV bias, exposure program, metering, flash, white balance
  - **Software**: TIFF `Software` (phiên bản iOS/firmware), HostComputer
  - **Date**: DateTimeOriginal/Digitized, TIFF DateTime, offset time zone, sub-second
  - **Shutter Count** (số lần chụp của body, chỉ hiện khi đọc được): `MakerNoteParser` (Domain, pure, có unit test) parse MakerNote thô từ **file gốc** (`PHAssetResourceManager.requestData`, edit sẽ strip MakerNote) — **Nikon** tag `0x00A7` plaintext (chắc chắn), **Sony** tag `0x9050` giải mã hoán vị `(b³ % 249)` rồi đọc int32u ở offset theo model (best-effort, body mới có thể trượt), **Fujifilm** `0x1438` (best-effort). **Canon** không lưu trong file → không hiện
  - **Location**: toạ độ + altitude (từ `PHAsset.location`)
  - **Other**: mọi property ImageIO còn lại (top-level + từng dict con `{Exif}`/`{TIFF}`/`{GPS}`/`{ExifAux}`…) chưa được mục nào dùng
  - **Asset** / **Resource N**: local id, media type/subtypes, pixel size, ngày, favorite/hidden; originalFilename, type, UTI, file size
  - Video giữ nguyên: section **Video** (duration) + **Video/Audio Track** (dimensions, frame rate, data rate, codec FourCC) + **Metadata** (`commonMetadata`) từ `AVAsset`
  - Row rỗng bị bỏ; value `textSelection(.enabled)`
- Không hiển thị giá trị không tồn tại

### 7.3 Collections

- Tab tên **"Collections"** (`AppTab.albums.title`). Nút **"+"** (`plus`) góc trên phải (own `ToolbarItem(.topBarTrailing)` để có glass circle riêng trên iOS 26) mở sheet tạo **Smart Album**. Hero card "On This Day" full-width đứng đầu tab (xem mục dưới, GIỮ NGUYÊN), phía dưới là các nhóm chip.
- Các nhóm chip dùng chung layout — mỗi nhóm là **grid scroll ngang** (`ScrollView(.horizontal)` + `LazyHGrid`) lấp đầy tối đa **3 hàng** theo cột rồi mới scroll sang phải (kiểu pinned-collections app Photos); số hàng = `max(1, min(3, (count + 2) / 3))` nên ít album thì thấp hơn. Chip = `AlbumChip` kích thước đồng nhất (`chipWidth` 190, `height` 60): thumbnail cover vuông nhỏ (44) bên trái + tên album + số ảnh, nền rounded rect.
  - **"Smart Albums"** (`smartAlbumsSection`): một section header duy nhất, grid gộp — smart album **do user tạo** (chip `SmartAlbumChip`, glyph phễu `line.3.horizontal.decrease.circle` khi chưa có cover) đứng trước, rồi tới smart album **hệ thống** Apple (Recently Added / Favorites / Screenshots — KHÔNG có Recents; `PHAssetCollectionType.smartAlbum`, chip `AlbumChip`). KHÔNG còn section "My Smart Albums" riêng.
  - **"My Albums"** (user album) và **"Shared Albums"** (iCloud shared, tách riêng): mỗi nhóm có header. Tách shared qua `AlbumItem.isShared` = `collection.assetCollectionSubtype == .albumCloudShared`; controller expose `userAlbums` (non-smart, non-shared) và `sharedAlbums` (non-smart, shared)
- Album Detail: grid phân trang (page size 120) dùng `PhotoGridCollectionView` chung với Library (top-anchored) — pinch interactive transition trong dải 1…8 (persist chung key `grid.columns`) + date section header luôn bật (fetch hard-sort theo creationDate); trang kế load khi cell gần cuối hiển thị (`willDisplay`, ngưỡng 30); chạm ảnh mở Photo Detail; multi-select đầy đủ như Library (checkmark toolbar / long-press / swipe-to-select, `SelectionBottomBar`: Share + Compare 2–4 + Delete). Paging cursor (`nextFetchIndex`) tách khỏi `photos.count` vì `PHFetchResult` snapshot bất biến — sau khi xoá ảnh, trang kế tiếp skip các id đã xoá thay vì append trùng
- Banner Limited Access + nút Manage khi quyền bị giới hạn

**On This Day (smart album "Ngày này năm xưa"):**

- Tổng hợp ảnh chụp đúng ngày/tháng đang chọn ở các năm TRƯỚC năm hiện tại (mặc định: hôm nay). Fetch qua PhotoKit `NSCompoundPredicate` — mỗi năm một cửa sổ `[00:00, +1 ngày)` trên `creationDate`, build bởi hàm pure `OnThisDayWindows.windows` (Domain, có unit test; bỏ qua 29/2 ở năm không nhuận, cap 100 năm). Tải toàn bộ một lần, không phân trang.
- Màn chi tiết (`OnThisDayScreen` + `OnThisDayController`): grid 3 cột nhóm theo năm (section header "2023 · N years ago", năm mới nhất trước), chạm ảnh mở Photo Detail.
- Đổi ngày: nút lịch trên toolbar mở sheet `DatePicker(.graphical)` (detent medium) + nút "Today"; chỉ tháng/ngày được dùng để so khớp.
- Xoá ảnh: long-press (hoặc nút toolbar) vào chế độ chọn nhiều (không giới hạn số lượng, badge checkmark, hỗ trợ swipe-to-select xuyên section — range tính trên mảng ảnh phẳng), bottom bar dưới (`SelectionBottomBar`, `onCompare: nil` nên không có nút Compare) hiện Share + "N Selected" + nút Delete → `PhotoLibraryService.deleteAssets` (`PHAssetChangeRequest.deleteAssets`, hệ thống tự hiện dialog xác nhận, ảnh vào Recently Deleted). Sau khi xoá thành công, xoá luôn row tương ứng trong DB (`MetadataDAO.deleteAssets`) để Library grid không stale; user hủy dialog → giữ nguyên selection.

**Smart Album (user tạo — saved filter):**

- **KHÔNG phải** smart album PhotoKit (PhotoKit không cho tạo smart album custom-predicate). Là **saved filter cấp app**: một **rule query** có tên, lưu trong DB (bảng `smart_albums`, migration `v3-smartAlbums`). `SmartAlbum { id, name, query, createdAt }` là Codable record (`SmartAlbumDAO`); `query` (`SmartAlbumQuery`) lưu **JSON string** trong cột text — cột **vẫn tên `criteria`** nên **không cần migration schema**. `SmartAlbum` encode/decode cột `criteria` như `String` thuần rồi tự `JSONEncoder/JSONDecoder` cho `query` (KHÔNG dựa vào nested-Codable ngầm của GRDB: lúc decode GRDB đưa cả row DB — không phải chuỗi JSON — cho nested `Codable`, khiến `SmartAlbumQuery.init(from:)` không thấy `rules`/`matchMode`, im lặng ra query rỗng → album khớp cả thư viện).
- **Model điều kiện** (`SmartAlbumQuery`, `Core/Models/SmartAlbumQuery.swift`): `matchMode` (`.all` = AND / `.any` = OR) + `rules: [SmartAlbumRule]`. Mỗi `SmartAlbumRule` = `field` + `op` + operand(s). `RuleField` gồm: camera brand / body / lens, sensor format, **file type**, **filename**, ISO, aperture, shutter, focal length, **date taken**, favorite. `RuleField.kind` (text / choice / number / date / favorite) quyết định operator hợp lệ + editor:
  - **text** (brand/body/lens/filename): `contains`, `does not contain`, `is` (exact), `is not`. Khớp trên cột normalized + raw (`LIKE %term%` cho contains; `= COLLATE NOCASE` cho exact; negation dùng `COALESCE(col,'')` để row NULL vẫn thoả) → "R6" bắt "Canon EOS R6".
  - **choice**: `sensor format` (enum `SensorFormat`) và `file type` (enum `PhotoFileType`: JPEG / HEIC / PNG / TIFF / GIF / DNG / RAW — map ra tập đuôi file, khớp `originalFilename LIKE %.ext`; RAW gộp nhiều đuôi cr2/cr3/nef/arw/…). Operator `is` / `is not`.
  - **number** (ISO/aperture/shutter/focal): `is` (=), `greater than` (>), `less than` (<), `is in range` (BETWEEN). Shutter nhận "1/500" hoặc thập phân (`NumericRangeField.parse/.format`, `numericKind`). Focal có toggle **Actual / FF Equivalent** (`focalMode`, chọn cột `focalLength`/`equivalentFocalLength`).
  - **date taken** (`creationDate` epoch): `is on` một ngày chính xác (DatePicker; khớp trọn ngày lịch `[startOfDay, startOfNextDay)` qua `Calendar.current`, đúng cả ngày DST — operator mặc định), `is in the last` N days (so với `strftime('%s','now')` — luôn "live"), `is before` / `is after` (DatePicker), `is in range`.
  - **favorite**: segmented Favorite / Not favorite (`isFavorite = 0/1`).
- **Tạo/sửa**: nút "+" mở `SmartAlbumEditorSheet` (NavigationStack + toolbar Cancel/Save). Bố cục kiểu smart album của Photos macOS: field **tên**; picker **Match all / any** (segmented) + câu mô tả; section **Conditions** — danh sách rule (`SmartAlbumRuleRow`, hai dòng: menu field + menu operator + nút **"−"** xoá condition ở dòng trên, editor value ở dưới; vẫn còn swipe-to-delete), nút **"Add Condition"** thêm rule mới (KHÔNG hiện sẵn cả loạt field như bản cũ). Footer hiện **live match count** (`LibraryQueryDAO.count(matching: query)` chạy off-main mỗi lần `query` đổi). Text field camera/lens **autocomplete inline**: chip gợi ý (lọc theo chữ đang gõ, substring không phân biệt hoa/thường, tối đa 12) hiện ngay dưới ô — chạm để điền, vẫn gõ tự do được (KHÔNG còn nút chevron menu bên phải ô value). Focal length: ô số có nhãn **"mm"** cố định bên phải + chỉ nhận chữ số/dấu chấm (không gõ được đơn vị vào giá trị). Save disable khi tên rỗng hoặc không có rule hợp lệ; lúc save chỉ giữ `validRules` (drop rule bỏ trống).
- **Compile SQL**: `LibraryQueryDAO.whereClause(for: SmartAlbumQuery)` build mỗi rule thành 1 điều kiện rồi nối bằng `AND` (all) / `OR` (any); rule chưa đủ input (`SmartAlbumRule.isValid`) bị bỏ qua để dòng dở dang không zero-out (all) hay nới rộng (any) kết quả. `gridItems(matching: query:)` / `count(matching: query:)` là overload cạnh bản `FilterCriteria`. **`FilterSheet` + `FilterCriteria` của Library giữ nguyên** (multi-select checkbox, AND-only) — rule builder chỉ dùng cho smart album.
- **Tương thích ngược**: `SmartAlbumQuery.init(from:)` tolerant — đọc shape mới `{matchMode, rules}`; nếu không có key `rules` thì thử decode `FilterCriteria` cũ và `migrating(_:)` chuyển sang rules (matchMode `.all`) để album lưu trước khi có rule builder vẫn resolve ảnh.
- **Hiển thị**: trong section "Smart Albums" (chip `SmartAlbumChip`); count + cover tính live qua `LibraryQueryDAO.count(matching:)` và `gridItems(...limit:1)` chạy off-main (`AlbumsController.loadSmartAlbums`, `SmartAlbumChipModel` `@unchecked Sendable` vì ôm `PHAsset`). Album count 0 vẫn hiện.
- **Mở**: chạm chip → **push** `SmartAlbumDetailScreen` (route `SmartAlbumRoute`, có nút back, VẪN ở tab Collections — KHÔNG nhảy tab Library). Màn detail như album thường: header điều kiện read-only ở top (`SmartAlbumConditionsBar` — match count + badge match all/any khi >1 rule + chip mô tả từng rule `SmartAlbumRule.displaySummary`), grid ảnh khớp query. `SmartAlbumDetailController` mirror `LibraryController` (query-driven, load một lần, conform `PhotoBrowsingSource`) — dùng chung viewer/multi-select/Compare/Delete với Album Detail. Long-press chip → context menu Edit / Delete (`AlbumsController.deleteSmartAlbum`).

### 7.4 Statistics

Màn Statistics là **dashboard chart tuỳ biến** (thay cho danh sách section cố định trước đây, kiểu tạo graph trong dashboard CloudWatch): một `List` dọc các **card chart** rời (mỗi card một div bo góc riêng), mỗi card là một `ChartWidget`. User thêm / sửa / xoá / kéo sắp xếp. Lần cài đầu tiên seed **hai** chart mặc định: **Top Camera** (bar theo camera body) và **Total Photos & Videos** (KPI đếm toàn bộ item) — cả hai editable / xoá được; user tự dựng thêm.

- **Mô hình widget** (`ChartWidget`, `Core/Models/ChartWidget.swift`): `kind` + `dimension` (trục X / group-by) + `metric` (trục Y) + `filter` (`SmartAlbumQuery` — dùng chung rule engine với Smart Album) + `seriesSplit` (chỉ `.line`) + `topN` + `scope` (`StatsDateScope`, date range **riêng từng chart**). Không còn scope toàn dashboard.
  - **`ChartKind`**: `.bar` (horizontal bar), `.donut` (SectorMark), `.line` (metric theo thời gian, tách series tuỳ chọn), `.kpi` (một số — scalar toàn thư viện, hoặc top group by count). Mỗi kind khai báo `allowedDimensions` / `allowedAggregations` (pattern như `RuleFieldKind.allowedOperators`).
  - **`ChartDimension`** (trục X): categorical (camera body / brand, lens, sensor format, favorite), binned-numeric (ISO / aperture / shutter / focal actual / focal FF — tái dùng bucket `ISOQuickGroup` / `ApertureQuickGroup` / `ShutterQuickGroup` / `FocalHistogramBucket`), temporal (date theo day / month / year, `strftime`). `fileType` hoãn (chưa có cột riêng). Mỗi dimension map tới **cột SQL hardcode** (`groupColumn`, closed switch) + `drillCriteria(key:)` sinh `FilterCriteria` cho drill-down.
  - **`ChartMetric`** (trục Y): `.photoCount` mặc định + aggregate `avg / median / sum / min / max` trên field số (`iso`, `aperture`, `shutter`, `focalLength`, `equivalentFocalLength`, `fileSize`, `megapixels`). **Median chỉ hợp lệ với `.kpi`** (median per-group không có dạng SQL rẻ) — chặn trong validity matrix.
- **Aggregate** qua `StatsDAO.chartData(for:scope:)` — dispatch theo `kind`; GROUP BY / bucket / temporal chạy trong SQLite (binned bucket vẫn fold trong Swift như `rangeHistogram`). Predicate của `filter` compile bởi **`SmartAlbumSQLCompiler`** (tách ra dùng chung với `LibraryQueryDAO`), AND với `scopeClause` (date scope). **Tên cột chỉ đến từ enum đóng, không bao giờ từ text user** → SQL build bằng chuỗi không có bề mặt injection; chỉ giá trị bound (`?`) đến từ input.
- **Persistence**: bảng `stat_charts` (migration `v4-statCharts`); `ChartWidget` lưu **JSON string** trong cột `config` (+ `position`), encode / decode JSON thủ công như `SmartAlbum` (tránh bẫy nested-Codable của GRDB). `StatChartDAO`: `fetchAllOrdered` (theo `position`), `upsert`, `delete`, `updatePositions`, `seedDefaultsIfEmpty`. Seed defaults gated một lần bằng `SettingsKeys.didSeedStatCharts` để board user cố ý xoá sạch không tự seed lại.
- **Controller** (`StatsController`): quản `charts: [ChartWidget]` + `results: [id: [ChartDatum]]` (không còn scope toàn cục); load + mọi aggregate chạy **off-main** (`Task.detached`), mỗi chart query với `widget.scope` của chính nó, rồi apply trên MainActor. `totalPhotos` (empty-state) đếm all-time. Edit ops `addChart` / `updateChart` / `deleteChart(s)` / `moveCharts` persist qua `StatChartDAO`.
- **Editor** (`ChartEditorSheet`, mirror `SmartAlbumEditorSheet`): NavigationStack + Cancel / Save. Chọn chart type (Picker), X-Axis dimension (Menu lọc theo `kind.allowedDimensions`; `.kpi` có thêm "Whole library"), Y-Axis metric (aggregation + field khi ≠ count), series / topN, section **Conditions** nhúng **`RuleBuilderSections`** (component dùng chung với Smart Album / Advanced Search) cho `filter`, và section **Date Range** (presets All Time / This Year / This Month + Custom Range… mở `DateRangePickerSheet` ngay trong editor, bound `StatsDAO.earliestCreationDate()`). **Live preview** render `ChartContentView` với data thật của draft (gồm cả scope đã chọn).
- **Card** (`ChartCard` + `ChartContentView`): mỗi card là một `List` row **có nền bo góc riêng** (`secondarySystemGroupedBackground`, corner 16), `List` dùng `.plain` + `listRowSeparator(.hidden)` + row insets tạo khoảng cách → các chart là div rời chứ không dính một cục; vẫn một `ForEach` để kéo-sắp-xếp / vuốt-xoá được. Header: title + **subtitle = scope.title** (mỗi card tự hiện date range của nó) + menu Edit / Duplicate / Delete. Body theo kind (reuse renderer bar / donut / line + KPI). **Chart style** giữ nguyên: horizontal bar (label ở trục Y, cao ~28pt/row, bo góc + gradient), donut innerRadius 0.6, màu qua `ChartPalette`. Tap bar / slice / row categorical hoặc binned → `AppNavigation.openLibrary(with:)` (drill-down); temporal (line) không drill (`FilterCriteria` không có field ngày). Bucket **"Unknown"** ẩn khỏi chart, hiện footnote "N photos without this info".
- **Reorder / Edit**: nút Edit (`EditButton`) bật `EditMode` → `.onMove` / `.onDelete`; nút "+" mở editor tạo mới. Empty state: chưa index → "No Indexed Photos"; board rỗng → "No Charts" (gợi ý bấm +).
- **Date scope — riêng từng chart** (KHÔNG còn nút range toàn màn hình): mỗi `ChartWidget` mang `scope` riêng, chọn trong section **Date Range** của editor (All Time / This Year / This Month + Custom Range… mở `DateRangePickerSheet` — calendar range picker kiểu app book máy bay, tháng dọc từ `StatsDAO.earliestCreationDate()` tới nay). `StatsDateScope` là enum `Codable` với case `custom(ClosedRange<Int>)` epoch seconds trọn ngày, lưu trong JSON config của widget. Card hiện scope.title dưới title. Ảnh không có `creationDate` (NULL) không khớp scope BETWEEN → chỉ xuất hiện ở chart để All Time.
- Lens normalize gom lens trùng tên khác cách ghi (`RF100-500mm F4.5-7.1 L IS USM` / `Canon RF100-500mm…` / `RF 100-500mm F4.5-7.1L…` → một lens) — do `LensNormalizer` ở tầng index, áp cho mọi chart dùng dimension lens.

### 7.5 Settings

Mở bằng nút gear (`gearshape`) top-left của Library/Albums/Statistics; hiển thị dạng bottom sheet trượt từ dưới lên (native `.sheet`, `presentationDetents([.medium, .large])`, grabber hiện, kéo xuống để đóng), giống panel metadata màn detail ảnh, title `.inline`.

- **Photo Library**: permission status, Manage photo access, Re-index library, Re-index Incomplete Photos (đếm row `pendingICloud` + `error`, chạy qua LibraryController nên progress/cancel dùng chung UI index), toggle "Use Cellular Data for Indexing" (mặc định tắt; footer giải thích streaming vài trăm KB/ảnh, Wi-Fi luôn được phép), toggle "Keep Screen Awake While Indexing" (mặc định tắt), index progress, last indexed time, số ảnh đã index
  - **Keep Screen Awake While Indexing**: khi bật, trong lúc index chạy màn hình không tự tắt (`UIApplication.isIdleTimerDisabled`). Sau 1 phút không chạm, tự dim để tiết kiệm pin bằng overlay đen phủ toàn màn hình (OLED thì pixel đen = tắt); chạm lại gỡ overlay và reset bộ đếm. **KHÔNG đụng `UIScreen.brightness`**: auto-brightness của iOS đè giá trị set tay trong vài giây (hạ thêm chẳng tiết kiệm được gì so với overlay đen), còn nhánh restore chạy lúc scene đang resign có thể trượt — để lại độ sáng máy kẹt gần 0 (bug thực tế đã gặp); overlay đen một mình đủ giữ màn tối. Overlay vẫn hiển thị mờ (chữ trắng ~60%, font to) nhãn "Indexing", progress bar + `processed/total · percent%`, tốc độ (`ảnh/phút`) và thời gian còn lại (kiểu "2 hours remaining"), **dòng trạng thái mạng luôn hiện** (`IndexNetworkStatus.detailedLine` — loại kết nối + tốc độ download + tổng dung lượng, **hiện cả khi = 0** như "Wi-Fi · 0 KB/s · 0 KB", khác `displayLine` ẩn số 0), **2 dòng diagnostics** (`IndexDiagnostics.thermalLine`/`iCloudLine` — nhiệt độ máy + fan-out, số stream iCloud in-flight/requested, trạng thái breaker), và **đoạn giải thích streaming** (giống footer Settings: chỉ stream vài trăm KB đầu mỗi ảnh để đọc metadata, không lưu gì xuống máy). Cụm chữ tự trôi lên/xuống cực chậm (±16pt, đổi vị trí mỗi 20 giây, animate gần trọn khoảng ~19s nên ~1–2 pt/s, gần như không nhận ra) để tránh burn-in màn OLED. Chạm khi đang dim chỉ đánh thức màn (gỡ overlay, hiện lại đúng màn hình trước đó) — overlay đen lúc dim là interactive nuốt cú chạm nên KHÔNG lọt xuống grid mở ảnh detail; lúc chưa dim thì dùng probe không chặn (`IdleActivityDetector`) chỉ để reset bộ đếm 1 phút. **Bộ đếm reset suốt cả gesture, không chỉ lúc chạm đầu**: `ActivityRecognizer` giữ trạng thái `.possible` và báo activity ở cả `touchesBegan` lẫn `touchesMoved` (chỉ `.failed` khi gesture kết thúc để re-arm) — kéo/giữ/zoom liên tục dài hơn 1 phút không bao giờ bị dim giữa lúc đang thao tác (bug cũ: recognizer `.failed` ngay ở `touchesBegan` nên mất hết `touchesMoved`, chỉ lần chạm đầu được tính). iOS không có API đọc thời gian Auto-Lock của hệ thống nên 1 phút là hằng số cố định (`ScreenAwakeController.idleDimDelay`), không có setting riêng. Chỉ có hiệu lực khi cả setting bật lẫn đang index; index xong / tắt setting / app vào background thì khôi phục idle timer + gỡ overlay. **Low Power Mode** (`PowerStatusService` quan sát `NSProcessInfoPowerStateDidChange` + `UIDevice.batteryStateDidChange`, wired ở `AppDependencies`, observe bởi `LibraryController.handlePowerChange`): vào LPM → **stop** run đang chạy (`cancelIndexing`) và **không** giữ màn sáng/dim cho các run tự động (để màn ngủ theo hệ thống); LPM cũng chặn mọi auto-index (`startIndexing`/`startReindexIncomplete` guard `manual || !isLowPowerMode`). User vẫn **start index bằng tay** được trong LPM — run thủ công (`isManualIndexRun`) vẫn giữ màn sáng + dim như thường (gate keep-awake = `keepScreenAwake && isIndexing && (!isLowPowerMode || isManualIndexRun)`). **Cắm sạc trong LPM** → auto-resume index (`resumeIndexingForCharger`, là ngoại lệ auto-start duy nhất trong LPM, chạy không giữ màn sáng). Do `ScreenAwakeController` (`@MainActor`, app layer) điều khiển; bắt chạm toàn màn hình qua `IdleActivityDetector` (gesture recognizer gắn lên window, không nuốt touch) reset bộ đếm lúc chưa dim, gắn tại `HomeTabScaffold` cho cả 2 path iOS. Overlay dim hiển thị trong một `UIWindow` riêng (`windowLevel = .alert + 1`) nên phủ lên mọi thứ kể cả `fullScreenCover` màn detail ảnh (nếu chỉ `.overlay` trên scaffold thì sẽ bị cover che, không thấy overlay); window này đọc `indexProgress`/`indexThroughput`/`indexNetworkStatus` từ `LibraryController` (weak ref)
- **Display**: metadata dưới thumbnail — toggle từng field (ISO, aperture, shutter, focal, megapixels, file size); Focal Length Style (Actual / Equivalent); grid density không phải toggle — chỉ dòng chú thích hướng dẫn pinch trên grid
- **Camera Database**: Unknown Cameras (danh sách camera chưa resolve, mở mapping thủ công tại đây), Reset Custom Mappings
- **Privacy**: giải thích local processing, Clear local metadata index

(Section "Statistics" với toggle "Focal Lengths as FF Equivalent" đã bỏ — focal actual vs FF equivalent nay là lựa chọn dimension per-chart trong dashboard, xem §7.4.)
- Lưu bằng `UserDefaults` (`@AppStorage`); key mới `index.keepScreenAwake` (registry `SettingsKeys.keepScreenAwake`)

### 7.6 Onboarding và Permission

- Không xin quyền ngay khi mở app — onboarding ngắn trước permission prompt:
  - Find photos by camera and lens
  - Explore your most-used gear
  - Compare focal lengths across sensor sizes
  - Your photos stay on your device
- `PHPhotoLibrary.requestAuthorization(for: .readWrite)` — cần `.readWrite` vì favorite toggle
- Xử lý đủ trạng thái:
  - **Not Determined**: onboarding rồi mới prompt
  - **Authorized**: full access
  - **Limited**: hiển thị rõ app chỉ phân tích ảnh được cấp + nút Manage Selected Photos (`presentLimitedLibraryPicker`)
  - **Denied**: empty state, giải thích lý do cần quyền, nút mở app settings (`UIApplication.openSettingsURLString`)
  - **Restricted**: empty state tương ứng
- `Info.plist`: `NSPhotoLibraryUsageDescription`

### 7.7 Import (từ thẻ nhớ / USB / folder)

Import ảnh + video từ thẻ máy ảnh (SD qua đầu đọc), USB drive, hoặc folder ngoài — **lọc RAW** (JPEG/HEIC/video vào, RAW/DNG bỏ theo mặc định). Giải bài toán: thẻ máy ảnh chứa cả RAW + JPG, app Photos mặc định không lọc được lúc import.

**Ràng buộc iOS (định hình thiết kế)**

- **Không import trực tiếp thân máy ảnh qua USB (PTP/MTP)** như mục "Devices" của Photos app — cần private entitlement, không cấp cho third-party. Chỉ đọc được **volume mount qua Files** (thẻ SD/USB/folder).
- **Không auto-detect lúc cắm thiết bị**: `FileManager.mountedVolumeURLs` không expose external USB/SD trên iOS, không có mount notification. Truy cập bắt buộc qua `.fileImporter` (user chủ động chọn folder). Vì vậy nút Import **luôn hiện** ở toolbar Library (không tự ẩn/hiện theo thiết bị).

**Luồng** (`ImportScreen` mở `fullScreenCover` từ nút Import ở Library, có `NavigationStack` riêng)

1. **Chọn folder**: `.fileImporter(allowedContentTypes: [.folder])`; user trỏ vào DCIM của thẻ. URL là security-scoped — `ImportController` giữ `startAccessingSecurityScopedResource()` suốt phiên, release lúc dismiss.
2. **Quét nhanh** (`ImportService.scanFolder`, off-main): `FileManager.enumerator` đệ quy, phân loại đuôi qua `ImportCandidate.classify(url:)` → `(kind, fileType?)`: ảnh qua `PhotoFileType.classify` (kind `.image`), video qua `ImportCandidate.videoExtensions` (mov/mp4/m4v/avi/mts… kind `.video`, fileType nil); file lạ bỏ. Đọc file attrs (size, ngày). Mỗi file thành `ImportCandidate` với `PhotoMetadata` placeholder (mediaType theo kind) để lọc file-type/ngày chạy ngay. Newest-first.
3. **Grid** (`ImportGridTile`): thumbnail ảnh decode thẳng bằng ImageIO (`CGImageSourceCreateThumbnailAtIndex`), video lấy poster frame bằng `AVAssetImageGenerator`. **RAW ẩn mặc định** (`hideRaw`; video không phải RAW nên luôn hiện), badge đếm số RAW đã ẩn; video có badge play.
4. **Quét EXIF nền** (`ImportService.fullMetadata`, TaskGroup 8-way): ảnh đọc EXIF qua `ExifService.readExif(fromImageAt:)` + `MetadataComposer` (cùng normalizer/sensor như index) → row đầy đủ; **video compose không EXIF** (`noExif`, mirror `IndexPipeline`). Xong thì mở filter camera/lens/ISO. Progress ở status bar.
5. **Filter**: nút filter mở `RuleBuilderSections` (dùng chung Smart Album / Advanced Search) trên một `SmartAlbumQuery`, đánh giá **in-memory** qua `SmartAlbumQuery.matches(_:)` (`SmartAlbumMatcher.swift` — mirror clause-for-clause `SmartAlbumSQLCompiler`, có unit test giữ đồng bộ). Rule camera/lens/ISO chỉ chính xác sau khi quét EXIF xong.
6. **Import**: item đã chọn (giao của selection ∩ visible) copy vào thư viện qua `PhotoLibraryService.importFile(at:isVideo:)` (`PHAssetCreationRequest.addResource(.photo/.video, fileURL:)`, `shouldMoveFile = false`, giữ `originalFilename`). Progress tuần tự. Xong hiện summary (imported / failed).
7. **Index tự chạy**: asset mới bắn `photoLibraryDidChange` → `libraryChangeToken` → `IndexPipeline` incremental nhặt — **không gọi index thủ công**. Ảnh/video vào Library + Statistics như mọi asset khác (video = row noExif, xem §7.1).

**Auth/Info.plist**: dùng lại `.readWrite` đã xin (đủ cho tạo asset); không cần entitlement/khóa Info.plist mới.

**Wiring**: `ImportService` (`Data/Sources`) inject qua `AppDependencies`; `ImportController` (`Features/Import`, `@Observable`) giữ state phiên import.

## 8. Sensor Format và Crop Factor

Xác định sensor format từ camera model qua local camera database (`sensor_database.json` bundle trong app, load vào database khi khởi tạo):

- Cấu trúc: manufacturer, camera model, sensor format, crop factor
- Ví dụ: Canon EOS R6 Mark II → Full Frame → 1.0x; Sony A6700 → APS-C → 1.5x; Canon EOS R7 → APS-C → 1.6x; OM System OM-1 → Micro Four Thirds → 2.0x; Sony RX100 VII → 1-inch → 2.7x
- Phạm vi (~580 model): mirrorless/DSLR/compact phổ biến (Canon gồm EXIF short form "EOS R5m2"/"EOS R6m2" + tên Rebel/Kiss theo vùng, Sony ILCE/DSC/NEX/SLT codes, Nikon, Fujifilm, Olympus/OM System, Panasonic DMC/DC, Leica, Ricoh/Pentax, Hasselblad, Sigma), action cam/drone (GoPro, DJI), điện thoại và tablet (iPhone/iPad/iPod touch đầy đủ các đời, Samsung Galaxy theo mã SM-, Google Pixel, BlackBerry, Lumia)

Normalize camera model trước khi lookup: bỏ khoảng trắng thừa, case-insensitive, chuẩn hóa manufacturer prefix, hỗ trợ alias.

Khi app khởi động (`AppDependencies.resolveNewlyKnownCameras`): các model đang Unknown được resolve lại với bundled database + custom mappings (`MetadataDAO.resolveUnknownCameras`) — app update mang database mới tự sửa ảnh đã index (sensor format, crop factor, equivalent focal length), không cần reindex.

Không xác định được:

- Sensor format = Unknown, crop factor = null
- Cho phép chọn thủ công trong Settings (Unknown Cameras)
- Lưu custom mapping cho lần sau

## 9. Full-frame Equivalent Focal Length

```
fullFrameEquivalent = actualFocalLength × cropFactor
```

Ví dụ: 25mm trên MFT → 50mm; 50mm trên APS-C 1.5x → 75mm; 50mm trên Canon APS-C 1.6x → 80mm; 150mm trên MFT → 300mm.

Thứ tự ưu tiên:

1. `FocalLenIn35mmFilm` từ EXIF nếu có và hợp lệ
2. Tính từ focal length thực tế × crop factor
3. Không xác định được crop factor → không hiển thị equivalent

Settings cho chọn hiển thị: Actual hoặc Full-frame equivalent.

## 10. Privacy

Local-only:

- Không upload ảnh hoặc EXIF lên server
- Không yêu cầu tài khoản, không cloud backend
- Metadata index lưu local
- Onboarding và Settings ghi rõ: *"Your photos and metadata never leave your device."*

## 11. Empty States và Error States

- Chưa cấp quyền
- Không có ảnh
- Đang index
- Không tìm thấy ảnh phù hợp filter → "No photos match these filters." + nút "Clear Filters"
- Không có EXIF
- Camera chưa xác định được sensor
- Index bị lỗi
- iCloud asset chưa tải về
- Limited Photos Access

Empty state ngắn gọn, có hành động rõ ràng.

## 12. Testing

Dùng **Swift Testing** (`@Test`):

- Unit test domain: CameraNormalizer, LensNormalizer, SearchParser, EquivalentFocalLength, SensorLookup, MetadataComposer, FormatUtils (kèm date header), GridDensity, PhotoGridSectionBuilder, IndexPipeline.needsReindex
- Database test (GRDB in-memory): migration, LibraryQueryDAO (filter/search/sort), StatsDAO (aggregate), SensorDatabaseService
- EXIF parsing: fixture ảnh nhỏ có EXIF trong test bundle
- UI test cơ bản: PhotoGridTile, FilterSheet, chart views

## 13. Trình tự triển khai

### Phase 1 — Foundation
- Tạo Xcode project (SwiftUI app, bundle id, iOS 17, SPM: GRDB)
- Info.plist permission, bundle `sensor_database.json`
- Models (PhotoMetadata, FilterCriteria, SortOption, SensorFormat, Stats)
- GRDB schema + migrations + DAO skeleton
- PhotoLibraryService (permission, fetch, thumbnail, change observer)
- App shell: HomeTabScaffold + glass chrome (LiquidGlassTabBar với material blur)

### Phase 2 — Metadata
- ExifService (ImageIO)
- CameraNormalizer, LensNormalizer, SensorLookup, EquivalentFocalLength, MetadataComposer (+ unit tests ngay trong phase này)
- SensorDatabaseService (JSON loader)
- IndexPipeline actor: batch 200, progress, cancel, resume, pendingICloud + iCloud streaming EXIF, incremental diff (kèm auto-retry row incomplete)

### Phase 3 — Library
- Photo grid (UICollectionView representable, pinch density, thumbnail prefetch)
- Metadata labels dưới thumbnail
- Search (SearchParser + autosuggest)
- Filter sheet + chips + match count
- Sort menu
- Photo Detail (pager, zoom, dismiss, share, favorite, metadata panel)

### Phase 4 — Albums + Statistics
- Albums grid + Album Detail
- StatsDAO aggregate queries
- Statistics screen: summary cards, camera/lens usage, focal histogram (actual + equivalent), sensor donut, ISO/aperture/shutter histogram, drill-down về Library

### Phase 5 — Polish
- Onboarding + đủ permission states (limited picker, denied)
- Settings đầy đủ (Unknown Cameras mapping, re-index, clear index)
- Empty/error states
- Dark Mode audit, Dynamic Type, VoiceOver/accessibility
- Performance với thư viện lớn (50k–100k ảnh)
- Hoàn thiện test suite

Mỗi phase: nêu mục tiêu, liệt kê file tạo/sửa, code hoàn chỉnh, project build được (`xcodebuild`), không thêm dependency không cần thiết. Gặp giới hạn nền tảng (PhotoKit, iCloud) — không âm thầm giả lập dữ liệu, mô tả rõ giới hạn và triển khai phương án thực tế tốt nhất.

## 14. Yêu cầu code

- Không mock UI — logic thật
- Không để logic trong View — tách presentation / domain / data
- Swift Concurrency đúng cách: `@MainActor` cho UI state, actor cho pipeline, không block main thread
- Optional handling đúng — không force unwrap khi không cần
- Error handling + loading states đầy đủ
- PhotoKit/ImageIO/GRDB cô lập trong service/DAO layer, không rò rỉ lên UI
- SwiftLint (tùy chọn) giữ code style nhất quán

## 15. MVP Scope

1. Xin quyền Photo Library (onboarding + đủ permission states)
2. Index ảnh và EXIF (batch, progress, cancel, resume, incremental)
3. Photo grid với metadata dưới thumbnail (ISO, aperture, focal)
4. Filter: camera body, lens, ISO, shutter, aperture, actual focal, FF equivalent focal, sensor format
5. Photo detail (zoom, swipe, share, favorite, metadata panel)
6. Statistics: camera body, lens, actual focal, equivalent focal, sensor format
7. Sensor database + manual mapping
8. Local-only privacy
9. Dark Mode
10. Accessibility cơ bản

Không login, server, subscription, AI trong MVP.

## 16. Khả năng mở rộng tương lai (ngoài MVP)

Kiến trúc không được khóa các hướng: statistics theo year/trip, map, favorite lens combinations, camera+lens combination stats, RAW/JPEG comparison, duplicate detection, photo rating, export statistics, WidgetKit widgets, iPad layout, so sánh hai date range, personalized insights (ví dụ: *"You used the RF100-500mm for 62% of your wildlife photos."*).
