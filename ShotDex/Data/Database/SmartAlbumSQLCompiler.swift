import Foundation
import GRDB

/// Compiles a `SmartAlbumQuery` (match mode + rules) into a SQL predicate over
/// `photo_metadata`. Shared by `LibraryQueryDAO` (smart-album grid/count) and
/// `StatsDAO` (chart filters) so the two stay in exact sync.
///
/// All column names come from closed `switch`es keyed by `RuleField` — never
/// from user text — so string-built SQL here carries no injection surface.
/// Only bound values (`?` placeholders) originate from user input.
enum SmartAlbumSQLCompiler {
    /// The rules joined by `AND` (match all) / `OR` (match any), **without** a
    /// leading `WHERE`. An `.any` join with more than one clause is wrapped in
    /// parentheses so an outer `AND` (date scope, NOT-NULL guards) can't bind
    /// across the inner `OR`. Empty when the query has no compilable rule.
    static func predicate(for query: SmartAlbumQuery) -> (sql: String, values: [DatabaseValueConvertible]) {
        let rules = query.validRules
        guard !rules.isEmpty else { return ("", []) }

        var clauses: [String] = []
        var values: [DatabaseValueConvertible] = []
        for rule in rules {
            guard let compiled = clause(for: rule) else { continue }
            clauses.append(compiled.sql)
            values.append(contentsOf: compiled.values)
        }
        guard !clauses.isEmpty else { return ("", []) }

        let joiner = query.matchMode == .all ? " AND " : " OR "
        let joined = clauses.joined(separator: joiner)
        let sql = (clauses.count > 1 && query.matchMode == .any) ? "(\(joined))" : joined
        return (sql, values)
    }

    /// The predicate as a full `WHERE …` clause (empty → no WHERE).
    static func whereClause(for query: SmartAlbumQuery) -> (sql: String, arguments: StatementArguments) {
        let (sql, values) = predicate(for: query)
        guard !sql.isEmpty else { return ("", StatementArguments()) }
        return ("WHERE " + sql, StatementArguments(values))
    }

    /// SQL + bound values for a single rule, or nil if it carries nothing to
    /// compile. NULL columns are wrapped in `COALESCE` for the negating
    /// operators so a missing value still satisfies "does not contain" / "is
    /// not" (and behaves under `OR` in match-any albums).
    static func clause(for rule: SmartAlbumRule) -> (sql: String, values: [DatabaseValueConvertible])? {
        switch rule.field.kind {
        case .text:
            return textClause(rule.op, term: rule.text, columns: textColumns(rule.field))

        case .choice:
            switch rule.field {
            case .sensorFormat:
                let value = rule.text
                switch rule.op {
                case .isExactly: return ("sensorFormat = ?", [value])
                case .isNot: return ("COALESCE(sensorFormat, '') <> ?", [value])
                default: return nil
                }
            case .fileType:
                guard let type = PhotoFileType(rawValue: rule.text) else { return nil }
                let patterns = type.extensions.map { "%.\($0)" }
                let values = patterns.map { $0 as DatabaseValueConvertible }
                switch rule.op {
                case .isExactly:
                    let ors = patterns.map { _ in "originalFilename LIKE ? COLLATE NOCASE" }
                    return ("(" + ors.joined(separator: " OR ") + ")", values)
                case .isNot:
                    let ands = patterns.map { _ in "COALESCE(originalFilename, '') NOT LIKE ? COLLATE NOCASE" }
                    return ("(" + ands.joined(separator: " AND ") + ")", values)
                default: return nil
                }
            default:
                return nil
            }

        case .number:
            guard let value = rule.number else { return nil }
            let column = numberColumn(rule.field, focalMode: rule.focalMode)
            switch rule.op {
            case .equalTo: return ("\(column) = ?", [value])
            case .greaterThan: return ("\(column) > ?", [value])
            case .lessThan: return ("\(column) < ?", [value])
            case .inRange:
                guard let upper = rule.numberUpper else { return nil }
                let (lo, hi) = value <= upper ? (value, upper) : (upper, value)
                return ("\(column) BETWEEN ? AND ?", [lo, hi])
            default: return nil
            }

        case .date:
            switch rule.op {
            case .on:
                // Match every photo captured on the picked calendar day:
                // [startOfDay, startOfNextDay). Calendar handles DST-length days.
                guard let epoch = rule.number else { return nil }
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: Date(timeIntervalSince1970: epoch))
                let end = calendar.date(byAdding: .day, value: 1, to: start)
                    ?? start.addingTimeInterval(86_400)
                return ("creationDate >= ? AND creationDate < ?",
                        [Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970)])
            case .inLastDays:
                guard let days = rule.number, days > 0 else { return nil }
                let seconds = Int(days.rounded()) * 86_400
                return ("creationDate >= CAST(strftime('%s','now') AS INTEGER) - ?", [seconds])
            case .before:
                guard let epoch = rule.number else { return nil }
                return ("creationDate < ?", [Int(epoch)])
            case .after:
                guard let epoch = rule.number else { return nil }
                return ("creationDate > ?", [Int(epoch)])
            case .inRange:
                guard let lower = rule.number, let upper = rule.numberUpper else { return nil }
                let (lo, hi) = lower <= upper ? (lower, upper) : (upper, lower)
                return ("creationDate BETWEEN ? AND ?", [Int(lo), Int(hi)])
            default:
                return nil
            }

        case .favorite:
            return ("isFavorite = ?", [rule.boolValue ? 1 : 0])
        }
    }

    /// Text clause across one or more columns (normalized + raw for
    /// camera/lens, so "R6" matches "Canon EOS R6").
    private static func textClause(
        _ op: RuleOperator,
        term rawTerm: String,
        columns: [String]
    ) -> (sql: String, values: [DatabaseValueConvertible])? {
        let term = rawTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !columns.isEmpty else { return nil }
        let likeValues = columns.map { _ in "%\(term)%" as DatabaseValueConvertible }
        let exactValues = columns.map { _ in term as DatabaseValueConvertible }
        switch op {
        case .contains:
            let ors = columns.map { "\($0) LIKE ? COLLATE NOCASE" }
            return ("(" + ors.joined(separator: " OR ") + ")", likeValues)
        case .doesNotContain:
            let ands = columns.map { "COALESCE(\($0), '') NOT LIKE ? COLLATE NOCASE" }
            return ("(" + ands.joined(separator: " AND ") + ")", likeValues)
        case .isExactly:
            let ors = columns.map { "\($0) = ? COLLATE NOCASE" }
            return ("(" + ors.joined(separator: " OR ") + ")", exactValues)
        case .isNot:
            let ands = columns.map { "COALESCE(\($0), '') <> ? COLLATE NOCASE" }
            return ("(" + ands.joined(separator: " AND ") + ")", exactValues)
        default:
            return nil
        }
    }

    private static func textColumns(_ field: RuleField) -> [String] {
        switch field {
        case .cameraBrand: ["normalizedCameraManufacturer", "cameraManufacturer"]
        case .cameraBody: ["normalizedCameraModel", "cameraModel"]
        case .lens: ["normalizedLensModel", "lensModel"]
        case .filename: ["originalFilename"]
        default: []
        }
    }

    private static func numberColumn(_ field: RuleField, focalMode: FocalLengthMode) -> String {
        switch field {
        case .iso: "iso"
        case .aperture: "aperture"
        case .shutter: "shutterSpeedSeconds"
        case .focalLength: focalMode == .equivalent ? "equivalentFocalLength" : "focalLength"
        default: "iso"
        }
    }
}
