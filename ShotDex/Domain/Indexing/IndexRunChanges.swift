import Foundation
import os

/// What one index run learned about the library, handed to every observer
/// once the run ends (FS-01.12 AC-11; shared with FS-02.07 AC-10).
///
/// Built from **what Photos reported**, not from the run's work list: an id
/// Photos says was updated but whose modification date did not move is
/// skipped by `IndexPipeline.needsReindex` — no file is read — and is still
/// here, because favorite, star rating, caption and keywords can all change
/// without the date. Each observer refreshes its own facts for these ids.
struct IndexRunChanges: Equatable, Sendable {
    /// Inserted ∪ updated, minus deleted. On a full walk: the assets the walk
    /// read again plus those whose favorite or rating drifted.
    var changed: Set<String>
    /// Ids Photos reports gone (incremental) or the walk no longer found.
    var deleted: Set<String>
    /// The run walked the whole library instead of replaying history — an
    /// observer that keeps a mirror of its own may want to do the same.
    var isFullWalk: Bool
    /// Full photo access while the run ran. Under `.limited` a photo that
    /// left the shared set looks deleted to a full walk, and user data must
    /// not be removed on that evidence (FS-01.12 §4).
    var accessIsFull: Bool

    var isEmpty: Bool { changed.isEmpty && deleted.isEmpty }

    /// The incremental run's changes, straight from Photos' history.
    static func incremental(
        inserted: Set<String>, updated: Set<String>, deleted: Set<String>, accessIsFull: Bool
    ) -> IndexRunChanges {
        IndexRunChanges(
            changed: inserted.union(updated).subtracting(deleted),
            deleted: deleted,
            isFullWalk: false,
            accessIsFull: accessIsFull
        )
    }
}

/// Who hears about a finished run. Registered once at launch from the
/// composition root; called in registration order, each awaited, so an
/// observer that writes the database is done before the next run starts.
final class IndexRunObservers: Sendable {
    typealias Observer = @Sendable (IndexRunChanges) async -> Void

    private let observers = OSAllocatedUnfairLock<[Observer]>(initialState: [])

    func add(_ observer: @escaping Observer) {
        observers.withLock { $0.append(observer) }
    }

    func deliver(_ changes: IndexRunChanges) async {
        guard !changes.isEmpty else { return }
        for observer in observers.withLock({ $0 }) {
            await observer(changes)
        }
    }
}

/// Favorite and Photos star rating as read off an asset in memory.
struct AssetFacts: Equatable, Sendable {
    var isFavorite: Bool
    /// iOS 27 and later; nil below.
    var rating: Int?

    /// Whether the indexed row disagrees with the asset on a fact the
    /// modification date does not always track. Pure — `IndexDiffTests`.
    static func drifted(stored: IndexedAssetState?, current: AssetFacts) -> Bool {
        guard let stored else { return false }
        if let favorite = stored.isFavorite, favorite != current.isFavorite { return true }
        if let rating = current.rating, stored.rating != rating { return true }
        return false
    }
}

/// The first observer of `IndexRunChanges`: rewrites favorite and Photos
/// rating for every changed id from the assets in memory. Reads no file —
/// it has no reader to read one with.
struct AssetFactsRefresher: Sendable {
    let metadataStore: MetadataStore
    /// Facts by id for the ids that still exist. PhotoKit in the app, a
    /// dictionary in tests.
    let readFacts: @Sendable ([String]) -> [String: AssetFacts]

    static let batchSize = 2_000

    func refresh(_ changes: IndexRunChanges) {
        let ids = Array(changes.changed.subtracting(changes.deleted))
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let slice = Array(ids[start..<min(start + Self.batchSize, ids.count)])
            try? metadataStore.updateAssetFacts(readFacts(slice))
        }
    }
}
