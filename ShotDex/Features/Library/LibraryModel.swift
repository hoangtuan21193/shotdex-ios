import Foundation
import Photos
import SwiftUI
import os

/// Index speed and ETA, derived from progress samples over the current run.
struct IndexThroughput: Equatable {
    /// Photos processed per minute, averaged over the run so far.
    let photosPerMinute: Double
    /// Estimated time until the run finishes; nil until estimable.
    let remaining: Duration?

    var rateText: String {
        "\(Int(photosPerMinute.rounded())) photos/min"
    }

    var remainingText: String? {
        remaining.map(Self.format)
    }

    /// e.g. "2 hours remaining", "1 hr 20 min remaining", "45 min remaining".
    static func format(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        if total < 60 { return "less than a minute remaining" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 1 {
            if minutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
            }
            return "\(hours) hr \(minutes) min remaining"
        }
        return "\(minutes) min remaining"
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

    private(set) var isIndexing = false
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

    init(dependencies: AppDependencies) {
        self.libraryQueries = dependencies.libraryQueries
        self.filterSuggestions = dependencies.filterSuggestions
        self.metadataStore = dependencies.metadataStore
        self.pipeline = dependencies.indexPipeline
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
        }
    }

    /// Autosuggest source for search: known camera + lens names.
    func suggestions(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        var result: [String] = []
        result.reserveCapacity(8)
        for values in [availableBodies, availableLenses, availableBrands] {
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

    /// Entry point for PhotoKit library-change notifications. Outside a run,
    /// behaves like the old inline handler (reload so new photos appear on
    /// the fast path, then index them). Mid-run, defers to the end-of-run
    /// reload: streaming iCloud originals fires a change per downloaded
    /// asset, and reloading the whole grid per photo is what made the grid
    /// flicker and the device heat up.
    func libraryDidChange() {
        guard !isIndexing else {
            pendingLibraryChange = true
            return
        }
        reload()
        startIndexing()
    }

    func startIndexing(fullReindex: Bool = false, manual: Bool = false) {
        guard !isIndexing else { return }
        // No automatic indexing in Low Power Mode. The user can still start it
        // by hand (`manual`), and a charger connecting resumes it through
        // `resumeIndexingForCharger` (which drives `runPipeline` directly).
        guard manual || !isLowPowerMode else { return }
        let allowNetwork = allowNetworkForIndexing
        runPipeline(allowsNetwork: allowNetwork, manual: manual) { pipeline, onProgress in
            try await pipeline.run(fullReindex: fullReindex, allowNetwork: allowNetwork, onProgress: onProgress)
        }
    }

    /// Re-reads only the assets stuck at `pendingICloud`/`error`
    /// (Settings → Re-index Incomplete Photos). Always uses the network.
    func reindexIncompleteAssets(manual: Bool = false) {
        guard !isIndexing else { return }
        guard manual || !isLowPowerMode else { return }
        runPipeline(allowsNetwork: { true }, manual: manual) { pipeline, onProgress in
            try await pipeline.reindexIncomplete(onProgress: onProgress)
        }
    }

    /// A charger connected while in Low Power Mode — the one automatic resume
    /// allowed there. Runs an incremental pass without keeping the screen awake
    /// (`manual: false`), bypassing the LPM start-guard by driving the pipeline
    /// directly.
    private func resumeIndexingForCharger() {
        guard !isIndexing else { return }
        let allowNetwork = allowNetworkForIndexing
        runPipeline(allowsNetwork: allowNetwork, manual: false) { pipeline, onProgress in
            try await pipeline.run(fullReindex: false, allowNetwork: allowNetwork, onProgress: onProgress)
        }
    }

    /// `allowsNetwork` mirrors what the pipeline run may do, so the status
    /// line can show speed/total (even at zero) whenever streaming is possible.
    private func runPipeline(
        allowsNetwork: @escaping @Sendable () -> Bool,
        manual: Bool,
        _ operation: @escaping @Sendable (IndexPipeline, @escaping @Sendable (IndexProgress) -> Void) async throws -> IndexRunSummary
    ) {
        isIndexing = true
        isManualIndexRun = manual
        pendingLibraryChange = false
        indexProgress = nil
        indexThroughput = nil
        indexRunStart = nil
        cancelScheduledAutoRetry()
        let pipeline = self.pipeline
        let networkStatus = self.networkStatus
        // .utility: parse/compose/DB writes and PhotoKit XPC servicing must
        // not compete with interactive image loads at UI priority.
        Task(priority: .utility) {
            // Resolve the real network path before showing status, so the
            // indicator reflects Wi-Fi/cellular from the first frame rather
            // than `NWPathMonitor`'s metered-until-first-update default.
            await networkStatus.awaitInitialPath()
            self.indexTraffic.reset()
            IndexTrafficMonitor.healthLogger.log(
                "run start: connection \(networkStatus.connectionType.displayName, privacy: .public), expensivePath \(networkStatus.isExpensivePath), allowCellularSetting \(UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)), allowNetwork \(allowsNetwork())"
            )
            self.indexNetworkStatus = IndexNetworkStatus(
                connection: networkStatus.connectionType,
                bytesDownloaded: 0,
                bytesPerSecond: nil,
                isNetworkAllowed: allowsNetwork()
            )
            self.refreshPausedState()
            let samplingTask = self.startNetworkSampling(allowsNetwork: allowsNetwork)
            // Keeps the run alive through a brief trip to the background;
            // on expiry it cancels cleanly and hands off to the BGProcessingTask.
            self.backgroundIndex.beginRunAssertion()
            defer {
                samplingTask.cancel()
                self.isIndexing = false
                self.isManualIndexRun = false
                self.indexProgress = nil
                self.indexThroughput = nil
                self.indexNetworkStatus = nil
                self.indexDiagnostics = nil
                self.backgroundIndex.endRunAssertion()
                // One-tap Retry: the cancelled run has now stopped (isIndexing
                // cleared above), so a fresh incomplete pass can start. Next
                // tick, so this Task fully unwinds first.
                if self.pendingRetryAfterCancel {
                    self.pendingRetryAfterCancel = false
                    // User-initiated retry — allowed even in Low Power Mode.
                    Task { @MainActor in self.reindexIncompleteAssets(manual: true) }
                } else if self.pendingLibraryChange {
                    // A library change arrived mid-run (deferred by
                    // libraryDidChange). The end-of-run reload below has
                    // already re-fetched the grid; one incremental run picks
                    // up whatever the change added. Next tick, so this Task
                    // fully unwinds first.
                    self.pendingLibraryChange = false
                    Task { @MainActor in self.startIndexing() }
                }
            }
            var summary: IndexRunSummary?
            do {
                summary = try await operation(pipeline) { progress in
                    Task { @MainActor in
                        self.indexProgress = progress
                    }
                }
            } catch {
                self.loadError = "Indexing failed."
            }
            self.reload()
            self.refreshFilterOptions(force: true)
            // A local-only run leaves iCloud-only photos pending; surface a
            // persistent "waiting for Wi-Fi" state when they can't stream now.
            self.refreshPausedState()
            self.scheduleAutoRetryIfNeeded(after: summary)
        }
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

    // MARK: Auto-retry
    //
    // A run can end with photos still `pendingICloud` on an allowed network
    // (iCloud auth dead — accountsd Code=7 — or a Wi-Fi that can't serve
    // originals). Indexing must never sit dead in that state: the model
    // schedules an automatic `reindexIncomplete` every 30 s, and the UI shows
    // a small "retrying in Ns" card instead of the old dead-end
    // "iCloud not downloading over Wi-Fi" banner. A fixed interval, no
    // backoff — a failed attempt is cheap (the breaker trips within ~12
    // reads), and picking iCloud up seconds after it recovers matters more.

    static let autoRetryDelay: Duration = .seconds(30)

    /// When the next automatic retry fires — drives the countdown card.
    /// nil when no retry is scheduled.
    private(set) var indexAutoRetryDate: Date?
    @ObservationIgnored private var autoRetryTask: Task<Void, Never>?

    /// Called at the end of every uncancelled run. Schedules a follow-up
    /// incomplete pass when iCloud work remains and the network is allowed.
    private func scheduleAutoRetryIfNeeded(after summary: IndexRunSummary?) {
        guard let summary, !summary.wasCancelled else { return }
        guard pendingICloudCount > 0 else { return }
        // Metered cellular without opt-in: the paused card owns this state.
        guard allowNetworkForIndexing() else { return }
        IndexTrafficMonitor.healthLogger.log("auto-retry scheduled in \(Int(Self.autoRetryDelay.components.seconds))s — \(self.pendingICloudCount) photos still pending iCloud")
        armAutoRetry(after: Self.autoRetryDelay)
    }

    private func armAutoRetry(after delay: Duration) {
        indexAutoRetryDate = Date().addingTimeInterval(TimeInterval(delay.components.seconds))
        autoRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.indexAutoRetryDate = nil
            // A run in flight reschedules on its own when it ends.
            guard !self.isIndexing else { return }
            // Network became disallowed mid-countdown (left Wi-Fi, no
            // cellular opt-in): keep the loop armed instead of dying —
            // `reindexIncompleteAssets` always streams, so firing it here
            // would burn cellular data against the user's setting.
            guard self.allowNetworkForIndexing() else {
                self.armAutoRetry(after: delay)
                return
            }
            self.reindexIncompleteAssets()
        }
    }

    private func cancelScheduledAutoRetry() {
        autoRetryTask?.cancel()
        autoRetryTask = nil
        indexAutoRetryDate = nil
    }

    /// Recomputes `pendingICloudCount`/`isIndexStreamingPaused` from the DB and
    /// the current network path. Cheap query; called at run edges and on path
    /// changes (both rare).
    func refreshPausedState() {
        pendingICloudCount = (try? metadataStore.pendingICloudReadCount()) ?? 0
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
        if (wasPaused || retryWasScheduled), !isIndexStreamingPaused, pendingICloudCount > 0,
           !isIndexing, allowNetworkForIndexing() {
            cancelScheduledAutoRetry()
            reindexIncompleteAssets()
        }
    }

    /// Set while cancelling a stalled run so the completion can immediately
    /// kick off a fresh `reindexIncomplete` (a one-tap "Retry").
    @ObservationIgnored private var pendingRetryAfterCancel = false

    /// "Retry Now" action from the auto-retry card: skips the countdown and
    /// tries the incomplete iCloud reads again *now*. If a (futile) run is
    /// still walking, cancel it first and resume once it has stopped — the
    /// `isIndexing` guard would otherwise swallow the retry.
    func retryIncompleteAssets() {
        cancelScheduledAutoRetry()
        if isIndexing {
            pendingRetryAfterCancel = true
            cancelIndexing()
        } else {
            reindexIncompleteAssets(manual: true)
        }
    }

    /// "Use Cellular" action from the paused/stalled indicator: opts into
    /// cellular indexing. A futile Wi-Fi run in flight is cancelled so the
    /// cellular retry (on the next path change, or manual Retry) isn't blocked
    /// by the `isIndexing` guard; when nothing is running it resumes now.
    func resumeIndexingOverCellular() {
        UserDefaults.standard.set(true, forKey: SettingsKeys.allowCellularIndexing)
        if isIndexing {
            // Don't restart here — isIndexing is still true (cancel is async);
            // the resume happens when the user reaches cellular (handleNetwork
            // change) or taps Retry once the run has stopped.
            cancelIndexing()
        }
        refreshPausedState()
        if pendingICloudCount > 0, !isIndexing {
            reindexIncompleteAssets(manual: true)
        }
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
                    IndexTrafficMonitor.healthLogger.log(
                        "health: \(progress, privacy: .public) · \(networkStatus.connectionType.displayName, privacy: .public) \(speed) B/s, total \(total) B · \(diagnostics.iCloudLine, privacy: .public) · \(diagnostics.thermalLine, privacy: .public) · allowNetwork \(allowsNetwork())"
                    )
                }
                previousBytes = total
            }
        }
    }

    func cancelIndexing() {
        let pipeline = self.pipeline
        Task { await pipeline.cancel() }
    }

    /// Reacts to Low Power Mode / charging changes (from `PowerMonitor`):
    /// entering LPM stops any running index; connecting a charger while in LPM
    /// auto-resumes it. The user may always start indexing by hand in LPM.
    private func handlePowerChange(lowPower: Bool, charging: Bool) {
        let enteredLowPower = lowPower && !isLowPowerMode
        let pluggedIn = charging && !wasCharging
        isLowPowerMode = lowPower
        wasCharging = charging

        if enteredLowPower, isIndexing {
            cancelIndexing()
        } else if pluggedIn, lowPower, !isIndexing {
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
