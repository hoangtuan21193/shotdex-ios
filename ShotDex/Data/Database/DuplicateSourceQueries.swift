import Foundation
import GRDB

/// The Source popup of Duplicates (FS-19.04 §4): groups are found and kept
/// per source, and the popup shows one source's or every source's side by
/// side — never a group that mixes two.
struct DuplicateSourceQueries: Sendable {
    let database: AppDatabase

    struct SourceGroup: Equatable, Sendable {
        let sourceId: String
        let group: DuplicateGroup
    }

    /// The sources the popup offers: those with a scan or a photo with two
    /// copies inside them, Photos Library first.
    func sources() throws -> [(id: String, name: String)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.id, s.name FROM sources s
                WHERE EXISTS (SELECT 1 FROM duplicate_scan_state d WHERE d.sourceId = s.id)
                   OR EXISTS (SELECT 1 FROM photo_copies c WHERE c.sourceId = s.id AND c.missingSince IS NULL AND c.isHidden = 0
                              GROUP BY c.photoId HAVING COUNT(*) > 1)
                ORDER BY s.kind != 'photos', s.createdAt, s.id
                """).map { (id: $0["id"], name: $0["name"]) }
        }
    }

    /// The cached groups of one source, or of all of them (`sourceId` nil),
    /// each tagged with the source it belongs to.
    func groups(sourceId: String?) throws -> [SourceGroup] {
        let ids = try sourceId.map { [$0] } ?? sources().map(\.id)
        let store = PerceptualHashStore(database: database)
        return try ids.flatMap { id in
            (try store.cachedGroups(sourceId: id) ?? []).map { SourceGroup(sourceId: id, group: $0) }
        }
    }

    static let allSources = String(localized: "All Sources", comment: "Duplicates and Statistics: the Source popup's every-source choice")
    static let footnote = String(localized: "Groups stay inside one source. An identical copy in another source is the same photo (matched by content hash): it is counted once and never offered for deletion.",
                                 comment: "Duplicates: under the Source popup")
}
