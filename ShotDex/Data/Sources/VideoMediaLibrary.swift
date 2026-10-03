import Foundation
import Photos

/// What the Video Studio's Media panel lists (FS-12.09 §2): the photo
/// library read straight from PhotoKit, as a **lazy** fetch result — no cap,
/// no array of 55,000 `PHAsset`s built on the main actor. The grid asks for
/// the item at an index when a cell needs it, so scrolling to the oldest
/// photo costs what the cells on screen cost.
///
/// One per Media panel. It lists one source at a time — Recents, one album,
/// or the result of a search — and refetches when the library changes, so a
/// grant made in the limited-access picker shows up without closing the
/// panel (FS-12.09 §5).
@MainActor @Observable
final class VideoMediaLibrary {
    enum Source: Equatable {
        /// Every photo and video, newest first.
        case recents
        /// One album, by its collection's local identifier.
        case album(String)
        /// The items a Library search matched, newest first.
        case search([String])
    }

    let photoLibrary: PhotoLibraryService
    private(set) var source: Source = .recents
    @ObservationIgnored private var result: PHFetchResult<PHAsset> = PHFetchResult()
    /// Bumped on every refetch, so a view holding the grid knows to reload it.
    private(set) var revision = 0
    /// How many items the current source has — the grid's item count.
    private(set) var count = 0

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    /// Whether the library can be listed at all.
    var canRead: Bool { photoLibrary.authorizationState.canReadLibrary }

    /// The asset at `index` of the current source, or nil past the end
    /// (a change can land between a count and a cell asking).
    func asset(at index: Int) -> PHAsset? {
        guard index >= 0, index < result.count else { return nil }
        return result.object(at: index)
    }

    /// Several at once, for prefetching: one call into PhotoKit, not one
    /// per index.
    func assets(in range: Range<Int>) -> [PHAsset] {
        let clamped = range.clamped(to: 0..<result.count)
        guard !clamped.isEmpty else { return [] }
        return result.objects(at: IndexSet(integersIn: clamped))
    }

    func show(_ source: Source) {
        guard source != self.source || revision == 0 else { return }
        self.source = source
        reload()
    }

    /// Fetches the current source again — on open, on a change of source,
    /// and whenever the library changes underneath.
    func reload() {
        if canRead {
            switch source {
            case .recents:
                result = PHAsset.fetchAssets(with: Self.recentsOptions())
            case .album(let id):
                if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
                    result = PHAsset.fetchAssets(in: album, options: Self.albumOptions())
                } else {
                    result = PHFetchResult()
                }
            case .search(let ids):
                result = ids.isEmpty
                    ? PHFetchResult()
                    : PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.searchOptions())
            }
        } else {
            result = PHFetchResult()
        }
        count = result.count
        revision &+= 1
    }

    // MARK: Fetch options (pure, so they are tested)

    /// Recents: photos and videos, newest first, and **no fetch limit** — the
    /// old pool stopped at 400 and sent everything older to the system
    /// picker, which the Media panel does not have.
    nonisolated static func recentsOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    /// An album's own items, photos and videos, newest first.
    nonisolated static func albumOptions() -> PHFetchOptions {
        recentsOptions()
    }

    /// A search's matches in the order Recents would show them.
    nonisolated static func searchOptions() -> PHFetchOptions {
        recentsOptions()
    }
}

/// How far ahead the Media grid asks PhotoKit to prepare thumbnails
/// (FS-12.09 §7): at most two screens of grid beyond what is on screen —
/// one above, one below — so a fast fling still lands on painted cells and
/// a 55,000-item library never has more than three screens' worth cached.
enum VideoMediaPrefetch {
    /// Items one screen of grid holds: whole rows, rounded up.
    static func itemsPerScreen(columns: Int, cellHeight: CGFloat, viewportHeight: CGFloat) -> Int {
        guard columns > 0, cellHeight > 0 else { return 0 }
        return Int((viewportHeight / cellHeight).rounded(.up)) * columns
    }

    /// The items to keep warm for a visible range: a screen either side,
    /// inside the fetch.
    static func window(visible: Range<Int>, itemsPerScreen: Int, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let lower = max(0, visible.lowerBound - itemsPerScreen)
        let upper = min(count, visible.upperBound + itemsPerScreen)
        return lower..<max(lower, upper)
    }

    /// The parts of `range` that `removed` does not cover — none, one, or
    /// the two ends — so a moved window starts and stops caching only what
    /// actually entered or left it.
    static func subtract(_ removed: Range<Int>, from range: Range<Int>) -> [Range<Int>] {
        guard !range.isEmpty else { return [] }
        guard removed.overlaps(range) else { return [range] }
        var parts: [Range<Int>] = []
        if range.lowerBound < removed.lowerBound { parts.append(range.lowerBound..<removed.lowerBound) }
        if removed.upperBound < range.upperBound { parts.append(removed.upperBound..<range.upperBound) }
        return parts
    }
}
