import Foundation

/// Sort orders for the Library grid.
enum SortOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case dateTakenNewest
    case dateTakenOldest
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

    var id: String { rawValue }

    /// Date-ordered grids show date section headers; metric sorts don't.
    var isDateSort: Bool {
        self == .dateTakenNewest || self == .dateTakenOldest
    }

    var displayName: String {
        switch self {
        case .dateTakenNewest: "Date Taken (Newest)"
        case .dateTakenOldest: "Date Taken (Oldest)"
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
        }
    }

    static let `default` = SortOption.dateTakenNewest
}
