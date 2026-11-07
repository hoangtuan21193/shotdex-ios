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
/// a file photo's own stars (FS-19.05 §3), else what Photos holds
/// (`photosRating`, read off the asset by the caller), else 0. Where stars are stored is decided once, by whether a
/// `ratingWriter` is given: none below iOS 27 (pending rows), the PhotoKit
/// writer from iOS 27 (FS-01.12 §4–5). Tests inject either.
@MainActor
@Observable
final class PhotoMarks {
    /// Bumped on every change, so the grid can tell "new marks" without
    /// diffing two maps of 55k ids.
    private(set) var version = 0

    @ObservationIgnored private var flags: [String: PhotoFlag] = [:]
    @ObservationIgnored private var pendingRatings: [String: Int] = [:]
    /// Stars of file photos — read from their sidecars or set in ShotDex
    /// (FS-19.05 §3). Below a pending star, above Photos' own.
    @ObservationIgnored private var fileRatings: [String: Int] = [:]
    /// Ratings this session wrote to Photos. The grid's `PHAsset`s are not
    /// refetched after a content-only change, so their `rating` is stale
    /// until the chunk reloads; this map is what the cells read meanwhile.
    @ObservationIgnored private var writtenRatings: [String: Int] = [:]
    @ObservationIgnored private let store: PhotoMarksStore
    @ObservationIgnored private let metadataStore: MetadataStore?
    @ObservationIgnored private let ratingWriter: (any PhotoPropertyWriting)?
    /// `PHAsset.rating` by id, for the "before" of an undo when the caller
    /// did not pass it. Empty below iOS 27.
    @ObservationIgnored private let readPhotosRatings: @Sendable ([String]) -> [String: Int]
    /// Where a file photo's stars go after its row (FS-19.02 §5); nil writes
    /// no sidecars.
    @ObservationIgnored private let sidecarQueue: SidecarWriteQueue?
    @ObservationIgnored private var hasLoaded = false

    /// Set when a write to Photos failed; the host shows "Couldn't save
    /// rating." with Try Again (FS-01.12 AC-10).
    private(set) var failedRatingWrite: FailedRatingWrite?
    /// Told when a write to Photos failed — the host raises the banner.
    @ObservationIgnored var onRatingWriteFailed: (@MainActor () -> Void)?

    init(
        store: PhotoMarksStore,
        metadataStore: MetadataStore? = nil,
        ratingWriter: (any PhotoPropertyWriting)? = nil,
        readPhotosRatings: @escaping @Sendable ([String]) -> [String: Int] = { _ in [:] },
        sidecarQueue: SidecarWriteQueue? = nil
    ) {
        self.sidecarQueue = sidecarQueue
        self.store = store
        self.metadataStore = metadataStore
        self.ratingWriter = ratingWriter
        self.readPhotosRatings = readPhotosRatings
        if let sidecarQueue {
            // Values another app wrote into a sidecar come in during a write;
            // the cells follow them.
            let reload: @Sendable (Set<String>) async -> Void = { [weak self] _ in await self?.reload() }
            Task { await sidecarQueue.setOnReread(reload) }
        }
    }

    /// Whether stars go to Photos rather than to pending rows.
    var writesRatingsToPhotos: Bool { ratingWriter != nil }

    // MARK: Reads

    func flag(for assetId: String) -> PhotoFlag? { flags[assetId] }

    /// The rating the app shows. `photosRating` is `PHAsset.rating` on
    /// iOS 27 (nil below it, or when the caller has no asset).
    func rating(for assetId: String, photosRating: Int? = nil) -> Int {
        pendingRatings[assetId] ?? writtenRatings[assetId] ?? fileRatings[assetId] ?? photosRating ?? 0
    }

    func summary(for assetId: String, photosRating: Int? = nil) -> PhotoMarkSummary {
        PhotoMarkSummary(rating: rating(for: assetId, photosRating: photosRating), flag: flags[assetId])
    }

    /// Ids flagged `flag` — the culling pass's counts and Delete Rejected.
    func assetIds(flagged flag: PhotoFlag) -> Set<String> {
        Set(flags.lazy.filter { $0.value == flag }.map(\.key))
    }

    /// The marks an album's Photos fetch filters by.
    var filterSnapshot: MarkFilterSnapshot {
        var photosHoldsRatings = false
        if #available(iOS 27, macOS 27, *) { photosHoldsRatings = true }
        return MarkFilterSnapshot(flags: flags, pendingRatings: pendingRatings, photosHoldsRatings: photosHoldsRatings)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        let store = store
        let (flags, ratings, fileRatings) = await Task.detached(priority: .utility) {
            ((try? store.allFlags()) ?? [:], (try? store.allPendingRatings()) ?? [:],
             (try? PhotoUserMarksStore(database: store.database).allRatings()) ?? [:])
        }.value
        self.flags = flags
        self.pendingRatings = ratings
        self.fileRatings = fileRatings
        version += 1
    }

    // MARK: Writes

    /// Sets the stars of every id (0 clears them) and returns what to undo.
    ///
    /// Below iOS 27 the rating is a pending row: one per photo, removed again
    /// when the stars are cleared, since there is nothing in Photos for a
    /// row of 0 to win over.
    @discardableResult
    func setRating(_ rating: Int, ids: [String], photosRatings: [String: Int]? = nil) async -> MarkChange {
        let rating = StarRating.clamped(rating)
        // A PhotoKit fetch of the whole selection: never on the main actor.
        let read = readPhotosRatings
        let known = if let photosRatings { photosRatings } else if ratingWriter == nil { [String: Int]() } else {
            await Task.detached(priority: .userInitiated) { read(ids) }.value
        }
        var previous: [String: Int] = [:]
        for id in ids { previous[id] = self.rating(for: id, photosRating: known[id]) }
        let change = MarkChange(kind: .rating(previous: previous))
        let ids = await setFileRatings(ids.reduce(into: [:]) { $0[$1] = rating })
        guard !ids.isEmpty else { return change }
        if ratingWriter != nil {
            await writeToPhotos(ids.reduce(into: [:]) { $0[$1] = rating }, previous: previous)
            return change
        }
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

    /// Stars of photos with a file copy go to their own row and on to the
    /// sidecars beside the files; returns the ids that also go to Photos —
    /// every id with a Photos copy (FS-19.05 §2). A file-only photo has no
    /// asset, so it never reaches the pending table or the Photos write.
    private func setFileRatings(_ ratings: [String: Int]) async -> [String] {
        let userMarks = PhotoUserMarksStore(database: store.database)
        let ids = Array(ratings.keys)
        let kinds = await Task.detached(priority: .userInitiated) {
            (try? userMarks.copyKinds(ids: ids)) ?? (files: [], photos: [])
        }.value
        let files = ratings.filter { kinds.files.contains($0.key) }
        if !files.isEmpty {
            for (id, rating) in files { fileRatings[id] = rating }
            version += 1
            await Task.detached(priority: .userInitiated) {
                try? userMarks.setRatings(files)
            }.value
            await sidecarQueue?.schedule(Array(files.keys))
        }
        return ids.filter { !kinds.files.contains($0) || kinds.photos.contains($0) }
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
        await scheduleSidecars(ids)
        return change
    }

    /// Photos with a file copy carry their flag in their sidecars too.
    private func scheduleSidecars(_ ids: [String]) async {
        guard let sidecarQueue else { return }
        let userMarks = PhotoUserMarksStore(database: store.database)
        let files = await Task.detached(priority: .userInitiated) {
            (try? userMarks.copyKinds(ids: ids).files) ?? []
        }.value
        if !files.isEmpty { await sidecarQueue.schedule(Array(files)) }
    }

    /// iOS 27: one block for the whole command. The cells show the new value
    /// at once; on success the filter column, the modification date and any
    /// pending rows of these photos follow; on failure every photo goes back
    /// to what it showed and the failure is kept for Try Again.
    private func writeToPhotos(_ ratings: [String: Int], previous: [String: Int]) async {
        guard let ratingWriter, !ratings.isEmpty else { return }
        let removedPending = pendingRatings.filter { ratings[$0.key] != nil }
        for (id, rating) in ratings {
            writtenRatings[id] = rating
            pendingRatings[id] = nil
        }
        failedRatingWrite = nil
        version += 1
        do {
            let result = try await ratingWriter.setRatings(ratings)
            let store = store
            let metadataStore = metadataStore
            let ids = Array(ratings.keys)
            await Task.detached(priority: .userInitiated) {
                try? metadataStore?.recordRatingWrite(ratings, result: result)
                try? store.deletePendingRatings(ids: ids)
            }.value
        } catch {
            for (id, rating) in previous { writtenRatings[id] = rating }
            for (id, rating) in removedPending { pendingRatings[id] = rating }
            failedRatingWrite = FailedRatingWrite(ratings: ratings)
            version += 1
            onRatingWriteFailed?()
        }
    }

    /// Try Again on a failed write: the same photos, the same stars.
    func retryFailedRatingWrite() async {
        guard let failed = failedRatingWrite else { return }
        var previous: [String: Int] = [:]
        for id in failed.ratings.keys { previous[id] = rating(for: id) }
        await writeToPhotos(failed.ratings, previous: previous)
    }

    func dismissFailedRatingWrite() { failedRatingWrite = nil }

    /// Puts back what `change` replaced.
    func undo(_ change: MarkChange) async {
        let store = store
        switch change.kind {
        case .rating(let all):
            let photosIds = Set(await setFileRatings(all))
            let previous = all.filter { photosIds.contains($0.key) }
            if !previous.isEmpty { await undoRating(previous) }
        case .flag(let previous):
            for (id, flag) in previous { flags[id] = flag }
            version += 1
            await Task.detached(priority: .userInitiated) {
                try? store.restoreFlags(previous)
            }.value
            await scheduleSidecars(Array(previous.keys))
        }
    }

    /// Undo of a rating on photos that have a Photos copy.
    private func undoRating(_ previous: [String: Int]) async {
        if ratingWriter != nil {
            var current: [String: Int] = [:]
            for id in previous.keys { current[id] = rating(for: id) }
            await writeToPhotos(previous, previous: current)
            return
        }
        var restore: [String: Int?] = [:]
        for (id, rating) in previous {
            pendingRatings[id] = rating == 0 ? nil : rating
            restore[id] = rating == 0 ? .some(nil) : .some(rating)
        }
        version += 1
        let store = store
        await Task.detached(priority: .userInitiated) {
            try? store.restorePendingRatings(restore)
        }.value
    }

    /// One key or menu row on `ids` — the viewer, the selection and the
    /// culling pass all come through here.
    @discardableResult
    func apply(_ action: MarkKeyAction, to ids: [String]) async -> MarkChange {
        switch action {
        case .rate(let stars): await setRating(stars, ids: ids)
        case .flag(let flag): await setFlag(flag, ids: ids)
        }
    }

    /// Removes every mark of photos that are gone — the rows and the memory.
    /// Used when the user clears marks; a photo leaving the library only
    /// leaves memory (`forget`), its rows wait out `OrphanRetention`.
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
            writtenRatings.removeValue(forKey: id)
            if flags.removeValue(forKey: id) != nil { changed = true }
            if pendingRatings.removeValue(forKey: id) != nil { changed = true }
            if fileRatings.removeValue(forKey: id) != nil { changed = true }
        }
        if changed { version += 1 }
    }
}

/// A rating write Photos refused, kept so Try Again sends the same command.
struct FailedRatingWrite: Equatable, Sendable {
    let ratings: [String: Int]
}
