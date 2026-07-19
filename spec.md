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
- 3 tab chính: Library, Albums, Statistics — custom tab chrome overlay trên `ZStack` chứa các `NavigationStack`. **Re-tap tab Library** (tab đang chọn) → grid nhảy về đáy (ảnh mới nhất): `AppNavigation.libraryRetapToken` (Int đơn điệu) bump từ cả hai đường tab bar (iOS 26 qua custom selection `Binding`, pre-26 qua `onReselect` của `LiquidGlassTabBar`); `LibraryScreen` bump counter local truyền làm `jumpToNewestToken` của `PhotoGridCollectionView` — collection view `setContentOffset` về đáy (O(1), content size là phép nhân hàng). Settings KHÔNG phải tab: mở qua nút menu (`line.3.horizontal`) ở góc trên trái của cả 3 tab, trượt drawer từ trái vào (kiểu ChatGPT iOS) — panel ~80% width (max 360pt), scrim tối phía sau, đóng bằng tap scrim hoặc kéo panel sang trái; drawer có `NavigationStack` riêng (push được Unknown Cameras)
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

Thiết kế cần: tối giản, nhiều không gian cho ảnh, ít màu trang trí, ưu tiên typography và hierarchy, cảm giác app hệ thống của Apple. Không dashboard kiểu web, không lạm dụng card, không button lớn nếu control hệ thống phù hợp hơn.

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
mediaType
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
```

Index trên: `normalizedCameraModel`, `normalizedLensModel`, `iso`, `aperture`, `shutterSpeedSeconds`, `focalLength`, `equivalentFocalLength`, `sensorFormat`, `creationDate`.

Bảng phụ: `custom_camera_mappings` (manual sensor mapping), `index_state` (con trỏ resume, last indexed time).

Favorite: đọc/ghi thẳng PhotoKit (`PHAsset.isFavorite`, toggle qua `PHAssetChangeRequest`); cột trong DB chỉ để query/filter nhanh, sync qua change observer.

## 6. Metadata Indexing (PhotoKit + ImageIO)

Pipeline (mỗi run 2 pha):

0. **Fast pass (pha 1)**: duyệt toàn bộ fetchResult, asset chưa có row → ghi ngay row từ dữ kiện PHAsset thuần (ngày, kích thước, GPS, favorite; fileSize để nil, **không gọi XPC per-asset nào**), `exifStatus = pendingRead`, upsert theo batch 1000/transaction (`IndexPipeline.fastPassBatchSize`). Toàn thư viện có row trong vài giây → grid/sort/date dùng được ngay, EXIF fill dần ở pha 2. Không đè row đã tồn tại (kể cả khi full reindex — dữ liệu cũ hiển thị đến khi bị đọc lại đè lên)
1. **EXIF pass (pha 2)**: `PHAsset.fetchAssets` với `PHFetchOptions` (sort theo creationDate **descending — ảnh mới nhất index trước**), duyệt theo batch **200 ảnh**; trong batch đọc EXIF **song song 16 asset** (`TaskGroup`, `IndexPipeline.readConcurrency`) vì thời gian index bị chi phối bởi round-trip PhotoKit từng asset, không phải CPU. Kết quả gom lại đúng thứ tự batch; khi cancel giữa chừng chỉ lưu prefix liên tục để con trỏ resume không bao giờ trỏ quá một asset chưa đọc
2. Mỗi asset: đọc EXIF từ file gốc **không decode ảnh**, một đường streaming thống nhất cho cả local lẫn iCloud (`ExifService.readExif`):
   - `PHAssetResource.assetResources(for:)` gọi **đúng 1 lần/asset** (trong `IndexPipeline`), lấy resource truyền vào `ExifService` + original filename — không lặp XPC
   - **KHÔNG đọc file size lúc index**: `resource.fileSize` (KVC) nạp property set original-metadata của asset; với asset chỉ-ở-iCloud, PhotoKit fetch on-demand **trên main queue**, làm nghẽn cả pipeline. Cột `fileSize` để nil; kích thước fetch lazy khi mở Photo Detail (một asset một lần, chấp nhận được). Kéo theo: **bỏ sort theo file size**
   - Screenshot (`mediaSubtypes.contains(.photoScreenshot)`) không có EXIF camera → bỏ qua hẳn bước đọc file, ghi thẳng `noExif` (`IndexPipeline.shouldSkipExifRead`, pure, có unit test)
   - *Stream* file qua `PHAssetResourceManager.requestData`, cap 8 MB: thử **network off** trước (file local đọc từ disk); đọc local **thất bại vì bất kì lỗi gì** → thử tiếp **bản rendition local** (dưới đây) trước khi mới đụng mạng
   - **Fallback bản rendition local (quan trọng khi "Optimize iPhone Storage" bật)** `ExifService.readExifFromLocalDerivative`: khi original chỉ-ở-iCloud, `PHAssetResourceManager` đọc local thất bại vì file gốc không có trên máy — nhưng Photos vẫn giữ **bản downscaled trên thiết bị**, và bản này **giữ nguyên khối metadata EXIF/TIFF** (chỉ pixel bị thu nhỏ), đủ cho `parse`. Đọc byte bản đó bằng `PHImageManager.requestImageDataAndOrientation` với `isNetworkAccessAllowed = false` + `deliveryMode = .fastFormat` (**không** `.highQualityFormat` — mode đó đòi bản chất lượng cao chỉ-có-ở-iCloud nên trả nil local, ép đọc mạng vô ích; `.fastFormat` trả bất kỳ rendition local nào, khối EXIF vẫn nguyên) → **không kích hoạt tải iCloud** nên tránh luôn lỗi account-auth (`com.apple.accounts` Code=7) mà việc kéo original gây ra khi iCloud không phục vụ được. Parse bằng `CGImageSourceCreateWithData`. Chỉ khi **không có rendition local nào** (ảnh chưa mở / vừa sync) mới trả tín hiệu để rơi xuống đọc original qua mạng. Kết quả: đa số ảnh offloaded resolve local, cắt mạnh traffic iCloud
   - Cần mạng (không còn rendition local) → nếu được phép, stream lại với network on (byte đếm vào traffic monitor)
   - **Timeout là cửa sổ "no-progress" (stall), KHÔNG phải deadline tuyệt đối**: chỉ hủy khi trọn một cửa sổ trôi qua mà không có byte mới (local 10s, network **8s**). Trước đây iCloud original không tải được (0 B) chặn trọn 30s tuyệt đối mỗi asset → thư viện nhiều ảnh offloaded bị serialize 30s/ảnh, index rất chậm; nay bail sau ~8s. Original ở iCloud không tải được → `pendingICloud`, retry bằng nút thủ công / background task
   - **Circuit breaker mạng** (`IndexTrafficMonitor`): khi iCloud không phục vụ được original (account error, sync chưa xong), mọi network read stall 0 byte. Đếm stall 0-byte liên tiếp; đạt `stallTripThreshold` (24) → "trip", các iCloud read còn lại của run trả `pendingICloud` **tức thì** (không tốn cửa sổ stall/asset). Một byte tiến triển thật reset đếm (link chập chờn không trip nhầm). Reset đầu mỗi run; nút thủ công / background task chạy với monitor mới nên vẫn thử lại
   - **Early-stop chỉ áp dụng cho đường network**: khi stream từ iCloud, parse tăng dần bằng `CGImageSourceCreateIncremental` mỗi chunk và hủy request ngay khi có metadata (thường 64–300 KB) để tiết kiệm băng thông. Đường local **không** parse từng chunk — file về từ disk trong mili-giây, nên gom hết buffer rồi parse **một lần** ở completion handler. Lý do: feed buffer HEIC dở dang vào `CGImageSourceCopyPropertiesAtIndex` khiến ImageIO cố init HEVC decoder trên mỗi chunk → lỗi lặp (`err -39`/`-12894`, `makeImagePlus ... initImage failed`) spam log và đốt CPU, làm index chậm — không chỉ riêng `PHPhotosError.networkAccessRequired`, vì Photos trả lỗi original-ở-iCloud với domain không ổn định giữa các version; file local hỏng thật thì lần thử mạng cũng fail → vẫn ra `error`. Buffer chỉ nằm trong RAM, không ghi file gốc xuống máy. Ảnh đã edit đọc resource `.photo` = file **gốc** → EXIF đúng nguồn, không tốn công render bản chỉnh sửa
   - Parse bằng `CGImageSourceCopyPropertiesAtIndex` (`kCGImageSourceShouldCache = false`) → đọc `{Exif}`, `{TIFF}`, `{ExifAux}` dictionary: ISO, FNumber, ExposureTime, FocalLength, FocalLenIn35mmFilm, LensModel, LensMake, Make, Model
   - Fallback hiếm: metadata nằm ngoài cap 8 MB của file local (layout container lạ) → `requestContentEditingInput` (`canHandleAdjustmentData = true` để nhận URL file gốc, không render; timeout 10s) + `CGImageSourceCreateWithURL` đọc tại chỗ
   - Không được dùng mạng hoặc stream thất bại → `exifStatus = pendingICloud`, retry sau
   - Chính sách mạng: Wi-Fi (đường mạng không "expensive" theo `NWPathMonitor`) luôn được phép; cellular chỉ khi bật toggle "Use Cellular Data for Indexing" trong Settings (mặc định tắt). Nút thủ công "Re-index Incomplete Photos" luôn được dùng mạng. Quyết định `allowNetwork` là **closure đánh giá lại mỗi batch**, không chốt một lần đầu run — run tự động lúc mở app thường chạy trước khi `NWPathMonitor` báo path đầu tiên (mặc định coi là expensive), chốt sớm sẽ khoá mạng cả run dù đang Wi-Fi; ngược lại user rời Wi-Fi giữa run thì batch kế tiếp ngừng stream
   - Chỉ đọc EXIF tag chuẩn, không parse maker notes trong MVP
3. Normalize camera và lens (mục 8)
4. Xác định sensor format từ sensor database + custom mappings
5. Tính full-frame equivalent focal length (mục 9)
6. Batch insert vào GRDB, cập nhật con trỏ resume
7. GPS: lấy từ `PHAsset.location`, không cần đọc GPS EXIF tag

Yêu cầu hiệu năng:

- Chạy trong actor / `Task.detached`, không block MainActor
- Progress hiển thị trong UI (số ảnh đã index / tổng + phần trăm, `IndexProgress.percent`), cho phép cancel; chỗ hiển thị progress kèm chú thích "chỉ đọc metadata, không tải full ảnh nên không tốn bộ nhớ, app có thể lag đến khi index xong" — empty state và Settings hiện luôn, panel Library chỉ hiện khi mở rộng (xem dưới)
- **Progress là số cộng dồn (cumulative), không reset mỗi run**: `processed = baseline + newlyDone` với `baseline` = số row đã đọc xong (`indexed`/`noExif`) trước run (`MetadataDAO.completedCount()`), `newlyDone` = số ảnh đọc xong trong run này; `total` = tổng ảnh trong library (`PHAsset` count). Emit `baseline` ngay đầu run nên panel hiện đúng điểm bắt đầu tức thì, không nhảy từ 0 và không tụt lùi khi mở lại app (VD 100 ảnh đã index 3 → mở lại tiếp tục `4/100`, `5/100`, không phải "1/97 còn lại"). `fullReindex` bắt đầu từ 0 (đọc lại tất cả). Ảnh đã xong bị bỏ qua trong incremental không emit thêm (đã nằm trong `baseline`); ảnh đã-xong nhưng bị sửa (đọc lại) trừ khỏi `baseline` để `newlyDone` đếm lại không vượt `total`. `reindexIncomplete` cũng dùng cùng công thức cộng dồn theo tổng library, không hiện "N/số-retryable"
- Progress UI kèm dòng trạng thái mạng: loại kết nối đang dùng (Wi-Fi/Cellular/Wired/Offline theo `NWPathMonitor`), tốc độ download hiện tại và tổng dung lượng đã stream từ iCloud trong run (`IndexNetworkStatus.displayLine`, ví dụ "Wi-Fi · 1.2 MB/s · 45 MB"). Byte được đếm bởi `IndexTrafficMonitor` (mỗi chunk `PHAssetResourceManager` trả về khi stream, reset đầu mỗi run); `LibraryController` sample mỗi 1s, tốc độ = delta byte giữa hai lần sample. Tốc độ và dung lượng **ẩn khi bằng 0** (`displayLine` bỏ phần tương ứng): run local-only chỉ hiện tên kết nối (ví dụ "Wi-Fi"), chỉ số download chỉ xuất hiện khi thực sự có traffic từ iCloud
- Resume sau khi đóng app (lưu con trỏ tiến độ trong database)
- **Index tiếp tục khi rời foreground** (`BackgroundIndexService`, identifier `tech.karabiner.shotdex.index`):
  - Mỗi run foreground giữ một background-task assertion (`UIApplication.beginBackgroundTask`) — user thoát app giữa chừng thì run vẫn chạy thêm ~30s; hết hạn thì cancel sạch (con trỏ đã lưu) và bàn giao cho `BGProcessingTask`
  - `BGProcessingTask` (đăng ký trong `ShotDexApp.init`, khai báo `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: processing` trong `Info.plist`) chạy tiếp khi app bị suspend/kill, vào lúc hệ thống thấy phù hợp (máy rảnh, pin ổn); mỗi lần tiếp tục đều rẻ nhờ incremental diff bỏ qua ảnh đã index. Run nền không dùng mạng (`allowNetwork: false`) — ảnh iCloud-only giữ `pendingICloud` chờ retry foreground. Chưa xong thì tự schedule lần kế
  - Khi app vào background mà còn việc dở (run đang chạy hoặc con trỏ còn trong DB) → submit `BGProcessingTaskRequest`
  - Lưu ý: `BGTaskScheduler` không chạy trên simulator; hệ thống tự quyết thời điểm chạy, không đảm bảo ngay lập tức
- Incremental: `PHPhotoLibraryChangeObserver` cho change notification; khi mở app diff theo `modificationDate` + `exifStatus` (`IndexPipeline.needsReindex`, pure, có unit test) — index ảnh mới/đã thay đổi, đồng thời tự re-enqueue row `error`/`pendingRead` (luôn) và `pendingICloud` (khi được phép dùng mạng) dù ảnh không đổi
- **Auto-index luôn chạy khi mở/quay lại foreground**, độc lập tab đang mở: trigger đặt ở `HomeTabScaffold` (root, luôn sống) qua `.task` lúc tạo controller + `.onChange(scenePhase == .active)`, không chỉ ở `LibraryScreen.task`. Trên iOS 26 `TabView`/`Tab` build nội dung tab lazy nên nếu app mở vào tab khác (Statistics/Albums) thì `LibraryScreen` chưa dựng → index sẽ không chạy nếu chỉ dựa vào `LibraryScreen`. `startIndexing`/`run()` idempotent (guard `isIndexing`/`isRunning`) nên gọi lặp an toàn
- Progress emit khi mỗi asset **bắt đầu đọc** lẫn khi **xong**, throttle 200ms (`BatchProgressState`, tối đa ~5 lần/s) — batch iCloud chậm (timeout 30s/ảnh) mà chỉ emit theo mốc số lượng thì counter đứng im hàng phút, user tưởng treo. `IndexProgress.activeItems` = danh sách `originalFilename` đang đọc **song song** (bắt đầu đọc append, xong remove, tối đa `readConcurrency` = 16) để dialog mở rộng thấy các ảnh đang lấy ngay cả khi số chưa nhích. Pha skip-scan của incremental pass **không** emit (số cộng dồn đã có sẵn `baseline` từ đầu run nên không cần đếm lại ảnh đã index), `activeItems` rỗng. Fast pass **không** emit progress (xong trong vài giây; emit sẽ làm progress bar nhảy 100% rồi reset về 0 khi EXIF pass bắt đầu) — trong lúc đó panel hiện "Indexing…" không số, đúng hành vi khi `indexProgress` còn nil
- Instrumentation: `OSSignposter` interval `fastPass` / `exifRead` / `dbWrite` (subsystem `tech.karabiner.shotdex`, category `index`) cho Instruments; cuối mỗi run `Logger` ghi 1 dòng tổng kết — số lượng theo outcome, thời gian chạy, assets/giây, avg ms/asset từng stage (resources / exif / compose / dbWrite) — để đo trước/sau khi tối ưu
- Panel progress ở Library hiển thị **ngay khi `isIndexing`**, kể cả lúc `indexProgress` còn nil (chưa có callback đầu tiên) — hiện "Indexing…" không số, giống row trong Settings; empty state cũng vậy
- Index indicator ở Library đặt **`overlay(alignment: .topTrailing)`** — góc trên-phải, ngang hàng với pinned date-section header (không còn ở đáy nên không che hàng ảnh mới nhất). **Mặc định = chip capsule glass thu gọn**: spinner + "Indexing" + phần trăm (`IndexProgress.percent`), khi chưa có callback đầu (`indexProgress` nil) chỉ "Indexing". **Tap chip → card mở rộng** (`frame(maxWidth: 300)`, vẫn neo top-right): dòng đếm đầy đủ `processed/total (%)`, progress bar, dòng trạng thái mạng, chú thích metadata, nút **Cancel** (không còn liệt kê danh sách file đang đọc). Chip thu gọn neo top-trailing **ngang hàng với chip date-section header bên trái** (cùng inset top 4pt). Khi mở rộng grid **vẫn scroll/tap bình thường**: grid báo `onUserScroll` (scrollViewWillBeginDragging) + tap ảnh — cả hai thu card về chip; tap card cũng thu về chip. Indicator biến mất (index xong) tự reset về thu gọn (`onDisappear`). Đang multi-select thì tray selection ẩn indicator (overlay `.bottom` riêng)
- Không load full-resolution image chỉ để đọc metadata (local đọc properties tại chỗ; iCloud chỉ stream header)
- Thumbnail grid: `PHCachingImageManager.requestImage` với `targetSize` khớp cell (scale cap 2x — 3x không phân biệt được ở cỡ cell, tốn 2.25x decode/memory), `deliveryMode = .opportunistic`, **`isNetworkAccessAllowed = false`** — scroll grid không bao giờ tải iCloud, chỉ dùng derivative local (Photos luôn cache sẵn cho mọi asset); bản nét full-quality (network on) chỉ tải ở detail view. Prewarm `startCachingImages` cho vùng scroll sắp tới: cân nhắc lại nếu profiling cho thấy cần (delivery `.opportunistic` + cache nội bộ của `PHCachingImageManager` đã đủ mượt). PHAsset cho tile grid resolve qua `ChunkedLookupCache` (Domain/Grid): chunk 400 id quanh index đang hiển thị, tối đa 5 chunk LRU (~2000 PHAsset trần) — grid không bao giờ giữ PHAsset cho toàn thư viện; clear khi nhận memory warning
- Grid scroll mượt với thư viện lớn 50.000–100.000 ảnh (`PHFetchResult` lazy sẵn + UICollectionView cell reuse + prefetch)

## 7. Các màn hình

Ứng dụng gồm 3 tab: Library, Albums, Statistics. Settings mở dạng drawer trượt từ trái (nút menu góc trên trái mọi tab).

### 7.1 Library

**Photo grid**

- View chung `PhotoGridCollectionView` (Features/Shared) dùng cho Library + Album Detail
- **Load toàn thư viện một lần, slim rows (kiểu Google Photos)**: Library KHÔNG phân trang — một query async trả toàn bộ thư viện đã filter/sort dưới dạng `LibraryGridItem` (projection: assetId, creationDate + các field overlay của tile; ~200 KB / 1k ảnh), collection view reuse cell nên memory phẳng dù cuộn tới đâu. `matchCount` = `items.count` (miễn phí, không cần query COUNT riêng). Full `PhotoMetadata` chỉ fetch on-demand theo assetId (detail viewer, Compare)
- **Nguồn của `items` — PhotoKit-first cho view mặc định (hiện ảnh tức thì kiểu app Photos/Metapho)**: khi KHÔNG có filter (`criteria.isEmpty`) và sort theo ngày (`SortOption.isDateSort`), `LibraryController.reload()` dựng list từ `PHFetchResult<PHAsset>` (mọi ảnh, theo creationDate), join mỗi asset với row DB đã index nếu có (để có overlay exposure) và dùng `LibraryGridItem(asset:)` (chỉ facts PhotoKit, exposure = nil → tile chỉ hiện thumbnail) cho ảnh chưa index. Nhờ vậy toàn bộ ảnh xuất hiện NGAY, không phải chờ `IndexPipeline`; index chạy nền chỉ để bơm overlay/filter/sort metric/statistics, và mỗi lần `reload()` (index xong, hoặc library thay đổi qua `libraryChangeToken`) overlay được điền dần. Có filter bất kỳ hoặc sort metric → fallback về `LibraryQueryDAO.gridItems` (chỉ ảnh đã index) như trước. Enumerate `PHFetchResult` chạy off-main (materialize mọi asset). Đây là pattern có sẵn của `AlbumDetailController` (`PhotoMetadata.placeholder(for:)`), nay port sang Library. Detail viewer: `metadata(for:)` fallback `placeholder(for:)` cho ảnh chưa index nên chrome favorite/share/info + Compare vẫn hoạt động
- **Video trong grid + detail (KHÔNG vào index/stats)**: các surface duyệt ảnh (Library grid, Albums, On This Day, detail viewer) fetch cả photo lẫn video qua `PhotoLibraryService.browsableMediaPredicate` (`mediaType = image OR video`). Tile video hiện poster frame (`requestImage`) + badge play/duration góc trên phải. Nhưng `IndexPipeline` và `StatsDAO` giữ **chỉ ảnh** (predicate `mediaType = image` không đổi) → video không bao giờ có row `photo_metadata`, nên tự động loại khỏi Statistics và filter gear (camera/lens/exposure). Metadata video xem qua nút Info (đọc live, xem §7.2). Vì video không có DB row, khi bật filter bất kỳ (đường DB) video biến mất — đúng ý đồ app đo gear
- **Grid engine = UICollectionView (`PhotoGridCollectionView`, UIViewRepresentable)** — Library + Album Detail. SwiftUI LazyVGrid không kham nổi feature set này ở scale toàn thư viện (100k+): bottom-anchor ép ước lượng tổng content height (mở app đen lâu, tile không render tới khi chạm — bug materialize của lazy container neo đáy), mọi đổi layout invalidate cả container (pinch lag), offset thô sau đổi cột trỏ sai vùng/vượt content (scroll bay xa, màn đen). UICollectionView + **flow layout** (`GridFlowLayout` — KHÔNG compositional: `UICollectionViewTransitionLayout` của pinch không hỗ trợ compositional, `startInteractiveTransition` trả layout đích không bọc → crash `setTransitionProgress`; grid vuông đều cột không cần compositional, pinned header flow có sẵn `sectionHeadersPinToVisibleBounds`): content size = phép nhân hàng (O(1)), neo đáy tức thì bằng `setContentOffset` sau `reloadData`. Contract với screens giữ nguyên DensityPhotoGrid cũ: mảng photos phẳng, callback flat-index (tap → pager index), `SwipeSelectEvent`. Cell `PhotoGridCell` thuần UIKit (UIImageView + gradient + metadata label + video badge + selection badge/border); header section = UICollectionViewCell đăng ký làm supplementary + `UIHostingConfiguration { GridSectionHeader }` (tái dùng capsule glass SwiftUI). **Prefetch thumbnail**: `UICollectionViewDataSourcePrefetching` → `PhotoLibraryService.startCachingThumbnails/stopCaching...` (bọc `PHCachingImageManager` — mảnh Metapho từng thiếu: ảnh sẵn sàng trước khi scroll tới). Display toggles (ISO/aperture/…) cell đọc thẳng UserDefaults (cùng key @AppStorage của Settings).
- **Bottom-anchored kiểu app Photos** (chỉ Library, Album Detail vẫn top-anchored): kết quả "đầu" của sort nằm DƯỚI CÙNG (sort newest → ảnh mới nhất ở đáy), mở tab đứng sẵn ở đáy, cuộn lên xem ảnh cũ. SQL/ORDER BY giữ nguyên — controller đảo mảng một lần sau khi load (đảo ở Swift, không ở SQL, để giữ NULLS LAST = section "No Date" ở trên cùng). Đổi filter/sort/index run xong → `contentGeneration` bump = `contentVersion` của collection view → `reloadData` + re-anchor đáy; tab retap (`jumpToNewestToken`) → scroll về đáy. Album paging chỉ tăng count → reload GIỮ offset (không re-anchor). Không còn `PhotoPrependEvent`/re-anchor/trigger 30 item — không có gì prepend nữa
- **Pinch đổi mật độ — interactive layout transition (mechanic Photos thật)**: dải cột liền **`GridDensity.columnRange` (1…8)**, API UIKit chuẩn `UICollectionViewTransitionLayout`. Pinch xác định hướng (spread = bớt cột/cell to, pinch vào = thêm cột), `startInteractiveTransition(to:)` sang layout ±1 cột; magnification (log-space, span 0.35) map vào `transitionProgress` — **cell to/nhỏ theo ngón tay, UIKit nội suy frame + contentOffset giữa hai layout** (không còn màn đen/bay xa — offset được nội suy, không stale). Progress chạm 1 → `finishInteractiveTransition` + re-arm baseline (một gesture dài bước được nhiều cột, mỗi segment đúng 1); thả tay giữa chừng: >0.4 finish, ngược lại cancel (spring về cũ); đảo chiều ngón → progress về 0 → cancel + cho segment ngược. **Segment phải serialize qua cờ `isSettling`**: từ finish/cancel tới completion callback của UIKit không được `startInteractiveTransition` mới — gọi giữa lúc settle làm hỏng state machine (UIKit trả layout đích trần → crash `setTransitionProgress`, đơ grid); movement trong cửa sổ settle chỉ re-baseline rồi bỏ qua. Sau mỗi commit: granularity đổi (day↔month tại 3↔4) → rebuild sections + `reloadData`; reconfigure visible cells xin thumbnail nét hơn; prefetch cache size cũ bị drop (`stopCachingAllThumbnails`). Math thuần ở `Domain/Grid/GridDensity` (`clamped`/`stepped`, có unit test). Mức cột persist `@AppStorage("grid.columns")` chung Library + Album Detail (sanitize `GridDensity.clamped`, legacy 9 → 8). Pinch disabled khi đang multi-select. Mức to nhất (1 cột) cell vẫn vuông — native aspect là follow-up.
- **Date section header** (chỉ khi sort theo ngày chụp; sort metric → grid phẳng): nhóm theo **ngày** ("Today"/"Yesterday"/"July 19, 2026") ở ≤3 cột, theo **tháng** ("July 2026") ở >3 cột; header pinned khi scroll (`sectionHeadersPinToVisibleBounds`, dạng **capsule chip glass** nhỏ lề trái — ultraThinMaterial + hairline stroke, không phủ full-width); ảnh không có ngày chụp → section "No Date" (khớp NULLS LAST: nằm cuối ở grid top-anchored như Album Detail, nằm trên cùng ở Library bottom-anchored vì mảng được đảo sau khi load). Grouping thuần một pass ở `Domain/Grid/PhotoGridSectionBuilder` (range flat-index như OnThisDay, có unit test) — swipe-select/tap/paging vẫn tính trên mảng phẳng.
- Mỗi thumbnail hiển thị 1 dòng metadata nhỏ overlay phần dưới ảnh, nền gradient nhẹ:
  - Mặc định: `ISO 400 · 85mm · f/1.8`
  - Tùy chọn thêm shutter speed: `ISO 400 · 85mm · f/1.8 · 1/500s`
  - **Ẩn khi cell hẹp hơn ~90pt** (mức cột dày)
- Thumbnail size theo cell width tính từ bounds collection view + số cột (2x scale cap — 3x không phân biệt được ở cỡ cell, đỡ 2.25x decode); khi cell to lên (pinch về ít cột) cell re-request bản resolution cao hơn (ngưỡng 1.4×), giữ ảnh cũ tới khi bản nét về. (On This Day vẫn dùng SwiftUI `PhotoGridTile` + `.measureWidth(into:)` — grid nhỏ 3 cột cố định)
- Metadata nhỏ nhưng dễ đọc, không làm rối ảnh, tự thích nghi Light/Dark Mode
- Chỉ hiển thị giá trị có thật — KHÔNG hiển thị placeholder kiểu `ISO -- · --mm · f/--`

**Navigation bar**

- Large title "Library"
- Filter button (đổi icon filled khi có filter active)
- Sort button (`Menu`)
- Search KHÔNG nằm trong nav bar — nút search tròn trong thanh chrome nổi phía dưới
- Nút Select (checkmark) bật chế độ chọn nhiều ảnh (xem **Multi-select** bên dưới)

**Search**

- Tìm theo: filename, camera model, lens model, focal length, ISO, aperture, shutter speed, sensor format
- Ví dụ: `IMG_1234`, `Canon R6`, `RF 100-500`, `85mm`, `ISO 3200`
- Query DSL (`SearchParser`): tự nhận diện ISO, aperture (f/1.8), shutter (1/500), focal length (85mm), sensor format; còn lại match tự do vào camera/lens/filename; số trần (không đơn vị) được OR vào ISO/focal/tên thiết bị/filename
- `originalFilename` chỉ được ghi ở EXIF pass (fast pass không fetch resource); ảnh mới chỉ có placeholder row chưa match được theo filename cho tới khi EXIF pass chạy xong
- Autosuggest dựa trên danh sách camera/lens có trong database
- Chạy trên local database đã index, không quét lại file

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

- Date taken newest/oldest, ISO, focal length, FF equivalent focal length, aperture, shutter speed (KHÔNG có sort theo file size — kích thước không được index, xem §6)
- Mọi ORDER BY kết thúc bằng tiebreaker `assetId` và dùng `NULLS LAST` cho creationDate — thứ tự total nên display order deterministic qua các lần reload (giá trị trùng hoặc NULL không làm xáo vị trí)

**Multi-select (chọn nhiều ảnh)**

- Vào chế độ chọn: nút checkmark trên nav bar, hoặc long-press một ảnh trong grid (ảnh đó được chọn luôn)
- Không giới hạn số lượng; tile được chọn hiển thị badge checkmark + viền accent (thứ tự chọn vẫn được giữ trong state — quyết định thứ tự pane khi Compare)
- **Swipe-to-select** (kiểu app Photos): trong chế độ chọn, vuốt ngón tay qua grid để chọn/bỏ chọn hàng loạt — 8pt đầu của drag quyết định hướng (ngang = chọn, dọc = nhường scroll); range tính theo **index** trong mảng ảnh phẳng giữa ô bắt đầu và ô dưới ngón tay, áp lên snapshot selection lúc bắt đầu drag nên kéo lùi tự hoàn tác; bắt đầu trên ô đã chọn → drag bỏ chọn range; scroll bị disable trong lúc drag active; chưa có edge auto-scroll (follow-up); pinch đổi mật độ cột bị tắt trong chế độ chọn để không xung đột gesture. Logic thuần (direction lock, range) nằm ở `Domain/Selection/SwipeSelectionEngine`, có unit test. Library + Album Detail: UIPanGestureRecognizer trong `PhotoGridCollectionView` (hit-test ô bằng `indexPathForItem(at:)`, chạy simultaneous với pan của scroll); On This Day: bản SwiftUI `SwipeToSelectModifier` (PreferenceKey thu frame ô + DragGesture trên named coordinate space)
- Tray nổi dưới màn hình (`SelectionActionsTray`, glass panel, luôn hiển thị khi đang chọn — ưu tiên trên panel tiến độ index): "N selected" + nút **Compare** (chỉ enable khi chọn 2–4 ảnh, kèm hint khi ngoài khoảng) + nút **Delete** (destructive, đi qua `deleteAssets` như On This Day: hệ thống hiện dialog xác nhận, prune DB + state local, user hủy → giữ selection)

**Compare (So sánh ảnh)**

- Mở từ chế độ chọn khi có 2–4 ảnh; thứ tự pane = thứ tự chọn
- Màn hình compare (fullscreen): 2–3 ảnh xếp dọc, 4 ảnh lưới 2x2; mỗi pane pinch-zoom/pan; sync zoom và sync pan bật/tắt độc lập kiểu Lightroom (offset chuẩn hóa theo content size nên ảnh khác tỷ lệ vẫn khớp vị trí tương đối)
- Caption metadata mỗi pane (camera · focal · aperture · ISO); khi 4 ảnh bỏ camera model cho gọn

### 7.2 Photo Detail

- Fullscreen, swipe ngang chuyển ảnh trước/sau — **`UIPageViewController`** (`PhotoPager: UIViewControllerRepresentable`, transition `.scroll`) chứ KHÔNG dùng `TabView(.page)`: TabView dựng mọi page eager nên trước đây phải windowed ±2, mỗi lần đổi index lại remount page giữa lúc vuốt → giật/kẹt (cùng lý do grid bỏ SwiftUI qua UICollectionView). PageViewController dựng page **lazy** qua data source (`viewControllerBefore/After` → `PhotoPageHost` nhớ `index`), library cỡ nào cũng rẻ, paging native. `PhotoBrowsingSource` vẫn là protocol index-based (`photoCount`/`photoId(at:)`/`metadata(for:)`/`asset(for:)`) nên pager không ôm cả mảng metadata; Library fetch full `PhotoMetadata` on-demand từ DB theo assetId, Albums/On This Day trả từ mảng in-memory. `didFinishAnimating` ghi index về binding + `loadNextPageIfNeeded`
- Pinch-to-zoom + double-tap zoom (`UIScrollView` representable) cho ảnh; `ZoomableImageView.onZoomChange` báo zoom scale lên pager để **tắt swipe-down-dismiss khi đang zoom** (vuốt lúc đó pan ảnh)
- **Video**: `PhotoDetailPage` branch theo `asset.mediaType` — video dùng `VideoPlayer` (AVKit) với `AVPlayer` dựng từ `PHImageManager.requestPlayerItem(forVideo:)` (`isNetworkAccessAllowed = true`, phát được cả video iCloud), pause khi rời trang; ảnh vẫn đi đường `ZoomableImageView`
- **Ảnh full-size qua `requestDetailImage`** (`.opportunistic`, `isNetworkAccessAllowed = true`): hiện preview degraded trước rồi stream bản full từ iCloud. Trong lúc bản full còn tải hiện **badge iCloud** (`icloud.and.arrow.down` + % từ `progressHandler`); ảnh full tới (`PHImageResultIsDegradedKey == false`) thì badge tắt
- Swipe-down-to-dismiss (ngưỡng velocity/khoảng cách, animation thu nhỏ) — `UIPanGestureRecognizer` trên view của pager, delegate chỉ cho begin khi **vuốt xuống dọc** (`velocity.y > 0 && |vy| > |vx|`) và **chưa zoom** nên vuốt ngang vẫn thuộc paging, `shouldRecognizeSimultaneouslyWith = false`
- **Chrome tách trên/dưới**: chỉ nút X (Close) ở góc trên trái; các nút hành động (Favorite / Share / Info) nằm ở **bottom bar** dưới info panel
- Share qua `UIActivityViewController`: ảnh share image data, video share URL từ `AVURLAsset` (`requestAVAsset(forVideo:)`); file chưa tải về máy (iCloud) → alert "Unable to Share"
- Favorite qua `PHAssetChangeRequest` (PhotoKit thật)
- Info panel luôn hiện ở dưới: filename + badge định dạng (RAW/JPG/HEIC) + gear + exposure + file size
- **Nút Info → dump metadata thô đầy đủ** (`MetadataPanel`, sheet inset grouped list): KHÔNG phải index đã curate mà là toàn bộ property đọc **live** khi mở sheet qua `AssetMetadataDump.load(for:)` (async, có thể chạm iCloud) — nhóm theo block nguồn:
  - **Asset**: local id, media type/subtypes, pixel size, ngày tạo/sửa, favorite/hidden, duration (video), toạ độ + altitude
  - **Resource N**: originalFilename, type, UTI, file size
  - Ảnh: **mọi** property ImageIO (top-level + từng dict con `{Exif}`/`{TIFF}`/`{GPS}`/`{ExifAux}`… mỗi cái một section) đọc từ rendition local qua `requestImageDataAndOrientation`
  - Video: section **Video** (duration) + **Video/Audio Track** (dimensions, frame rate, data rate, codec FourCC) + **Metadata** (`commonMetadata`) từ `AVAsset`
  - Row rỗng bị bỏ; value `textSelection(.enabled)`
- Không hiển thị giá trị không tồn tại

### 7.3 Albums

- Hero card "On This Day" full-width đứng đầu tab (xem mục dưới), tiếp theo grid 2 cột: "Recents" (toàn bộ ảnh), smart album hệ thống (`PHAssetCollection.fetchAssetCollections(.smartAlbum)`: Recently Added, Favorites, Screenshots) và user album — mỗi ô cover thumbnail + số lượng ảnh
- Album Detail: grid phân trang (page size 120) dùng `PhotoGridCollectionView` chung với Library (top-anchored) — pinch interactive transition trong dải 1…8 (persist chung key `grid.columns`) + date section header luôn bật (fetch hard-sort theo creationDate); trang kế load khi cell gần cuối hiển thị (`willDisplay`, ngưỡng 30); chạm ảnh mở Photo Detail; multi-select đầy đủ như Library (checkmark toolbar / long-press / swipe-to-select, tray Compare 2–4 + Delete). Paging cursor (`nextFetchIndex`) tách khỏi `photos.count` vì `PHFetchResult` snapshot bất biến — sau khi xoá ảnh, trang kế tiếp skip các id đã xoá thay vì append trùng
- Banner Limited Access + nút Manage khi quyền bị giới hạn

**On This Day (smart album "Ngày này năm xưa"):**

- Tổng hợp ảnh chụp đúng ngày/tháng đang chọn ở các năm TRƯỚC năm hiện tại (mặc định: hôm nay). Fetch qua PhotoKit `NSCompoundPredicate` — mỗi năm một cửa sổ `[00:00, +1 ngày)` trên `creationDate`, build bởi hàm pure `OnThisDayWindows.windows` (Domain, có unit test; bỏ qua 29/2 ở năm không nhuận, cap 100 năm). Tải toàn bộ một lần, không phân trang.
- Màn chi tiết (`OnThisDayScreen` + `OnThisDayController`): grid 3 cột nhóm theo năm (section header "2023 · N years ago", năm mới nhất trước), chạm ảnh mở Photo Detail.
- Đổi ngày: nút lịch trên toolbar mở sheet `DatePicker(.graphical)` (detent medium) + nút "Today"; chỉ tháng/ngày được dùng để so khớp.
- Xoá ảnh: long-press (hoặc nút toolbar) vào chế độ chọn nhiều (không giới hạn số lượng, badge checkmark, hỗ trợ swipe-to-select xuyên section — range tính trên mảng ảnh phẳng), tray dưới (`SelectionActionsTray`, không có nút Compare) hiện "N selected" + nút Delete → `PhotoLibraryService.deleteAssets` (`PHAssetChangeRequest.deleteAssets`, hệ thống tự hiện dialog xác nhận, ảnh vào Recently Deleted). Sau khi xoá thành công, xoá luôn row tương ứng trong DB (`MetadataDAO.deleteAssets`) để Library grid không stale; user hủy dialog → giữ nguyên selection.

### 7.4 Statistics

- Bộ chọn phạm vi: **nút lịch trên toolbar top-left** (ToolbarItem riêng cạnh nút Settings để iOS 26 render thành glass circle riêng; scope khác All Time thì hiện thêm title cạnh icon, ví dụ "This Year"). Tap mở Menu: All Time / This Year / This Month (checkmark ở scope đang chọn) + **Custom Range…** mở `DateRangePickerSheet` — calendar range picker kiểu app book máy bay (danh sách tháng dọc từ tháng có ảnh cũ nhất `StatsDAO.earliestCreationDate()` tới hiện tại, mở sẵn ở đáy; tap 1 chọn start, tap 2 chọn end, dải giữa highlight; ngày tương lai disable; Apply với 1 ngày = range 1 ngày). Đã áp dụng thì item Custom hiện label khoảng ngày ("Mar 12 – Jun 4, 2026"), tap lại để sửa. Không còn hàng chips ghim đầu page → List cuộn dưới nav bar, top bar transparent-at-top như Library. Model: `StatsDateScope` enum thường (không raw-String) với case `custom(ClosedRange<Int>)` epoch seconds trọn ngày; mọi query vẫn đi qua `scopeClause`
- Aggregate chạy trên SQLite qua `StatsDAO` (GROUP BY, bucket), không tính lại trong Swift
- **Summary cards** đầu màn hình: Total Photos, Most Used Camera, Most Used Lens, Most Used Focal Length, Most Used Equivalent Focal Length, Most Used Sensor Format — nhỏ, đơn giản, kiểu native (inset grouped / ô nền secondarySystemGroupedBackground), không dashboard web
- **Camera Body Usage**: số ảnh + % theo body, body dùng nhiều nhất, xu hướng theo thời gian (Swift Charts); chạm body → mở Library đã filter theo body đó
- **Lens Usage**: số ảnh + % theo lens, top lens; normalize gom lens trùng tên khác cách ghi (ví dụ `RF100-500mm F4.5-7.1 L IS USM` / `Canon RF100-500mm F4.5-7.1 L IS USM` / `RF 100-500mm F4.5-7.1L IS USM` → một lens); group prime/zoom nếu xác định được
- **Bucket "Unknown"**: `StatsDAO` vẫn tổng hợp row thiếu metadata (NULL/rỗng) thành bucket "Unknown" (tổng bucket = Total Photos, % trên toàn scope; sensor format gộp NULL với rawValue `Unknown`), nhưng UI **không hiện row/slice Unknown** — `StatsController` tách ra (`splitUnknown`) thành `cameraUnknownCount`/`lensUnknownCount`/`sensorUnknownCount`, hiển thị dạng footnote cuối section ("N photos without camera info"). Most Used Camera/Lens không bao giờ là Unknown
- **Ảnh không có ngày chụp**: `creationDate` NULL không khớp scope BETWEEN nên chỉ xuất hiện ở All Time; footer của section Summary hiện "N photos without a capture date appear only in All Time" khi scope khác All Time
- **Focal Length Usage**: histogram actual + FF equivalent, top focal lengths, phân nhóm góc nhìn, bucket cho zoom lens (12–19, 20–27, 28–34, 35–49, 50–69, 70–99, 100–199, 200–299, 300–499, 500+)
- **Chart style**: mọi bar chart (focal/ISO/aperture/shutter) là **horizontal bar** — label bucket nằm trục Y bên trái (không chồng chữ như trục X), chiều cao chart scale theo số bucket (~28pt/row), bar bo góc + gradient. Màu series dùng palette riêng `ChartPalette` (App/Theme, system colors: indigo/teal/orange/…) qua `chartForegroundStyleScale` cho line trend + donut thay vì default của Swift Charts
- **Sensor Format Usage**: donut chart (SectorMark), số ảnh theo format; chạm → filter Library
- **ISO Usage**: ISO phổ biến nhất, histogram, số ảnh theo range, average + median ISO
- **Aperture Usage**: phổ biến nhất, histogram, số ảnh theo nhóm khẩu
- **Shutter Speed Usage**: phổ biến nhất, histogram, số ảnh theo nhóm tốc độ, tỷ lệ ảnh chậm hơn 1/focal-equivalent nếu tính được

### 7.5 Settings

Mở bằng nút menu (`line.3.horizontal`) top-left của Library/Albums/Statistics; hiển thị trong drawer trượt từ trái (~80% width, max 360pt, scrim, kéo trái hoặc tap scrim để đóng), title `.inline`.

- **Photo Library**: permission status, Manage photo access, Re-index library, Re-index Incomplete Photos (đếm row `pendingICloud` + `error`, chạy qua LibraryController nên progress/cancel dùng chung UI index), toggle "Use Cellular Data for Indexing" (mặc định tắt; footer giải thích streaming vài trăm KB/ảnh, Wi-Fi luôn được phép), index progress, last indexed time, số ảnh đã index
- **Display**: metadata dưới thumbnail — toggle từng field (ISO, aperture, shutter, focal); Focal Length Style (Actual / Equivalent); grid density không phải toggle — chỉ dòng chú thích hướng dẫn pinch trên grid
- **Camera Database**: Unknown Cameras (danh sách camera chưa resolve, mở mapping thủ công tại đây), Reset Custom Mappings
- **Statistics**: một toggle "Focal Lengths as FF Equivalent"
- **Privacy**: giải thích local processing, Clear local metadata index
- Lưu bằng `UserDefaults` (`@AppStorage`)

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
