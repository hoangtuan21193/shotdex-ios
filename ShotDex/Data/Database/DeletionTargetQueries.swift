import Foundation
import GRDB

/// One copy a deletion will act on.
struct DeletionTarget: Hashable, Sendable {
    let photoId: String
    let copyId: String
    let sourceId: String
    let sourceName: String
    /// `photos` · `file` · `server`
    let kind: String
    let photoKitId: String?
    let relativePath: String?
    let pairedPath: String?
    let destination: DeletionDestination
}

/// Which copies a Move / Delete / Hide removes (FS-19.04 §1): in a source's
/// own view, that source's copies; elsewhere the copy the photo opens from,
/// the others left as backups.
struct DeletionTargetQueries: Sendable {
    let database: AppDatabase
    /// False for a volume without a Trash (a USB-C drive on iPad, some
    /// exFAT/FAT volumes, a share mounted in Finder).
    var hasTrash: @Sendable (_ sourceId: String) -> Bool = { _ in true }

    /// Every copy of each photo that could be deleted, in copy order.
    func copies(photoIds: [String]) throws -> [String: [DeletionTarget]] {
        guard !photoIds.isEmpty else { return [:] }
        return try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoId, c.sourceId, c.kind, c.photoKitId, c.relativePath, c.pairedPath, c.isOnline,
                       c.isCloudPlaceholder, s.name, s.kind AS sourceKind
                FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId IN (\(databaseQuestionMarks(count: photoIds.count))) AND c.missingSince IS NULL AND c.isHidden = 0
                """, arguments: StatementArguments(photoIds))
            var out: [String: [(CopyOrder.Candidate, DeletionTarget)]] = [:]
            for row in rows {
                let kind: String = row["kind"], sourceId: String = row["sourceId"], name: String = row["name"]
                let destination: DeletionDestination = switch kind {
                case "photos": .recentlyDeleted
                case "server": .hide(sourceName: name)
                default: hasTrash(sourceId) ? .trash : .permanent(sourceName: name)
                }
                let target = DeletionTarget(photoId: row["photoId"], copyId: row["id"], sourceId: sourceId, sourceName: name, kind: kind,
                                            photoKitId: row["photoKitId"], relativePath: row["relativePath"],
                                            pairedPath: row["pairedPath"], destination: destination)
                let candidate = CopyOrder.Candidate(copyId: target.copyId, kind: kind, sourceKind: row["sourceKind"],
                                                    isOnline: row["isOnline"], isCloudPlaceholder: row["isCloudPlaceholder"])
                out[target.photoId, default: []].append((candidate, target))
            }
            return out.mapValues { pairs in
                let order = CopyOrder.sorted(pairs.map(\.0)).map(\.copyId)
                return pairs.map(\.1).sorted { order.firstIndex(of: $0.copyId)! < order.firstIndex(of: $1.copyId)! }
            }
        }
    }

    /// The copies a deletion removes by default: `sourceId`'s when the user
    /// is inside that source, else each photo's first copy.
    func targets(photoIds: [String], inSource sourceId: String? = nil) throws -> [[DeletionTarget]] {
        let all = try copies(photoIds: photoIds)
        return photoIds.compactMap { id in
            guard let copies = all[id] else { return nil }
            if let sourceId { return copies.filter { $0.sourceId == sourceId } }
            return Array(copies.prefix(1))
        }.filter { !$0.isEmpty }
    }

    func plan(photoIds: [String], inSource sourceId: String? = nil, selection: MixedDeletionPlan.Selection) throws -> MixedDeletionPlan {
        MixedDeletionPlan(photos: try targets(photoIds: photoIds, inSource: sourceId).map { $0.map(\.destination) }, selection: selection)
    }
}
