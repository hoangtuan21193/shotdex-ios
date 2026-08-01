import Foundation

/// How the conditions of a smart album combine.
enum RuleMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case all   // AND — every condition must match
    case any   // OR  — at least one condition must match

    var id: String { rawValue }

    /// Word used inline in "Match __ of the following conditions".
    var word: String {
        switch self {
        case .all: "all"
        case .any: "any"
        }
    }
}

/// The kind of value a `RuleField` holds — drives which operators are offered
/// and which editor the rule row renders.
enum RuleFieldKind: Equatable, Sendable {
    case text       // free-typed string, matched against normalized + raw columns
    case choice     // one value from a closed set (sensor format, file type)
    case number     // numeric metadata (ISO, aperture, shutter, focal length)
    case date       // capture date
    case favorite   // boolean favorite flag
}

/// A photo attribute a smart-album condition can test.
enum RuleField: String, Codable, CaseIterable, Identifiable, Sendable {
    case cameraBrand
    case cameraBody
    case lens
    case sensorFormat
    case fileType
    case filename
    /// Where the photo was taken, matched against the reverse-geocoded address
    /// (`photo_metadata.placeSearchText`). Only photos the geocoding pass has
    /// reached can match — see `PlaceIndexPass`.
    case place
    case iso
    case aperture
    case shutter
    case focalLength
    case dateTaken
    case favorite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraBrand: "Camera Brand"
        case .cameraBody: "Camera Model"
        case .lens: "Lens"
        case .sensorFormat: "Sensor Format"
        case .fileType: "File Type"
        case .filename: "Filename"
        case .place: "Place"
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutter: "Shutter Speed"
        case .focalLength: "Focal Length"
        case .dateTaken: "Date Taken"
        case .favorite: "Favorite"
        }
    }

    var kind: RuleFieldKind {
        switch self {
        case .cameraBrand, .cameraBody, .lens, .filename, .place: .text
        case .sensorFormat, .fileType: .choice
        case .iso, .aperture, .shutter, .focalLength: .number
        case .dateTaken: .date
        case .favorite: .favorite
        }
    }

    /// Parse/format kind for numeric fields (ignored for other kinds).
    var numericKind: NumericFieldKind {
        switch self {
        case .iso: .int
        case .shutter: .shutter
        default: .double
        }
    }

    /// The closed value set for `.choice` fields, as (rawValue, label) pairs.
    var choiceValues: [(value: String, label: String)] {
        switch self {
        case .sensorFormat:
            SensorFormat.allCases.map { ($0.rawValue, $0.displayName) }
        case .fileType:
            PhotoFileType.allCases.map { ($0.rawValue, $0.displayName) }
        default:
            []
        }
    }

    var defaultOperator: RuleOperator {
        kind.allowedOperators.first ?? .contains
    }
}

extension RuleFieldKind {
    /// Operators offered for this kind, in menu order.
    var allowedOperators: [RuleOperator] {
        switch self {
        case .text: [.contains, .doesNotContain, .isExactly, .isNot]
        case .choice: [.isExactly, .isNot]
        case .number: [.equalTo, .greaterThan, .lessThan, .inRange]
        case .date: [.on, .inLastDays, .before, .after, .inRange]
        case .favorite: []
        }
    }
}

/// Comparison applied by a single condition. One superset enum; each field
/// kind exposes only the subset it supports (`RuleFieldKind.allowedOperators`).
enum RuleOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    // Text
    case contains
    case doesNotContain
    case isExactly
    case isNot
    // Number
    case equalTo
    case greaterThan
    case lessThan
    case inRange
    // Date
    case on          // exact capture day
    case inLastDays
    case before
    case after

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .isExactly, .equalTo: "is"
        case .isNot: "is not"
        case .greaterThan: "greater than"
        case .lessThan: "less than"
        case .inRange: "is in range"
        case .on: "is on"
        case .inLastDays: "is in the last"
        case .before: "is before"
        case .after: "is after"
        }
    }

    /// True when the operator needs a second numeric/date bound.
    var needsUpperBound: Bool { self == .inRange }
}

/// A recognized photo file type, mapped to the filename extensions that
/// identify it. Matched against `originalFilename` (no dedicated column).
enum PhotoFileType: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case heic
    case png
    case tiff
    case gif
    case dng
    case raw

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .heic: "HEIC / HEIF"
        case .png: "PNG"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .dng: "DNG"
        case .raw: "RAW"
        }
    }

    /// Extensions (lowercased, no dot) that identify this type.
    var extensions: [String] {
        switch self {
        case .jpeg: ["jpg", "jpeg"]
        case .heic: ["heic", "heif"]
        case .png: ["png"]
        case .tiff: ["tif", "tiff"]
        case .gif: ["gif"]
        case .dng: ["dng"]
        case .raw: ["cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf", "raf",
                    "rw2", "orf", "pef", "dng", "3fr", "fff", "iiq", "erf",
                    "mos", "mrw", "x3f"]
        }
    }
}

/// One condition of a smart album: a field, an operator, and its operand(s).
/// A single struct carries every value shape; `field.kind` + `op` decide which
/// members are meaningful (`isValid` enforces the ones a compile needs).
struct SmartAlbumRule: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var field: RuleField
    var op: RuleOperator
    /// Text value (`.text`) or selected raw value (`.choice`).
    var text: String
    /// Primary numeric operand: number for `.number`, epoch seconds for date
    /// `before`/`after`/`inRange` lower bound, or day count for `inLastDays`.
    var number: Double?
    /// Upper bound for `inRange` (number, or epoch seconds for dates).
    var numberUpper: Double?
    /// Favorite target for `.favorite` fields.
    var boolValue: Bool
    /// Which focal-length column `.focalLength` compares against.
    var focalMode: FocalLengthMode

    init(
        id: UUID = UUID(),
        field: RuleField = .cameraBody,
        op: RuleOperator? = nil,
        text: String = "",
        number: Double? = nil,
        numberUpper: Double? = nil,
        boolValue: Bool = true,
        focalMode: FocalLengthMode = .actual
    ) {
        self.id = id
        self.field = field
        self.op = op ?? field.defaultOperator
        self.text = text
        self.number = number
        self.numberUpper = numberUpper
        self.boolValue = boolValue
        self.focalMode = focalMode
    }

    /// Whether this rule carries enough input to produce a SQL condition.
    /// Incomplete rules are silently skipped so a half-typed row never zeroes
    /// out (match all) or widens (match any) the result set.
    var isValid: Bool {
        switch field.kind {
        case .text, .choice:
            return !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .number:
            return op.needsUpperBound ? (number != nil && numberUpper != nil) : number != nil
        case .date:
            switch op {
            case .on: return number != nil
            case .inLastDays: return (number ?? 0) > 0
            case .before, .after: return number != nil
            case .inRange: return number != nil && numberUpper != nil
            default: return false
            }
        case .favorite:
            return true
        }
    }
}

/// A named smart album's saved conditions: a match mode plus an ordered list
/// of rules. Stored as JSON in `smart_albums.criteria` (see `SmartAlbum`).
struct SmartAlbumQuery: Codable, Equatable, Sendable {
    var matchMode: RuleMatchMode
    var rules: [SmartAlbumRule]

    init(matchMode: RuleMatchMode = .all, rules: [SmartAlbumRule] = []) {
        self.matchMode = matchMode
        self.rules = rules
    }

    static let empty = SmartAlbumQuery()

    /// Only the rules complete enough to compile.
    var validRules: [SmartAlbumRule] { rules.filter(\.isValid) }

    /// No compilable condition — the album would have no predicate.
    var isEmpty: Bool { validRules.isEmpty }

    // MARK: Codable (tolerant + legacy migration)

    private enum CodingKeys: String, CodingKey {
        case matchMode, rules
    }

    init(from decoder: Decoder) throws {
        // New shape: { matchMode, rules }.
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.rules) {
            matchMode = try c.decodeIfPresent(RuleMatchMode.self, forKey: .matchMode) ?? .all
            rules = try c.decodeIfPresent([SmartAlbumRule].self, forKey: .rules) ?? []
            return
        }
        // Legacy shape: a JSON-encoded `FilterCriteria` (pre-rule smart albums).
        if let legacy = try? FilterCriteria(from: decoder) {
            self = SmartAlbumQuery.migrating(legacy)
            return
        }
        matchMode = .all
        rules = []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(matchMode, forKey: .matchMode)
        try c.encode(rules, forKey: .rules)
    }

    /// Best-effort conversion of a legacy AND-only `FilterCriteria` into rules
    /// so smart albums saved before the rule builder keep resolving photos.
    static func migrating(_ criteria: FilterCriteria) -> SmartAlbumQuery {
        var rules: [SmartAlbumRule] = []

        func textRules(_ values: some Sequence<String>, field: RuleField, op: RuleOperator) {
            for value in values where !value.trimmingCharacters(in: .whitespaces).isEmpty {
                rules.append(SmartAlbumRule(field: field, op: op, text: value))
            }
        }

        textRules(criteria.cameraBrandTerms, field: .cameraBrand, op: .contains)
        textRules(criteria.cameraBodyTerms, field: .cameraBody, op: .contains)
        textRules(criteria.lensTerms, field: .lens, op: .contains)
        textRules(criteria.cameraBrands.sorted(), field: .cameraBrand, op: .isExactly)
        textRules(criteria.cameraBodies.sorted(), field: .cameraBody, op: .isExactly)
        textRules(criteria.lenses.sorted(), field: .lens, op: .isExactly)
        textRules(criteria.sensorFormats.map(\.rawValue).sorted(), field: .sensorFormat, op: .isExactly)

        func rangeRule(_ range: NumericRangeFilter, field: RuleField, focalMode: FocalLengthMode = .actual) {
            switch (range.lowerBound, range.upperBound) {
            case let (lower?, upper?):
                rules.append(SmartAlbumRule(field: field, op: .inRange, number: lower, numberUpper: upper, focalMode: focalMode))
            case let (lower?, nil):
                rules.append(SmartAlbumRule(field: field, op: .greaterThan, number: lower, focalMode: focalMode))
            case let (nil, upper?):
                rules.append(SmartAlbumRule(field: field, op: .lessThan, number: upper, focalMode: focalMode))
            case (nil, nil):
                break
            }
        }

        rangeRule(criteria.isoRange, field: .iso)
        rangeRule(criteria.shutterRange, field: .shutter)
        rangeRule(criteria.apertureRange, field: .aperture)
        rangeRule(criteria.focalRange, field: .focalLength, focalMode: criteria.focalLengthMode)

        if criteria.favoritesOnly {
            rules.append(SmartAlbumRule(field: .favorite, boolValue: true))
        }

        return SmartAlbumQuery(matchMode: .all, rules: rules)
    }
}
