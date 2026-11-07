import Foundation

/// Sort orders for the Library grid.
enum SortOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case dateTakenNewest
    case dateTakenOldest
    case dateModifiedNewest
    case dateModifiedOldest
    case isoDescending
    case isoAscending
    case focalLengthDescending
    case focalLengthAscending
    case equivalentFocalLengthDescending
    case equivalentFocalLengthAscending
    case apertureAscending
    case apertureDescending
    case shutterSpeedFastest
    case shutterSpeedSlowest
    case fileSizeLargest
    case fileSizeSmallest

    var id: String { rawValue }

    /// The four date orders: the ones a date scrubber or day headers can
    /// follow. Under any other order neighbouring photos are days or years
    /// apart, so the grid drops both (FS-01.05 §5.1).
    var isDateOrdered: Bool {
        self == .dateTakenNewest || self == .dateTakenOldest
            || self == .dateModifiedNewest || self == .dateModifiedOldest
    }

    /// The `PHAsset` key this order maps to, or nil for the metric orders,
    /// which only the indexed rows can answer. A non-nil key lets the grid skip
    /// the EXIF index and show the whole library straight from PhotoKit.
    var photoKitSortKey: String? {
        switch self {
        case .dateTakenNewest, .dateTakenOldest: "creationDate"
        case .dateModifiedNewest, .dateModifiedOldest: "modificationDate"
        default: nil
        }
    }

    /// Whether `photoKitSortKey` runs oldest-first.
    var isAscending: Bool {
        self == .dateTakenOldest || self == .dateModifiedOldest
    }

    /// The orders the Library's filter menu offers. The metric orders stay in
    /// the enum (queries and smart albums still use them) but not in the menu;
    /// file size is the one metric the menu does offer (FS-01.05 §5.1).
    static let menuOrders: [SortOption] = [
        .dateTakenNewest, .dateTakenOldest, .dateModifiedNewest, .dateModifiedOldest,
        .fileSizeLargest, .fileSizeSmallest,
    ]

    var displayName: String {
        switch self {
        case .dateTakenNewest: "Date Taken (Newest)"
        case .dateTakenOldest: "Date Taken (Oldest)"
        case .dateModifiedNewest: "Date Modified (Newest)"
        case .dateModifiedOldest: "Date Modified (Oldest)"
        case .isoDescending: "ISO (High to Low)"
        case .isoAscending: "ISO (Low to High)"
        case .focalLengthDescending: "Focal Length (Long to Short)"
        case .focalLengthAscending: "Focal Length (Short to Long)"
        case .equivalentFocalLengthDescending: "FF Equivalent (Long to Short)"
        case .equivalentFocalLengthAscending: "FF Equivalent (Short to Long)"
        case .apertureAscending: "Aperture (Wide to Narrow)"
        case .apertureDescending: "Aperture (Narrow to Wide)"
        case .shutterSpeedFastest: "Shutter Speed (Fastest)"
        case .shutterSpeedSlowest: "Shutter Speed (Slowest)"
        case .fileSizeLargest: "File Size (Largest)"
        case .fileSizeSmallest: "File Size (Smallest)"
        }
    }

    static let `default` = SortOption.dateTakenNewest
}
