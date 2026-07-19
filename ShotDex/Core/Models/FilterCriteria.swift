import Foundation

/// A closed numeric range filter. Either bound may be open-ended.
struct NumericRangeFilter: Equatable, Sendable {
    var lowerBound: Double?
    var upperBound: Double?

    init(lowerBound: Double? = nil, upperBound: Double? = nil) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    var isEmpty: Bool { lowerBound == nil && upperBound == nil }

    func contains(_ value: Double) -> Bool {
        if let lowerBound, value < lowerBound { return false }
        if let upperBound, value > upperBound { return false }
        return true
    }
}

/// Which focal length column a focal filter applies to.
enum FocalLengthMode: String, Codable, CaseIterable, Sendable {
    case actual
    case equivalent
}

/// Angle-of-view buckets defined over full-frame equivalent focal length.
enum FocalAngleBucket: String, CaseIterable, Identifiable, Sendable {
    case ultraWide = "Ultra-wide"
    case wide = "Wide"
    case standard = "Standard"
    case portrait = "Portrait / Short telephoto"
    case telephoto = "Telephoto"
    case superTelephoto = "Super telephoto"

    var id: String { rawValue }

    var range: NumericRangeFilter {
        switch self {
        case .ultraWide: NumericRangeFilter(upperBound: 19.999)
        case .wide: NumericRangeFilter(lowerBound: 20, upperBound: 34.999)
        case .standard: NumericRangeFilter(lowerBound: 35, upperBound: 69.999)
        case .portrait: NumericRangeFilter(lowerBound: 70, upperBound: 134.999)
        case .telephoto: NumericRangeFilter(lowerBound: 135, upperBound: 299.999)
        case .superTelephoto: NumericRangeFilter(lowerBound: 300)
        }
    }
}

/// Quick ISO groups from the spec.
enum ISOQuickGroup: String, CaseIterable, Identifiable, Sendable {
    case upTo100 = "≤ 100"
    case from101To400 = "101–400"
    case from401To1600 = "401–1600"
    case from1601To6400 = "1601–6400"
    case above6400 = "> 6400"

    var id: String { rawValue }

    var range: NumericRangeFilter {
        switch self {
        case .upTo100: NumericRangeFilter(upperBound: 100)
        case .from101To400: NumericRangeFilter(lowerBound: 101, upperBound: 400)
        case .from401To1600: NumericRangeFilter(lowerBound: 401, upperBound: 1600)
        case .from1601To6400: NumericRangeFilter(lowerBound: 1601, upperBound: 6400)
        case .above6400: NumericRangeFilter(lowerBound: 6401)
        }
    }
}

/// Quick shutter speed groups (values in seconds).
enum ShutterQuickGroup: String, CaseIterable, Identifiable, Sendable {
    case slowerThan1_30 = "Slower than 1/30s"
    case from1_30To1_125 = "1/30 – 1/125"
    case from1_126To1_500 = "1/126 – 1/500"
    case fasterThan1_500 = "Faster than 1/500s"

    var id: String { rawValue }

    var range: NumericRangeFilter {
        switch self {
        case .slowerThan1_30: NumericRangeFilter(lowerBound: 1.0 / 30.0)
        case .from1_30To1_125: NumericRangeFilter(lowerBound: 1.0 / 125.0, upperBound: 1.0 / 30.0)
        case .from1_126To1_500: NumericRangeFilter(lowerBound: 1.0 / 500.0, upperBound: 1.0 / 126.0)
        case .fasterThan1_500: NumericRangeFilter(upperBound: 1.0 / 500.0)
        }
    }
}

/// Quick aperture groups.
enum ApertureQuickGroup: String, CaseIterable, Identifiable, Sendable {
    case f1To2 = "f/1.0 – 2.0"
    case f2_1To4 = "f/2.1 – 4.0"
    case f4_1To8 = "f/4.1 – 8.0"
    case smallerThanF8 = "Smaller than f/8"

    var id: String { rawValue }

    var range: NumericRangeFilter {
        switch self {
        case .f1To2: NumericRangeFilter(lowerBound: 1.0, upperBound: 2.0)
        case .f2_1To4: NumericRangeFilter(lowerBound: 2.1, upperBound: 4.0)
        case .f4_1To8: NumericRangeFilter(lowerBound: 4.1, upperBound: 8.0)
        case .smallerThanF8: NumericRangeFilter(lowerBound: 8.001)
        }
    }
}

/// Combined filter state for the Library screen. All conditions are ANDed;
/// values inside a multi-select set are ORed.
struct FilterCriteria: Equatable, Sendable {
    var cameraBrands: Set<String> = []
    var cameraBodies: Set<String> = []
    var lenses: Set<String> = []
    var sensorFormats: Set<SensorFormat> = []

    var isoRange = NumericRangeFilter()
    var shutterRange = NumericRangeFilter()
    var apertureRange = NumericRangeFilter()
    var focalRange = NumericRangeFilter()
    var focalLengthMode: FocalLengthMode = .actual

    var favoritesOnly = false

    /// Free-text search terms produced by SearchParser (camera/lens match).
    var searchText: String?

    var isEmpty: Bool {
        cameraBrands.isEmpty
            && cameraBodies.isEmpty
            && lenses.isEmpty
            && sensorFormats.isEmpty
            && isoRange.isEmpty
            && shutterRange.isEmpty
            && apertureRange.isEmpty
            && focalRange.isEmpty
            && !favoritesOnly
            && (searchText?.isEmpty ?? true)
    }

    var activeConditionCount: Int {
        var count = 0
        if !cameraBrands.isEmpty { count += 1 }
        if !cameraBodies.isEmpty { count += 1 }
        if !lenses.isEmpty { count += 1 }
        if !sensorFormats.isEmpty { count += 1 }
        if !isoRange.isEmpty { count += 1 }
        if !shutterRange.isEmpty { count += 1 }
        if !apertureRange.isEmpty { count += 1 }
        if !focalRange.isEmpty { count += 1 }
        if favoritesOnly { count += 1 }
        if let searchText, !searchText.isEmpty { count += 1 }
        return count
    }

    static let empty = FilterCriteria()
}
