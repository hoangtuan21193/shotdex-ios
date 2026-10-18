import Foundation
import Photos

/// Anything that can feed the fullscreen viewer with photo pages. Index
/// based so the viewer renders only a small window around the current page
/// — sources may hold the whole library and must not be forced to hand the
/// pager a full metadata array. Full `PhotoMetadata` is fetched per page.
@MainActor
protocol PhotoBrowsingSource: AnyObject {
    var photoCount: Int { get }
    /// Writable user album that owns the opened grid, if any. New copies are
    /// added back to this collection after Edit/Compress.
    var sourceAlbum: PHAssetCollection? { get }
    func photoId(at index: Int) -> String?
    /// Current position of a photo by its stable id. Viewers open by identity
    /// (not a captured position) so a deletion that shifts the array can't
    /// desync the opened page.
    func index(of assetId: String) -> Int?
    /// Full row for the chrome/metadata panel (Library: a DB lookup by primary key;
    /// Albums/On This Day: in-memory array).
    func metadata(for assetId: String) -> PhotoMetadata?
    func asset(for assetId: String) -> PHAsset?
    /// Sources that page (Albums) top up here; full-load sources no-op.
    func loadNextPageIfNeeded(currentIndex: Int)
    func syncFavorite(assetId: String, isFavorite: Bool)
    /// Deletes one asset via PhotoKit (which shows its own system confirm) and
    /// prunes it from the source. Throws `PHPhotosError.userCancelled` if the
    /// user cancels the system dialog.
    func deleteAsset(id: String) async throws
    /// After a full-size image finishes downloading from iCloud, read its EXIF
    /// and persist it so a `pendingICloud`/`error`/unindexed row fills in and
    /// never needs re-downloading. Returns the refreshed row (for the info
    /// panel), or nil when nothing changed.
    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata?
    /// Drops photos a deletion through the sources removed (FS-19.04 §2).
    /// A requirement, not only an extension method, so a source's own
    /// version is the one a viewer calls.
    func removeDeleted(ids: Set<String>)
}

extension PhotoBrowsingSource {
    var sourceAlbum: PHAssetCollection? { nil }

    /// Sources that hold only Photos assets drop them on their next load.
    func removeDeleted(ids: Set<String>) {}

    /// Every photo the viewer is paging through, for Cull From Here
    /// (FS-01.12b §5). The default walks the indices — the whole list for a
    /// source that loads everything; a paging source (Albums) covers what
    /// it has loaded so far.
    func allPhotoIds() -> [String] {
        (0..<photoCount).compactMap(photoId(at:))
    }
}
