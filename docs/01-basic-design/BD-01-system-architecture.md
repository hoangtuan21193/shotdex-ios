# BD-01 — Kiến trúc hệ thống và cấu trúc project

`BD-01` · `ShotDex/App/AppDependencies.swift` + cả cây `ShotDex/` · cập nhật 2026-09-22

**Một câu:** phân tầng, cây thư mục, và luật nào quyết định một file mới nằm ở đâu.

## 1. Quy tắc

- **Bốn tầng**: `Core` (model, format) → `Domain` (logic thuần) → `Data` (store/queries + service) →
  `Features` (View + `@Observable` model). Phụ thuộc chỉ đi một chiều xuống.
- **PhotoKit, ImageIO, GRDB không rò lên View** — chúng dừng ở tầng Data.
- **Domain là Swift thuần, không phụ thuộc framework** — đó là điều kiện để unit test được.
- **Composition root duy nhất**: composition root, dựng một lần trong điểm khởi động app, tiêm qua
  environment. Không singleton, trừ một lớp dựng database duy nhất.
- Việc chạy nền là `actor` và publish tiến độ qua state `@Observable`.
- Tên tầng: `*Store` khi vừa đọc vừa ghi, `*Queries` khi chỉ đọc, `*Model` cho state holder
  ([QA-02](../05-testing-and-conventions/QA-02-code-conventions.md)).

## 2. Cây thư mục

```
ShotDex/
├── App/            ShotDexApp · RootTabView · Glass/ · AppDependencies
│                   OnThisDayNotificationScheduler (actor) + …Service (façade @MainActor)
├── Core/           Models/ (PhotoMetadata, LibraryGridItem, FilterCriteria, SortOption,
│                   SensorFormat, Stats) · Utils/MetadataFormatter · Utils/ActiveDisplay
├── Data/
│   ├── Database/   AppDatabase (setup + migration) · MetadataStore · LibraryQueries
│   │               StatisticsQueries · OnThisDayQueries · PerceptualHashStore
│   │               SmartAlbumStore · ChartStore · FilterSuggestionCache
│   └── Sources/    PhotoLibraryService · ExifReader · SensorDatabaseLoader
│                   PerceptualHashReader · SubjectVisionReader · DepthImageReader
│                   PhotoRenderService (actor CI) · PhotoEditingService · VideoTrimService
│                   ImportService · MusicTrackCatalog
│                   VideoFrameCompositor · VideoCompositionBuilder · VideoStudioService
│                   VideoExportWriter (AVAssetReader→Writer)
├── Domain/         Normalize/ (Camera, Lens) · Filtering/SearchParser · Grid/ (2 lookup cache)
│                   Indexing/ (IndexPipeline, SubjectScanPipeline, MetadataComposer)
│                   Duplicates/ (PerceptualHash, DuplicateGrouper, DuplicateScanPipeline)
│                   OnThisDay/ (windows, tally, schedule, copy)
│                   Editing/ · Collage/ · Video/ · Presentation/
│                   SensorLookup · EquivalentFocalLength
├── Features/       Library · Albums · Duplicates · Editing · Collage · VideoStudio
│                   Import · Statistics · Settings · Onboarding · Shared
└── Resources/      sensor_database.json · Models/ (DETR mlpackage) · Music/ · Localizable.xcstrings
```

Target `ShotDexKit` (framework, render core) nằm ngoài cây này —
[EX-01](../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md).

## 3. Ai gọi ai

| Tầng | Được gọi bởi | Không được gọi |
|---|---|---|
| `Domain` | Data, Features | không gọi ai (thuần) |
| `Data` | Features | không gọi Features |
| `Features` | — | không gọi thẳng PhotoKit / GRDB / ImageIO |

Logic không nằm trong View. Một tính năng mới cắt làm ba: phần tính được → `Domain`, phần chạm hệ
thống → `Data`, phần vẽ → `Features`.
