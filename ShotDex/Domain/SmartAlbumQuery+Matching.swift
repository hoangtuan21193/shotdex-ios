import Foundation

/// In-memory evaluation of a `SmartAlbumQuery` against a single `PhotoMetadata`
/// row. Mirrors `SmartAlbumSQLBuilder` clause-for-clause so filtering a not-
/// yet-indexed import candidate (which has no DB row to run SQL against) gives
/// the exact same result the Library/Statistics would once the photo is indexed.
///
/// Any change to the SQL builder's semantics must be mirrored here, and vice
/// versa — `SmartAlbumQueryMatchingTests` pins the two together.
extension SmartAlbumQuery {
    /// Whether `metadata` satisfies this query. An empty query (no compilable
    /// rule) matches everything, matching the builder's "no predicate" case.
    func matches(_ metadata: PhotoMetadata) -> Bool {
        let rules = validRules.filter(Self.isEvaluableInMemory)
        guard !rules.isEmpty else { return true }
        switch matchMode {
        case .all: return rules.allSatisfy { Self.matches(rule: $0, metadata) }
        case .any: return rules.contains { Self.matches(rule: $0, metadata) }
        }
    }

    /// Rules this matcher cannot answer, so callers can leave them out instead of
    /// silently getting `false`.
    ///
    /// `.place` is the only one: the reverse-geocoded address lives in columns
    /// deliberately kept off `PhotoMetadata` (an indexer upsert carrying empty
    /// place values would erase them), and an import candidate has no row to read
    /// them from anyway. Treating it as "no match" would make an import filter
    /// that mentions a place quietly return nothing.
    static func isEvaluableInMemory(_ rule: SmartAlbumRule) -> Bool {
        rule.field != .place
    }

    private static func matches(rule: SmartAlbumRule, _ metadata: PhotoMetadata) -> Bool {
        switch rule.field.kind {
        case .text:
            return textMatch(rule.op, term: rule.text, values: textValues(rule.field, metadata))
        case .choice:
            return choiceMatch(rule, metadata)
        case .number:
            return numberMatch(rule, metadata)
        case .date:
            return dateMatch(rule, metadata)
        case .favorite:
            return metadata.isFavorite == rule.boolValue
        }
    }

    // MARK: Text (mirrors SmartAlbumSQLBuilder.textClause)

    private static func textValues(_ field: RuleField, _ metadata: PhotoMetadata) -> [String?] {
        switch field {
        case .cameraBrand: [metadata.normalizedCameraManufacturer, metadata.cameraManufacturer]
        case .cameraBody: [metadata.normalizedCameraModel, metadata.cameraModel]
        case .lens: [metadata.normalizedLensModel, metadata.lensModel]
        case .filename: [metadata.originalFilename]
        default: []
        }
    }

    private static func textMatch(_ op: RuleOperator, term rawTerm: String, values: [String?]) -> Bool {
        let term = rawTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !values.isEmpty else { return false }
        func contains(_ value: String?) -> Bool {
            (value ?? "").range(of: term, options: .caseInsensitive) != nil
        }
        func equals(_ value: String?) -> Bool {
            (value ?? "").compare(term, options: .caseInsensitive) == .orderedSame
        }
        switch op {
        // `%term%` OR across columns; `NOT LIKE` AND with NULL→'' for negation.
        case .contains: return values.contains { contains($0) }
        case .doesNotContain: return values.allSatisfy { !contains($0 ?? "") }
        case .isExactly: return values.contains { $0 != nil && equals($0) }
        case .isNot: return values.allSatisfy { !equals($0 ?? "") }
        default: return false
        }
    }

    // MARK: Choice (sensor format / file type)

    private static func choiceMatch(_ rule: SmartAlbumRule, _ metadata: PhotoMetadata) -> Bool {
        switch rule.field {
        case .sensorFormat:
            switch rule.op {
            case .isExactly: return metadata.sensorFormat == rule.text
            case .isNot: return (metadata.sensorFormat ?? "") != rule.text
            default: return false
            }
        case .fileType:
            guard let type = PhotoFileType(rawValue: rule.text) else { return false }
            let name = (metadata.originalFilename ?? "").lowercased()
            // Mirrors `originalFilename LIKE '%.ext'` — suffix match on extension.
            let hit = type.extensions.contains { name.hasSuffix(".\($0)") }
            switch rule.op {
            case .isExactly: return hit
            case .isNot: return !hit
            default: return false
            }
        default:
            return false
        }
    }

    // MARK: Number (iso / aperture / shutter / focal)

    private static func numberMatch(_ rule: SmartAlbumRule, _ metadata: PhotoMetadata) -> Bool {
        guard let target = rule.number, let value = numberValue(rule.field, focalMode: rule.focalMode, metadata) else {
            return false
        }
        switch rule.op {
        case .equalTo: return value == target
        case .greaterThan: return value > target
        case .lessThan: return value < target
        case .inRange:
            guard let upper = rule.numberUpper else { return false }
            let (lo, hi) = target <= upper ? (target, upper) : (upper, target)
            return value >= lo && value <= hi
        default: return false
        }
    }

    private static func numberValue(_ field: RuleField, focalMode: FocalLengthMode, _ metadata: PhotoMetadata) -> Double? {
        switch field {
        case .iso: metadata.iso.map(Double.init)
        case .aperture: metadata.aperture
        case .shutter: metadata.shutterSpeedSeconds
        case .focalLength: focalMode == .equivalent ? metadata.equivalentFocalLength : metadata.focalLength
        default: nil
        }
    }

    // MARK: Date (creationDate epoch seconds)

    private static func dateMatch(_ rule: SmartAlbumRule, _ metadata: PhotoMetadata) -> Bool {
        guard let epoch = metadata.creationDate.map(Double.init) else { return false }
        switch rule.op {
        case .on:
            guard let day = rule.number else { return false }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date(timeIntervalSince1970: day))
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return epoch >= start.timeIntervalSince1970 && epoch < end.timeIntervalSince1970
        case .inLastDays:
            guard let days = rule.number, days > 0 else { return false }
            let cutoff = Date().timeIntervalSince1970 - Double(Int(days.rounded()) * 86_400)
            return epoch >= cutoff
        case .before:
            guard let bound = rule.number else { return false }
            return epoch < bound
        case .after:
            guard let bound = rule.number else { return false }
            return epoch > bound
        case .inRange:
            guard let lower = rule.number, let upper = rule.numberUpper else { return false }
            let (lo, hi) = lower <= upper ? (lower, upper) : (upper, lower)
            return epoch >= lo && epoch <= hi
        default:
            return false
        }
    }
}
