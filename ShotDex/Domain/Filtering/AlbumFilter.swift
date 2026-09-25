import Foundation
import Photos

/// What an album screen is narrowed by (FS-06.09): the quick filters from the
/// Filter menu **or** one advanced query, never both — the same one-source rule
/// Library keeps (FS-01.05 §1). Lives with the screen, not the album, so it is
/// gone the next time the album opens.
struct AlbumFilter: Equatable, Sendable {
    private(set) var criteria = FilterCriteria()
    private(set) var advancedQuery: SmartAlbumQuery?

    var isActive: Bool { !criteria.isEmpty || advancedQuery != nil }

    /// Setting a quick filter drops the advanced query.
    mutating func setCriteria(_ newValue: FilterCriteria) {
        criteria = newValue
        if !newValue.isEmpty { advancedQuery = nil }
    }

    /// Setting an advanced query drops the quick filters. An empty query means
    /// no query.
    mutating func setAdvancedQuery(_ newValue: SmartAlbumQuery?) {
        advancedQuery = (newValue?.isEmpty ?? true) ? nil : newValue
        if advancedQuery != nil { criteria = FilterCriteria() }
    }

    mutating func clear() {
        criteria = FilterCriteria()
        advancedQuery = nil
    }
}

/// The part of the quick filters Photos can answer itself, as a fetch predicate
/// for an album's assets: favorite, photo/video, and capture kind.
///
/// Photos is asked rather than the index so a photo the indexer has not reached
/// yet still filters correctly. The one exception is a panorama ShotDex
/// stitched: it carries no system flag, so its id comes from the index and is
/// matched by identifier (FS-14 §7).
enum AlbumFilterPredicate {
    /// Nil when the criteria ask Photos for nothing.
    static func predicate(
        for criteria: FilterCriteria,
        stitchedPanoramaIds: [String] = []
    ) -> NSPredicate? {
        var parts: [NSPredicate] = []

        if criteria.favoritesOnly {
            parts.append(NSPredicate(format: "favorite == YES"))
        }

        // Both kinds, or none, constrain nothing — as in the index query.
        if criteria.mediaKinds.count == 1, let kind = criteria.mediaKinds.first {
            parts.append(NSPredicate(format: "mediaType == %d", mediaType(for: kind).rawValue))
        }

        if !criteria.mediaSubtypes.isEmpty {
            var kinds: [NSPredicate] = criteria.mediaSubtypes
                .sorted { $0.bit < $1.bit }
                .map { NSPredicate(format: "(mediaSubtypes & %d) != 0", $0.bit) }
            if criteria.mediaSubtypes.contains(.panorama), !stitchedPanoramaIds.isEmpty {
                kinds.append(NSPredicate(format: "localIdentifier IN %@", stitchedPanoramaIds))
            }
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: kinds))
        }

        switch parts.count {
        case 0: return nil
        case 1: return parts[0]
        default: return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        }
    }

    /// Whether the criteria hold anything Photos cannot answer — camera, lens,
    /// exposure, search text. The Filter menu never sets these, but a criteria
    /// value carrying them must go to the index instead.
    static func needsIndex(_ criteria: FilterCriteria) -> Bool {
        var photosOnly = FilterCriteria()
        photosOnly.favoritesOnly = criteria.favoritesOnly
        photosOnly.mediaKinds = criteria.mediaKinds
        photosOnly.mediaSubtypes = criteria.mediaSubtypes
        return photosOnly != criteria
    }

    private static func mediaType(for kind: MediaKind) -> PHAssetMediaType {
        switch kind {
        case .photo: .image
        case .video: .video
        }
    }
}
