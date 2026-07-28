import Foundation
import Photos
import os

/// Progress snapshot published while indexing.
struct IndexProgress: Equatable, Sendable {
    var processed: Int
    var total: Int
    /// Original filenames currently being read by the EXIF pass (up to
    /// `readConcurrency`; empty during skip-scans and at batch boundaries).
    /// Shown by the expanded indexing dialog so slow iCloud batches still
    /// visibly move.
    var activeItems: [String] = []

    var fraction: Double { total > 0 ? Double(processed) / Double(total) : 0 }
    var percent: Int { Int((fraction * 100).rounded(.down)) }
}

/// Result of one indexing run.
struct IndexRunSummary: Equatable, Sendable {
    var indexed: Int
    var skipped: Int
    var pendingICloud: Int
    var failed: Int
    var deleted: Int
    var wasCancelled: Bool
    /// The actor refused this run because another one already owns it — the
    /// foreground/background collision (`BGProcessingTask` drives the pipeline
    /// directly, since a background launch has no UI to drive it through).
    /// Without this flag the refusal is indistinguishable from "ran, found
    /// nothing": callers concluded the library was done and stopped, while tens
    /// of thousands of rows were still unread.
    var didNotStart = false
}

/// Background metadata indexer, two phases per run:
///
/// - **Fast pass**: rows for brand-new assets from PHAsset facts alone
///   (dates, dimensions, GPS, favorite — no per-asset XPC), so the grid is
///   usable within seconds. Rows carry `exifStatus = pendingRead`.
/// - **EXIF pass**: walks the library newest-first in batches of 200, streams
///   EXIF via ImageIO, composes full rows, and writes them to GRDB.
///
/// Supports cancel, resume (cursor persisted per batch), incremental diff
/// by modificationDate, and pendingICloud re-runs.
actor IndexPipeline {
    static let batchSize = 200
    /// After this many consecutive failed reads a row is written as `noExif`
    /// instead of `error`, so an unreadable original (corrupt/truncated file,
    /// or one PhotoKit won't serve) stops being re-enqueued on every run and
    /// simply appears in the library without camera metadata. Only `error`
    /// counts toward this; `pendingICloud` retries indefinitely (a genuine
    /// cloud original that just hasn't downloaded yet).
    static let maxReadAttempts = 5
    /// EXIF reads within a batch run concurrently — indexing time is
    /// dominated by per-asset PhotoKit round-trips, not CPU.
    static let readConcurrency = 12

    /// Target reader fan-out from thermal state + Low Power Mode. A long
    /// EXIF pass (12-way PhotoKit XPC + ImageIO) can heat the device;
    /// stepping the fan-out down per thermal level trades speed for
    /// temperature instead of letting the run drive the device to critical.
    /// Low Power Mode caps the fan-out at the `.fair` level; thermal backoff
    /// still lowers it further. Re-sampled at every read completion, so the
    /// fan-out shrinks/grows mid-batch — in-flight reads are never killed,
    /// they just aren't replaced while over target.
    static func readConcurrency(thermal: ProcessInfo.ThermalState, isLowPowerMode: Bool) -> Int {
        let thermalTarget: Int
        switch thermal {
        case .nominal: thermalTarget = readConcurrency
        case .fair: thermalTarget = readConcurrency / 2
        case .serious: thermalTarget = readConcurrency / 4
        case .critical: thermalTarget = 2
        @unknown default: thermalTarget = readConcurrency / 4
        }
        let capped = isLowPowerMode ? min(thermalTarget, readConcurrency / 2) : thermalTarget
        return max(capped, 1)
    }

    /// Breather between EXIF batches so the SoC duty-cycles instead of
    /// running flat-out. Low Power Mode forces a minimum pause even when
    /// thermally nominal. Skipped before the first batch of a run.
    static func interBatchPause(thermal: ProcessInfo.ThermalState, isLowPowerMode: Bool) -> Duration {
        let thermalPause: Duration
        switch thermal {
        case .nominal: thermalPause = .zero
        case .fair: thermalPause = .seconds(3)
        case .serious, .critical: thermalPause = .seconds(10)
        @unknown default: thermalPause = .seconds(10)
        }
        return isLowPowerMode ? max(thermalPause, .seconds(3)) : thermalPause
    }

    /// How many new reads to spawn at a refill opportunity. Over target →
    /// zero (fan-out decays as in-flight reads drain); under target → the
    /// gap, clamped to what's left. Always ≥ 1 when nothing is in flight
    /// and work remains, so the task group's drain loop can never starve
    /// and the batch's contiguous-prefix/cursor invariant holds.
    static func refillCount(inFlight: Int, target: Int, remaining: Int) -> Int {
        guard remaining > 0 else { return 0 }
        let gap = max(0, target - inFlight)
        if gap == 0 && inFlight == 0 { return 1 }
        return min(gap, remaining)
    }
    /// Fast-pass rows per transaction; no EXIF is read, so batches can be
    /// much larger than EXIF batches.
    static let fastPassBatchSize = 1000

    /// Above this many unfinished rows the persistent-change fast path stops
    /// being fast: it has to fetch and sort every unfinished id through
    /// PhotoKit, which cost **69.7 s** for 42.5k rows on the measured library,
    /// against 6.8 s for the full walk's straight scan of 55k assets. Past the
    /// threshold the walk wins outright, so hand the run over to it.
    static let maxUnfinishedForChangeHistory = 5_000

    /// While planning takes this long or more, the run is doing invisible work.
    /// Above this many candidates the fast path signals work *before* the
    /// PhotoKit fetch, so the indicator appears instead of the app looking dead
    /// (measured: 70 s of silent planning with 42.5k unfinished rows).
    static let planningWorkSignalThreshold = 200

    /// Returned when the actor refuses a run because another one owns it. Zero
    /// counts, `didNotStart` set — never mistakable for a completed no-op run.
    static let notStartedSummary = IndexRunSummary(
        indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0,
        wasCancelled: false, didNotStart: true
    )

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "index")
    private static let signposter = OSSignposter(subsystem: "com.hoangtuan.shotdex", category: "index")

    private let metadataStore: MetadataStore
    private let exifReader: ExifReader
    private let sensorDatabaseLoader: SensorDatabaseLoader
    /// Interactive-demand signal from the fullscreen viewer; the EXIF pass
    /// stops spawning reads while it is held. nil (tests) never pauses.
    private let interactionGate: IndexInteractionGate?
    /// Injected so tests can drive thermal/power transitions; production
    /// defaults read ProcessInfo. Sampled at read completions and batch
    /// boundaries — no notification observers needed.
    private let thermalState: @Sendable () -> ProcessInfo.ThermalState
    private let isLowPowerMode: @Sendable () -> Bool

    private var isCancelled = false
    private var isRunning = false

    init(metadataStore: MetadataStore, exifReader: ExifReader = ExifReader(),
         sensorDatabaseLoader: SensorDatabaseLoader = SensorDatabaseLoader(),
         interactionGate: IndexInteractionGate? = nil,
         thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
         isLowPowerMode: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }) {
        self.metadataStore = metadataStore
        self.exifReader = exifReader
        self.sensorDatabaseLoader = sensorDatabaseLoader
        self.interactionGate = interactionGate
        self.thermalState = thermalState
        self.isLowPowerMode = isLowPowerMode
    }

    func cancel() {
        isCancelled = true
    }

    /// Suspends while an interactive photo load holds the gate — the tapped
    /// photo's iCloud download gets the bandwidth. In-flight reads drain on
    /// their own (header early-stop / 8 s stall watchdog); no new PhotoKit
    /// requests start. The actor stays free while sleeping, so `cancel()`
    /// still lands mid-pause and exits the wait within one poll tick.
    private func waitWhileInteractionPaused() async {
        guard let interactionGate, interactionGate.shouldPauseIndexing else { return }
        Self.logger.log("EXIF pass paused: interactive photo load in progress")
        let signpostState = Self.signposter.beginInterval("interactivePause")
        defer { Self.signposter.endInterval("interactivePause", signpostState) }
        while !isCancelled && interactionGate.shouldPauseIndexing {
            try? await Task.sleep(for: .milliseconds(250))
        }
        Self.logger.log("EXIF pass resumed")
    }

    /// Suspends while the device is thermally critical — no new reads spawn
    /// until it cools to serious or better (reduced concurrency then takes
    /// over). Same shape as `waitWhileInteractionPaused`: the actor stays
    /// free while sleeping, so `cancel()` lands within one poll tick.
    private func waitWhileThermalCritical() async {
        guard thermalState() == .critical else { return }
        Self.logger.log("EXIF pass paused: device thermally critical")
        let signpostState = Self.signposter.beginInterval("thermalPause")
        defer { Self.signposter.endInterval("thermalPause", signpostState) }
        while !isCancelled && thermalState() == .critical {
            try? await Task.sleep(for: .seconds(1))
        }
        Self.logger.log("EXIF pass resumed after thermal pause")
    }

    /// Suspends while the iCloud circuit breaker is cooling down.
    ///
    /// Without this the pass keeps consuming assets during the 30 s cooldown:
    /// each one costs only a failed local read plus an instant breaker
    /// rejection (~40 ms × 12 readers ≈ 300 assets/s), so a single cooldown
    /// marks ~9 000 rows `pendingICloud` **without ever asking iCloud**. On a
    /// library whose originals live in iCloud that burns through the whole
    /// remaining library in a couple of cooldowns — the run then "finishes"
    /// having read almost nothing, which is exactly the observed
    /// works-then-dies-then-retries cycle. Waiting instead costs 30 s and keeps
    /// every one of those assets for the probe that follows.
    ///
    /// Only waits while the network is actually allowed and is the thing the
    /// run needs; same 1 s-tick shape as the thermal wait, so `cancel()` lands
    /// within one tick.
    /// Each wait is bounded — the breaker half-opens on its own after its
    /// cooldown — but a dead iCloud can re-trip indefinitely, and a run that
    /// pauses forever holds the "Indexing…" indicator forever and never reaches
    /// the end-of-run auto-retry (whose card at least shows a countdown). So the
    /// pauses are capped per run: past the cap the pass walks on as it used to,
    /// finishes, and hands off to `LibraryModel`'s 30 s retry loop.
    static let maxBreakerPausesPerRun = 3

    private var breakerPauses = 0

    private func waitWhileNetworkBreakerTripped(allowNetwork: Bool) async {
        guard allowNetwork, exifReader.trafficMonitor?.isNetworkTripped == true else { return }
        guard breakerPauses < Self.maxBreakerPausesPerRun else { return }
        breakerPauses += 1
        let signpostState = Self.signposter.beginInterval("breakerPause")
        defer { Self.signposter.endInterval("breakerPause", signpostState) }
        IndexTrafficMonitor.health(
            "EXIF pass paused (\(breakerPauses)/\(Self.maxBreakerPausesPerRun)): iCloud breaker cooling down"
        )
        while !isCancelled, exifReader.trafficMonitor?.isNetworkTripped == true {
            try? await Task.sleep(for: .seconds(1))
        }
        IndexTrafficMonitor.health("EXIF pass resumed: breaker half-open, probing iCloud")
    }

    /// Duty-cycle sleep between EXIF batches, scaled by thermal/power state
    /// (`interBatchPause`). Same shape as the other waits: 250 ms ticks with
    /// the actor free, so `cancel()` lands within one tick. State is
    /// re-sampled per call, never latched.
    private func pauseBetweenBatches() async {
        let pause = Self.interBatchPause(thermal: thermalState(), isLowPowerMode: isLowPowerMode())
        guard pause > .zero else { return }
        let signpostState = Self.signposter.beginInterval("batchBreather")
        defer { Self.signposter.endInterval("batchBreather", signpostState) }
        let clock = ContinuousClock()
        let deadline = clock.now + pause
        while !isCancelled && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Builds a composer from the current sensor database + custom mappings.
    private func makeComposer() -> MetadataComposer {
        MetadataComposer(
            sensorLookup: SensorLookup(
                records: (try? sensorDatabaseLoader.loadRecords()) ?? [],
                customMappings: (try? metadataStore.customMappings()) ?? []
            )
        )
    }

    /// Reads and persists EXIF for **one** asset, allowing iCloud streaming —
    /// called by the detail viewer once a full image has downloaded so a
    /// previously `pendingICloud`/`error`/placeholder photo fills in and never
    /// needs re-downloading. Independent of `run()` (no `isRunning` gate, GRDB
    /// serializes the write) and it never advances the resume cursor.
    ///
    /// Returns the fresh row, or nil when the row is already complete
    /// (`indexed`/`noExif` — left untouched), the asset is missing, or the read
    /// still couldn't reach the original (leaves the existing status as-is).
    func indexSingle(assetId: String) async -> PhotoMetadata? {
        if let state = try? metadataStore.assetState(assetId: assetId),
           let status = ExifStatus(rawValue: state.exifStatus),
           status == .indexed || status == .noExif {
            return nil
        }
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first else { return nil }
        let composer = makeComposer()
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = ExifReader.photoResource(among: resources)
        // Facts (size/filename) fall back to any resource so videos — which
        // have no photo resource — still record them.
        let factsResource = resource ?? resources.first
        let fileSize = (factsResource?.value(forKey: "fileSize") as? NSNumber)?.intValue
        let info = Self.assetInfo(for: asset, fileSize: fileSize, originalFilename: factsResource?.originalFilename)

        let record: PhotoMetadata
        if Self.shouldSkipExifRead(mediaType: asset.mediaType.rawValue, mediaSubtypes: asset.mediaSubtypes) {
            record = composer.compose(asset: info, exif: .empty, exifStatus: .indexed)   // → noExif
        } else {
            switch await exifReader.readExif(for: asset, resource: resource, allowNetwork: true) {
            case .success(let exif):
                record = composer.compose(asset: info, exif: exif, exifStatus: .indexed)
            case .unreadable:
                // Viewer downloaded the full image but ImageIO can't parse it —
                // deterministically no readable EXIF. Resolve the row to
                // `noExif` (indexed + empty EXIF) so it stops being pending.
                record = composer.compose(asset: info, exif: .empty, exifStatus: .indexed)
            case .pendingICloud, .failure:
                // Couldn't obtain the bytes (still in iCloud / network failed /
                // hard error) — don't clobber the existing row; retry later.
                return nil
            }
        }
        try? metadataStore.upsert(record)
        return record
    }

    /// Whether a run is currently in flight (used by background scheduling).
    var isActive: Bool { isRunning }

    /// Decides whether an asset must be (re-)read. Pure — unit-tested.
    /// Incomplete reads (`error`, `pendingRead`, and `pendingICloud` when the
    /// network may be used) are re-enqueued even when the asset is unchanged.
    /// A row written by an older indexer build (`indexerVersion` below the
    /// current) is also re-read so newly-indexed fields backfill onto it.
    static func needsReindex(
        existing: IndexedAssetState?,
        currentModificationDate: Int?,
        allowNetworkRetry: Bool,
        currentIndexerVersion: Int = PhotoMetadata.currentIndexerVersion
    ) -> Bool {
        guard let existing else { return true }
        if existing.modificationDate != currentModificationDate { return true }
        if existing.indexerVersion < currentIndexerVersion { return true }
        switch ExifStatus(rawValue: existing.exifStatus) {
        case .indexed, .noExif: return false
        case .pendingRead: return true
        case .pendingICloud: return allowNetworkRetry
        case .error, nil: return true
        }
    }

    /// Assets whose file read is skipped and whose row goes straight to
    /// `noExif`: screenshots (never carry camera EXIF) and videos (indexed for
    /// browsing + counts, but ImageIO can't read them as photos). Pure —
    /// unit-tested.
    static func shouldSkipExifRead(
        mediaType: Int,
        mediaSubtypes: PHAssetMediaSubtype
    ) -> Bool {
        mediaType == PHAssetMediaType.video.rawValue
            || mediaSubtypes.contains(.photoScreenshot)
    }

    /// Runs a full or incremental pass over the library.
    /// - Parameters:
    ///   - fullReindex: ignore the incremental diff and re-read everything.
    ///   - allowNetwork: stream EXIF of iCloud-only originals (and retry
    ///     assets previously stuck at `pendingICloud`). Re-evaluated per
    ///     batch, never latched at run start: `NWPathMonitor` hasn't
    ///     delivered its first path update when a launch-triggered run
    ///     begins (it defaults to "expensive"), and the user can leave
    ///     Wi-Fi mid-run.
    ///   - onWorkFound: called once, the moment the run establishes that it has
    ///     real work (a row to write or an asset to read). A run that finds
    ///     nothing never calls it — that's what keeps the "Indexing…" indicator
    ///     off on a launch where the library is already fully indexed.
    ///   - onProgress: called when each asset read starts and completes,
    ///     throttled to ~5/s (EXIF pass only; the fast pass finishes within
    ///     seconds and stays on the indeterminate "Indexing…" display).
    @discardableResult
    func run(
        fullReindex: Bool = false,
        allowNetwork: @escaping @Sendable () -> Bool = { false },
        onWorkFound: @escaping @Sendable () -> Void = {},
        onProgress: @escaping @Sendable (IndexProgress) -> Void = { _ in }
    ) async throws -> IndexRunSummary {
        guard !isRunning else {
            IndexTrafficMonitor.health("run refused: another run owns the pipeline")
            return Self.notStartedSummary
        }
        isRunning = true
        isCancelled = false
        breakerPauses = 0
        defer { isRunning = false }

        let clock = ContinuousClock()
        let runStart = clock.now
        let timings = OSAllocatedUnfairLock(initialState: StageTotals())

        let composer = makeComposer()

        // Sampled *before* any diffing, and only persisted once the run
        // completes: a change landing mid-run is then replayed by the next run
        // rather than lost. Replaying a change already handled is harmless —
        // `needsReindex` skips rows that are complete and unchanged.
        let tokenAtStart = PHPhotoLibrary.shared().currentChangeToken

        // Preferred path: ask Photos what changed instead of walking the whole
        // library. Returns nil when the change history can't answer (no token
        // yet, or an expired one), which is what the full walk below is for.
        if !fullReindex,
           let summary = try await runFromPersistentChanges(
               composer: composer,
               allowNetwork: allowNetwork,
               timings: timings,
               tokenAtStart: tokenAtStart,
               clock: clock,
               onWorkFound: onWorkFound,
               onProgress: onProgress
           ) {
            return summary
        }

        var hasSignalledWork = false
        let signalWork = { [onWorkFound] in
            guard !hasSignalledWork else { return }
            hasSignalledWork = true
            onWorkFound()
        }

        // Rows already present — the fast pass must never overwrite them
        // (a full reindex still keeps old EXIF visible until re-read).
        var mark = clock.now
        let existingStates = try metadataStore.indexedAssetStates()
        let statesTime = clock.now - mark
        // Diff snapshot for the EXIF pass; fullReindex re-reads everything.
        let existing = fullReindex ? [:] : existingStates

        mark = clock.now
        let fetchResult = PHAsset.fetchAssets(with: Self.browsableFetchOptions())

        let total = fetchResult.count
        let fetchTime = clock.now - mark
        IndexTrafficMonitor.health(
            "run setup: \(total) assets, \(existingStates.count) rows — states \(Self.milliseconds(statesTime))ms, fetch \(Self.milliseconds(fetchTime))ms"
        )
        var summary = IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)

        // Phase 1 — fast pass over brand-new assets.
        try fastPass(
            fetchResult: fetchResult, existingStates: existingStates,
            composer: composer, clock: clock, onWorkFound: signalWork
        )

        // Phase 2 — EXIF enrichment.
        //
        // Progress is cumulative: `baseline` = assets already fully read
        // (`indexed`/`noExif`) before this run, `newlyDone` = assets read to
        // completion this run. The reported count is `baseline + newlyDone`,
        // so a resumed run continues from where the last one stopped instead
        // of restarting at zero. `fullReindex` re-reads everything, so it
        // starts from zero. Emitted once up front so the panel shows the true
        // starting point immediately (no jump, no apparent backward step).
        var baseline = fullReindex ? 0 : (try? metadataStore.completedCount()) ?? 0
        var newlyDone = 0
        onProgress(IndexProgress(processed: baseline, total: total))

        var seenAssetIds = Set<String>(minimumCapacity: total)
        var batch: [PHAsset] = []
        batch.reserveCapacity(Self.batchSize)

        // Split of the EXIF-pass loop's wall clock: `batchTime` is real read
        // work, the remainder is the incremental diff scan (materializing every
        // PHAsset and hashing it against `existing`). On a fully-indexed launch
        // the scan is the *whole* cost, so the two must be reported apart.
        var batchTime = Duration.zero
        var needsRead = 0

        var firstBatch = true
        func runBatch(_ assets: [PHAsset]) async throws {
            signalWork()
            let batchMark = clock.now
            defer { batchTime += clock.now - batchMark }
            // No breather before the first batch: a cool device starts
            // instantly and short incremental runs feel unchanged.
            if !firstBatch { await pauseBetweenBatches() }
            firstBatch = false
            await waitWhileInteractionPaused()
            let base = baseline + newlyDone
            let done = try await processBatch(assets, composer: composer, allowNetwork: allowNetwork(), timings: timings, summary: &summary) { done, item in
                onProgress(IndexProgress(processed: base + done, total: total, activeItems: item))
            }
            newlyDone += done
            onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        }

        let loopMark = clock.now
        for index in 0..<total {
            if isCancelled { break }
            let asset = fetchResult.object(at: index)
            seenAssetIds.insert(asset.localIdentifier)

            // Incremental diff: skip unchanged assets with a complete read.
            // Skipped assets are already counted in `baseline`, so they need
            // no per-asset emit (the up-front baseline covers them).
            if !fullReindex {
                let existingState = existing[asset.localIdentifier]
                let currentModified = asset.modificationDate.map { Int($0.timeIntervalSince1970) }
                if !Self.needsReindex(
                    existing: existingState,
                    currentModificationDate: currentModified,
                    allowNetworkRetry: allowNetwork()
                ) {
                    summary.skipped += 1
                    continue
                }
                // An edited asset that was already done is re-read this run:
                // drop it from the baseline so `newlyDone` re-counting it
                // keeps the total exact (never overshoots `total`).
                if let existingState,
                   let status = ExifStatus(rawValue: existingState.exifStatus),
                   status == .indexed || status == .noExif {
                    baseline -= 1
                }
            }

            needsRead += 1
            batch.append(asset)
            if batch.count == Self.batchSize {
                try await runBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty && !isCancelled {
            try await runBatch(batch)
        }

        IndexTrafficMonitor.health(
            "diff scan: \(needsRead) of \(total) need a read — scan \(Self.milliseconds((clock.now - loopMark) - batchTime))ms, batches \(Self.milliseconds(batchTime))ms"
        )

        // Remove rows for assets that vanished from the library
        // (only safe to compute after a full, uncancelled walk).
        if !isCancelled && !fullReindex {
            let deletedIds = existing.keys.filter { !seenAssetIds.contains($0) }
            if !deletedIds.isEmpty {
                signalWork()
                try metadataStore.deleteAssets(ids: deletedIds)
                summary.deleted = deletedIds.count
            }
        }

        summary.wasCancelled = isCancelled

        var state = try metadataStore.indexState()
        state.lastIndexedAt = Int(Date().timeIntervalSince1970)
        if !isCancelled {
            state.cursorAssetId = nil
            state.lastFullIndexAt = Int(Date().timeIntervalSince1970)
            // The walk just brought the DB into agreement with the library, so
            // the change history can take over from here: every later run reads
            // only what Photos reports as changed. Only ever set after an
            // uncancelled walk — a partial walk would let the next run skip
            // assets it never reached.
            state.changeToken = Self.archived(tokenAtStart)
        }
        try metadataStore.saveIndexState(state)

        onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        Self.logSummary("run", summary: summary, elapsed: clock.now - runStart, timings: timings.withLock { $0 })
        return summary
    }

    /// Re-reads only the assets whose EXIF is incomplete (`pendingICloud` or
    /// `error`), always allowing iCloud streaming — this action exists
    /// precisely to fetch what a local-only run couldn't.
    @discardableResult
    func reindexIncomplete(
        onWorkFound: @escaping @Sendable () -> Void = {},
        onProgress: @escaping @Sendable (IndexProgress) -> Void = { _ in }
    ) async throws -> IndexRunSummary {
        guard !isRunning else {
            IndexTrafficMonitor.health("reindexIncomplete refused: another run owns the pipeline")
            return Self.notStartedSummary
        }
        isRunning = true
        isCancelled = false
        breakerPauses = 0
        defer { isRunning = false }

        let clock = ContinuousClock()
        let runStart = clock.now
        let timings = OSAllocatedUnfairLock(initialState: StageTotals())

        let composer = makeComposer()
        let ids = try metadataStore.retryableAssetIds()
        var summary = IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return summary }
        onWorkFound()

        // Progress is cumulative against the whole library, matching `run()`:
        // the count climbs from what's already done toward the library total,
        // never the "1 of 97 retryable" view.
        let total = PHAsset.fetchAssets(with: Self.browsableFetchOptions()).count
        let baseline = (try? metadataStore.completedCount()) ?? 0
        var newlyDone = 0
        onProgress(IndexProgress(processed: baseline, total: total))

        var firstBatch = true
        for chunk in stride(from: 0, to: assets.count, by: Self.batchSize) {
            if isCancelled { break }
            if !firstBatch { await pauseBetweenBatches() }
            firstBatch = false
            await waitWhileInteractionPaused()
            let batch = Array(assets[chunk..<min(chunk + Self.batchSize, assets.count)])
            let base = baseline + newlyDone
            let done = try await processBatch(batch, composer: composer, allowNetwork: true, timings: timings, summary: &summary) { done, item in
                onProgress(IndexProgress(processed: base + done, total: total, activeItems: item))
            }
            newlyDone += done
            onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        }
        summary.wasCancelled = isCancelled
        Self.logSummary("reindexIncomplete", summary: summary, elapsed: clock.now - runStart, timings: timings.withLock { $0 })
        return summary
    }

    // MARK: Persistent-change fast path

    /// Fetch options shared by every full-library walk and count.
    private static func browsableFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        // Newest first: recently shot photos get their metadata soonest.
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        return options
    }

    /// Incremental run driven by Photos' persistent change history: instead of
    /// materializing every asset in the library to diff it against the DB, ask
    /// Photos what was inserted/updated/deleted since the last complete run and
    /// combine that with the rows still unfinished. On a fully-indexed library
    /// this is two scoped queries and no work at all — where the full walk costs
    /// seconds of pure scanning on every launch (measured: 6.8 s over 55k
    /// assets, all of it skips).
    ///
    /// Returns nil when the history can't serve this run — no stored token (no
    /// full walk has completed yet) or Photos has expired it — leaving the
    /// caller to fall back to the full walk, which re-establishes the token.
    private func runFromPersistentChanges(
        composer: MetadataComposer,
        allowNetwork: @escaping @Sendable () -> Bool,
        timings: OSAllocatedUnfairLock<StageTotals>,
        tokenAtStart: PHPersistentChangeToken,
        clock: ContinuousClock,
        onWorkFound: @escaping @Sendable () -> Void,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws -> IndexRunSummary? {
        let start = clock.now
        guard let stored = try metadataStore.indexState().changeToken,
              let since = Self.unarchivedToken(stored) else { return nil }

        let changes: PersistentChanges
        do {
            changes = try Self.persistentChanges(since: since)
        } catch {
            // Photos keeps a bounded change window; past it the token expires
            // and the only correct answer is a full walk. Drop the token so the
            // fallback re-establishes a fresh one.
            let nsError = error as NSError
            IndexTrafficMonitor.health(
                "persistent changes unavailable (\(nsError.domain) code \(nsError.code)) — full walk"
            )
            var state = try metadataStore.indexState()
            state.changeToken = nil
            try metadataStore.saveIndexState(state)
            return nil
        }

        var summary = IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)

        // Rows whose read never finished carry over regardless of what changed:
        // `pendingRead` placeholders, `error` retries, and `pendingICloud` once
        // the network is allowed again.
        let unfinished = try metadataStore.unfinishedAssetStates()

        // A large unfinished backlog is the case this path handles *worse* than
        // the walk it exists to avoid — fetching and sorting tens of thousands
        // of ids through PhotoKit takes over a minute. Hand it back.
        if unfinished.count > Self.maxUnfinishedForChangeHistory {
            IndexTrafficMonitor.health(
                "persistent changes: \(unfinished.count) unfinished rows exceeds \(Self.maxUnfinishedForChangeHistory) — full walk instead"
            )
            return nil
        }

        var candidateIds = Set(unfinished.keys)
        candidateIds.formUnion(changes.inserted)
        candidateIds.formUnion(changes.updated)
        candidateIds.subtract(changes.deleted)

        // Planning a big candidate set costs seconds of PhotoKit fetch + sort
        // before the first read starts. Claim the indicator now, so that stretch
        // reads as "working" rather than as an app that ignored the launch. Only
        // when the set genuinely contains work: `pendingICloud` rows with the
        // network disallowed all skip, and a run that ends up doing nothing must
        // leave the indicator off.
        if candidateIds.count >= Self.planningWorkSignalThreshold,
           allowNetwork() || unfinished.values.contains(where: { ExifStatus(rawValue: $0.exifStatus) != .pendingICloud }) {
            onWorkFound()
        }

        // Assets that left the library: drop only the ids we actually hold, so
        // `summary.deleted` stays an accurate count of rows removed.
        if !changes.deleted.isEmpty {
            let present = try metadataStore.assetStates(ids: Array(changes.deleted))
            if !present.isEmpty {
                onWorkFound()
                try metadataStore.deleteAssets(ids: Array(present.keys))
                summary.deleted = present.count
            }
        }

        // Newest-first, matching the full walk's ordering, so recently shot
        // photos get their metadata soonest.
        let candidates = PhotoLibraryService.fetchAssets(ids: Array(candidateIds))
            .filter { $0.mediaType == .image || $0.mediaType == .video }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        let states = try metadataStore.assetStates(ids: candidates.map(\.localIdentifier))

        var work: [PHAsset] = []
        var newAssets: [PHAsset] = []
        // Assets being re-read that already counted as complete — the progress
        // baseline has to give them back, exactly as the full walk does.
        var rereadComplete = 0
        // Why each asset made the work list. A re-read that "shouldn't" happen
        // is either an edit Photos reported (modificationDate moved), a version
        // bump backfilling fields, or a row whose read never finished — and only
        // the reason tells which.
        var noRow = 0, edited = 0, versionBump = 0, incompleteStatus = 0
        for asset in candidates {
            let state = states[asset.localIdentifier]
            let currentModified = asset.modificationDate.map { Int($0.timeIntervalSince1970) }
            guard Self.needsReindex(
                existing: state,
                currentModificationDate: currentModified,
                allowNetworkRetry: allowNetwork()
            ) else {
                summary.skipped += 1
                continue
            }
            if let state {
                if state.modificationDate != currentModified {
                    edited += 1
                } else if state.indexerVersion < PhotoMetadata.currentIndexerVersion {
                    versionBump += 1
                } else {
                    incompleteStatus += 1
                }
                if let status = ExifStatus(rawValue: state.exifStatus),
                   status == .indexed || status == .noExif {
                    rereadComplete += 1
                }
            } else {
                noRow += 1
                newAssets.append(asset)
            }
            work.append(asset)
        }

        guard !work.isEmpty || summary.deleted > 0 else {
            // Nothing to do. Advance the token so the next run starts here. The
            // indicator stays off unless the planning-threshold signal above
            // already claimed it — a set of 200+ candidates that all skip, which
            // needs the honest "it was working" more than it needs silence.
            try persistCompletion(token: tokenAtStart)
            IndexTrafficMonitor.health(
                "persistent changes: no work — \(changes.inserted.count) inserted, \(changes.updated.count) updated, \(changes.deleted.count) deleted, \(unfinished.count) unfinished, \(summary.skipped) skipped in \(Self.milliseconds(clock.now - start))ms"
            )
            return summary
        }
        onWorkFound()
        // Same breakdown as the no-work line: a run with unexpectedly much work
        // has to say whether it came from the DB (rows never finished) or from
        // Photos' history (assets it reports as inserted/updated), because the
        // two mean completely different things.
        IndexTrafficMonitor.health(
            "persistent changes: \(work.count) to read — history \(changes.inserted.count) inserted / \(changes.updated.count) updated / \(changes.deleted.count) deleted, DB \(unfinished.count) unfinished, \(summary.skipped) skipped, \(summary.deleted) rows deleted; reason — noRow \(noRow), edited \(edited), versionBump \(versionBump), incomplete \(incompleteStatus) — planned in \(Self.milliseconds(clock.now - start))ms"
        )

        // Placeholder rows for brand-new assets first (the fast pass' job), so
        // they appear in the grid before their EXIF is read.
        if !newAssets.isEmpty {
            let rows = newAssets.map {
                composer.compose(
                    asset: Self.assetInfo(for: $0, fileSize: nil), exif: .empty, exifStatus: .pendingRead
                )
            }
            for chunk in stride(from: 0, to: rows.count, by: Self.fastPassBatchSize) {
                let slice = Array(rows[chunk..<min(chunk + Self.fastPassBatchSize, rows.count)])
                try metadataStore.saveBatch(slice, cursorAssetId: nil)
            }
        }

        // Progress is cumulative against the whole library, matching `run()`.
        let total = PHAsset.fetchAssets(with: Self.browsableFetchOptions()).count
        let baseline = ((try? metadataStore.completedCount()) ?? 0) - rereadComplete
        var newlyDone = 0
        onProgress(IndexProgress(processed: baseline, total: total))

        var firstBatch = true
        for chunk in stride(from: 0, to: work.count, by: Self.batchSize) {
            if isCancelled { break }
            if !firstBatch { await pauseBetweenBatches() }
            firstBatch = false
            await waitWhileInteractionPaused()
            let batch = Array(work[chunk..<min(chunk + Self.batchSize, work.count)])
            let base = baseline + newlyDone
            let done = try await processBatch(
                batch, composer: composer, allowNetwork: allowNetwork(),
                timings: timings, summary: &summary
            ) { done, item in
                onProgress(IndexProgress(processed: base + done, total: total, activeItems: item))
            }
            newlyDone += done
            onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        }

        summary.wasCancelled = isCancelled
        if !isCancelled { try persistCompletion(token: tokenAtStart) }
        onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        Self.logSummary(
            "persistentChanges", summary: summary, elapsed: clock.now - start,
            timings: timings.withLock { $0 }
        )
        return summary
    }

    private struct PersistentChanges {
        var inserted: Set<String> = []
        var updated: Set<String> = []
        var deleted: Set<String> = []
    }

    /// Collapses Photos' change history since `token` into one insert/update/
    /// delete set. Throws when the history is unavailable (expired token), which
    /// the caller answers with a full walk.
    private static func persistentChanges(since token: PHPersistentChangeToken) throws -> PersistentChanges {
        var changes = PersistentChanges()
        let result = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
        for change in result {
            let details = try change.changeDetails(for: .asset)
            changes.inserted.formUnion(details.insertedLocalIdentifiers)
            changes.updated.formUnion(details.updatedLocalIdentifiers)
            changes.deleted.formUnion(details.deletedLocalIdentifiers)
        }
        return changes
    }

    /// Marks the run complete and hands the next one a change token to diff
    /// from. `lastFullIndexAt` is deliberately untouched — it records the last
    /// *full walk*, and an incremental run isn't one.
    private func persistCompletion(token: PHPersistentChangeToken) throws {
        var state = try metadataStore.indexState()
        state.lastIndexedAt = Int(Date().timeIntervalSince1970)
        state.cursorAssetId = nil
        state.changeToken = Self.archived(token)
        try metadataStore.saveIndexState(state)
    }

    private static func archived(_ token: PHPersistentChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func unarchivedToken(_ data: Data) -> PHPersistentChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }

    // MARK: Fast pass

    /// Writes placeholder rows (`pendingRead`) for assets with no row yet,
    /// using PHAsset facts only — no per-asset XPC, large transactions.
    private func fastPass(
        fetchResult: PHFetchResult<PHAsset>,
        existingStates: [String: IndexedAssetState],
        composer: MetadataComposer,
        clock: ContinuousClock,
        onWorkFound: () -> Void
    ) throws {
        guard !isCancelled else { return }
        let start = clock.now
        let signpostState = Self.signposter.beginInterval("fastPass")
        defer { Self.signposter.endInterval("fastPass", signpostState) }

        var rows: [PhotoMetadata] = []
        rows.reserveCapacity(Self.fastPassBatchSize)
        var written = 0
        for index in 0..<fetchResult.count {
            if isCancelled { break }
            let asset = fetchResult.object(at: index)
            guard existingStates[asset.localIdentifier] == nil else { continue }
            rows.append(composer.compose(
                asset: Self.assetInfo(for: asset, fileSize: nil),
                exif: .empty,
                exifStatus: .pendingRead
            ))
            if rows.count == Self.fastPassBatchSize {
                onWorkFound()
                try metadataStore.saveBatch(rows, cursorAssetId: nil)
                written += rows.count
                rows.removeAll(keepingCapacity: true)
            }
        }
        if !rows.isEmpty {
            onWorkFound()
            try metadataStore.saveBatch(rows, cursorAssetId: nil)
            written += rows.count
        }
        // Logged even at zero rows: the scan walks (and materializes) every
        // asset in the library whether or not it writes anything, so its cost
        // on a fully-indexed launch has to be visible.
        IndexTrafficMonitor.health(
            "fast pass: \(written) placeholder rows, scanned \(fetchResult.count) in \(Self.milliseconds(clock.now - start))ms"
        )
    }

    // MARK: Batch processing

    /// `onAssetProcessed` receives `(done count, in-flight filenames)` — `done`
    /// counts only assets that finished a read (`.indexed`/`noExif`), matching
    /// the run's cumulative baseline, so the number never overshoots and snaps
    /// back — when each read starts and completes, throttled to one emission per
    /// 200 ms — slow iCloud batches (30 s timeouts) must still visibly move,
    /// and the start-of-read emission updates the list even while the count
    /// stalls.
    private struct BatchItem: Sendable {
        enum Outcome: Sendable { case indexed, pendingICloud, failed }
        let index: Int
        let record: PhotoMetadata
        let outcome: Outcome
        /// For removal from the in-flight list on completion.
        let filename: String?
    }

    /// Shared between concurrent reads and the completion loop; throttles
    /// progress emissions and tracks the filenames currently being read.
    /// `done` counts only assets that reached a finished read this batch
    /// (`outcome == .indexed`, which also covers screenshots → `noExif`), so
    /// the reported number matches the cumulative done-count baseline.
    private struct BatchProgressState: Sendable {
        var done = 0
        var active: [String] = []
        var lastEmit: ContinuousClock.Instant
    }

    /// Returns the number of assets in this batch that finished with a read
    /// (`outcome == .indexed`) — the caller adds it to the run's `newlyDone`.
    @discardableResult
    private func processBatch(
        _ assets: [PHAsset],
        composer: MetadataComposer,
        allowNetwork: Bool,
        timings: OSAllocatedUnfairLock<StageTotals>,
        summary: inout IndexRunSummary,
        onAssetProcessed: (@Sendable (Int, [String]) -> Void)? = nil
    ) async throws -> Int {
        var results = [PhotoMetadata?](repeating: nil, count: assets.count)
        // Assets whose read came back with no bytes — their rows must keep the
        // EXIF a previous run wrote (see `MetadataStore.saveBatch`).
        var unreadAssetIds = Set<String>()
        var completed = 0
        var doneCount = 0
        // Per-batch stage split, so a slow run can be attributed live (which
        // stage, on which batch) instead of only from the end-of-run averages.
        let batchClock = ContinuousClock()
        let batchStart = batchClock.now
        let timingsBefore = timings.withLock { $0 }
        let exifBefore = ExifReader.currentMetrics
        let monitor = exifReader.trafficMonitor
        let networkBefore = (
            reads: monitor?.networkReadsStarted ?? 0,
            stalls: monitor?.stallCount ?? 0,
            skips: monitor?.networkSkipCount ?? 0,
            bytes: monitor?.totalBytes ?? 0
        )

        let progressClock = ContinuousClock()
        let progressState = OSAllocatedUnfairLock(
            initialState: BatchProgressState(lastEmit: progressClock.now - .seconds(1))
        )

        await withTaskGroup(of: BatchItem.self) { group in
            let exifReader = self.exifReader
            let metadataStore = self.metadataStore

            @Sendable func read(_ index: Int, _ asset: PHAsset) async -> BatchItem {
                let clock = ContinuousClock()
                var mark = clock.now

                // One XPC round-trip per asset: the resource list feeds the
                // EXIF streaming read (and the original filename). `fileSize`
                // is read here off the pipeline actor (never the main queue),
                // persisting it so the grid can badge it without a per-cell
                // KVC read at scroll time. For iCloud-only assets this KVC can
                // still fault in the original-metadata set, but the full read
                // already streams from the file, so the cost is amortized.
                let resources = PHAssetResource.assetResources(for: asset)
                let resource = ExifReader.photoResource(among: resources)
                // Facts (size/filename) fall back to any resource so videos —
                // which have no photo resource — still record them.
                let factsResource = resource ?? resources.first
                let resourcesTime = clock.now - mark
                // Timed apart from the resource list: this KVC can fault in a
                // whole original-metadata set for an iCloud asset, and it is the
                // one part of the pre-read step that could be dropped.
                mark = clock.now
                let fileSize = (factsResource?.value(forKey: "fileSize") as? NSNumber)?.intValue
                let fileSizeTime = clock.now - mark
                let info = Self.assetInfo(for: asset, fileSize: fileSize, originalFilename: factsResource?.originalFilename)

                if let onAssetProcessed, let filename = factsResource?.originalFilename {
                    let payload = progressState.withLock { state -> (Int, [String])? in
                        state.active.append(filename)
                        guard progressClock.now - state.lastEmit >= .milliseconds(200) else { return nil }
                        state.lastEmit = progressClock.now
                        return (state.done, state.active)
                    }
                    if let payload { onAssetProcessed(payload.0, payload.1) }
                }

                var exifTime = Duration.zero
                var hasReadExif = false
                let exifResult: ExifReadResult
                if Self.shouldSkipExifRead(mediaType: asset.mediaType.rawValue, mediaSubtypes: asset.mediaSubtypes) {
                    // Composer turns indexed + empty EXIF into `noExif`.
                    exifResult = .success(.empty)
                } else {
                    mark = clock.now
                    let signpostId = Self.signposter.makeSignpostID()
                    let signpostState = Self.signposter.beginInterval("exifRead", id: signpostId)
                    exifResult = await exifReader.readExif(for: asset, resource: resource, allowNetwork: allowNetwork)
                    Self.signposter.endInterval("exifRead", signpostState)
                    exifTime = clock.now - mark
                    hasReadExif = true
                }

                mark = clock.now
                let filename = factsResource?.originalFilename
                let item: BatchItem
                switch exifResult {
                case .success(let exif):
                    item = BatchItem(index: index,
                                     record: composer.compose(asset: info, exif: exif, exifStatus: .indexed),
                                     outcome: .indexed,
                                     filename: filename)
                case .pendingICloud:
                    // Couldn't download (in iCloud, or the network failed).
                    // ALWAYS retryable — a flaky link must never end with a
                    // photo wrongly marked no-metadata. No attempt counting.
                    item = BatchItem(index: index,
                                     record: composer.compose(asset: info, exif: .empty, exifStatus: .pendingICloud),
                                     outcome: .pendingICloud,
                                     filename: filename)
                case .unreadable, .failure:
                    // Both are deterministic, NON-network failures: `.unreadable`
                    // = bytes obtained (local file present, or iCloud download
                    // completed) but unparseable; `.failure` = a hard local read
                    // error / no resource. Network transport problems never land
                    // here — they return `pendingICloud`. So count attempts and,
                    // once the cap is hit, give up: write `noExif` (composer maps
                    // indexed + empty EXIF → noExif) so the photo shows with no
                    // camera data and drops out of the retry set. A flaky link
                    // can never reach this path, so it can never wrongly mark a
                    // downloadable photo as no-metadata.
                    let attempts = ((try? metadataStore.readAttempts(assetId: asset.localIdentifier)) ?? 0) + 1
                    if attempts >= Self.maxReadAttempts {
                        item = BatchItem(index: index,
                                         record: composer.compose(asset: info, exif: .empty, exifStatus: .indexed),
                                         outcome: .indexed,
                                         filename: filename)
                    } else {
                        var record = composer.compose(asset: info, exif: .empty, exifStatus: .error)
                        record.readAttempts = attempts
                        item = BatchItem(index: index, record: record, outcome: .failed, filename: filename)
                    }
                }
                // Trace stuck assets: on a resumed run only the still-incomplete
                // rows reach here, so logging every non-indexed outcome with its
                // assetId (the key that maps back to a Photos asset) and filename
                // pinpoints the handful that keep retrying, alongside the
                // per-branch reason ExifReader already logged.
                if item.outcome != .indexed {
                    Self.logger.log("asset \(asset.localIdentifier, privacy: .public) [\(filename ?? "?", privacy: .public)] outcome=\(String(describing: item.outcome), privacy: .public) allowNetwork=\(allowNetwork)")
                } else {
                    switch exifResult {
                    case .unreadable, .failure:
                        Self.logger.log("asset \(asset.localIdentifier, privacy: .public) [\(filename ?? "?", privacy: .public)] unreadable local original after \(Self.maxReadAttempts) attempts — marked noExif")
                    default:
                        break
                    }
                }
                let composeTime = clock.now - mark

                timings.withLock {
                    $0.resources += resourcesTime
                    $0.fileSize += fileSizeTime
                    $0.exif += exifTime
                    $0.compose += composeTime
                    $0.assets += 1
                    if hasReadExif { $0.exifReads += 1 }
                }
                return item
            }

            await waitWhileInteractionPaused()
            await waitWhileThermalCritical()
            await waitWhileNetworkBreakerTripped(allowNetwork: allowNetwork)
            // Target fan-out is re-sampled at every read completion below, so
            // a device that heats mid-batch stops replacing finished reads
            // (fan-out decays to the new target) and ramps back up on cooling
            // — no in-flight read is ever killed.
            var nextIndex = 0
            var inFlight = 0
            let seedTarget = Self.readConcurrency(thermal: thermalState(), isLowPowerMode: isLowPowerMode())
            while nextIndex < min(seedTarget, assets.count) {
                let index = nextIndex
                let asset = assets[index]
                group.addTask { await read(index, asset) }
                nextIndex += 1
                inFlight += 1
            }

            for await item in group {
                inFlight -= 1
                results[item.index] = item.record
                switch item.outcome {
                case .indexed: summary.indexed += 1
                case .pendingICloud:
                    summary.pendingICloud += 1
                    unreadAssetIds.insert(item.record.assetId)
                case .failed:
                    summary.failed += 1
                    unreadAssetIds.insert(item.record.assetId)
                }
                completed += 1
                if item.outcome == .indexed { doneCount += 1 }
                if let onAssetProcessed {
                    let payload = progressState.withLock { state -> (Int, [String])? in
                        state.done = doneCount
                        if let filename = item.filename,
                           let position = state.active.firstIndex(of: filename) {
                            state.active.remove(at: position)
                        }
                        guard completed < assets.count else { return nil }
                        guard progressClock.now - state.lastEmit >= .milliseconds(200) else { return nil }
                        state.lastEmit = progressClock.now
                        // Report `done` (assets that actually finished a read),
                        // NOT `completed` (which also counts pendingICloud/failed):
                        // the run's cumulative baseline advances by `done` only, so
                        // emitting `completed` here made an all-iCloud batch ramp the
                        // count up then snap back down at the batch boundary.
                        return (state.done, state.active)
                    }
                    if let payload { onAssetProcessed(payload.0, payload.1) }
                }
                if !isCancelled && nextIndex < assets.count {
                    // Pausing here also stops consuming results — fine:
                    // in-flight reads finish and buffer inside the group,
                    // then the loop drains them and refills on resume.
                    await waitWhileInteractionPaused()
                    await waitWhileThermalCritical()
                    await waitWhileNetworkBreakerTripped(allowNetwork: allowNetwork)
                    guard !isCancelled else { continue }
                    let target = Self.readConcurrency(thermal: thermalState(), isLowPowerMode: isLowPowerMode())
                    var toSpawn = Self.refillCount(
                        inFlight: inFlight, target: target, remaining: assets.count - nextIndex
                    )
                    while toSpawn > 0 {
                        let index = nextIndex
                        let asset = assets[index]
                        group.addTask { await read(index, asset) }
                        nextIndex += 1
                        inFlight += 1
                        toSpawn -= 1
                    }
                }
            }
        }

        // Save only the contiguous prefix in batch order: after a cancel the
        // result array can have holes, and the cursor must never point past
        // an unread asset. Dropped out-of-order results are re-read next run.
        var records: [PhotoMetadata] = []
        records.reserveCapacity(assets.count)
        for record in results {
            guard let record else { break }
            records.append(record)
        }

        guard !records.isEmpty else { return doneCount }
        let mark = batchClock.now
        let signpostState = Self.signposter.beginInterval("dbWrite")
        try metadataStore.saveBatch(
            records, unreadAssetIds: unreadAssetIds, cursorAssetId: records.last?.assetId
        )
        Self.signposter.endInterval("dbWrite", signpostState)
        timings.withLock { $0.dbWrite += batchClock.now - mark }
        Self.logBatch(
            assets.count, elapsed: batchClock.now - batchStart,
            before: timingsBefore, after: timings.withLock { $0 },
            exif: ExifReader.currentMetrics - exifBefore,
            networkReads: (monitor?.networkReadsStarted ?? 0) - networkBefore.reads,
            networkStalls: (monitor?.stallCount ?? 0) - networkBefore.stalls,
            networkSkips: (monitor?.networkSkipCount ?? 0) - networkBefore.skips,
            networkBytes: (monitor?.totalBytes ?? 0) - networkBefore.bytes,
            outcomes: summary
        )
        return doneCount
    }

    private static func assetInfo(for asset: PHAsset, fileSize: Int?, originalFilename: String? = nil) -> AssetInfo {
        AssetInfo(
            assetId: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            mediaType: asset.mediaType.rawValue,
            width: asset.pixelWidth > 0 ? asset.pixelWidth : nil,
            height: asset.pixelHeight > 0 ? asset.pixelHeight : nil,
            fileSize: fileSize,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            originalFilename: originalFilename
        )
    }

    // MARK: Instrumentation

    /// Wall-clock totals per pipeline stage, accumulated across the
    /// concurrent reads, for the end-of-run summary log.
    private struct StageTotals: Sendable {
        var resources: Duration = .zero
        /// The `fileSize` KVC alone, split out of `resources`.
        var fileSize: Duration = .zero
        var exif: Duration = .zero
        var compose: Duration = .zero
        var dbWrite: Duration = .zero
        /// Assets that went through `read()` — denominator for
        /// resources/compose averages.
        var assets = 0
        /// Assets whose EXIF was actually read from the file (screenshots
        /// are skipped) — denominator for the exif average.
        var exifReads = 0
    }

    /// One line per finished batch: wall clock plus the per-asset split of this
    /// batch alone (the run summary only reports averages over the whole run,
    /// which hides a stage degrading partway through — a thermal step-down, or
    /// iCloud starting to stall).
    private static func logBatch(
        _ count: Int, elapsed: Duration, before: StageTotals, after: StageTotals,
        exif: ExifReadMetrics,
        networkReads: Int, networkStalls: Int, networkSkips: Int, networkBytes: Int64,
        outcomes: IndexRunSummary
    ) {
        let assets = after.assets - before.assets
        let reads = after.exifReads - before.exifReads
        // `parse` is a *subset* of `exif` (ImageIO runs inside the streaming
        // window), and `read` is the remainder — the PhotoKit resource transfer.
        // `KB` is bytes actually pulled per read, the lever an early-stop pulls.
        let parseMilliseconds = Double(exif.parseNanos) / 1_000_000
        let streamMilliseconds = Double(exif.streamNanos) / 1_000_000
        let streamReads = max(exif.reads, 1)
        IndexTrafficMonitor.health(
            "batch: \(count) assets in \(milliseconds(elapsed))ms"
                + String(format: " (%.1f/s)", Double(count) / max(seconds(elapsed), 0.001))
                + "; ms/asset — resources \(averageMilliseconds(after.resources - before.resources, over: assets))"
                + ", fileSize \(averageMilliseconds(after.fileSize - before.fileSize, over: assets))"
                + ", exif \(averageMilliseconds(after.exif - before.exif, over: reads))"
                + ", compose \(averageMilliseconds(after.compose - before.compose, over: assets))"
                + ", dbWrite \(averageMilliseconds(after.dbWrite - before.dbWrite, over: assets))"
                + String(
                    format: "; per stream read — read %.1f, parse %.1f (%.1f calls), %.0f KB",
                    (streamMilliseconds - parseMilliseconds) / Double(streamReads),
                    parseMilliseconds / Double(streamReads),
                    Double(exif.parseCalls) / Double(streamReads),
                    Double(exif.bytes) / Double(streamReads) / 1024
                )
                // iCloud side of the same batch. `skips` are assets the breaker
                // rejected without a request — a batch that is mostly skips did
                // no work at all, however fast it looked.
                + "; net — \(networkReads) reads, \(networkStalls) stalls, \(networkSkips) skipped, \(networkBytes / 1024) KB"
                + "; resolved via — localOriginal \(exif.viaLocalOriginal), localDerivative \(exif.viaLocalDerivative), netOriginal \(exif.viaNetwork)"
                + "; run totals — indexed \(outcomes.indexed), pendingICloud \(outcomes.pendingICloud), failed \(outcomes.failed)"
        )
    }

    private static func logSummary(_ kind: String, summary: IndexRunSummary, elapsed: Duration, timings: StageTotals) {
        let elapsedSeconds = max(seconds(elapsed), 0.001)
        let read = summary.indexed + summary.pendingICloud + summary.failed
        let line = "index \(kind): indexed \(summary.indexed), skipped \(summary.skipped), "
            + "pendingICloud \(summary.pendingICloud), failed \(summary.failed), deleted \(summary.deleted)"
            + (summary.wasCancelled ? " (cancelled)" : "")
            + String(format: " in %.1fs — %.1f assets/s", elapsedSeconds, Double(read) / elapsedSeconds)
            + "; avg ms/asset — resources \(averageMilliseconds(timings.resources, over: timings.assets))"
            + ", fileSize \(averageMilliseconds(timings.fileSize, over: timings.assets))"
            + ", exif \(averageMilliseconds(timings.exif, over: timings.exifReads))"
            + ", compose \(averageMilliseconds(timings.compose, over: timings.assets))"
            + ", dbWrite \(averageMilliseconds(timings.dbWrite, over: timings.assets))"
        // On the health category so a run's boundary lines, stalls, breaker
        // events, and 10 s snapshots read as one stream.
        IndexTrafficMonitor.health(line)
    }

    private static func milliseconds(_ duration: Duration) -> String {
        String(format: "%.0f", seconds(duration) * 1000)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    private static func averageMilliseconds(_ total: Duration, over count: Int) -> String {
        guard count > 0 else { return "–" }
        return String(format: "%.1f", seconds(total) * 1000 / Double(count))
    }
}
