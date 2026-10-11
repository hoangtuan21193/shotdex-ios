import Foundation
import GRDB

/// Two identical files in the same source are one photo with two copies
/// there (FS-19.04 §4) — Duplicates shows them as an Exact group. Groups
/// never cross sources: an identical copy elsewhere is the same photo,
/// counted once and never offered for deletion.
struct ExactCopyGroup: Equatable, Sendable, Identifiable {
    let photoId: String
    let sourceId: String
    let sourceName: String
    /// The copies in this source, in copy order — the one to keep first.
    let copies: [DeletionTarget]
    var id: String { "\(sourceId)|\(photoId)" }

    /// "2 identical copies of DSC04512.ARW · both on T7 RAW Archive"
    var title: String {
        let name = copies.first?.relativePath.map { ($0 as NSString).lastPathComponent } ?? ""
        let where_ = copies.count == 2
            ? String(localized: "both on \(sourceName)", comment: "Duplicates: two identical copies in one source")
            : String(localized: "all on \(sourceName)", comment: "Duplicates: three or more identical copies in one source")
        return String(localized: "\(copies.count) identical copies of \(name) · \(where_)", comment: "Duplicates: an Exact group of one photo's copies")
    }
}

struct ExactCopyGroupQueries: Sendable {
    let database: AppDatabase
    var hasTrash: @Sendable (_ sourceId: String) -> Bool = { _ in true }

    /// Groups of one source, or of every file source when `sourceId` is nil.
    func groups(sourceId: String? = nil) throws -> [ExactCopyGroup] {
        let pairs = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT photoId, sourceId FROM photo_copies
                WHERE kind IN ('file', 'server') AND missingSince IS NULL AND isHidden = 0 \(sourceId == nil ? "" : "AND sourceId = ?")
                GROUP BY sourceId, photoId HAVING COUNT(*) > 1
                ORDER BY sourceId, photoId
                """, arguments: sourceId.map { [$0] } ?? [])
                .map { (photoId: $0["photoId"] as String, sourceId: $0["sourceId"] as String) }
        }
        let copies = try DeletionTargetQueries(database: database, hasTrash: hasTrash).copies(photoIds: Array(Set(pairs.map(\.photoId))))
        return pairs.compactMap { pair in
            let here = (copies[pair.photoId] ?? []).filter { $0.sourceId == pair.sourceId }
            guard here.count > 1, let first = here.first else { return nil }
            return ExactCopyGroup(photoId: pair.photoId, sourceId: pair.sourceId, sourceName: first.sourceName, copies: here)
        }
    }
}
