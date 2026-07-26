# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ShotDex — native iOS app (SwiftUI, Swift Concurrency) for photographers: browse photo library, filter by camera/lens/exposure metadata, view gear-usage statistics. Full product spec in `spec.md`. Only third-party dependency: GRDB.swift (SPM). Min deployment target iOS 17; iOS 26 gets native Liquid Glass UI via `#available` branches.

## Commands

```bash
# Build (simulator)
xcodebuild -project ShotDex.xcodeproj -scheme ShotDex \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# All tests
xcodebuild -project ShotDex.xcodeproj -scheme ShotDex \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Single test class / method
xcodebuild ... test -only-testing:ShotDexTests/DatabaseTests
xcodebuild ... test -only-testing:ShotDexTests/DatabaseTests/testSomething
```

Run in simulator: build, then `xcrun simctl install <udid> <path/to/ShotDex.app>` + `xcrun simctl launch <udid> com.hoangtuan.shotdex`. Grant photo permission for testing: `xcrun simctl privacy <udid> grant photos com.hoangtuan.shotdex` (app may still prompt; permission dialog needs a UI tap).

## Architecture

Layered, composition root at `ShotDex/App/AppDependencies.swift` — built once in `ShotDexApp`, injected via SwiftUI environment (`@Observable` + `.environment`). No singletons except `AppDatabase.makeShared()`.

**Data flow:** PhotoKit assets → `IndexPipeline` (actor, batches of 200) reads EXIF via `ExifReader` (ImageIO, no image decode) → `MetadataComposer` normalizes (camera/lens names, sensor lookup) → GRDB SQLite rows → the store/query types serve UI queries.

- `ShotDex/Data/Database/` — `AppDatabase` (GRDB setup/migrations) plus: `MetadataStore` (index writes, cursor persistence), `LibraryQueries` (filtered/sorted grid queries — whole library as slim `LibraryGridItem` rows, full rows by id on demand), `StatisticsQueries` (SQL aggregates for statistics; GROUP BY/histograms done in SQL, not Swift — this is why GRDB over SwiftData), `SmartAlbumStore`, `ChartStore`, `FilterSuggestionCache`.
- `ShotDex/Data/Sources/` — `PhotoLibraryService` (`@Observable`, PhotoKit auth + change observation + image caching), `ExifReader`, `SensorDatabaseLoader` (loads bundled `Resources/sensor_database.json` of camera→sensor-format records).
- `ShotDex/Domain/` — pure logic, all unit-tested: normalizers (`CameraNormalizer`, `LensNormalizer`), `SearchParser` (query DSL: "Canon R6 85mm ISO 3200"), `EquivalentFocalLength`/`SensorLookup` (full-frame equivalence), `IndexPipeline` (supports cancel, resume via persisted cursor, incremental diff by modificationDate).
- `ShotDex/Features/` — one folder per screen; each has a `*Model` (`@Observable`, owns query state) + views. `LibraryModel` is owned by `RootTabView` (not `LibraryScreen`) so the search tab/sheet shares its state.
- `ShotDex/App/` — `RootTabView` (root; native `TabView` with `Tab(role: .search)` on iOS 26, custom `LiquidGlassTabBar` ZStack pre-26), `AppNavigation` (cross-tab state, e.g. Statistics drill-down → Library filter via `pendingLibraryFilter`).

**Naming.** The codebase was migrated from Flutter, so no Flutter/Material vocabulary: no `Scaffold`, `Widget`, `Drawer`, `Chip`, `Surface`, `Route`, and no `*Controller` for an `@Observable` state holder (that means `UIViewController` on iOS — use `*Model`). Data-layer types are `*Store` when they read *and* write and `*Queries` when read-only — not `DAO` or `Repository`. Otherwise follow the Swift API Design Guidelines: Bools read as assertions (`showsISO`, not `showISO`), `has*` not `did*` for latch flags, no `set*` methods shadowing a property, no abbreviations.

**iOS 26 vs earlier:** every screen that padded content for the old floating chrome wraps those spacers in `if #unavailable(iOS 26.0)`. When touching tab/search/toolbar UI, keep both paths working.

**Tests** (`ShotDexTests/`) cover Domain + Database layers only (in-memory GRDB via `AppDatabase.makeEmpty()` / `AppDependencies.preview()`). No UI tests.

## Working rules

- Unclear or ambiguous request: ask back to confirm scope before acting. Never decide alone on unstated requirement.
- Test/build run costs many tokens (xcodebuild, simulator): tell user to run it themself instead of running it directly.
- Code change alters behavior/architecture described in `spec.md`: update `spec.md` too, same turn.
