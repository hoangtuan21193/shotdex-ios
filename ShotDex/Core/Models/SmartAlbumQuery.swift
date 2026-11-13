import Foundation
import ShotDexKit

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
    /// What kind of item it is — favorite, edited, Live Photo, panorama,
    /// burst, screenshot… (`PhotoKind`), Photos' *Photo is …* condition
    /// (FS-06.08 §3c).
    case photoKind

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
        case .photoKind: String(localized: "Photo", comment: "Rule field: what kind of item it is — edited, Live Photo, panorama, burst, screenshot…")
        }
    }

    var kind: RuleFieldKind {
        switch self {
        case .cameraBrand, .cameraBody, .lens, .filename, .place, .anyText: .text
        case .sensorFormat, .fileType, .mediaType, .flag, .source, .original, .photoKind: .choice
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
        case .photoKind:
            PhotoKind.allCases.map { ($0.rawValue, $0.label) }
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
        case .date: [.on, .inMonth, .inLastDays, .notInLast, .before, .after, .inRange]
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
    /// Within the last `number` `unit`s (days when the rule has no unit —
    /// the raw value is from when days were the only unit).
    case inLastDays
    /// Older than the last `number` `unit`s (FS-06.08 §3c); undated photos
    /// do not match.
    case notInLast
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
        case .notInLast: "is not in the last"
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
    /// The unit of `inLastDays` / `notInLast` (FS-06.08 §3c). Nil = days, so
    /// albums saved before units read the way they were written.
    var unit: DateUnit?
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
        folder: String? = nil,
        unit: DateUnit? = nil
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
        self.unit = unit
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
            case .inLastDays, .notInLast: return (number ?? 0) > 0
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

/// A nested set of conditions with its own match mode — "Any of the
/// following are true" inside an album that matches all (FS-06.08 §2b). One
/// level deep, as the Mac editor draws it; the group is one condition of the
/// query it sits in.
struct SmartAlbumRuleGroup: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var matchMode: RuleMatchMode
    var rules: [SmartAlbumRule]

    init(id: UUID = UUID(), matchMode: RuleMatchMode = .any, rules: [SmartAlbumRule] = [SmartAlbumRule()]) {
        self.id = id
        self.matchMode = matchMode
        self.rules = rules
    }

    var validRules: [SmartAlbumRule] { rules.filter(\.isValid) }

    private enum CodingKeys: String, CodingKey {
        case id, matchMode, rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        matchMode = (try? c.decodeIfPresent(RuleMatchMode.self, forKey: .matchMode)) ?? .any
        rules = (try? c.decodeIfPresent([LossyRule].self, forKey: .rules))?.compactMap(\.rule) ?? []
    }
}

/// A named smart album's saved conditions: a match mode, an ordered list of
/// rules and any nested groups. Stored as JSON in `smart_albums.criteria`
/// (see `SmartAlbum`).
struct SmartAlbumQuery: Codable, Equatable, Sendable {
    var matchMode: RuleMatchMode
    var rules: [SmartAlbumRule]
    /// Nested condition groups, each one more condition of this query
    /// (FS-06.08 §2b). Screens that only list `rules` leave them as they are.
    var groups: [SmartAlbumRuleGroup]

    init(matchMode: RuleMatchMode = .all, rules: [SmartAlbumRule] = [], groups: [SmartAlbumRuleGroup] = []) {
        self.matchMode = matchMode
        self.rules = rules
        self.groups = groups
    }

    static let empty = SmartAlbumQuery()

    /// Only the rules complete enough to compile.
    var validRules: [SmartAlbumRule] { rules.filter(\.isValid) }

    /// Groups with at least one rule complete enough to compile.
    var validGroups: [SmartAlbumRuleGroup] {
        groups.compactMap { group in
            let rules = group.validRules
            return rules.isEmpty ? nil : SmartAlbumRuleGroup(id: group.id, matchMode: group.matchMode, rules: rules)
        }
    }

    /// No compilable condition — the album would have no predicate.
    var isEmpty: Bool { validRules.isEmpty && validGroups.isEmpty }

    /// What a sheet saves or applies: blank rows and empty groups dropped,
    /// nested groups kept.
    var cleaned: SmartAlbumQuery {
        SmartAlbumQuery(matchMode: matchMode, rules: validRules, groups: validGroups)
    }

    /// Every rule, the groups' included — for questions any condition answers.
    var allRules: [SmartAlbumRule] { rules + groups.flatMap(\.rules) }

    // MARK: Codable (tolerant + legacy migration)

    private enum CodingKeys: String, CodingKey {
        case matchMode, rules, groups
    }

    init(from decoder: Decoder) throws {
        groups = []
        // New shape: { matchMode, rules, groups? }.
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.rules) {
            matchMode = try c.decodeIfPresent(RuleMatchMode.self, forKey: .matchMode) ?? .all
            rules = try c.decodeIfPresent([LossyRule].self, forKey: .rules)?.compactMap(\.rule) ?? []
            // One unreadable group drops itself, not the album.
            groups = (try? c.decodeIfPresent(LossyArray<SmartAlbumRuleGroup>.self, forKey: .groups))?.elements ?? []
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
        if !groups.isEmpty { try c.encode(groups, forKey: .groups) }
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

        // One capture kind is a *Photo is …* rule (FS-06.08 §3c); several OR
        // in the filter and stay a gap (`migrationGaps`).
        if criteria.mediaSubtypes.count == 1, let kind = criteria.mediaSubtypes.first.flatMap(PhotoKind.init(subtype:)) {
            rules.append(SmartAlbumRule(field: .photoKind, op: .isExactly, text: kind.rawValue))
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
        if criteria.mediaSubtypes.count > 1
            || criteria.mediaSubtypes.contains(where: { PhotoKind(subtype: $0) == nil }) {
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
    var usesOriginal: Bool { allRules.contains { $0.field == .original } }
}


// MARK: - Units, kinds and row edits (FS-06.08 §3c)

/// The unit of a *is (not) in the last N …* date condition — Photos' Days /
/// Weeks / Months / Years.
enum DateUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case days, weeks, months, years

    var id: String { rawValue }

    /// Plural label for the unit pop-up ("weeks"), Photos' wording.
    var label: String {
        switch self {
        case .days: String(localized: "days", comment: "Date rule unit: is in the last N days")
        case .weeks: String(localized: "weeks", comment: "Date rule unit: is in the last N weeks")
        case .months: String(localized: "months", comment: "Date rule unit: is in the last N months")
        case .years: String(localized: "years", comment: "Date rule unit: is in the last N years")
        }
    }

    /// Chip letter: `last 2w`.
    var letter: String {
        switch self {
        case .days: "d"
        case .weeks: "w"
        case .months: "mo"
        case .years: "y"
        }
    }

    /// The instant `count` units before `now`, on the local calendar — three
    /// months back is the same day three months ago, not 90 days.
    func cutoff(count: Int, from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = switch self {
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        case .years: .year
        }
        return calendar.date(byAdding: component, value: -count, to: now)
            ?? now.addingTimeInterval(-Double(count) * 86_400)
    }
}

/// The values of the *Photo* condition: what PhotoKit can tell about an item,
/// in Photos' order. Hidden, selfie, long exposure, ProRes, referenced and
/// "unable to upload" are not here — ShotDex cannot read them (FS-06.08 §3c).
enum PhotoKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case favorite
    case edited
    case taggedWithGPS
    case raw
    case video
    case livePhoto
    case burst
    case panorama
    case hdr
    case portrait
    case screenshot
    case screenRecording
    case slowMotion
    case timelapse
    case cinematic
    case spatial
    case animated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .favorite: String(localized: "favorite", comment: "Photo rule value: Photo is favorite")
        case .edited: String(localized: "edited", comment: "Photo rule value: Photo is edited in Photos")
        case .taggedWithGPS: String(localized: "tagged with GPS", comment: "Photo rule value: Photo has a location")
        case .raw: "RAW"
        case .video: String(localized: "video", comment: "Photo rule value: the item is a video")
        case .livePhoto: String(localized: "Live Photo", comment: "Photo rule value")
        case .burst: String(localized: "burst", comment: "Photo rule value: a frame of a burst")
        case .panorama: String(localized: "panorama", comment: "Photo rule value")
        case .hdr: "HDR"
        case .portrait: String(localized: "portrait", comment: "Photo rule value: a Portrait mode photo")
        case .screenshot: String(localized: "screenshot", comment: "Photo rule value")
        case .screenRecording: String(localized: "screen recording", comment: "Photo rule value")
        case .slowMotion: String(localized: "slo-mo", comment: "Photo rule value")
        case .timelapse: String(localized: "time-lapse", comment: "Photo rule value")
        case .cinematic: String(localized: "Cinematic", comment: "Photo rule value: a Cinematic mode video")
        case .spatial: String(localized: "Spatial", comment: "Photo rule value: spatial photo or video")
        case .animated: String(localized: "animated", comment: "Photo rule value: an animated image (GIF)")
        }
    }
}

extension SmartAlbumRule {
    /// The rule with its field changed, keeping what still fits (FS-06.08 §3c
    /// A4): the operator when the new field offers it, numbers and ranges
    /// between number fields, text between text fields. Anything else starts
    /// blank, as a new row would.
    func changingField(to newField: RuleField) -> SmartAlbumRule {
        guard newField != field else { return self }
        var next = SmartAlbumRule(id: id, field: newField)
        let sameKind = newField.kind == field.kind
        if newField.kind.allowedOperators.contains(op) { next.op = op }
        guard sameKind else { return next }
        switch newField.kind {
        case .number, .date, .rating:
            next.number = number
            next.numberUpper = numberUpper
            next.unit = unit
        case .text, .caption:
            next.text = text
        default:
            break // a choice value belongs to its own field's value set
        }
        return next
    }
}

extension SmartAlbumQuery {
    /// Inserts a blank condition right after `id` (Photos' **+** on a row,
    /// FS-06.08 §3c D2), on the same field as that row; at the end when `id`
    /// is not a top-level rule. Returns the new rule's id.
    @discardableResult
    mutating func insertRule(after id: SmartAlbumRule.ID) -> SmartAlbumRule.ID {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            let rule = SmartAlbumRule()
            rules.append(rule)
            return rule.id
        }
        let rule = SmartAlbumRule(field: rules[index].field)
        rules.insert(rule, at: index + 1)
        return rule.id
    }

    /// How many conditions the match mode would join — rows and groups. One
    /// or none hides All / Any (FS-06.08 §3c D1).
    func conditionCount(excluding hidden: Set<RuleField> = [.mediaType]) -> Int {
        rules.filter { !hidden.contains($0.field) }.count + groups.count
    }
}

extension PhotoKind {
    /// The *Photo is …* value a Filter-menu capture kind saves as; nil for
    /// Unsupported RAW, which is a verdict, not a kind Photos has.
    init?(subtype: PhotoMediaSubtype) {
        switch subtype {
        case .screenshot: self = .screenshot
        case .livePhoto: self = .livePhoto
        case .portrait: self = .portrait
        case .panorama: self = .panorama
        case .hdr: self = .hdr
        case .timelapse: self = .timelapse
        case .slowMotion: self = .slowMotion
        case .cinematic: self = .cinematic
        case .unsupportedRAW: return nil
        }
    }
}
