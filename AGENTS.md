# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

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

**Data flow:** PhotoKit assets → `IndexPipeline` (actor, batches of 200) reads EXIF via `ExifService` (ImageIO, no image decode) → `MetadataComposer` normalizes (camera/lens names, sensor lookup) → GRDB SQLite rows → DAOs serve UI queries.

- `ShotDex/Data/Database/` — `AppDatabase` (GRDB setup/migrations) plus three DAOs: `MetadataDAO` (index writes, cursor persistence), `LibraryQueryDAO` (filtered/sorted grid queries — whole library as slim `LibraryGridItem` rows, full rows by id on demand), `StatsDAO` (SQL aggregates for statistics; GROUP BY/histograms done in SQL, not Swift — this is why GRDB over SwiftData).
- `ShotDex/Data/Sources/` — `PhotoLibraryService` (`@Observable`, PhotoKit auth + change observation + image caching), `ExifService`, `SensorDatabaseService` (loads bundled `Resources/sensor_database.json` of camera→sensor-format records).
- `ShotDex/Domain/` — pure logic, all unit-tested: normalizers (`CameraNormalizer`, `LensNormalizer`), `SearchParser` (query DSL: "Canon R6 85mm ISO 3200"), `EquivalentFocalLength`/`SensorLookup` (full-frame equivalence), `IndexPipeline` (supports cancel, resume via persisted cursor, incremental diff by modificationDate).
- `ShotDex/Features/` — one folder per screen; each has a `*Controller` (`@Observable`, owns query state) + views. `LibraryController` is owned by `HomeTabScaffold` (not `LibraryScreen`) so the search tab/sheet shares its state.
- `ShotDex/App/` — `HomeTabScaffold` (root; native `TabView` with `Tab(role: .search)` on iOS 26, custom `LiquidGlassTabBar` ZStack scaffold pre-26), `AppNavigation` (cross-tab state, e.g. Statistics drill-down → Library filter via `pendingLibraryFilter`).

**iOS 26 vs earlier:** every screen that padded content for the old floating chrome wraps those spacers in `if #unavailable(iOS 26.0)`. When touching tab/search/toolbar UI, keep both paths working.

**Tests** (`ShotDexTests/`) cover Domain + Database layers only (in-memory GRDB via `AppDatabase.makeEmpty()` / `AppDependencies.preview()`). No UI tests.

## Working rules

- **UI work: read `DESIGN.md` first.** It is the single source of truth for ShotDex's design language (tokens, colors, corner radii, components). Before adding or editing any screen, read it and reuse what's there — do not invent new tokens, colors, radii, or components that already exist. When a rule in `DESIGN.md` conflicts with current code, the current code is tech debt (follow `DESIGN.md`).
- Unclear or ambiguous request: ask back to confirm scope before acting. Never decide alone on unstated requirement.
- Test/build run costs many tokens (xcodebuild, simulator): tell user to run it themself instead of running it directly.
- Code change alters behavior/architecture described in `spec.md`: update `spec.md` too, same turn.
