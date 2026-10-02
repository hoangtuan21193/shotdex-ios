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
/// for an album's assets: favorite, photo/video, capture kind — and stars and
/// flags, by identifier from the app's own marks (FS-01.12 §7).
///
/// Photos is asked rather than the index so a photo the indexer has not reached
/// yet still filters correctly. The one exception is a panorama ShotDex
/// stitched: it carries no system flag, so its id comes from the index and is
/// matched by identifier (FS-14 §7).
enum AlbumFilterPredicate {
    /// Nil when the criteria ask Photos for nothing.
    static func predicate(
        for criteria: FilterCriteria,
        stitchedPanoramaIds: [String] = [],
        unsupportedRAWIds: [String] = [],
        marks: MarkFilterSnapshot = .empty
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
                .filter(\.hasSystemBit)
                .sorted { $0.bit < $1.bit }
                .map { NSPredicate(format: "(mediaSubtypes & %d) != 0", $0.bit) }
            if criteria.mediaSubtypes.contains(.panorama), let byId = identifierPredicate(stitchedPanoramaIds) {
                kinds.append(byId)
            }
            // Unsupported RAW has no system flag: the index's ids, cut to the
            // album by the fetch itself (FS-03.04b AC-13). None → matches none.
            if criteria.mediaSubtypes.contains(.unsupportedRAW) {
                kinds.append(identifierPredicate(unsupportedRAWIds) ?? NSPredicate(value: false))
            }
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: kinds))
        }

        if let rating = criteria.ratingFilter {
            parts.append(ratingPredicate(rating, marks: marks))
        }
        if let flags = flagPredicate(criteria.flags, marks: marks) {
            parts.append(flags)
        }

        switch parts.count {
        case 0: return nil
        case 1: return parts[0]
        default: return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        }
    }

    /// The current rating — the pending row when there is one, else what
    /// Photos holds — as a fetch predicate: the same rule as
    /// `PhotoMarksStore.ratingCondition`, with the pending ids carried by
    /// identifier. Below iOS 27 Photos holds no rating, so outside the
    /// pending rows every photo is unrated.
    static func ratingPredicate(_ filter: RatingFilter, marks: MarkFilterSnapshot) -> NSPredicate {
        let matchingPending = marks.pendingRatings.filter { filter.matches($0.value) }.map(\.key).sorted()
        let photosTest: NSPredicate = switch (filter, marks.photosHoldsRatings) {
        case (.atLeast(let stars), true): NSPredicate(format: "rating >= %d", StarRating.clamped(stars))
        case (.unrated, true): NSPredicate(format: "rating == 0")
        case (.atLeast, false): NSPredicate(value: false)
        case (.unrated, false): NSPredicate(value: true)
        }
        let fromPhotos: NSPredicate = identifierPredicate(marks.pendingRatings.keys.sorted()).map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [NSCompoundPredicate(notPredicateWithSubpredicate: $0), photosTest])
        } ?? photosTest
        guard let fromPending = identifierPredicate(matchingPending) else { return fromPhotos }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [fromPending, fromPhotos])
    }

    /// Picks / Rejected / Unflagged by identifier. Nil when nothing or
    /// everything is asked for.
    static func flagPredicate(_ filters: Set<PhotoFlagFilter>, marks: MarkFilterSnapshot) -> NSPredicate? {
        guard !filters.isEmpty, filters.count < PhotoFlagFilter.allCases.count else { return nil }
        let ids = { (flag: PhotoFlag) in marks.flags.filter { $0.value == flag }.map(\.key).sorted() }
        let parts: [NSPredicate] = PhotoFlagFilter.allCases.filter(filters.contains).map { filter in
            switch filter {
            case .picks: identifierPredicate(ids(.pick)) ?? NSPredicate(value: false)
            case .rejected: identifierPredicate(ids(.reject)) ?? NSPredicate(value: false)
            case .unflagged: identifierPredicate(marks.flags.keys.sorted())
                .map { NSCompoundPredicate(notPredicateWithSubpredicate: $0) } ?? NSPredicate(value: true)
            }
        }
        return parts.count == 1 ? parts[0] : NSCompoundPredicate(orPredicateWithSubpredicates: parts)
    }

    /// Largest id list one `IN` clause carries. Photos documents no ceiling,
    /// so a selection of 20,000 or a library of stitched panoramas is split
    /// rather than handed over as one array.
    static let identifierChunkSize = 500

    /// `localIdentifier IN …` for `ids`, split into ORed chunks of at most
    /// `identifierChunkSize`. Nil for no ids.
    static func identifierPredicate(_ ids: [String]) -> NSPredicate? {
        guard !ids.isEmpty else { return nil }
        let chunks = stride(from: 0, to: ids.count, by: identifierChunkSize).map { start in
            NSPredicate(
                format: "localIdentifier IN %@",
                Array(ids[start..<min(start + identifierChunkSize, ids.count)])
            )
        }
        return chunks.count == 1 ? chunks[0] : NSCompoundPredicate(orPredicateWithSubpredicates: chunks)
    }

    /// Whether the criteria hold anything Photos cannot answer — camera, lens,
    /// exposure, search text. `predicate(for:)` silently ignores those, so an
    /// album asserts this is false before building a fetch; the Filter menu
    /// never sets them.
    static func needsIndex(_ criteria: FilterCriteria) -> Bool {
        var photosOnly = FilterCriteria()
        photosOnly.favoritesOnly = criteria.favoritesOnly
        photosOnly.mediaKinds = criteria.mediaKinds
        photosOnly.mediaSubtypes = criteria.mediaSubtypes
        // Stars and flags are answered by identifier from `PhotoMarks`.
        photosOnly.ratingFilter = criteria.ratingFilter
        photosOnly.flags = criteria.flags
        return photosOnly != criteria
    }

    private static func mediaType(for kind: MediaKind) -> PHAssetMediaType {
        switch kind {
        case .photo: .image
        case .video: .video
        }
    }
}
