import Foundation
import Observation

/// One undoable change to marks: what each touched photo held before it.
struct MarkChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Previous rating per id as the app showed it.
        case rating(previous: [String: Int])
        /// Previous flag per id (`nil` = no flag).
        case flag(previous: [String: PhotoFlag?])
    }

    let kind: Kind

    var assetIds: [String] {
        switch kind {
        case .rating(let previous): Array(previous.keys)
        case .flag(let previous): Array(previous.keys)
        }
    }
}

/// Star ratings and Pick/Reject flags in memory, for every surface that
/// reads them per photo — the grid's glyphs, the viewer's second line, the
/// culling pass — without a database query per cell (FS-01.12 §4, NF-01
/// rule 1). Also the **one** place marks are written, so a key, a menu row
/// and a swipe all go through the same code.
///
/// The current rating of a photo is the pending row when there is one, else
/// what Photos holds (`photosRating`, read off the asset by the caller),
/// else 0.
@MainActor
@Observable
final class PhotoMarks {
    /// Bumped on every change, so the grid can tell "new marks" without
    /// diffing two maps of 55k ids.
    private(set) var version = 0

    @ObservationIgnored private var flags: [String: PhotoFlag] = [:]
    @ObservationIgnored private var pendingRatings: [String: Int] = [:]
    @ObservationIgnored private let store: PhotoMarksStore
    @ObservationIgnored private var hasLoaded = false

    init(store: PhotoMarksStore) {
        self.store = store
    }

    // MARK: Reads

    func flag(for assetId: String) -> PhotoFlag? { flags[assetId] }

    /// The rating the app shows. `photosRating` is `PHAsset.rating` on
    /// iOS 27 (nil below it, or when the caller has no asset).
    func rating(for assetId: String, photosRating: Int? = nil) -> Int {
        pendingRatings[assetId] ?? photosRating ?? 0
    }

    func summary(for assetId: String, photosRating: Int? = nil) -> PhotoMarkSummary {
        PhotoMarkSummary(rating: rating(for: assetId, photosRating: photosRating), flag: flags[assetId])
    }

    /// Ids flagged `flag` — the culling pass's counts and Delete Rejected.
    func assetIds(flagged flag: PhotoFlag) -> Set<String> {
        Set(flags.lazy.filter { $0.value == flag }.map(\.key))
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        let store = store
        let (flags, ratings) = await Task.detached(priority: .utility) {
            ((try? store.allFlags()) ?? [:], (try? store.allPendingRatings()) ?? [:])
        }.value
        self.flags = flags
        self.pendingRatings = ratings
        version += 1
    }

    // MARK: Writes

    /// Sets the stars of every id (0 clears them) and returns what to undo.
    ///
    /// Below iOS 27 the rating is a pending row: one per photo, removed again
    /// when the stars are cleared, since there is nothing in Photos for a
    /// row of 0 to win over.
    @discardableResult
    func setRating(_ rating: Int, ids: [String], photosRatings: [String: Int] = [:]) async -> MarkChange {
        let rating = StarRating.clamped(rating)
        var previous: [String: Int] = [:]
        for id in ids { previous[id] = self.rating(for: id, photosRating: photosRatings[id]) }
        let change = MarkChange(kind: .rating(previous: previous))
        for id in ids { pendingRatings[id] = rating == 0 ? nil : rating }
        version += 1
        let store = store
        await Task.detached(priority: .userInitiated) {
            if rating == 0 {
                try? store.deletePendingRatings(ids: ids)
            } else {
                try? store.setPendingRating(rating, ids: ids)
            }
        }.value
        return change
    }

    /// Sets (or with `nil` clears) the flag of every id. Pick on a Rejected
    /// photo replaces the flag — three exclusive states (FS-01.12 §6). Never
    /// touches favorite.
    @discardableResult
    func setFlag(_ flag: PhotoFlag?, ids: [String]) async -> MarkChange {
        var previous: [String: PhotoFlag?] = [:]
        for id in ids { previous[id] = .some(flags[id]) }
        let change = MarkChange(kind: .flag(previous: previous))
        for id in ids { flags[id] = flag }
        version += 1
        let store = store
        await Task.detached(priority: .userInitiated) {
            try? store.setFlag(flag, ids: ids)
        }.value
        return change
    }

    /// Puts back what `change` replaced.
    func undo(_ change: MarkChange) async {
        let store = store
        switch change.kind {
        case .rating(let previous):
            var restore: [String: Int?] = [:]
            for (id, rating) in previous {
                pendingRatings[id] = rating == 0 ? nil : rating
                restore[id] = rating == 0 ? .some(nil) : .some(rating)
            }
            version += 1
            await Task.detached(priority: .userInitiated) {
                try? store.restorePendingRatings(restore)
            }.value
        case .flag(let previous):
            for (id, flag) in previous { flags[id] = flag }
            version += 1
            await Task.detached(priority: .userInitiated) {
                try? store.restoreFlags(previous)
            }.value
        }
    }

    /// Removes every mark of photos that are gone — the rows and the memory.
    /// Callers decide *whether* they are gone (`UserMarkRemovalPolicy`).
    func removeMarks(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let store = store
        await Task.detached(priority: .utility) {
            try? store.deleteMarks(ids: ids)
        }.value
        forget(ids)
    }

    /// Forgets the marks of photos that are gone — after the store rows went.
    func forget(_ ids: some Sequence<String>) {
        var changed = false
        for id in ids {
            if flags.removeValue(forKey: id) != nil { changed = true }
            if pendingRatings.removeValue(forKey: id) != nil { changed = true }
        }
        if changed { version += 1 }
    }
}
