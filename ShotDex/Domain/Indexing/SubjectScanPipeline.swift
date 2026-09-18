import Foundation
import Photos

/// Progress of one subject scan: photos looked at out of the run's work list.
struct SubjectScanProgress: Equatable, Sendable {
    var processed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(processed) / Double(total) : 0 }
}

struct SubjectScanSummary: Equatable, Sendable {
    var scanned: Int
    var failed: Int
    var wasCancelled: Bool
    /// Another scan already owned the actor when this one was asked for.
    var didNotStart = false
}

/// Looks for people and pets in every indexed photo that has not been looked
/// at yet, in batches, so a cancelled or interrupted run resumes from the work
/// list next time.
///
/// **This never runs on its own.** The index pass deliberately decodes no
/// images — it reads EXIF headers only — and adding Vision to it would turn a
/// header read into a full decode of every photo in the library. So this is a
/// separate pass the user starts from Settings, and it is the only place in
/// the app that decodes images in bulk.
actor SubjectScanPipeline {
    static let batchSize = 100
    /// Concurrent reads inside a batch. Lower than the duplicate scan's: that
    /// one hashes a 96px thumbnail, this one runs two Vision requests over a
    /// 512px image, so the work is CPU-bound rather than XPC-bound.
    static let readConcurrency = 4

    private let store: MetadataStore
    private let reader: any SubjectVisionReading
    private var isRunning = false

    init(store: MetadataStore, reader: any SubjectVisionReading) {
        self.store = store
        self.reader = reader
    }

    /// Runs one scan. Cancel by cancelling the calling task; the batch in
    /// flight finishes and is written, then the run returns `wasCancelled`.
    func run(
        allowNetwork: Bool,
        onProgress: @escaping @Sendable (SubjectScanProgress) -> Void
    ) async -> SubjectScanSummary {
        guard !isRunning else {
            return SubjectScanSummary(scanned: 0, failed: 0, wasCancelled: false, didNotStart: true)
        }
        isRunning = true
        defer { isRunning = false }

        let pending = (try? store.assetIdsMissingSubjectScan()) ?? []
        var summary = SubjectScanSummary(scanned: 0, failed: 0, wasCancelled: false)
        var processed = 0
        onProgress(SubjectScanProgress(processed: 0, total: pending.count))

        for batchStart in stride(from: 0, to: pending.count, by: Self.batchSize) {
            if Task.isCancelled {
                summary.wasCancelled = true
                break
            }
            let ids = Array(pending[batchStart..<min(batchStart + Self.batchSize, pending.count)])
            let observations = await observeBatch(ids, allowNetwork: allowNetwork)
            try? store.applySubjectObservations(observations.filter(\.didRead))
            summary.scanned += observations.filter(\.didRead).count
            summary.failed += observations.filter { !$0.didRead }.count
            processed += ids.count
            onProgress(SubjectScanProgress(processed: processed, total: pending.count))
        }
        return summary
    }

    private func observeBatch(
        _ assetIds: [String],
        allowNetwork: Bool
    ) async -> [SubjectObservation] {
        let reader = self.reader
        return await withTaskGroup(of: SubjectObservation.self) { group in
            var results: [SubjectObservation] = []
            results.reserveCapacity(assetIds.count)
            var next = 0
            func enqueue() {
                guard next < assetIds.count else { return }
                let assetId = assetIds[next]
                next += 1
                group.addTask { await reader.observe(assetId: assetId, allowNetwork: allowNetwork) }
            }
            for _ in 0..<min(Self.readConcurrency, assetIds.count) { enqueue() }
            while let result = await group.next() {
                results.append(result)
                enqueue()
            }
            return results
        }
    }
}
