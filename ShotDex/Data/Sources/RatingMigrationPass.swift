import Foundation

/// Moves the stars set below iOS 27 into Photos, once, after first paint on
/// the first launch under iOS 27 (FS-01.12 §5, AC-3–AC-5).
///
/// One block for the whole lot. A failure leaves every row where it was —
/// they still filter — and the next launch tries again; never more than once
/// per launch. A success says so once: "Moved 1,232 star ratings to Photos."
@MainActor
final class RatingMigrationPass {
    enum Outcome: Equatable, Sendable {
        /// Nothing pending, no writer (below iOS 27), or already tried.
        case notRun
        case moved(Int)
        case failed
    }

    private let store: PhotoMarksStore
    private let metadataStore: MetadataStore
    private let writer: (any PhotoPropertyWriting)?
    /// `PHAsset.rating` of the ids PhotoKit returns — existing and visible.
    private let readPhotosRatings: @Sendable ([String]) -> [String: Int]
    private let accessIsFull: () -> Bool
    private let now: () -> Date
    private var hasRunThisLaunch = false

    /// Told how many stars moved, for the banner.
    var onMoved: ((Int) -> Void)?
    /// Told after any change to the pending rows, so the in-memory index
    /// re-reads them.
    var onPendingChanged: (() async -> Void)?

    init(
        store: PhotoMarksStore,
        metadataStore: MetadataStore,
        writer: (any PhotoPropertyWriting)?,
        readPhotosRatings: @escaping @Sendable ([String]) -> [String: Int],
        accessIsFull: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.metadataStore = metadataStore
        self.writer = writer
        self.readPhotosRatings = readPhotosRatings
        self.accessIsFull = accessIsFull
        self.now = now
    }

    @discardableResult
    func runIfNeeded() async -> Outcome {
        guard let writer, !hasRunThisLaunch else { return .notRun }
        hasRunThisLaunch = true
        let store = store
        let readAt = Int(now().timeIntervalSince1970)
        let pending = await Task.detached(priority: .utility) { (try? store.pendingRatingRows()) ?? [] }.value
        guard !pending.isEmpty else { return .notRun }

        let read = readPhotosRatings
        let photosRatings = await Task.detached(priority: .utility) { read(pending.map(\.assetId)) }.value
        let plan = RatingMigrationPlan.make(pending: pending, photosRatings: photosRatings, accessIsFull: accessIsFull())
        guard !plan.isEmpty else { return .notRun }

        let result: PropertyWriteResult
        do {
            result = plan.writes.isEmpty ? .empty : try await writer.setRatings(plan.writes)
        } catch {
            return .failed
        }
        let metadataStore = metadataStore
        await Task.detached(priority: .utility) {
            try? metadataStore.recordRatingWrite(plan.writes, result: result)
            try? store.deletePendingRatings(ids: plan.rowsToDelete, ratedAtOrBefore: readAt)
        }.value
        await onPendingChanged?()
        if !plan.writes.isEmpty { onMoved?(plan.writes.count) }
        return .moved(plan.writes.count)
    }
}
