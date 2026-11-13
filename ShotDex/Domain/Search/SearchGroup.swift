import Foundation

/// One searchable value of the library — a camera, a lens, a place, a year —
/// with how many photos have it and the newest of them (FS-01.03c §1).
///
/// The same idea as Photos' search index, whose SQL ships in the binary as
/// `groups(category, content_string, normalized_string, score …)`: the value is
/// the row, not the photo, so typing matches a few thousand names instead of
/// scanning every photo.
struct SearchGroup: Identifiable, Hashable, Sendable {
    var id: Int64
    var category: SearchGroupCategory
    /// What the row shows: `Canon EOS R6`, `85mm`, `June 2024`.
    var name: String
    var count: Int
    /// The newest photo with this value — the row's picture.
    var keyAssetId: String?
    /// The condition this value stands for, as a search token or a smart album
    /// rule would hold it.
    var rule: SmartAlbumRule

    static func == (lhs: SearchGroup, rhs: SearchGroup) -> Bool {
        lhs.id == rhs.id && lhs.count == rhs.count && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What kind of value a group is. The order of the cases is the order
/// suggestions of equal match quality are listed in (FS-01.03c §2).
enum SearchGroupCategory: String, CaseIterable, Codable, Sendable, Comparable {
    case camera
    case lens
    case place
    case year
    case month
    case cameraBrand
    case focalLength
    case aperture
    case iso
    case photoKind
    case fileType
    case keyword
    case season
    case monthOfYear
    case dayOfWeek
    case sensorFormat

    var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// The second line of a suggestion row.
    var label: String {
        switch self {
        case .camera: String(localized: "Camera", comment: "Search suggestion kind: a camera model")
        case .lens: String(localized: "Lens", comment: "Search suggestion kind")
        case .place: String(localized: "Place", comment: "Search suggestion kind")
        case .year: String(localized: "Year", comment: "Search suggestion kind")
        case .month: String(localized: "Month", comment: "Search suggestion kind: a month of one year, June 2024")
        case .cameraBrand: String(localized: "Camera Brand", comment: "Search suggestion kind")
        case .focalLength: String(localized: "Focal Length", comment: "Search suggestion kind")
        case .aperture: String(localized: "Aperture", comment: "Search suggestion kind")
        case .iso: String(localized: "ISO", comment: "Search suggestion kind")
        case .photoKind: String(localized: "Photo Kind", comment: "Search suggestion kind: Live Photo, panorama, screenshot…")
        case .fileType: String(localized: "File Type", comment: "Search suggestion kind")
        case .keyword: String(localized: "Keyword", comment: "Search suggestion kind")
        case .season: String(localized: "Season", comment: "Search suggestion kind")
        case .monthOfYear: String(localized: "Month of Year", comment: "Search suggestion kind: June in any year")
        case .dayOfWeek: String(localized: "Day of Week", comment: "Search suggestion kind")
        case .sensorFormat: String(localized: "Sensor Format", comment: "Search suggestion kind")
        }
    }

    /// SF Symbol for a row that has no photo to show.
    var symbol: String {
        switch self {
        case .camera, .cameraBrand: "camera"
        case .lens, .focalLength, .aperture: "camera.aperture"
        case .place: "mappin.and.ellipse"
        case .year, .month, .monthOfYear, .dayOfWeek, .season: "calendar"
        case .iso: "dial.medium"
        case .photoKind: "photo.on.rectangle"
        case .fileType: "doc"
        case .keyword: "tag"
        case .sensorFormat: "square.dashed"
        }
    }
}

/// The one way search folds text, on both sides: the index's names and what
/// the user types. Case, diacritics and `đ` go, so `da lat` finds `Đà Lạt`.
enum SearchFolding {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }

    /// Words of a typed query, folded, in order — split the way the FTS5
    /// `unicode61` tokenizer splits the names, so `f/1.8` is `f`, `1`, `8`.
    static func words(_ text: String) -> [String] {
        fold(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// An FTS5 query in which every word is a prefix and all must match:
    /// `"can"* "r6"*`. Quotes are doubled so typed text is never syntax.
    static func ftsPrefixQuery(_ text: String) -> String? {
        let words = words(text)
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " ")
    }
}
