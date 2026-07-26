import Foundation

/// Results of lazy per-cell badge lookups, keyed by assetId.
///
/// While an index run is filling the DB, grid tiles that were loaded without
/// EXIF (PhotoKit fast path, or rows still `pendingRead`) fetch their badge
/// on display instead of the whole grid reloading per indexed photo. This
/// cache remembers *final* answers so a tile scrolled past twice doesn't hit
/// the DB twice, and deliberately forgets *non-final* ones so a tile whose
/// row upgrades (`pendingRead` → `indexed`) picks the badge up on its next
/// display.
///
/// Main-actor confined: callers are the grid cells and `LibraryModel`.
@MainActor
final class GridBadgeCache {
    /// What a lookup found.
    enum LookupResult: Equatable {
        /// Final: the row is indexed — show these fields (may all be nil).
        case badge(LibraryGridItem)
        /// Final: no badge will ever exist (no EXIF, or no row at all —
        /// videos and deleted assets). Named to avoid resolving as
        /// `Optional.none` in `LookupResult?` contexts.
        case noBadge
    }

    private var entries: [String: LookupResult] = [:]

    /// The decision matrix, kept pure for testability: which fetch results
    /// are final (cache them) and which may still change (return nil so the
    /// next display retries — a primary-key SELECT costs microseconds).
    nonisolated static func entry(for row: PhotoMetadata?) -> LookupResult? {
        guard let row else { return .noBadge }
        switch row.resolvedExifStatus {
        case .indexed:
            return .badge(LibraryGridItem(
                assetId: row.assetId,
                creationDate: row.creationDate,
                iso: row.iso,
                aperture: row.aperture,
                shutterSpeedDisplay: row.shutterSpeedDisplay,
                focalLength: row.focalLength,
                equivalentFocalLength: row.equivalentFocalLength,
                width: row.width,
                height: row.height,
                fileSize: row.fileSize
            ))
        case .noExif:
            return .noBadge
        case .pendingRead, .pendingICloud, .error:
            return nil
        }
    }

    func cachedEntry(for assetId: String) -> LookupResult? {
        entries[assetId]
    }

    /// Records a fetch result. Returns the item to display now (nil when the
    /// row has no badge yet or never will).
    @discardableResult
    func record(_ row: PhotoMetadata?, assetId: String) -> LibraryGridItem? {
        guard let entry = Self.entry(for: row) else { return nil }
        entries[assetId] = entry
        if case .badge(let item) = entry { return item }
        return nil
    }

    /// A full grid reload re-fetched every row — everything here is stale.
    func removeAll() {
        entries.removeAll()
    }
}
