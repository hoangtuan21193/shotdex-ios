import Foundation

/// One condition as a language model is allowed to express it: plain strings and
/// numbers, nothing app-specific.
///
/// Deliberately not `SmartAlbumRule`. A generated value cannot be trusted to be a
/// valid case of anything, so the model writes into a shape where every field is
/// free-form and `SearchIntentMapper` is the only thing that turns it into a real
/// rule. That keeps exactly one place to audit, and keeps the model's vocabulary
/// stable even if the rule model grows a case.
struct GeneratedSearchRule: Equatable, Sendable {
    /// One of: place, camera, brand, lens, iso, aperture, shutter, focal,
    /// filename, date, favorite, filetype, sensor.
    var field: String
    /// One of: is, contains, not, greater, less, range, before, after, lastdays.
    var comparison: String
    /// Text operand for text and choice fields.
    var text: String?
    var value: Double?
    var upperValue: Double?
}

/// Validates model output into rules the rest of the app can run.
///
/// Everything the model produces passes through here, and nothing else does the
/// conversion. Three jobs, in order of how much they matter:
///
/// 1. **Drop what is not real.** An unknown field or comparison is discarded
///    rather than guessed at.
/// 2. **Refuse the implausible.** "ISO 1.4" and "f/3200" are mislabelled, and a
///    rule made from them produces a confident chip over an empty grid.
/// 3. **Never touch SQL.** Rules go to `SmartAlbumSQLBuilder`, whose column names
///    come from closed switches and whose values are always bound — so even a
///    hostile string is only ever a `LIKE` operand.
enum SearchIntentMapper {
    static func rules(from generated: [GeneratedSearchRule]) -> [SmartAlbumRule] {
        generated.compactMap(rule(from:))
    }

    static func rule(from generated: GeneratedSearchRule) -> SmartAlbumRule? {
        guard let field = field(generated.field) else { return nil }
        let text = generated.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch field.kind {
        case .text:
            guard !text.isEmpty, let op = textOperator(generated.comparison) else { return nil }
            return SmartAlbumRule(field: field, op: op, text: text)

        case .choice:
            // The value has to be a case of the closed set, matched loosely: a
            // model writes "JPEG" or "jpg" where the app stores "jpeg".
            guard let value = choiceValue(text, for: field),
                  let op = textOperator(generated.comparison)
            else { return nil }
            return SmartAlbumRule(
                field: field,
                op: op == .doesNotContain || op == .isNot ? .isNot : .isExactly,
                text: value
            )

        case .number:
            guard let op = numberOperator(generated.comparison),
                  let lower = generated.value,
                  SearchIntentParser.isPlausible(lower, for: field)
            else { return nil }
            if op == .inRange {
                guard let upper = generated.upperValue,
                      SearchIntentParser.isPlausible(upper, for: field)
                else { return nil }
                return SmartAlbumRule(
                    field: field,
                    op: .inRange,
                    number: min(lower, upper),
                    numberUpper: max(lower, upper)
                )
            }
            return SmartAlbumRule(field: field, op: op, number: lower)

        case .date:
            guard let op = dateOperator(generated.comparison), let value = generated.value
            else { return nil }
            if op == .inRange {
                guard let upper = generated.upperValue else { return nil }
                return SmartAlbumRule(
                    field: field,
                    op: .inRange,
                    number: min(value, upper),
                    numberUpper: max(value, upper)
                )
            }
            if op == .inLastDays {
                // Days, not an epoch. A model that confuses the two would ask for
                // the last fifty-six thousand years.
                guard value > 0, value <= 3_650 else { return nil }
                return SmartAlbumRule(field: field, op: .inLastDays, number: value.rounded())
            }
            guard Self.plausibleEpochs.contains(value) else { return nil }
            return SmartAlbumRule(field: field, op: op, number: value)

        case .favorite:
            // "not favorite" is a real thing to ask for.
            let negated = ["not", "isnot", "false", "no"].contains(
                generated.comparison.lowercased()
            )
            return SmartAlbumRule(field: field, boolValue: !negated)
        }
    }

    /// 1970 through 2200 — wide enough for any real capture date, narrow enough to
    /// catch milliseconds passed as seconds.
    private static let plausibleEpochs: ClosedRange<Double> = 0...7_258_118_400

    private static func field(_ raw: String) -> RuleField? {
        switch raw.lowercased() {
        case "place", "location", "city", "country": .place
        case "camera", "cameramodel", "body", "camerabody": .cameraBody
        case "brand", "make", "manufacturer", "camerabrand": .cameraBrand
        case "lens": .lens
        case "iso": .iso
        case "aperture", "f", "fstop", "fnumber": .aperture
        case "shutter", "shutterspeed", "exposure": .shutter
        case "focal", "focallength": .focalLength
        case "filename", "name": .filename
        case "date", "datetaken", "year": .dateTaken
        case "favorite", "favourite": .favorite
        case "filetype", "format", "type": .fileType
        case "sensor", "sensorformat": .sensorFormat
        default: nil
        }
    }

    private static func textOperator(_ raw: String) -> RuleOperator? {
        switch raw.lowercased() {
        case "contains", "like", "": .contains
        case "is", "equals", "equal", "isexactly": .isExactly
        case "not", "isnot", "notequals": .isNot
        case "doesnotcontain", "excludes", "without": .doesNotContain
        default: nil
        }
    }

    private static func numberOperator(_ raw: String) -> RuleOperator? {
        switch raw.lowercased() {
        case "is", "equals", "equal", "equalto", "": .equalTo
        case "greater", "greaterthan", "above", "over", "atleast", "min": .greaterThan
        case "less", "lessthan", "below", "under", "atmost", "max": .lessThan
        case "range", "between", "inrange", "from": .inRange
        default: nil
        }
    }

    private static func dateOperator(_ raw: String) -> RuleOperator? {
        switch raw.lowercased() {
        case "before": .before
        case "after", "since": .after
        case "range", "between", "inrange", "in": .inRange
        case "lastdays", "last", "recent": .inLastDays
        case "is", "on", "": .on
        default: nil
        }
    }

    /// Loose match against a closed set: raw value, display name, or a prefix.
    private static func choiceValue(_ text: String, for field: RuleField) -> String? {
        let wanted = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !wanted.isEmpty else { return nil }
        let candidates = field.choiceValues
        if let exact = candidates.first(where: {
            $0.value.lowercased() == wanted
                || $0.label.lowercased().replacingOccurrences(of: " ", with: "") == wanted
        }) {
            return exact.value
        }
        // "jpg" for JPEG, "aps c" for APS-C.
        if field == .fileType,
           let type = PhotoFileType.allCases.first(where: { $0.extensions.contains(wanted) }) {
            return type.rawValue
        }
        return candidates.first {
            $0.value.lowercased().hasPrefix(wanted) || wanted.hasPrefix($0.value.lowercased())
        }?.value
    }
}
