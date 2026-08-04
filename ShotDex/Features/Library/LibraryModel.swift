import Foundation
import Photos
import SwiftUI
import os

/// Index speed and ETA, derived from progress samples over the current run.
struct IndexThroughput: Equatable {
    /// Items (photos *and* videos — both are indexed) processed per minute,
    /// averaged over the run so far.
    let photosPerMinute: Double
    /// Estimated time until the run finishes; nil until estimable.
    let remaining: Duration?

    /// `1,548 photos and videos per minute` — grouped, and spelled out rather than
    /// `photos/min`, which reads as a unit off a spec sheet.
    var rateText: String {
        let rate = Int(photosPerMinute.rounded()).formatted()
        return "\(rate) " + String(localized: "photos and videos per minute")
    }

    var remainingText: String? {
        remaining.map(Self.format)
    }

    /// Time first, speed second: the wait is what the user is actually
    /// reading for — `About 2 hr 15 min left · 1,548 photos and videos per minute`.
    /// Drops to the rate alone until an estimate exists.
    var summaryLine: String {
        guard let remainingText else { return rateText }
        return "\(remainingText) · \(rateText)"
    }

    /// e.g. "About 2 hours left", "About 1 hr 20 min left", "About 45 min left".
    /// "About" is honest — the estimate is a run average, so it moves.
    static func format(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        if total < 60 { return String(localized: "Less than a minute left") }
        let about = String(localized: "About")
        let left = String(localized: "left")
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 1 {
            if minutes == 0 {
                return "\(about) \(hours) hour\(hours == 1 ? "" : "s") \(left)"
            }
            return "\(about) \(hours) hr \(minutes) min \(left)"
        }
        return "\(about) \(minutes) min \(left)"
    }
}

/// Presentation state for the Library tab: the whole filtered/sorted
/// library as slim grid rows, plus index pipeline coordination.
@MainActor
@Observable
final class LibraryModel {

    private let libraryQueries: LibraryQueries
    private let filterSuggestions: FilterSuggestionCache
    private let metadataStore: MetadataStore
    private let pipeline: IndexPipeline
    private let placeIndexPass: PlaceIndexPass
    private let backgroundIndex: BackgroundIndexService
    private let photoLibrary: PhotoLibraryService
    private let networkStatus: NetworkMonitor
    private let powerStatus: PowerMonitor
    private let indexTraffic: IndexTrafficMonitor

    /// The whole filtered library as slim rows, in bottom-anchored display
    /// order: the sort's primary results sit at the END of the array = the
    /// bottom of the grid, like the system Photos app. Loaded in one query;
    /// the grid virtualizes rendering, so this is the only per-photo state.
    private(set) var items: [LibraryGridItem] = []
    /// Bumped whenever the content is replaced (filter/sort change, index
    /// run, retap). The screen re-ids its ScrollView off it so
    /// `defaultScrollAnchor(.bottom)` re-applies without a long-distance
    /// `scrollTo` (which would materialize thousands of lazy tiles).
    private(set) var contentGeneration = 0
    /// Bumped when a reload produces the SAME ordered asset list but refreshed
    /// per-tile data (an index run filling in exposure overlays). The grid
    /// re-renders visible cells in place — it must NOT re-anchor, so the user's
    /// scroll position survives an index run finishing or being cancelled.
    private(set) var contentRefreshGeneration = 0
    private(set) var isLoading = false
    private(set) var loadError: String?

    var matchCount: Int { items.count }

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// SwiftUI `.task` can run again when a full-screen cover is dismissed.
    /// Initial grid loading is model-scoped and must happen only once;
    /// explicit filter/library changes still call `reload()` directly.
    @ObservationIgnored private var hasRequestedInitialLoad = false
    /// Bounded, non-blocking PHAsset resolution for grid tiles. A miss returns
    /// nil immediately, resolves the surrounding chunk off-main, then bumps
    /// `contentRefreshGeneration` so visible cells pick it up. This keeps
    /// PhotoKit fetches out of collection-view data-source/prefetch callbacks.
    @ObservationIgnored private let assetCache: AsyncChunkedLookupCache<PHAsset>
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    /// Lazy badge lookups for tiles indexed mid-run (see `lazyBadgeItem`).
    @ObservationIgnored private let badgeCache = GridBadgeCache()

    /// UI-visible indexing state. A **manual** run sets it the instant it
    /// starts — the user tapped something and needs the acknowledgement. An
    /// **automatic** run sets it only once it has found real work (a row to
    /// write or an asset to read), never merely because it is walking the
    /// library to decide: a launch on a fully-indexed library used to hold this
    /// true for ~7 s while skipping all 55k assets, which read as "still
    /// indexing" long after indexing was done. Use `isIndexRunActive` for
    /// reentrancy, not this.
    private(set) var isIndexing = false
    /// A pipeline run is in flight, whether or not it has found work — the
    /// reentrancy guard for every start path. Not observed: no UI depends on a
    /// run that may turn out to have nothing to do.
    @ObservationIgnored private var isIndexRunActive = false
    /// Bumped once per run. A run abandoned by the unwind watchdog compares
    /// this against the generation it started with, so if it ever does unwind it
    /// keeps its hands off state a newer run now owns.
    @ObservationIgnored private var runGeneration = 0
    /// The in-flight run's task. Cancelling the pipeline actor only asks it to
    /// stop; this is what lets a stuck run be cancelled outright.
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// The current run's network sampler, so an abandoned run's samples stop
    /// overwriting the next run's readout.
    @ObservationIgnored private var runSamplingTask: Task<Void, Never>?
    @ObservationIgnored private var runUnwindWatchdog: Task<Void, Never>?
    /// The current run was cancelled by the user. Its UI is already gone, so
    /// every late callback from the unwinding run (work signal, progress emit,
    /// network/thermal sample) must stay silent instead of flashing the
    /// indicator back on.
    @ObservationIgnored private var hasCancelledIndexRun = false
    /// A start was requested while a run was still in flight. Almost always this
    /// is the app returning to the foreground after the system stopped the
    /// previous run (the background-task assertion expired): that run is still
    /// unwinding, so the `isIndexRunActive` guard would swallow the request and
    /// indexing would simply stay stopped until the *next* foreground. Honoured
    /// once the current run finishes.
    @ObservationIgnored private var pendingStartAfterCurrentRun = false
    /// Whether the system is in Low Power Mode. Drives keep-awake suppression
    /// and the automatic-indexing guard.
    private(set) var isLowPowerMode = false
    /// True while the current run was started by an explicit user action
    /// (Settings re-index / retry). Automatic runs (library change, resume,
    /// charger auto-start) leave it false. In Low Power Mode only a manual run
    /// keeps the screen awake.
    private(set) var isManualIndexRun = false
    /// Previous charging state, so `handlePowerChange` can detect the
    /// unplugged→charging transition that auto-resumes indexing in LPM.
    @ObservationIgnored private var wasCharging = false
    /// A PhotoKit change arrived mid-run. Reloading then would cost a full
    /// library re-fetch per change (the index run itself generates changes
    /// while streaming iCloud originals), so the change is coalesced into
    /// the end-of-run reload plus one follow-up incremental run.
    @ObservationIgnored private var pendingLibraryChange = false
    private(set) var indexProgress: IndexProgress?
    /// Speed (photos/min) and ETA for the current run; nil until estimable.
    private(set) var indexThroughput: IndexThroughput?
    /// Sampled once a second while indexing: connection type, bytes streamed
    /// from iCloud this run, and the download speed derived from the delta.
    private(set) var indexNetworkStatus: IndexNetworkStatus?
    /// Thermal + iCloud read diagnostics, sampled once a second while a run
    /// is active (same tick as `indexNetworkStatus`).
    private(set) var indexDiagnostics: IndexDiagnostics?

    /// Run-relative baseline for throughput: when the first sample of this run
    /// arrived and how many photos were already processed then.
    @ObservationIgnored private var indexRunStart: ContinuousClock.Instant?
    @ObservationIgnored private var indexRunStartProcessed = 0

    var criteria: FilterCriteria = .empty {
        didSet {
            guard criteria != oldValue else { return }
            // Normal search/filter and advanced search are mutually exclusive:
            // activating one clears the other so the grid has a single source.
            if !criteria.isEmpty, advancedQuery != nil { advancedQuery = nil }
            reload()
        }
    }
    /// Advanced search: a smart-album-style rule query driving the grid instead
    /// of `criteria`. Non-nil (with valid rules) means advanced search is active.
    var advancedQuery: SmartAlbumQuery? {
        didSet {
            guard advancedQuery != oldValue else { return }
            if advancedQuery != nil, !criteria.isEmpty { criteria = .empty }
            reload()
        }
    }
    /// Any filter, search, or advanced query is narrowing the grid.
    var hasActiveQuery: Bool {
        !criteria.isEmpty || (advancedQuery?.isEmpty == false)
    }
    var sort: SortOption = .default {
        didSet { if sort != oldValue { reload() } }
    }

    /// Filter sheet option lists.
    private(set) var availableBrands: [String] = []
    private(set) var availableBodies: [String] = []
    private(set) var availableLenses: [String] = []
    /// Reverse-geocoded place names in the library — autosuggest, the Place rule
    /// row, and the vocabulary the search parser matches a bare term against.
    private(set) var availablePlaces: [String] = []

    init(dependencies: AppDependencies) {
        self.libraryQueries = dependencies.libraryQueries
        self.filterSuggestions = dependencies.filterSuggestions
        self.metadataStore = dependencies.metadataStore
        self.pipeline = dependencies.indexPipeline
        self.placeIndexPass = dependencies.placeIndexPass
        self.backgroundIndex = dependencies.backgroundIndex
        self.photoLibrary = dependencies.photoLibrary
        self.networkStatus = dependencies.networkStatus
        self.powerStatus = dependencies.powerStatus
        self.indexTraffic = dependencies.indexTraffic
        self.isLowPowerMode = dependencies.powerStatus.isLowPowerMode
        self.wasCharging = dependencies.powerStatus.isCharging
        let assetCache = AsyncChunkedLookupCache<PHAsset>(
            chunkSize: 120,
            maxChunks: 6,
            fetch: { ids in
                var byId: [String: PHAsset] = [:]
                for asset in PhotoLibraryService.fetchAssets(ids: ids) {
                    byId[asset.localIdentifier] = asset
                }
                return byId
            }
        )
        self.assetCache = assetCache
        assetCache.onChunkLoaded = { [weak self] in
            self?.contentRefreshGeneration &+= 1
        }
        // Under memory pressure the PHAsset chunks are the one cache we
        // hold; visible tiles re-fetch their chunk on the next request.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.assetCache.removeAll()
            }
        }
        // Pause/resume iCloud streaming as the network path flips between
        // Wi-Fi and (unpermitted) cellular.
        networkStatus.setPathChangeHandler { [weak self] _, _ in
            Task { @MainActor in self?.handleNetworkChange() }
        }
        // Low Power Mode stops automatic indexing; a charger auto-resumes it.
        powerStatus.setPowerChangeHandler { [weak self] lowPower, charging in
            Task { @MainActor in self?.handlePowerChange(lowPower: lowPower, charging: charging) }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        networkStatus.setPathChangeHandler(nil)
        powerStatus.setPowerChangeHandler(nil)
    }

    // MARK: Loading

    /// Newest slice shown at first paint on the PhotoKit fast path, before
    /// the full-library enumeration lands. Covers the visible grid plus a
    /// few screens of scroll headroom at the densest column setting.
    private static let firstPaintLimit = 600

    func loadIfNeeded() {
        guard !hasRequestedInitialLoad else { return }
        hasRequestedInitialLoad = true
        reload()
    }

    func reload() {
        loadTask?.cancel()
        loadError = nil
        isLoading = true
        let criteria = self.criteria
        let advancedQuery = self.advancedQuery
        let sort = self.sort
        let libraryQueries = self.libraryQueries
        // Fast path (no metadata filter/search + a date sort): drive the grid
        // from PhotoKit directly so the whole library shows instantly, like the
        // system Photos app, instead of waiting on the EXIF index. Any active
        // filter, advanced query, or metric sort falls back to the DB query.
        let usePhotoKit = criteria.isEmpty && advancedQuery == nil && sort.isDateSort
        // The capped first-paint phase exists only for a grid with nothing on
        // screen (enumerating a large library takes seconds). With rows already
        // showing, publishing the 600-row slice first would replace the content
        // twice — two `reloadData()`s and a content-height collapse/re-expand,
        // which is what made an index run finishing jump the grid and flicker.
        let useFirstPaintSlice = usePhotoKit && items.isEmpty
        loadTask = Task { [weak self] in
            do {
                if usePhotoKit {
                    var slice: [LibraryGridItem] = []
                    if useFirstPaintSlice {
                        slice = try await Self.photoKitGridItems(
                            sort: sort, libraryQueries: libraryQueries, limit: Self.firstPaintLimit
                        )
                        guard let self, !Task.isCancelled else { return }
                        self.applyLoadedRows(slice)
                    }
                    let all = try await Self.fullLibraryRows(
                        sort: sort, libraryQueries: libraryQueries, anchorSlice: slice
                    )
                    guard let self, !Task.isCancelled else { return }
                    self.applyLoadedRows(all)
                } else if let advancedQuery, !advancedQuery.isEmpty {
                    let rows = try await libraryQueries.gridItems(matching: advancedQuery, sort: sort)
                    guard let self, !Task.isCancelled else { return }
                    self.applyLoadedRows(rows)
                } else {
                    let rows = try await libraryQueries.gridItems(matching: criteria, sort: sort)
                    guard let self, !Task.isCancelled else { return }
                    self.applyLoadedRows(rows)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                // A failure after the first slice painted keeps the slice on
                // screen; the error banner is for a grid with nothing to show.
                if self.items.isEmpty {
                    self.loadError = "Couldn't load photos."
                }
                self.isLoading = false
            }
        }
    }

    /// Publishes freshly loaded rows to the grid, choosing between an
    /// in-place refresh and a full content replacement.
    private func applyLoadedRows(_ rows: [LibraryGridItem]) {
        // Reversed for the bottom-anchored grid; reversing in Swift
        // (not SQL) keeps NULLS LAST semantics = "No Date" at top.
        // `rows` is in sort order (newest-first for .dateTakenNewest)
        // from both paths, so the reverse is identical either way.
        let reversed = Array(rows.reversed())
        // Same ordered list = tiles only need their overlay refreshed
        // (typical after an index run): re-render in place, keep the
        // scroll spot. A changed list (filter/sort/library edit) is a
        // real content replacement and re-anchors to newest.
        let sameList = reversed.count == items.count
            && zip(reversed, items).allSatisfy { $0.assetId == $1.assetId }
        // Every row was just re-fetched — cached lazy-badge answers are stale.
        badgeCache.removeAll()
        items = reversed
        // Same ids in the same order = every resolved PHAsset chunk is still
        // valid. Re-seeding would drop them all, so `asset(atFlatIndex:)`
        // would return nil for every visible tile and each one would blank
        // and re-resolve — thumbnail flicker on an index-finish refresh.
        if !sameList {
            assetCache.replaceKeys(items.map(\.assetId))
        }
        if sameList {
            contentRefreshGeneration &+= 1
        } else {
            contentGeneration &+= 1
        }
        isLoading = false
    }

    /// The whole library for the phase that follows a first-paint slice.
    ///
    /// Materializing 55k `PHAsset`s costs ~930ms against ~350ms to decode the
    /// same rows out of SQLite, and when the index already covers every asset
    /// the enumeration learns nothing. So: read the DB, and use it only if it
    /// provably agrees with PhotoKit — same total count (O(1) on a fetch
    /// result), and the same set of ids at the anchored end as the slice that
    /// just painted. Otherwise fall back to the authoritative enumeration,
    /// which is also what every later reload uses, so a structural change can
    /// never be papered over by this shortcut.
    ///
    /// The slice's own rows are kept verbatim at the anchored end rather than
    /// the DB's: PhotoKit and SQL break creation-date ties differently (SQL
    /// falls back to `assetId`), and re-ordering a burst under the user's eyes
    /// is the thing the section-aligned slice exists to prevent.
    private static func fullLibraryRows(
        sort: SortOption,
        libraryQueries: LibraryQueries,
        anchorSlice: [LibraryGridItem]
    ) async throws -> [LibraryGridItem] {
        guard !anchorSlice.isEmpty else {
            return try await photoKitGridItems(sort: sort, libraryQueries: libraryQueries)
        }
        let rows = try await libraryQueries.gridItems(matching: FilterCriteria.empty, sort: sort)
        let assetCount = await Task.detached(priority: .userInitiated) {
            PHAsset.fetchAssets(with: Self.browsableFetchOptions(sort: sort)).count
        }.value
        let agrees = rows.count == assetCount
            && rows.count >= anchorSlice.count
            && Set(rows.prefix(anchorSlice.count).map(\.assetId))
                == Set(anchorSlice.map(\.assetId))
        guard agrees else {
            return try await photoKitGridItems(sort: sort, libraryQueries: libraryQueries)
        }
        return anchorSlice + rows.dropFirst(anchorSlice.count)
    }

    /// Every browsable-asset fetch in this type uses these: same predicate and
    /// sort, so a count taken here is comparable with a list built there.
    private nonisolated static func browsableFetchOptions(sort: SortOption) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: sort == .dateTakenOldest)
        ]
        return options
    }

    /// The whole library as grid rows sourced from PhotoKit, in `sort` order.
    /// Each asset uses its indexed DB row when one exists (so the exposure
    /// overlay shows) and a PhotoKit-only placeholder otherwise — so photos
    /// appear before, and regardless of, the EXIF index. The PHFetchResult
    /// enumeration runs off the main thread (it materializes every asset).
    /// `limit` takes the leading slice of the sort — the end the grid anchors
    /// to — for the first-paint phase; the capped DB read can miss overlays for
    /// assets indexed out of date order, which the full phase corrects.
    private static func photoKitGridItems(
        sort: SortOption,
        libraryQueries: LibraryQueries,
        limit: Int? = nil
    ) async throws -> [LibraryGridItem] {
        // Indexed rows keyed by id, for the exposure overlay. `.empty` +
        // matching sort reuses the existing query untouched.
        let indexed = try await libraryQueries.gridItems(matching: FilterCriteria.empty, sort: sort, limit: limit)
        var byId: [String: LibraryGridItem] = [:]
        byId.reserveCapacity(indexed.count)
        for row in indexed { byId[row.assetId] = row }

        return await Task.detached(priority: .userInitiated) {
            let options = Self.browsableFetchOptions(sort: sort)
            // Deliberately no `fetchLimit`: alongside a custom sort descriptor
            // it does not mean "the newest 600" — Photos may truncate in its
            // native order and sort only that window, so the slice was not the
            // sorted prefix. The grid anchors to the slice's own end, so the
            // full phase then grew a row of genuinely newer photos there —
            // the flicker-plus-extra-row on every cold launch. `PHFetchResult`
            // is lazy, so slicing an unlimited fetch by index costs the same
            // and is a true prefix of the full phase by construction.
            let fetch = PHAsset.fetchAssets(with: options)
            var items: [LibraryGridItem] = []
            if let limit {
                let upperBound = Self.dateGroupAlignedBound(min(limit, fetch.count), in: fetch)
                items.reserveCapacity(upperBound)
                for index in 0..<upperBound {
                    let asset = fetch.object(at: index)
                    items.append(byId[asset.localIdentifier] ?? LibraryGridItem(asset: asset))
                }
            } else {
                items.reserveCapacity(fetch.count)
                fetch.enumerateObjects { asset, _, _ in
                    items.append(byId[asset.localIdentifier] ?? LibraryGridItem(asset: asset))
                }
            }
            return items
        }.value
    }

    /// Grows `bound` until it sits on a month boundary, so the first-paint
    /// slice ends on a whole date group.
    ///
    /// Tiles pack into rows from the *start of their section*, so a slice that
    /// cuts a date group in half gives that group a different item count than
    /// the full phase — the group's whole row layout then shifts when the
    /// missing members arrive, which is the grid re-flowing and losing tiles
    /// from its last row a second after launch. A true prefix is not enough;
    /// it has to be a prefix of whole sections. A month boundary is also a day
    /// boundary, so this holds for either `PhotoGridDateGranularity`.
    ///
    /// Growing (not shrinking) because the anchored end is the newest group:
    /// shrinking to the previous boundary would empty the slice whenever that
    /// one group is larger than the limit. Capped so a single enormous month
    /// can't turn the first paint back into a whole-library enumeration — past
    /// the cap the slice stays misaligned and the full phase re-packs as before.
    private nonisolated static func dateGroupAlignedBound(
        _ bound: Int,
        in fetch: PHFetchResult<PHAsset>,
        calendar: Calendar = .current
    ) -> Int {
        guard bound > 0, bound < fetch.count else { return bound }
        let boundaryDate = fetch.object(at: bound - 1).creationDate
        let cap = min(fetch.count, bound * 8)
        var aligned = bound
        while aligned < cap {
            let date = fetch.object(at: aligned).creationDate
            // nil dates form their own `.undated` group; they sort to the far
            // end, so this only matters for a library of undated assets.
            let continuesGroup = switch (boundaryDate, date) {
            case (nil, nil): true
            case let (previous?, next?): calendar.isDate(previous, equalTo: next, toGranularity: .month)
            default: false
            }
            guard continuesGroup else { return aligned }
            aligned += 1
        }
        return aligned
    }

    /// PHAsset for the tile at a flat grid index. A cache miss schedules an
    /// off-main chunk lookup and returns nil, so the cell paints a placeholder
    /// instead of blocking the scroll callback.
    func asset(atFlatIndex index: Int) -> PHAsset? {
        assetCache.value(at: index)
    }

    func refreshFilterOptions(force: Bool = false) {
        // Shared actor cache: the three DISTINCT scans never block first paint
        // and repeated search/sheet presentations reuse the same catalog.
        let filterSuggestions = self.filterSuggestions
        Task { [weak self] in
            let catalog = await filterSuggestions.load(forceRefresh: force)
            guard let self, !Task.isCancelled else { return }
            self.availableBrands = catalog.brands
            self.availableBodies = catalog.bodies
            self.availableLenses = catalog.lenses
            self.availablePlaces = catalog.places
        }
    }

    // MARK: Search

    /// Applies a typed query to the grid.
    ///
    /// Returns immediately: the caller closes the search surface on the same tap,
    /// and the resolution — which may consult the on-device model — lands a moment
    /// later. Waiting would make the keyboard's Search key feel like it did
    /// nothing, which is worse than a grid that updates a beat behind.
    ///
    /// The one place a search becomes a grid state, so the keyboard's Search key,
    /// the "Search for …" row and a tapped suggestion cannot behave differently.
    func applySearch(_ text: String, using service: SearchService) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            criteria.searchText = nil
            return
        }
        // Remembered before the resolution lands, and remembered as typed: recents
        // are "what I asked for", not "what the parser made of it".
        service.recentSearches.remember(trimmed)
        Task { [weak self] in
            let resolution = await service.resolve(trimmed)
            guard let self else { return }
            // `criteria` and `advancedQuery` clear each other, so exactly one of
            // these is ever set.
            if resolution.hasRules {
                advancedQuery = resolution.query
            } else {
                criteria.searchText = resolution.searchText
            }
        }
    }

    // MARK: Places

    /// Photos with coordinates still waiting for an address, while the pass runs.
    /// Nil when nothing is in flight.
    private(set) var placeLookupRemaining: Int?

    /// Reverse-geocodes the library into place names, after an index run has
    /// settled. Deliberately its own task rather than part of the run: this is
    /// network work at someone else's pace, and holding the "Indexing…" indicator
    /// for the quarter of an hour it can take on a first pass would misdescribe
    /// what the app is doing. Cheap when there is nothing new — the work list
    /// query is one indexed scan.
    func startPlaceLookup() {
        guard Self.looksUpPlaces else { return }
        let pass = placeIndexPass
        Task(priority: .utility) { [weak self] in
            let summary = await pass.run(
                isEnabled: { Self.looksUpPlaces },
                onProgress: { remaining in
                    Task { @MainActor in
                        self?.placeLookupRemaining = remaining > 0 ? remaining : nil
                    }
                }
            )
            guard let self else { return }
            self.placeLookupRemaining = nil
            // New place names mean new search vocabulary and new autosuggest
            // entries; without this refresh they only appear on the next launch.
            if summary.didWork { self.refreshFilterOptions(force: true) }
        }
    }

    /// Defaults to on, and reads through an `object(forKey:)` check because
    /// `bool(forKey:)` answers false for a key nobody has written.
    ///
    /// `nonisolated` on purpose: the place pass re-reads it from its own task on
    /// every cell, so turning the switch off stops the run in progress instead of
    /// only affecting the next one.
    nonisolated static var looksUpPlaces: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.lookUpPlaces) as? Bool ?? true
    }

    /// Autosuggest source for search: known camera, lens and place names.
    func suggestions(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        var result: [String] = []
        result.reserveCapacity(8)
        for values in [availableBodies, availableLenses, availablePlaces, availableBrands] {
            for value in values where value.localizedCaseInsensitiveContains(query) {
                result.append(value)
                if result.count == 8 { return result }
            }
        }
        return result
    }

    // MARK: Indexing

    /// Streaming EXIF from iCloud is allowed on Wi-Fi; on cellular only when
    /// the user opted in via Settings. A closure — the pipeline re-evaluates
    /// it per batch, so the launch-triggered run isn't crippled by
    /// `NWPathMonitor`'s "expensive until first path update" default, and
    /// leaving Wi-Fi mid-run stops streaming at the next batch.
    private var allowNetworkForIndexing: @Sendable () -> Bool {
        let networkStatus = self.networkStatus
        return {
            !networkStatus.isExpensivePath
                || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
        }
    }

    /// Entry point for structural PhotoKit changes. Membership reloads
    /// immediately even during a long index run, so a photo just saved by the
    /// user appears without waiting for that run to finish. Only the follow-up
    /// incremental index is deferred; content-only iCloud rendition changes
    /// never reach this method because PhotoLibraryService filters them out.
    func libraryDidChange() {
        reload()
        guard !isIndexRunActive else {
            pendingLibraryChange = true
            return
        }
        startIndexing()
    }

    func startIndexing(fullReindex: Bool = false, manual: Bool = false) {
        if isIndexRunActive {
            // A tap must not queue behind a run that has hours of work left, and
            // must not vanish: it preempts, and the indicator says so now.
            if manual {
                enqueueManualRun(fullReindex ? .fullReindex : .incremental)
            } else {
                IndexTrafficMonitor.health("automatic start deferred: a run is already in flight")
                pendingStartAfterCurrentRun = true
            }
            return
        }
        // No automatic indexing in Low Power Mode. The user can still start it
        // by hand (`manual`), and a charger connecting resumes it through
        // `resumeIndexingForCharger` (which drives `runPipeline` directly).
        guard manual || !isLowPowerMode else { return }
        let allowNetwork = allowNetworkForIndexing
        runPipeline(
            allowsNetwork: allowNetwork,
            manual: manual,
            trigger: fullReindex ? "fullReindex" : (manual ? "manual" : "incremental")
        ) { pipeline, onWorkFound, onProgress in
            try await pipeline.run(
                fullReindex: fullReindex, allowNetwork: allowNetwork,
                onWorkFound: onWorkFound, onProgress: onProgress
            )
        }
    }

    /// Re-reads only the assets stuck at `pendingICloud`/`error`
    /// (auto-retry, "Retry Now", and Settings → Continue Indexing when every
    /// unread row is one of those). Always uses the network.
    func reindexIncompleteAssets(manual: Bool = false) {
        if isIndexRunActive {
            // Same as `startIndexing`: a tap preempts, an automatic call yields.
            // This used to `return` outright — the Settings button and "Retry Now"
            // simply did nothing whenever a run happened to be in flight.
            if manual { enqueueManualRun(.incomplete) }
            return
        }
        guard manual || !isLowPowerMode else { return }
        runPipeline(
            allowsNetwork: { true },
            manual: manual,
            trigger: manual ? "incomplete-manual" : "incomplete-auto"
        ) { pipeline, onWorkFound, onProgress in
            try await pipeline.reindexIncomplete(onWorkFound: onWorkFound, onProgress: onProgress)
        }
    }

    /// A charger connected while in Low Power Mode — the one automatic resume
    /// allowed there. Runs an incremental pass without keeping the screen awake
    /// (`manual: false`), bypassing the LPM start-guard by driving the pipeline
    /// directly.
    private func resumeIndexingForCharger() {
        guard !isIndexRunActive else { return }
        let allowNetwork = allowNetworkForIndexing
        runPipeline(allowsNetwork: allowNetwork, manual: false, trigger: "charger") { pipeline, onWorkFound, onProgress in
            try await pipeline.run(
                fullReindex: false, allowNetwork: allowNetwork,
                onWorkFound: onWorkFound, onProgress: onProgress
            )
        }
    }

    /// `allowsNetwork` mirrors what the pipeline run may do, so the status
    /// line can show speed/total (even at zero) whenever streaming is possible.
    /// `trigger` names what started the run on the health log — the indexing
    /// indicator is visible for exactly this run's lifetime, so an unexpected
    /// indicator has to be traceable back to its cause.
    private func runPipeline(
        allowsNetwork: @escaping @Sendable () -> Bool,
        manual: Bool,
        trigger: String,
        _ operation: @escaping @Sendable (
            IndexPipeline,
            @escaping @Sendable () -> Void,
            @escaping @Sendable (IndexProgress) -> Void
        ) async throws -> IndexRunSummary
    ) {
        isIndexRunActive = true
        runGeneration += 1
        let generation = runGeneration
        hasCancelledIndexRun = false
        pendingStartAfterCurrentRun = false
        // A run the user asked for shows its state **immediately**: the Settings
        // row and the toolbar token are the only acknowledgement of the tap, and
        // a full reindex needs seconds of scanning before its first batch. Only
        // automatic runs wait for `onWorkFound`, since those are the ones that
        // must stay invisible when there is nothing to do.
        isIndexing = manual
        isManualIndexRun = manual
        pendingLibraryChange = false
        indexProgress = nil
        indexThroughput = nil
        indexRunStart = nil
        cancelScheduledAutoRetry()
        startRetryTask?.cancel()
        let pipeline = self.pipeline
        let networkStatus = self.networkStatus
        // .utility: parse/compose/DB writes and PhotoKit XPC servicing must
        // not compete with interactive image loads at UI priority.
        let indicatorStart = ContinuousClock.now
        runTask = Task(priority: .utility) {
            // Resolve the real network path before showing status, so the
            // indicator reflects Wi-Fi/cellular from the first frame rather
            // than `NWPathMonitor`'s metered-until-first-update default.
            await networkStatus.awaitInitialPath()
            self.indexTraffic.reset()
            IndexTrafficMonitor.health(
                "run start [\(trigger)]: connection \(networkStatus.connectionType.displayName), expensivePath \(networkStatus.isExpensivePath), allowCellularSetting \(UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)), allowNetwork \(allowsNetwork())"
            )
            if !self.hasCancelledIndexRun {
                self.indexNetworkStatus = IndexNetworkStatus(
                    connection: networkStatus.connectionType,
                    bytesDownloaded: 0,
                    bytesPerSecond: nil,
                    isNetworkAllowed: allowsNetwork()
                )
            }
            self.refreshPausedState()
            // The pipeline may already be owned by a BGProcessingTask run, which
            // drives the actor directly (a background launch has no model to go
            // through). Take it back before starting, or `run` refuses and the
            // app shows nothing while work remains.
            guard await self.claimPipelineFromBackgroundRun(trigger: trigger) else {
                // Declared before this run's `defer`, so clean up by hand.
                self.isIndexRunActive = false
                self.isIndexing = false
                self.isManualIndexRun = false
                self.indexNetworkStatus = nil
                self.indexDiagnostics = nil
                self.scheduleStartRetry(after: Self.busyPipelineRetryDelay)
                return
            }
            let samplingTask = self.startNetworkSampling(allowsNetwork: allowsNetwork)
            self.runSamplingTask = samplingTask
            // Keeps the run alive through a brief trip to the background;
            // on expiry it cancels cleanly and hands off to the BGProcessingTask.
            self.backgroundIndex.beginRunAssertion { [weak self] in
                guard let self else { return }
                // System stopped the run because the app left the foreground.
                // Drop the indicator now rather than when the suspended task
                // eventually unwinds — otherwise reopening the app shows
                // "Indexing…" for a run that ended minutes earlier.
                self.isIndexing = false
                self.indexProgress = nil
                self.indexThroughput = nil
                self.indexNetworkStatus = nil
                self.indexDiagnostics = nil
                // The task above is only *asked* to stop. If it never unwinds it
                // keeps `isIndexRunActive` set, which silently swallows every
                // later start — this releases the latch by force.
                self.armRunUnwindWatchdog()
            }
            defer {
                samplingTask.cancel()
                // Span of the whole run, which is wider than the pipeline's own
                // summary (network path resolution at the head, grid reload +
                // filter refresh at the tail).
                let elapsed = indicatorStart.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
                // A `defer` block cannot `return`, and the abandoned-run case
                // needs an early out — so the rest lives in a method.
                self.finishRun(trigger: trigger, seconds: seconds, generation: generation)
            }
            var summary: IndexRunSummary?
            do {
                summary = try await operation(
                    pipeline,
                    {
                        // First real work of the run: only now does the UI say
                        // "Indexing…". A no-op run never gets here, and neither
                        // does a run the user already cancelled — nor an
                        // abandoned one, whose late callbacks would otherwise
                        // flash the indicator on over the run that replaced it.
                        Task { @MainActor in
                            guard self.runGeneration == generation, !self.hasCancelledIndexRun else { return }
                            self.isIndexing = true
                        }
                    },
                    { progress in
                        Task { @MainActor in
                            guard self.runGeneration == generation, !self.hasCancelledIndexRun else { return }
                            self.indexProgress = progress
                        }
                    }
                )
            } catch {
                self.loadError = "Indexing failed."
            }
            self.reload()
            self.refreshFilterOptions(force: true)
            self.startPlaceLookup()
            // A local-only run leaves iCloud-only photos pending; surface a
            // persistent "waiting for Wi-Fi" state when they can't stream now.
            self.refreshPausedState()
            if summary?.didNotStart == true {
                // Lost a race for the actor (a background run claimed it between
                // the check above and the call). Not a finished run — retry.
                IndexTrafficMonitor.health("run [\(trigger)] refused by the pipeline — retrying in \(Int(Self.busyPipelineRetryDelay.components.seconds))s")
                self.scheduleStartRetry(after: Self.busyPipelineRetryDelay)
            } else {
                self.scheduleAutoRetryIfNeeded(after: summary)
            }
        }
    }

    /// End of one run: clears its state and hands over to whatever was requested
    /// while it was in flight. `seconds` is the indicator's whole lifetime and
    /// `generation` identifies the run, so a run the unwind watchdog already gave
    /// up on reports the late unwind and then keeps out of the way — the state it
    /// would otherwise reset now belongs to the run that replaced it.
    private func finishRun(trigger: String, seconds: Double, generation: Int) {
        guard runGeneration == generation else {
            IndexTrafficMonitor.health(
                "run end [\(trigger)]: \(String(format: "%.1f", seconds))s, unwound after being abandoned"
            )
            return
        }
        // `indicator` says whether any of the run was ever visible as
        // "Indexing…" — a run that found no work must report false.
        IndexTrafficMonitor.health(
            "run end [\(trigger)]: \(String(format: "%.1f", seconds))s, indicator \(isIndexing)"
        )
        runUnwindWatchdog?.cancel()
        runUnwindWatchdog = nil
        runSamplingTask = nil
        runTask = nil
        isIndexRunActive = false
        isIndexing = false
        isManualIndexRun = false
        indexProgress = nil
        indexThroughput = nil
        indexNetworkStatus = nil
        indexDiagnostics = nil
        backgroundIndex.endRunAssertion()
        startPendingRequestAfterRun()
    }

    /// Starts whatever was requested while the run that just ended was still in
    /// flight — a tap that preempted it (Re-index, Retry Now, Use Cellular), a
    /// start deferred by the reentrancy guard, or a library change. Always on the
    /// next tick, so the finished run's task fully unwinds first, and with the
    /// indicator held on across the handover: dropping it for one frame reads as
    /// "the tap did nothing".
    private func startPendingRequestAfterRun() {
        if let request = pendingManualRun {
            pendingManualRun = nil
            isIndexing = true
            isManualIndexRun = true
            // User-initiated — allowed even in Low Power Mode.
            Task { @MainActor in self.startManualRun(request) }
        } else if pendingStartAfterCurrentRun, !hasCancelledIndexRun {
            // Usually the foreground return after a system stop. Cheap when
            // there is nothing to do (the change-token path settles in ~60 ms
            // and never shows the indicator).
            pendingStartAfterCurrentRun = false
            Task { @MainActor in self.startIndexing() }
        } else if pendingLibraryChange {
            // A library change arrived mid-run (deferred by libraryDidChange).
            // The end-of-run reload has already re-fetched the grid; one
            // incremental run picks up whatever the change added.
            pendingLibraryChange = false
            Task { @MainActor in self.startIndexing() }
        }
    }

    /// Time before a run that couldn't get the pipeline tries again.
    static let busyPipelineRetryDelay: Duration = .seconds(15)
    /// How long to wait for a cancelled background run to unwind. Cancelling
    /// stops new reads being spawned but never kills reads in flight, and an
    /// iCloud read can sit on the 8 s stall watchdog — so the wait has to
    /// outlast a full in-flight batch draining, not a single read.
    private static let pipelineHandoverTimeout: Duration = .seconds(30)
    /// How long a cancelled run gets to unwind before the reentrancy latch is
    /// released by force. Cancelling stops new reads being spawned but never
    /// kills reads in flight, so this has to outlast a full in-flight batch
    /// draining — the same reasoning as `pipelineHandoverTimeout`, with room to
    /// spare because releasing early would run two pipelines at once.
    private static let runUnwindTimeout: Duration = .seconds(45)

    /// Arms the release of `isIndexRunActive` for a run that has been asked to
    /// stop. `pipeline.cancel()` is cooperative: it cannot promise the run's
    /// task ever returns, and a read parked forever used to leave the latch set
    /// for the life of the process. Every later start — including both Settings
    /// buttons — then hit the reentrancy guard and returned before `runPipeline`,
    /// so nothing ran and nothing was logged. Force-quitting was the only cure.
    private func armRunUnwindWatchdog() {
        guard isIndexRunActive else { return }
        let generation = runGeneration
        runUnwindWatchdog?.cancel()
        runUnwindWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.runUnwindTimeout)
            guard !Task.isCancelled, let self else { return }
            self.abandonStuckRun(generation: generation)
        }
    }

    /// Gives up on a run that did not unwind: releases the latch and starts
    /// whatever the user asked for while it was stuck.
    private func abandonStuckRun(generation: Int) {
        guard isIndexRunActive, runGeneration == generation else { return }
        IndexTrafficMonitor.health(
            "run abandoned: still in flight \(Int(Self.runUnwindTimeout.components.seconds))s after being cancelled — releasing the latch"
        )
        runUnwindWatchdog = nil
        // Escalation: the pipeline was already asked to stop, so cancel the task
        // itself — the reads it is parked in may honour cancellation even when
        // the actor's own flag didn't reach them. Bumping the generation makes
        // its `defer` a no-op if it ever does unwind.
        runTask?.cancel()
        runTask = nil
        runSamplingTask?.cancel()
        runSamplingTask = nil
        runGeneration += 1
        isIndexRunActive = false
        isIndexing = false
        isManualIndexRun = false
        indexProgress = nil
        indexThroughput = nil
        indexNetworkStatus = nil
        indexDiagnostics = nil
        backgroundIndex.endRunAssertion()
        // Same handover as the end of a healthy run: a tap made while the run was
        // stuck is the whole reason this matters.
        startPendingRequestAfterRun()
    }

    @ObservationIgnored private var startRetryTask: Task<Void, Never>?

    /// Retries `startIndexing` after a delay. Separate from the iCloud
    /// auto-retry: this one means "the pipeline was busy", shows no countdown
    /// card, and always resumes the full incremental run rather than the
    /// iCloud-only subset.
    private func scheduleStartRetry(after delay: Duration) {
        startRetryTask?.cancel()
        startRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isIndexRunActive else { return }
            self.startIndexing()
        }
    }

    /// Stops a `BGProcessingTask` run so the foreground can index, and waits for
    /// the actor to come free.
    ///
    /// The background task has to drive `IndexPipeline` directly — the app can be
    /// launched into the background with no `LibraryModel` at all — so the actor
    /// can be busy with a run this model knows nothing about. `IndexPipeline.run`
    /// then refuses, and before `didNotStart` existed that refusal looked exactly
    /// like "the library is fully indexed": no indicator, no progress, no retry,
    /// with 42k rows still unread (observed on device, 2026-07-27).
    ///
    /// The foreground wins the tie-break: it has a UI to report progress in, and
    /// the background run is rescheduled on the way out anyway. Nothing is lost
    /// by cancelling — rows are written per batch.
    ///
    /// - Returns: whether the pipeline is free to run.
    private func claimPipelineFromBackgroundRun(trigger: String) async -> Bool {
        guard await pipeline.isActive else { return true }
        IndexTrafficMonitor.health("run start [\(trigger)]: a background run owns the pipeline — cancelling it")
        await pipeline.cancel()
        let deadline = ContinuousClock.now.advanced(by: Self.pipelineHandoverTimeout)
        while await pipeline.isActive {
            guard ContinuousClock.now < deadline else {
                IndexTrafficMonitor.health("run start [\(trigger)]: background run still unwinding after \(Int(Self.pipelineHandoverTimeout.components.seconds))s — deferring")
                return false
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }

    /// Averages photos-per-minute over the run and projects the remaining time.
    /// Baselined on the first sample so a resumed/incremental run measures only
    /// its own work, not the skipped-scan head start. Called once a second from
    /// `startNetworkSampling` (a reliable observed-property tick), not from the
    /// pipeline callback.
    private func updateThroughput() {
        guard let progress = indexProgress, progress.total > 0 else { return }
        let now = ContinuousClock.now
        guard let start = indexRunStart else {
            indexRunStart = now
            indexRunStartProcessed = progress.processed
            return
        }
        let doneThisRun = progress.processed - indexRunStartProcessed
        let elapsed = start.duration(to: now)
        let elapsedSeconds =
            Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        guard doneThisRun > 0, elapsedSeconds >= 1 else { return }
        let perSecond = Double(doneThisRun) / elapsedSeconds
        let remainingCount = max(0, progress.total - progress.processed)
        let remaining: Duration? =
            perSecond > 0 ? .seconds(Double(remainingCount) / perSecond) : nil
        indexThroughput = IndexThroughput(
            photosPerMinute: perSecond * 60,
            remaining: remaining
        )
    }

    // MARK: Cellular pause

    /// True when iCloud-only photos remain unread and can't stream: on a
    /// metered cellular path the user hasn't opted into. Local metadata reads
    /// still complete (they cost no data), so this only gates iCloud streaming.
    /// Drives a persistent "Indexing paused — waiting for Wi-Fi" indicator.
    private(set) var isIndexStreamingPaused = false
    /// Count of `pendingICloud` rows genuinely awaiting an iCloud/network read
    /// — **excludes** `error`. Local `error` rows (unreadable/hard-fail) are
    /// non-network and converge to `noExif` via the give-up cap on incremental
    /// runs, so they must not drive the "iCloud not responding" auto-retry/card
    /// (doing so popped that dialog for corrupt *local* files).
    private(set) var pendingICloudCount = 0
    /// Rows whose read hasn't finished for **any** reason — the iCloud tail plus
    /// `pendingRead` placeholders and `error` rows. What decides whether
    /// indexing is done; `pendingICloudCount` only decides whether *iCloud* is
    /// what it's waiting on.
    private(set) var unfinishedCount = 0
    /// Of `unfinishedCount`, how many `reindexIncomplete` would actually re-read
    /// (`pendingICloud` + `error`). When it's short of `unfinishedCount` the
    /// targeted retry can't finish the job and a full incremental run must run.
    @ObservationIgnored private var retryableCount = 0

    // MARK: Auto-retry
    //
    // A run can end with work still unread: photos `pendingICloud` on an allowed
    // network (iCloud auth dead — accountsd Code=7 — or a Wi-Fi that can't serve
    // originals), or `pendingRead` placeholders a stopped run never reached.
    // Indexing must never sit dead in either state: the model schedules an
    // automatic retry every 30 s, and the UI shows a small "retrying in Ns" card
    // instead of the old dead-end "iCloud not downloading over Wi-Fi" banner. A
    // fixed interval, no backoff — a failed attempt is cheap (the breaker trips
    // within ~12 reads), and picking iCloud up seconds after it recovers matters
    // more.
    //
    // The retry keys off `unfinishedCount`, not `pendingICloudCount`: keying off
    // the iCloud count meant a backlog of 42k `pendingRead` rows armed nothing at
    // all, and even when it did arm, `reindexIncomplete` reads only
    // `pendingICloud`/`error` — so those rows would never have been picked up.

    static let autoRetryDelay: Duration = .seconds(30)

    /// When the next automatic retry fires — drives the countdown card.
    /// nil when no retry is scheduled.
    private(set) var indexAutoRetryDate: Date?

    /// The countdown as the UI should use it: a card that says "iCloud isn't
    /// responding" may only appear when iCloud is in fact what the run is
    /// waiting on. A retry armed for `pendingRead` rows (a stopped run's
    /// leftovers) runs silently — there is nothing for the user to do about it.
    var indexICloudRetryDate: Date? {
        pendingICloudCount > 0 ? indexAutoRetryDate : nil
    }
    @ObservationIgnored private var autoRetryTask: Task<Void, Never>?

    /// Called at the end of every uncancelled run. Schedules a follow-up
    /// incomplete pass when iCloud work remains and the network is allowed.
    private func scheduleAutoRetryIfNeeded(after summary: IndexRunSummary?) {
        guard let summary, !summary.wasCancelled else { return }
        guard unfinishedCount > 0 else { return }
        // Metered cellular without opt-in: the paused card owns this state.
        guard allowNetworkForIndexing() else { return }
        IndexTrafficMonitor.healthLogger.log("auto-retry scheduled in \(Int(Self.autoRetryDelay.components.seconds))s — \(self.unfinishedCount) unread (\(self.pendingICloudCount) pending iCloud)")
        armAutoRetry(after: Self.autoRetryDelay)
    }

    private func armAutoRetry(after delay: Duration) {
        indexAutoRetryDate = Date().addingTimeInterval(TimeInterval(delay.components.seconds))
        autoRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.indexAutoRetryDate = nil
            // A run in flight reschedules on its own when it ends.
            guard !self.isIndexRunActive else { return }
            // Network became disallowed mid-countdown (left Wi-Fi, no
            // cellular opt-in): keep the loop armed instead of dying —
            // `reindexIncompleteAssets` always streams, so firing it here
            // would burn cellular data against the user's setting.
            guard self.allowNetworkForIndexing() else {
                self.armAutoRetry(after: delay)
                return
            }
            self.resumeUnfinishedWork()
        }
    }

    /// Picks the cheapest run that can actually finish what's left.
    /// `reindexIncomplete` only reads `pendingICloud`/`error` rows, so it is the
    /// right (and much cheaper) choice only when every unread row is one of
    /// those. Anything else left — `pendingRead` placeholders from a run that was
    /// stopped part-way, version-bumped rows — needs the incremental run.
    private func resumeUnfinishedWork(manual: Bool = false) {
        if retryableCount >= unfinishedCount {
            reindexIncompleteAssets(manual: manual)
        } else {
            IndexTrafficMonitor.healthLogger.log("resuming with a full incremental run — \(self.unfinishedCount) unread, only \(self.retryableCount) of them iCloud/error retryable")
            startIndexing(manual: manual)
        }
    }

    /// Settings' "Continue Indexing": finish the reading that's left without
    /// throwing away what's already read. Counts are re-read first — Settings
    /// keeps its own copy and this decides which run to start from them.
    func continueIndexing() {
        cancelScheduledAutoRetry()
        refreshPausedState()
        guard unfinishedCount > 0 else { return }
        resumeUnfinishedWork(manual: true)
    }

    private func cancelScheduledAutoRetry() {
        autoRetryTask?.cancel()
        autoRetryTask = nil
        indexAutoRetryDate = nil
    }

    /// Recomputes the unread counts and `isIndexStreamingPaused` from the DB and
    /// the current network path. Cheap queries; called at run edges and on path
    /// changes (both rare).
    func refreshPausedState() {
        pendingICloudCount = (try? metadataStore.pendingICloudReadCount()) ?? 0
        unfinishedCount = (try? metadataStore.unfinishedCount()) ?? 0
        retryableCount = (try? metadataStore.retryableCount()) ?? 0
        isIndexStreamingPaused = networkStatus.isExpensivePath
            && !UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
            && pendingICloudCount > 0
    }

    /// Invoked (on the main actor) whenever the network path changes. Refreshes
    /// the paused state and, once back on an allowed path with iCloud work
    /// still pending, resumes streaming exactly those rows.
    private func handleNetworkChange() {
        let wasPaused = isIndexStreamingPaused
        // A path change while an auto-retry is counting down is exactly the
        // signal that iCloud might serve now (different Wi-Fi, cellular) —
        // skip the wait and retry immediately.
        let retryWasScheduled = indexAutoRetryDate != nil
        refreshPausedState()
        // Resume on a genuine paused → allowed transition, or a path change
        // during a retry countdown — but not on the plain first path update
        // of a healthy launch run (guarded below), so the launch index run
        // (a full incremental diff, not just the incomplete rows) isn't
        // pre-empted by an eager reindex.
        if (wasPaused || retryWasScheduled), !isIndexStreamingPaused, unfinishedCount > 0,
           !isIndexRunActive, allowNetworkForIndexing() {
            cancelScheduledAutoRetry()
            resumeUnfinishedWork()
        }
    }

    /// What the user asked for while a run was still in flight.
    private enum ManualIndexRun {
        case fullReindex
        case incremental
        case incomplete
    }

    /// Set while cancelling the run a tap preempted, so the completion starts
    /// what the user actually asked for. Survives `hasCancelledIndexRun` (it is
    /// checked before that guard) — the cancel here is ours, not the user's.
    @ObservationIgnored private var pendingManualRun: ManualIndexRun?

    /// Acknowledges a tap that arrived mid-run: stop the current run and hold the
    /// request until the pipeline is free.
    ///
    /// The indicator is turned **on optimistically**, because the honest wait is
    /// not short: `cancel()` stops new reads being spawned but never kills reads
    /// in flight, and an iCloud read can sit on the 8 s stall watchdog. Without
    /// this the user tapped Re-index and the screen sat unchanged for seconds
    /// (or, when the request was silently dropped, forever).
    private func enqueueManualRun(_ request: ManualIndexRun) {
        // A tap that lands on the reentrancy guard used to leave no trace at all,
        // which is exactly what made a stuck run so hard to tell apart from a
        // network fault: the buttons greyed out and the log stayed empty.
        IndexTrafficMonitor.health("manual run queued behind the run in flight: \(request)")
        pendingManualRun = request
        cancelIndexing()
        isIndexing = true
        isManualIndexRun = true
    }

    private func startManualRun(_ request: ManualIndexRun) {
        switch request {
        case .fullReindex: startIndexing(fullReindex: true, manual: true)
        case .incremental: startIndexing(manual: true)
        case .incomplete: reindexIncompleteAssets(manual: true)
        }
    }

    /// "Retry Now" action from the auto-retry card: skips the countdown and
    /// tries the incomplete iCloud reads again *now*. A (futile) run still
    /// walking is preempted by `reindexIncompleteAssets` itself.
    func retryIncompleteAssets() {
        cancelScheduledAutoRetry()
        reindexIncompleteAssets(manual: true)
    }

    /// "Use Cellular" action from the paused/stalled indicator: opts into
    /// cellular indexing and resumes now. A futile Wi-Fi run in flight is
    /// preempted by the manual start paths themselves.
    func resumeIndexingOverCellular() {
        UserDefaults.standard.set(true, forKey: SettingsKeys.allowCellularIndexing)
        refreshPausedState()
        guard unfinishedCount > 0 else { return }
        resumeUnfinishedWork(manual: true)
    }

    /// Once a second, snapshots the traffic counter and the network path;
    /// the byte delta between ticks is the displayed download speed.
    private func startNetworkSampling(allowsNetwork: @escaping @Sendable () -> Bool) -> Task<Void, Never> {
        let networkStatus = self.networkStatus
        let indexTraffic = self.indexTraffic
        return Task {
            var previousBytes: Int64 = 0
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                guard !Task.isCancelled else { break }
                // Cancelled runs unwind with their UI already cleared; keep the
                // sampler quiet so it can't repaint the status it just lost.
                guard !self.hasCancelledIndexRun else { continue }
                let total = indexTraffic.totalBytes
                let speed = max(0, total - previousBytes)
                self.indexNetworkStatus = IndexNetworkStatus(
                    connection: networkStatus.connectionType,
                    bytesDownloaded: total,
                    bytesPerSecond: speed,
                    isNetworkAllowed: allowsNetwork()
                )
                let thermalState = ProcessInfo.processInfo.thermalState
                let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self.indexDiagnostics = IndexDiagnostics(
                    thermalState: thermalState,
                    readConcurrency: IndexPipeline.readConcurrency(thermal: thermalState, isLowPowerMode: isLowPowerMode),
                    isLowPowerMode: isLowPowerMode,
                    networkReadsStarted: indexTraffic.networkReadsStarted,
                    networkReadsInFlight: indexTraffic.networkReadsInFlight,
                    stallCount: indexTraffic.stallCount,
                    breakerCooldownRemaining: indexTraffic.breakerCooldownRemaining
                )
                self.updateThroughput()
                // Health snapshot every 10 s — one line correlating progress,
                // traffic, breaker, and thermal state, on the same category
                // as the monitor's stall/trip events. Replaces the old
                // per-second "net sample" debug spam.
                if tick % 10 == 0, let diagnostics = self.indexDiagnostics {
                    let progress = self.indexProgress.map { "\($0.processed)/\($0.total)" } ?? "-"
                    // Which fallback is answering, on the 10 s tick as well as
                    // per batch: at iCloud speeds a batch line can be ten
                    // minutes apart, far too slow to judge a change by.
                    let mix = ExifReader.currentMetrics
                    IndexTrafficMonitor.health(
                        "reads: localOriginal \(mix.viaLocalOriginal), localDerivative \(mix.viaLocalDerivative), netOriginal \(mix.viaNetwork)"
                    )
                    IndexTrafficMonitor.health(
                        "health: \(progress) · \(networkStatus.connectionType.displayName) \(speed) B/s, total \(total) B · \(diagnostics.iCloudLine) · \(diagnostics.thermalLine) · allowNetwork \(allowsNetwork())"
                    )
                }
                previousBytes = total
            }
        }
    }

    /// Cancels the run and clears the indexing UI **at once**. The pipeline
    /// itself takes seconds to unwind — up to 12 reads are in flight, each with
    /// its own stall window, and the end-of-run grid reload follows — so waiting
    /// for it left the spinner and progress up long after the tap, reading as an
    /// ignored Cancel. The tail of the run keeps going in the background: rows
    /// already read are still saved and the grid still reloads when it lands.
    func cancelIndexing() {
        hasCancelledIndexRun = true
        isIndexing = false
        isManualIndexRun = false
        indexProgress = nil
        indexThroughput = nil
        indexNetworkStatus = nil
        indexDiagnostics = nil
        let pipeline = self.pipeline
        Task { await pipeline.cancel() }
        // The cancel above may never land. Guarantee the latch is released so a
        // preempting tap can't be queued behind a run that never ends.
        armRunUnwindWatchdog()
    }

    /// Reacts to Low Power Mode / charging changes (from `PowerMonitor`):
    /// entering LPM stops any running index; connecting a charger while in LPM
    /// auto-resumes it. The user may always start indexing by hand in LPM.
    private func handlePowerChange(lowPower: Bool, charging: Bool) {
        let enteredLowPower = lowPower && !isLowPowerMode
        let pluggedIn = charging && !wasCharging
        isLowPowerMode = lowPower
        wasCharging = charging

        if enteredLowPower, isIndexRunActive {
            cancelIndexing()
        } else if pluggedIn, lowPower, !isIndexRunActive {
            resumeIndexingForCharger()
        }
    }

    // MARK: Deletion

    /// Deletes the given assets via PhotoKit (system shows its own confirm
    /// dialog), then syncs the local index and in-memory state.
    /// Throws `PHPhotosError.userCancelled` if the user cancels.
    func deleteAssets(ids: Set<String>) async throws {
        let assets = PhotoLibraryService.fetchAssets(ids: Array(ids))
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        // PhotoKit is the source of truth; prune the DB rows right away so
        // the grid doesn't show stale entries until the next index run.
        try? metadataStore.deleteAssets(ids: Array(ids))
        items.removeAll { ids.contains($0.assetId) }
        // Indexes shifted; rebuild the id list (drops cached chunks). No
        // contentGeneration bump — the user should keep their scroll spot.
        assetCache.replaceKeys(items.map(\.assetId))
    }

    // MARK: Favorites

    /// DB only — slim grid rows carry no favorite flag (the grid never
    /// rendered it; favorites filtering is query-side).
    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }
}

// MARK: PhotoBrowsingSource

extension LibraryModel: PhotoBrowsingSource {
    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func index(of assetId: String) -> Int? {
        items.firstIndex { $0.assetId == assetId }
    }

    func deleteAsset(id: String) async throws {
        try await deleteAssets(ids: [id])
    }

    /// Badge fields for one tile, fetched on display (grid cells call this
    /// while an index run fills the DB, instead of the whole grid reloading
    /// per indexed photo). Final answers are cached; rows still pending are
    /// retried on the next display. Returns nil when there is nothing (yet)
    /// to show.
    func lazyBadgeItem(assetId: String) async -> LibraryGridItem? {
        if let cached = badgeCache.cachedEntry(for: assetId) {
            if case .badge(let item) = cached { return item }
            return nil
        }
        let libraryQueries = self.libraryQueries
        let row = await Task.detached(priority: .utility) {
            (try? libraryQueries.metadata(assetId: assetId)) ?? nil
        }.value
        return badgeCache.record(row, assetId: assetId)
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        if let row = (try? libraryQueries.metadata(assetId: assetId)) ?? nil {
            return row
        }
        // Not indexed yet (PhotoKit fast path): synthesize PhotoKit-only
        // metadata so the detail viewer still shows favorite/share/info
        // chrome and Compare keeps the photo instead of silently dropping it.
        return PhotoLibraryService.fetchAssets(ids: [assetId]).first
            .map { PhotoMetadata.placeholder(for: $0) }
    }

    func asset(for assetId: String) -> PHAsset? {
        PhotoLibraryService.fetchAssets(ids: [assetId]).first
    }

    /// Whole library is loaded as slim rows — nothing to page.
    func loadNextPageIfNeeded(currentIndex: Int) {}

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        // Persisted to the DB; `metadata(for:)` re-reads it on the next refresh.
        await pipeline.indexSingle(assetId: assetId)
    }
}
