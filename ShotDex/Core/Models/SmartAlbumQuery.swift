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
    case favorite   // boolean favorite
    case rating     // the current star rating, 0–5 (FS-01.12)
    case keyword    // a Photos keyword (iOS 27, FS-02.07 §7)
    case caption    // the Photos caption (iOS 27, FS-02.07 §7)
    case server     // a server source + folder, Yes/No in `boolValue` (FS-19.07 §7)
}

/// A photo attribute a smart-album condition can test.
enum RuleField: String, Codable, CaseIterable, Identifiable, Sendable {
    case cameraBrand
    case cameraBody
    case lens
    case sensorFormat
    case fileType
    case mediaType
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
    /// The current star rating — the pending row, else Photos' (FS-01.12 §4).
    /// The raw value `rating` was a field once before (`v16` removed it and
    /// rewrote every album that held it), so reusing it reads nothing stale.
    case rating
    /// Pick / Reject / no flag. Same story as `rating`, with `v15`.
    case flag
    /// A Photos keyword, matched on the mirror without regard to case or
    /// diacritics (FS-02.07 §7). iOS 27 only.
    case keyword
    /// The Photos caption, matched the same way. iOS 27 only.
    case caption
    /// The words of a search the parser did not turn into a condition, matched
    /// against everything plain text search reads — camera, lens, filename,
    /// and (iOS 27) caption and keyword (FS-02.07 §7). Not offered in the
    /// builder; it only comes from the search field.
    case anyText
    /// Where a copy of the photo lives — a source's id (FS-19.04 §5). A
    /// Statistics card that names one keeps it whatever the screen's Source
    /// popup says (FS-18 04 §2). The builder offers Photos and folder/drive
    /// sources only; a server lives in `alsoOnServer` (FS-19.07 §7).
    case source
    /// Whether every original file is on this device (FS-06.10): read from
    /// the offline check's table, so an unchecked photo matches neither value.
    case original
    /// Whether every original file of the Photos item has a byte-identical
    /// copy in a server source's folder (FS-19.07 §7): `text` is the source
    /// id, `folder` narrows it, `boolValue` is Yes / No. An item not checked
    /// yet matches neither answer.
    case alsoOnServer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraBrand: "Camera Brand"
        case .cameraBody: "Camera Model"
        case .lens: "Lens"
        case .sensorFormat: "Sensor Format"
        case .fileType: "File Type"
        case .mediaType: "Media Type"
        case .filename: "Filename"
        case .place: "Place"
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutter: "Shutter Speed"
        case .focalLength: "Focal Length"
        case .dateTaken: "Date Taken"
        case .favorite: "Favorite"
        case .rating: MarkCopy.rating
        case .flag: MarkCopy.flag
        case .keyword: String(localized: "Keyword", table: KeywordCopy.table, comment: "Rule field: a Photos keyword")
        case .caption: String(localized: "Caption", table: KeywordCopy.table, comment: "Rule field: the Photos caption")
        case .source: String(localized: "Source", comment: "Rule field: the photo library, folder, drive or server a copy lives in")
        case .original: String(localized: "Original", comment: "Rule field: whether the photo's original files are on this device or only in iCloud")
        case .alsoOnServer: String(localized: "Also on Server", comment: "Rule field: whether the photo in the library also has an identical copy on a server folder")
        case .anyText: String(localized: "Text", table: KeywordCopy.table, comment: "Rule field: words searched across camera, lens, filename, caption and keywords")
        }
    }

    var kind: RuleFieldKind {
        switch self {
        case .cameraBrand, .cameraBody, .lens, .filename, .place, .anyText: .text
        case .sensorFormat, .fileType, .mediaType, .flag, .source, .original: .choice
        case .iso, .aperture, .shutter, .focalLength: .number
        case .dateTaken: .date
        case .favorite: .favorite
        case .rating: .rating
        case .keyword: .keyword
        case .caption: .caption
        case .alsoOnServer: .server
        }
    }

    /// Parse/format kind for numeric fields (ignored for other kinds).
    var numericKind: NumericFieldKind {
        switch self {
        case .iso, .rating: .int
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
        case .mediaType:
            MediaKind.allCases.map { ($0.rawValue, $0.displayName) }
        case .flag:
            SmartAlbumFlagValue.allCases.map { ($0.rawValue, $0.label) }
        case .original:
            OriginalPresence.allCases.map { ($0.rawValue, $0.label) }
        default:
            []
        }
    }

    var defaultOperator: RuleOperator {
        kind.allowedOperators.first ?? .contains
    }

    /// Fields the condition rows offer. `.mediaType` is left out because the
    /// rule builder gives photo-vs-video its own All/Photo/Video control — it is
    /// still a rule underneath, so offering it in the field menu too would show
    /// the same condition twice.
    static var selectableCases: [RuleField] {
        selectableCases(extendedMetadata: ExtendedMetadataSupport.isAvailable)
    }

    /// Keyword and Caption only where Photos can be read for them — iOS 27;
    /// below it they are hidden, not dimmed (FS-02.07 §6, AC-14).
    static func selectableCases(extendedMetadata: Bool) -> [RuleField] {
        allCases.filter {
            $0 != .mediaType && $0 != .anyText && (extendedMetadata || ($0 != .keyword && $0 != .caption))
        }
    }
}

extension RuleFieldKind {
    /// Operators offered for this kind, in menu order.
    var allowedOperators: [RuleOperator] {
        switch self {
        case .text: [.contains, .doesNotContain, .isExactly, .isNot]
        case .choice: [.isExactly, .isNot]
        case .number: [.equalTo, .greaterThan, .lessThan, .inRange]
        case .date: [.on, .inMonth, .inLastDays, .before, .after, .inRange]
        case .favorite, .server: []
        case .rating: [.atLeast, .equalTo, .atMost]
        case .keyword: [.hasKeyword, .lacksKeyword, .hasAnyKeyword, .hasNoKeywords]
        case .caption: [.contains, .doesNotContain]
        }
    }
}

/// The values a flag condition can test. `pick`/`reject` are the same words
/// `photo_flag.flag` stores; an album JSON holding anything else compiles to
/// no condition for that rule alone (FS-01.12 AC-8).
enum SmartAlbumFlagValue: String, CaseIterable, Sendable {
    case pick
    case reject
    case unflagged

    var label: String {
        switch self {
        case .pick: MarkCopy.flagWord(.pick)
        case .reject: MarkCopy.flagWord(.reject)
        case .unflagged: MarkCopy.unflaggedFilter
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
    /// The calendar month of the capture date. `number` holds
    /// `CaptureMonth.anchorDate` (the 15th at noon) of that month.
    case inMonth
    case inLastDays
    case before
    case after
    // Rating
    case atLeast
    case atMost
    // Keyword (FS-02.07 §7)
    case hasKeyword
    case lacksKeyword
    /// No value: photos that carry any keyword at all.
    case hasAnyKeyword
    /// No value: photos with no keyword — what is left to tag after a shoot.
    case hasNoKeywords

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
        case .inMonth: "is in"
        case .inLastDays: "is in the last"
        case .before: "is before"
        case .after: "is after"
        case .atLeast: "is at least"
        case .atMost: "is at most"
        case .hasKeyword: String(localized: "has", table: KeywordCopy.table, comment: "Keyword rule operator: the photo has this keyword")
        case .lacksKeyword: String(localized: "doesn't have", table: KeywordCopy.table, comment: "Keyword rule operator: the photo does not have this keyword")
        case .hasAnyKeyword: String(localized: "has any keyword", table: KeywordCopy.table, comment: "Keyword rule operator: the photo has at least one keyword")
        case .hasNoKeywords: String(localized: "has no keywords", table: KeywordCopy.table, comment: "Keyword rule operator: the photo has no keyword")
        }
    }

    /// False for the operators that test nothing typed — the row shows no field.
    var needsValue: Bool { self != .hasAnyKeyword && self != .hasNoKeywords }

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
        // The app's one RAW list (FS-03.04b §2).
        case .raw: FileTypeBadge.rawExtensions.map { $0.lowercased() }.sorted()
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
    /// `.source` on a folder or server source: the folder under the source's
    /// root it is narrowed to, any depth (FS-19.07 §7). Nil or empty = the
    /// whole source.
    var folder: String?

    init(
        id: UUID = UUID(),
        field: RuleField = .cameraBody,
        op: RuleOperator? = nil,
        text: String = "",
        number: Double? = nil,
        numberUpper: Double? = nil,
        boolValue: Bool = true,
        focalMode: FocalLengthMode = .actual,
        folder: String? = nil
    ) {
        self.id = id
        self.field = field
        self.op = op ?? field.defaultOperator
        self.text = text
        self.number = number
        self.numberUpper = numberUpper
        self.boolValue = boolValue
        self.focalMode = focalMode
        self.folder = folder
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
            case .on, .inMonth: return number != nil
            case .inLastDays: return (number ?? 0) > 0
            case .before, .after: return number != nil
            case .inRange: return number != nil && numberUpper != nil
            default: return false
            }
        case .favorite:
            return true
        case .rating:
            return number != nil
        case .keyword:
            return !op.needsValue || !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .caption, .server:
            return !text.trimmingCharacters(in: .whitespaces).isEmpty
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
            rules = try c.decodeIfPresent([LossyRule].self, forKey: .rules)?.compactMap(\.rule) ?? []
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

        // Only a single-kind selection carries a constraint: both kinds ANDed
        // under `.all` would match nothing, and neither means "no filter".
        if let kind = criteria.mediaKinds.count == 1 ? criteria.mediaKinds.first : nil {
            rules.append(SmartAlbumRule(field: .mediaType, op: .isExactly, text: kind.rawValue))
        }

        if criteria.favoritesOnly {
            rules.append(SmartAlbumRule(field: .favorite, boolValue: true))
        }

        // "Original on This iPhone" saves as the rule it is short for (FS-06.10 §4).
        if criteria.originalOnDeviceOnly {
            rules.append(SmartAlbumRule(field: .original, op: .isExactly, text: OriginalPresence.onDevice.rawValue))
        }

        if let month = criteria.captureMonth {
            rules.append(SmartAlbumRule(
                field: .dateTaken, op: .inMonth, number: month.anchorDate().timeIntervalSince1970
            ))
        }

        // Rating ▸ (FS-01.12 §7): "★★★ & Up" is at least 3, Unrated is 0.
        switch criteria.ratingFilter {
        case .atLeast(let stars)?:
            rules.append(SmartAlbumRule(field: .rating, op: .atLeast, number: Double(stars)))
        case .unrated?:
            rules.append(SmartAlbumRule(field: .rating, op: .equalTo, number: 0))
        case nil:
            break
        }

        // Flags OR together; rules under `.all` cannot. One flag is its rule;
        // two are "not the third" — the same photos; all three constrain nothing.
        let flagValue: (PhotoFlagFilter) -> SmartAlbumFlagValue = {
            switch $0 {
            case .picks: .pick
            case .rejected: .reject
            case .unflagged: .unflagged
            }
        }
        switch criteria.flags.count {
        case 1:
            rules.append(SmartAlbumRule(field: .flag, op: .isExactly, text: flagValue(criteria.flags.first!).rawValue))
        case 2:
            if let missing = PhotoFlagFilter.allCases.first(where: { !criteria.flags.contains($0) }) {
                rules.append(SmartAlbumRule(field: .flag, op: .isNot, text: flagValue(missing).rawValue))
            }
        default:
            break
        }

        // A search: the parts a rule says the same way (LibraryQueries'
        // search SQL). Focal length and bare numbers OR across columns and
        // have no rule — `migrationGaps` names them.
        if let text = criteria.searchText, !text.isEmpty {
            let parsed = SearchParser.parse(text)
            if let iso = parsed.iso {
                rules.append(SmartAlbumRule(field: .iso, op: .equalTo, number: Double(iso)))
            }
            if let aperture = parsed.aperture {
                rules.append(SmartAlbumRule(field: .aperture, op: .inRange, number: aperture - 0.05, numberUpper: aperture + 0.05))
            }
            if let shutter = parsed.shutterSeconds {
                rules.append(SmartAlbumRule(field: .shutter, op: .inRange, number: shutter * 0.9, numberUpper: shutter * 1.1))
            }
            if let format = parsed.sensorFormat {
                rules.append(SmartAlbumRule(field: .sensorFormat, op: .isExactly, text: format.rawValue))
            }
            for term in parsed.freeTextTerms {
                rules.append(SmartAlbumRule(field: .anyText, op: .contains, text: term))
            }
        }

        return SmartAlbumQuery(matchMode: .all, rules: rules)
    }

    /// The quick-filter conditions `migrating` cannot say as rules, in the
    /// words a reason line uses ("Capture Kind") — empty when the converted
    /// query matches exactly the photos the filter shows. Save as Smart
    /// Album… and Advanced Filter… stay off while it is not empty, rather
    /// than save an album that quietly matches more.
    static func migrationGaps(_ criteria: FilterCriteria) -> [String] {
        var gaps: [String] = []
        if !criteria.mediaSubtypes.isEmpty {
            gaps.append(String(localized: "Capture Kind", comment: "A filter condition a smart album cannot save"))
        }
        // Several values OR together in the filter; rules under All would AND them.
        if criteria.cameraBrands.count > 1 || criteria.cameraBrandTerms.count > 1 {
            gaps.append(String(localized: "several camera brands", comment: "A filter condition a smart album cannot save"))
        }
        if criteria.cameraBodies.count > 1 || criteria.cameraBodyTerms.count > 1 {
            gaps.append(String(localized: "several cameras", comment: "A filter condition a smart album cannot save"))
        }
        if criteria.lenses.count > 1 || criteria.lensTerms.count > 1 {
            gaps.append(String(localized: "several lenses", comment: "A filter condition a smart album cannot save"))
        }
        if criteria.sensorFormats.count > 1 {
            gaps.append(String(localized: "several sensor formats", comment: "A filter condition a smart album cannot save"))
        }
        if let text = criteria.searchText, !text.isEmpty {
            let parsed = SearchParser.parse(text)
            if parsed.focalLength != nil || !parsed.bareNumbers.isEmpty {
                gaps.append(String(localized: "a focal length or bare number in the search", comment: "A filter condition a smart album cannot save"))
            }
        }
        return gaps
    }
}

/// A rule that decodes to `nil` instead of throwing when its stored `field` is
/// one this build no longer has.
///
/// Without it, a single stale rule takes the whole album down: `SmartAlbum`
/// falls back to `SmartAlbumQuery.empty` when the JSON will not parse, and an
/// empty query has no predicate — the album would quietly match the entire
/// library. Dropping the one rule loses a condition; the fallback loses the
/// album's meaning. The `v15-dropCullFlag` migration rewrites the stored JSON
/// so this only has to catch albums written by a build that ran before it.
private struct LossyRule: Decodable {
    let rule: SmartAlbumRule?

    init(from decoder: Decoder) throws {
        rule = try? SmartAlbumRule(from: decoder)
    }
}

extension SmartAlbumQuery {
    /// The source a condition pins, if one does (`Source is …`).
    var pinnedSourceId: String? {
        rules.first { $0.field == .source && $0.op == .isExactly && !$0.text.isEmpty }?.text
    }
}

extension SmartAlbumQuery {
    /// Whether a condition reads the original-on-device check (FS-06.10):
    /// a screen showing it keeps the check going while it is open.
    var usesOriginal: Bool { rules.contains { $0.field == .original } }
}
