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

```bash
# Drive the UI on a simulator and collect screenshots + a measured element dump
Tools/ui-drive <udid> ShotDexUITests/scripts/<script>.json [out-dir]
```

`Tools/ui-drive` runs the `ShotDexUIDriver` scheme, whose only target is
`ShotDexUITests/UIDriverTests` — a driver that replays a JSON list of steps
(`tap` by accessibility label or normalized point, `swipe`, `typeText`,
`longPress`, `scrollTo`, `wait`, `screenshot`, `dump`). It is **not** in the
`ShotDex` scheme, so `xcodebuild … -scheme ShotDex test` still runs the unit
tests and nothing else. Each `dump` writes every on-screen element with its
label, identifier and frame in points, which is how a layout finding gets a
number instead of an adjective. A run takes three to six minutes, so script
the whole route to a screen in one go. Artifacts come back through the result
bundle because the test itself runs inside the simulator.

## Architecture

Layered, composition root at `ShotDex/App/AppDependencies.swift` — built once in `ShotDexApp`, injected via SwiftUI environment (`@Observable` + `.environment`). No singletons except `AppDatabase.makeShared()`.

**Targets.** `ShotDexKit` (framework) holds the render core — the edit recipe models, `PhotoRenderService` and its extensions, and the pure editing math (film looks, tone curve, colour, text/shape overlay layout, brush rasterizer). The app, the tests and the **ShotDexEdit** photo-editing extension all link it; nothing in it imports SwiftUI or GRDB. Everything else stays in the app target. Adding a type to the kit means marking it and its members `public` — that is the cost of the boundary, and the reason the kit is the renderer and not the whole editor.

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

- **UI work: read `DESIGN.md` first.** It is the single source of truth for ShotDex's design language (tokens, colors, corner radii, components). Before adding or editing any screen, read it and reuse what's there — do not invent new tokens, colors, radii, or components that already exist. When a rule in `DESIGN.md` conflicts with current code, the current code is tech debt (follow `DESIGN.md`).
- Unclear or ambiguous request: ask back to confirm scope before acting. Never decide alone on unstated requirement.
- **Always build after code changes** (`xcodebuild ... build`, quiet output: pipe through `grep -E "error:|warning: unused|BUILD"` or `xcbeautify -q` if available) and fix every error before reporting done. Never hand an unbuilt change to the user.
- **UI change: build, run in the simulator, screenshot, and inspect before reporting done.** Any change that touches a view, layout, tab/toolbar chrome, sheet, or overlay must be verified visually, not just compiled: install and launch the build on a booted simulator (iOS Simulator tools or `xcrun simctl`), navigate to every screen and state the change affects (both iOS 26 and pre-26 paths when the code branches on `#available`), and take a screenshot of each. Look at every screenshot for anything wrong — overlapping or clipped buttons, controls hidden behind tab/nav bars, misaligned or truncated text, wrong colors or spacing versus `DESIGN.md`, blank or half-rendered content, layout that differs from what the code intended. If a screenshot shows a problem, fix it in the same turn and re-screenshot until it is clean; never report a UI change done with a known visual defect, and never describe a screenshot you did not take. Mention in the final message which screens were checked.
- Code change alters behavior/architecture described in `spec.md`: update `spec.md` too, same turn.
- **`/review-sweep` runs the agents for you** (`.claude/skills/review-sweep/`): scopes an area, fans the right agents out in parallel, merges their findings into `REVIEW_QUEUE.md` (deduped, ranked, with anything `spec.md` already answers closed off), then works down the queue — build, test and screenshot behind each fix, one commit per item. Say "review the whole app", "review the editor", or "continue" to resume a half-finished queue.
- **Workflow skills** (`.claude/skills/`) — use these instead of retyping the commands:
  - `/build [scheme] [device]` — quiet simulator build into `build/sim`; the step every code change ends with.
  - `/test [Class[/method]]` — unit tests with only failures and the verdict printed; a filter that matches zero tests is not a pass.
  - `/sim [device]` — install, grant photos, launch, first screenshot; plus the blind-tap and transient-UI rules.
  - `/screens <feature>` — the "UI change: build, run, screenshot, inspect" rule as a checklist: every state, both `#available` paths, every device class, named files, inspected.
  - `/ui-drive <script>` — write and run a `Tools/ui-drive` JSON route; screenshots plus measured element dumps.
  - `/release-check` — versions, privacy manifest, usage strings, entitlements, localization completeness, archive.
  - `/spec-sync [range|path|all]` — code vs `spec.md`/`DESIGN.md` drift, with replacement text, applied.
  - `/new-screen <Name> [tier]` — scaffold `Features/<Name>/` the way the codebase expects.
- **Review agents live in `.claude/agents/`** — run the one that matches the work and act on its findings rather than re-deriving them:
  - `hig-components` — standard-iOS surfaces against Apple's HIG *Components* pages (fetches the page, never quotes from memory). Toolbars, menus, sheets, alerts, pickers, lists. Tier D is exempt except for target sizes, clipped text, accessibility labels, unconfirmed destructive actions and controls that misstate their state.
  - `device-layout` — **looks at the screen on each device it ships to** (iPhone, iPad, Duo inner and cover): builds, installs, screenshots, measures the controls it thinks are wrong. The one that catches chrome left at phone size on a 13" display. (Absorbed the old `ipad-expert`, which reviewed the same ground from source only.)
  - `component-consistency` — one concept, two implementations: an Add button that is a `+` here and a word there, two spinners, four corner radii. Sweeps every call site rather than sampling.
  - `copy-consistency` — user-visible strings: one action under two names, errors with no next step, jargon (`asset`, `recipe`) leaking on screen, title vs sentence case.
  - `a11y-voiceover` — VoiceOver and Dynamic Type: labels on icon-only controls, actions swallowed by `.combine`, custom-drawn tools with no elements, text that clips at accessibility sizes.
  - `perf-profiler` — cost per frame and per photo at 55k: per-cell queries, quadratic sweeps, unbounded caches, reload storms, oversized image requests.
  - `photokit-guard` — PhotoKit's traps and this app's history with them: Optimize Storage proxies, change-token storms, hidden/recently-deleted being unreadable, resource writes, `.limited` access.
  - `data-migration` — GRDB schema and stores, and the rule that keeps user data alive: the indexer rewrites whole `photo_metadata` rows, so anything the *user* typed needs its own table.
  - `ux-reviewer` — the flow: silent no-ops, recoverability, where the user is left after a bulk action, long-running work, empty states, naming drift.
  - `design-reviewer` — `DESIGN.md` compliance: invented constants, tier confusion, glass entry points, accent use, geometry tokens.
  - `challenger` — argues against a change: why this way, what it costs in screen space, what it breaks, what a photographer actually gets, and whether it is overthinking. Run it on anything that sounds obviously right.
  - `prior-art` — the fix side: given a finding, says how Photos, Lightroom, Halide, Darkroom, CapCut or Procreate solved the same thing and proposes the change with numbers, the tier it lands in and what it costs.
  - `video-nle-survey` — how the video editors people use (CapCut, LumaFusion, Final Cut for iPad, iMovie, Resolve) lay out a **tablet and a dual-screen device**, turned into a layout and interaction spec in points for one ShotDex screen. Use it when a timeline-shaped surface needs designing for iPad, Split View or the Duo; use `prior-art` when a single control needs a number.
  - `lightroom-parity` — what Lightroom does today that ShotDex should do next, with feasibility on iOS and where the work would live.
  - `swift-concurrency` — the Swift 6 checker the project does not have on: actor isolation, `@MainActor` leaks, Sendable holes, missing cancellation, tasks that outlive their owner. Any `actor`, `Task {}` or PhotoKit callback.
  - `memory-leak` — what stays alive and how big: strong `self` in stored closures, observers never removed, unbounded caches, full-res decodes, the ~120MB extension ceiling.
  - `ipad-multitasking` — everything `device-layout` does not: Split View widths, Stage Manager resize, multiple scenes, keyboard shortcuts and focus, pointer hover, Pencil, drag and drop.
  - `ios26-parity` — both sides of every `#available(iOS 26)` do the same thing; diffs the action set by element dump on 26.5 vs 18.6.
  - `test-coverage` — Domain/Database/kit code with no test, tests that assert nothing; writes the missing cases in house style.
  - `extension-boundary` — kit purity (no SwiftUI/GRDB), `public` surface the extensions need, app-only types reached from an extension, render paths that fit the extension memory ceiling.
  - `localization` — literals bypassing the String Catalog, plurals by concatenation, hand-formatted units and dates, fixed widths that break in German, RTL hardcodes.
  - `privacy-manifest` — `PrivacyInfo.xcprivacy` per shipping target, required-reason API codes matched to actual use, usage strings, GRDB's manifest in the product.
  - `crash-triage` — `.ips`/xcresult/log to `File.swift:NN`, classified (trap, isolation, jetsam, watchdog, PhotoKit, GRDB), handed to the owning agent.
