import Foundation
import Photos

/// Progress of one duplicate scan: photos hashed so far out of the run's work list.
struct DuplicateScanProgress: Equatable, Sendable {
    var processed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(processed) / Double(total) : 0 }
}

/// Result of one duplicate scan.
struct DuplicateScanSummary: Equatable, Sendable {
    var hashed: Int
    var failed: Int
    var pruned: Int
    var wasCancelled: Bool
    /// Another scan already owned the actor when this one was asked for.
    var didNotStart = false
}

/// Hashes every indexed photo that lacks an up-to-date perceptual hash and
/// persists the results in batches, so a cancelled or interrupted scan simply
/// resumes from the work list next time. Mirrors `IndexPipeline`'s shape: one
/// run at a time, batches of `batchSize`, a bounded fan-out of PhotoKit
/// requests per batch, progress reported after each batch.
actor DuplicateScanPipeline {
    static let batchSize = 200
    /// Concurrent thumbnail requests inside a batch. Renditions are served
    /// from PhotoKit's on-device thumbnail set, so this is XPC-bound, not CPU.
    static let readConcurrency = 8

    private let store: PerceptualHashStore
    private let reader: any PerceptualHashReading
    private var isRunning = false
    /// The last regroup asked for; the next waits for it (see `regroup`).
    private var regroupTail: Task<Bool, Never>?

    init(store: PerceptualHashStore, reader: any PerceptualHashReading) {
        self.store = store
        self.reader = reader
    }

    /// Runs one scan. Cancel by cancelling the calling task; the batch in
    /// flight finishes and is written, then the run returns `wasCancelled`.
    /// - Parameter keepsGoing: asked before each batch; false stops the run
    ///   as a cancel would (the automatic check yields to Low Power, heat
    ///   and an open editor, FS-06.06 §14.3).
    func run(
        allowNetwork: Bool,
        onProgress: @escaping @Sendable (DuplicateScanProgress) -> Void,
        keepsGoing: @Sendable () -> Bool = { true }
    ) async throws -> DuplicateScanSummary {
        guard !isRunning else {
            return DuplicateScanSummary(hashed: 0, failed: 0, pruned: 0, wasCancelled: false, didNotStart: true)
        }
        isRunning = true
        defer { isRunning = false }

        let pruned = try store.pruneOrphans()
        let pending = try store.pendingAssetIds(retryingFailed: allowNetwork)
        var summary = DuplicateScanSummary(hashed: 0, failed: 0, pruned: pruned, wasCancelled: false)
        var processed = 0
        onProgress(DuplicateScanProgress(processed: 0, total: pending.count))

        for batchStart in stride(from: 0, to: pending.count, by: Self.batchSize) {
            if Task.isCancelled || !keepsGoing() {
                summary.wasCancelled = true
                break
            }
            let ids = Array(pending[batchStart..<min(batchStart + Self.batchSize, pending.count)])
            let assets = PhotoLibraryService.fetchAssets(ids: ids)
            let records = await hashBatch(assets, allowNetwork: allowNetwork)
            try store.upsert(records)
            summary.hashed += records.filter { $0.hash != nil }.count
            summary.failed += records.filter { $0.hash == nil }.count
            processed += ids.count
            onProgress(DuplicateScanProgress(processed: processed, total: pending.count))
        }
        return summary
    }

    /// Groups every stored hash and writes the cache (`DuplicateRegroup`),
    /// one regroup at a time: the Check button, the cache repair on open and
    /// the automatic check (§14.3) all come through here, so none writes
    /// groups built from a snapshot older than another's checksums
    /// (review 2026-11-16). Cancelling the caller cancels its own regroup.
    /// - Returns: whether the cache was written.
    @discardableResult
    func regroup(allowNetwork: Bool, priority: TaskPriority) async -> Bool {
        let previous = regroupTail
        let store = self.store
        let work = Task.detached(priority: priority) { () -> Bool in
            _ = await previous?.value
            guard !Task.isCancelled else { return false }
            return await DuplicateRegroup.run(store: store, allowNetwork: allowNetwork)
        }
        regroupTail = work
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func hashBatch(_ assets: [PHAsset], allowNetwork: Bool) async -> [PerceptualHashRecord] {
        let reader = self.reader
        let now = Int(Date().timeIntervalSince1970)
        return await withTaskGroup(of: PerceptualHashRecord.self) { group in
            var records: [PerceptualHashRecord] = []
            records.reserveCapacity(assets.count)
            var next = 0
            func enqueue() {
                guard next < assets.count else { return }
                let asset = assets[next]
                next += 1
                group.addTask {
                    let hash = await reader.hash(for: asset, allowNetwork: allowNetwork)
                    return PerceptualHashRecord(
                        assetId: asset.localIdentifier,
                        hash: hash,
                        modificationDate: asset.modificationDate.map { Int($0.timeIntervalSince1970) },
                        computedAt: now
                    )
                }
            }
            for _ in 0..<min(Self.readConcurrency, assets.count) { enqueue() }
            while let record = await group.next() {
                records.append(record)
                enqueue()
            }
            return records
        }
    }
}
