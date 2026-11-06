import Foundation

/// Rewrites a smart album saved before Also on Server existed (FS-19.07 §7,
/// 2026-11-06): `Source is <server>` becomes `Also on Server: Yes`, `is not`
/// becomes `No`, folder kept — the album shows the same photos. The JSON does
/// not say which sources are servers, so the caller hands the ids over. Not
/// a data migration (ShotDex is unreleased): it keeps an album people delete
/// from from losing its only condition and widening to the whole library.
enum AlsoOnServerMigration {
    static func rewrite(_ query: SmartAlbumQuery, serverIds: Set<String>) -> SmartAlbumQuery {
        var query = query
        for index in query.rules.indices {
            let rule = query.rules[index]
            guard rule.field == .source, serverIds.contains(rule.text),
                  rule.op == .isExactly || rule.op == .isNot else { continue }
            query.rules[index] = SmartAlbumRule(
                id: rule.id,
                field: .alsoOnServer,
                text: rule.text,
                boolValue: rule.op == .isExactly,
                folder: rule.folder
            )
        }
        return query
    }
}
