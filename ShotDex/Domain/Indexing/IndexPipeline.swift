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
    /// EXIF reads within a batch run concurrently — indexing time is
    /// dominated by per-asset PhotoKit round-trips, not CPU.
    static let readConcurrency = 16
    /// Fast-pass rows per transaction; no EXIF is read, so batches can be
    /// much larger than EXIF batches.
    static let fastPassBatchSize = 1000

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "index")
    private static let signposter = OSSignposter(subsystem: "com.hoangtuan.shotdex", category: "index")

    private let metadataDAO: MetadataDAO
    private let exifService: ExifService
    private let sensorDatabaseService: SensorDatabaseService

    private var isCancelled = false
    private var isRunning = false

    init(metadataDAO: MetadataDAO, exifService: ExifService = ExifService(),
         sensorDatabaseService: SensorDatabaseService = SensorDatabaseService()) {
        self.metadataDAO = metadataDAO
        self.exifService = exifService
        self.sensorDatabaseService = sensorDatabaseService
    }

    func cancel() {
        isCancelled = true
    }

    /// Whether a run is currently in flight (used by background scheduling).
    var isActive: Bool { isRunning }

    /// Decides whether an asset must be (re-)read. Pure — unit-tested.
    /// Incomplete reads (`error`, `pendingRead`, and `pendingICloud` when the
    /// network may be used) are re-enqueued even when the asset is unchanged.
    static func needsReindex(
        existing: IndexedAssetState?,
        currentModificationDate: Int?,
        allowNetworkRetry: Bool
    ) -> Bool {
        guard let existing else { return true }
        if existing.modificationDate != currentModificationDate { return true }
        switch ExifStatus(rawValue: existing.exifStatus) {
        case .indexed, .noExif: return false
        case .pendingRead: return true
        case .pendingICloud: return allowNetworkRetry
        case .error, nil: return true
        }
    }

    /// Screenshots never carry camera EXIF — their file read is skipped and
    /// the row goes straight to `noExif`. Pure — unit-tested.
    static func shouldSkipExifRead(mediaSubtypes: PHAssetMediaSubtype) -> Bool {
        mediaSubtypes.contains(.photoScreenshot)
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
    ///   - onProgress: called when each asset read starts and completes,
    ///     throttled to ~5/s (EXIF pass only; the fast pass finishes within
    ///     seconds and stays on the indeterminate "Indexing…" display).
    @discardableResult
    func run(
        fullReindex: Bool = false,
        allowNetwork: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (IndexProgress) -> Void = { _ in }
    ) async throws -> IndexRunSummary {
        guard !isRunning else {
            return IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)
        }
        isRunning = true
        isCancelled = false
        defer { isRunning = false }

        let clock = ContinuousClock()
        let runStart = clock.now
        let timings = OSAllocatedUnfairLock(initialState: StageTotals())

        let composer = MetadataComposer(
            sensorLookup: SensorLookup(
                records: (try? sensorDatabaseService.loadRecords()) ?? [],
                customMappings: (try? metadataDAO.customMappings()) ?? []
            )
        )

        // Rows already present — the fast pass must never overwrite them
        // (a full reindex still keeps old EXIF visible until re-read).
        let existingStates = try metadataDAO.indexedAssetStates()
        // Diff snapshot for the EXIF pass; fullReindex re-reads everything.
        let existing = fullReindex ? [:] : existingStates

        let fetchOptions = PHFetchOptions()
        // Newest first: recently shot photos get their metadata soonest.
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

        let total = fetchResult.count
        var summary = IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)

        // Phase 1 — fast pass over brand-new assets.
        try fastPass(fetchResult: fetchResult, existingStates: existingStates, composer: composer, clock: clock)

        // Phase 2 — EXIF enrichment.
        //
        // Progress is cumulative: `baseline` = assets already fully read
        // (`indexed`/`noExif`) before this run, `newlyDone` = assets read to
        // completion this run. The reported count is `baseline + newlyDone`,
        // so a resumed run continues from where the last one stopped instead
        // of restarting at zero. `fullReindex` re-reads everything, so it
        // starts from zero. Emitted once up front so the panel shows the true
        // starting point immediately (no jump, no apparent backward step).
        var baseline = fullReindex ? 0 : (try? metadataDAO.completedCount()) ?? 0
        var newlyDone = 0
        onProgress(IndexProgress(processed: baseline, total: total))

        var seenAssetIds = Set<String>(minimumCapacity: total)
        var batch: [PHAsset] = []
        batch.reserveCapacity(Self.batchSize)

        func runBatch(_ assets: [PHAsset]) async throws {
            let base = baseline + newlyDone
            let done = try await processBatch(assets, composer: composer, allowNetwork: allowNetwork(), timings: timings, summary: &summary) { done, item in
                onProgress(IndexProgress(processed: base + done, total: total, activeItems: item))
            }
            newlyDone += done
            onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        }

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

            batch.append(asset)
            if batch.count == Self.batchSize {
                try await runBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty && !isCancelled {
            try await runBatch(batch)
        }

        // Remove rows for assets that vanished from the library
        // (only safe to compute after a full, uncancelled walk).
        if !isCancelled && !fullReindex {
            let deletedIds = existing.keys.filter { !seenAssetIds.contains($0) }
            if !deletedIds.isEmpty {
                try metadataDAO.deleteAssets(ids: deletedIds)
                summary.deleted = deletedIds.count
            }
        }

        summary.wasCancelled = isCancelled

        var state = try metadataDAO.indexState()
        state.lastIndexedAt = Int(Date().timeIntervalSince1970)
        if !isCancelled {
            state.cursorAssetId = nil
            state.lastFullIndexAt = Int(Date().timeIntervalSince1970)
        }
        try metadataDAO.saveIndexState(state)

        onProgress(IndexProgress(processed: baseline + newlyDone, total: total))
        Self.logSummary("run", summary: summary, elapsed: clock.now - runStart, timings: timings.withLock { $0 })
        return summary
    }

    /// Re-reads only the assets whose EXIF is incomplete (`pendingICloud` or
    /// `error`), always allowing iCloud streaming — this action exists
    /// precisely to fetch what a local-only run couldn't.
    @discardableResult
    func reindexIncomplete(
        onProgress: @escaping @Sendable (IndexProgress) -> Void = { _ in }
    ) async throws -> IndexRunSummary {
        guard !isRunning else {
            return IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)
        }
        isRunning = true
        isCancelled = false
        defer { isRunning = false }

        let clock = ContinuousClock()
        let runStart = clock.now
        let timings = OSAllocatedUnfairLock(initialState: StageTotals())

        let composer = MetadataComposer(
            sensorLookup: SensorLookup(
                records: (try? sensorDatabaseService.loadRecords()) ?? [],
                customMappings: (try? metadataDAO.customMappings()) ?? []
            )
        )
        let ids = try metadataDAO.retryableAssetIds()
        var summary = IndexRunSummary(indexed: 0, skipped: 0, pendingICloud: 0, failed: 0, deleted: 0, wasCancelled: false)
        let assets = PhotoLibraryService.fetchAssets(ids: ids)

        // Progress is cumulative against the whole library, matching `run()`:
        // the count climbs from what's already done toward the library total,
        // never the "1 of 97 retryable" view.
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let total = PHAsset.fetchAssets(with: fetchOptions).count
        let baseline = (try? metadataDAO.completedCount()) ?? 0
        var newlyDone = 0
        onProgress(IndexProgress(processed: baseline, total: total))

        for chunk in stride(from: 0, to: assets.count, by: Self.batchSize) {
            if isCancelled { break }
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

    // MARK: Fast pass

    /// Writes placeholder rows (`pendingRead`) for assets with no row yet,
    /// using PHAsset facts only — no per-asset XPC, large transactions.
    private func fastPass(
        fetchResult: PHFetchResult<PHAsset>,
        existingStates: [String: IndexedAssetState],
        composer: MetadataComposer,
        clock: ContinuousClock
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
                try metadataDAO.saveBatch(rows, cursorAssetId: nil)
                written += rows.count
                rows.removeAll(keepingCapacity: true)
            }
        }
        if !rows.isEmpty {
            try metadataDAO.saveBatch(rows, cursorAssetId: nil)
            written += rows.count
        }
        if written > 0 {
            let seconds = Self.seconds(clock.now - start)
            Self.logger.info("fast pass: \(written) placeholder rows in \(String(format: "%.2f", seconds), privacy: .public)s")
        }
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
        var completed = 0
        var doneCount = 0

        let progressClock = ContinuousClock()
        let progressState = OSAllocatedUnfairLock(
            initialState: BatchProgressState(lastEmit: progressClock.now - .seconds(1))
        )

        await withTaskGroup(of: BatchItem.self) { group in
            let exifService = self.exifService

            @Sendable func read(_ index: Int, _ asset: PHAsset) async -> BatchItem {
                let clock = ContinuousClock()
                var mark = clock.now

                // One XPC round-trip per asset: the resource list feeds the
                // EXIF streaming read (and the original filename). File size is
                // NOT read here — `resource.fileSize` KVC loads the asset's
                // original-metadata property set, which for iCloud-only assets
                // is fetched on demand ON THE MAIN QUEUE, stalling the whole
                // pipeline. Size is fetched lazily in the photo detail view.
                let resources = PHAssetResource.assetResources(for: asset)
                let resource = ExifService.photoResource(among: resources)
                let info = Self.assetInfo(for: asset, fileSize: nil, originalFilename: resource?.originalFilename)
                let resourcesTime = clock.now - mark

                if let onAssetProcessed, let filename = resource?.originalFilename {
                    let payload = progressState.withLock { state -> (Int, [String])? in
                        state.active.append(filename)
                        guard progressClock.now - state.lastEmit >= .milliseconds(200) else { return nil }
                        state.lastEmit = progressClock.now
                        return (state.done, state.active)
                    }
                    if let payload { onAssetProcessed(payload.0, payload.1) }
                }

                var exifTime = Duration.zero
                var didReadExif = false
                let exifResult: ExifReadResult
                if Self.shouldSkipExifRead(mediaSubtypes: asset.mediaSubtypes) {
                    // Composer turns indexed + empty EXIF into `noExif`.
                    exifResult = .success(.empty)
                } else {
                    mark = clock.now
                    let signpostId = Self.signposter.makeSignpostID()
                    let signpostState = Self.signposter.beginInterval("exifRead", id: signpostId)
                    exifResult = await exifService.readExif(for: asset, resource: resource, allowNetwork: allowNetwork)
                    Self.signposter.endInterval("exifRead", signpostState)
                    exifTime = clock.now - mark
                    didReadExif = true
                }

                mark = clock.now
                let filename = resource?.originalFilename
                let item: BatchItem
                switch exifResult {
                case .success(let exif):
                    item = BatchItem(index: index,
                                     record: composer.compose(asset: info, exif: exif, exifStatus: .indexed),
                                     outcome: .indexed,
                                     filename: filename)
                case .pendingICloud:
                    item = BatchItem(index: index,
                                     record: composer.compose(asset: info, exif: .empty, exifStatus: .pendingICloud),
                                     outcome: .pendingICloud,
                                     filename: filename)
                case .failure:
                    item = BatchItem(index: index,
                                     record: composer.compose(asset: info, exif: .empty, exifStatus: .error),
                                     outcome: .failed,
                                     filename: filename)
                }
                let composeTime = clock.now - mark

                timings.withLock {
                    $0.resources += resourcesTime
                    $0.exif += exifTime
                    $0.compose += composeTime
                    $0.assets += 1
                    if didReadExif { $0.exifReads += 1 }
                }
                return item
            }

            var nextIndex = 0
            while nextIndex < min(Self.readConcurrency, assets.count) {
                let index = nextIndex
                let asset = assets[index]
                group.addTask { await read(index, asset) }
                nextIndex += 1
            }

            for await item in group {
                results[item.index] = item.record
                switch item.outcome {
                case .indexed: summary.indexed += 1
                case .pendingICloud: summary.pendingICloud += 1
                case .failed: summary.failed += 1
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
                    let index = nextIndex
                    let asset = assets[index]
                    group.addTask { await read(index, asset) }
                    nextIndex += 1
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
        let clock = ContinuousClock()
        let mark = clock.now
        let signpostState = Self.signposter.beginInterval("dbWrite")
        try metadataDAO.saveBatch(records, cursorAssetId: records.last?.assetId)
        Self.signposter.endInterval("dbWrite", signpostState)
        timings.withLock { $0.dbWrite += clock.now - mark }
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

    private static func logSummary(_ kind: String, summary: IndexRunSummary, elapsed: Duration, timings: StageTotals) {
        let elapsedSeconds = max(seconds(elapsed), 0.001)
        let read = summary.indexed + summary.pendingICloud + summary.failed
        let line = "index \(kind): indexed \(summary.indexed), skipped \(summary.skipped), "
            + "pendingICloud \(summary.pendingICloud), failed \(summary.failed), deleted \(summary.deleted)"
            + (summary.wasCancelled ? " (cancelled)" : "")
            + String(format: " in %.1fs — %.1f assets/s", elapsedSeconds, Double(read) / elapsedSeconds)
            + "; avg ms/asset — resources \(avgMs(timings.resources, timings.assets))"
            + ", exif \(avgMs(timings.exif, timings.exifReads))"
            + ", compose \(avgMs(timings.compose, timings.assets))"
            + ", dbWrite \(avgMs(timings.dbWrite, timings.assets))"
        logger.info("\(line, privacy: .public)")
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    private static func avgMs(_ total: Duration, _ count: Int) -> String {
        guard count > 0 else { return "–" }
        return String(format: "%.1f", seconds(total) * 1000 / Double(count))
    }
}
