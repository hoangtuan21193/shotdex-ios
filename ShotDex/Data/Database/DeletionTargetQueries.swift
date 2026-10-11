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
        let rows = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoId, c.sourceId, c.kind, c.photoKitId, c.relativePath, c.pairedPath, c.isOnline,
                       c.isCloudPlaceholder, s.name, s.kind AS sourceKind
                FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId IN (\(databaseQuestionMarks(count: photoIds.count))) AND c.missingSince IS NULL AND c.isHidden = 0
                """, arguments: StatementArguments(photoIds))
        }
        // Outside the read: `hasTrash` resolves the source's folder, which
        // reads the database itself, and GRDB reads are not reentrant.
        var trashBySource: [String: Bool] = [:]
        var out: [String: [(CopyOrder.Candidate, DeletionTarget)]] = [:]
        for row in rows {
            let kind: String = row["kind"], sourceId: String = row["sourceId"], name: String = row["name"]
            let destination: DeletionDestination
            switch kind {
            case "photos": destination = .recentlyDeleted
            case "server": destination = .hide(sourceName: name)
            default:
                let hasTrash = trashBySource[sourceId] ?? self.hasTrash(sourceId)
                trashBySource[sourceId] = hasTrash
                destination = hasTrash ? .trash : .permanent(sourceName: name)
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

    /// Every copy of each photo in `photoIds` order — what the checklist of
    /// a deletion from All Photos lists.
    func allCopies(photoIds: [String]) throws -> [[DeletionTarget]] {
        let all = try copies(photoIds: photoIds)
        return photoIds.compactMap { all[$0] }
    }

    func plan(photoIds: [String], inSource sourceId: String? = nil, selection: MixedDeletionPlan.Selection) throws -> MixedDeletionPlan {
        MixedDeletionPlan(photos: try targets(photoIds: photoIds, inSource: sourceId).map { $0.map(\.destination) }, selection: selection)
    }

    /// One deletion of a selection, ready to confirm and run.
    struct Request: Identifiable, Sendable {
        let id = UUID()
        let photoIds: [String]
        let targets: [[DeletionTarget]]
        /// Photos assets with no copy row yet (not indexed): deleted with
        /// the Photos part.
        let photosOnly: [String]
        let plan: MixedDeletionPlan
    }

    /// The deletion of `photoIds` through their sources, or nil when every
    /// one of them goes to Recently Deleted — then the system's own dialog
    /// is the whole confirmation and the old PhotoKit path runs.
    func request(photoIds: [String], inSource sourceId: String? = nil, selection: MixedDeletionPlan.Selection) throws -> Request? {
        let targets = try targets(photoIds: photoIds, inSource: sourceId)
        guard targets.joined().contains(where: { $0.kind != "photos" }) else { return nil }
        let covered = Set(targets.compactMap(\.first?.photoId))
        let photosOnly = photoIds.filter { !covered.contains($0) }
        let destinations = targets.map { $0.map(\.destination) } + photosOnly.map { _ in [DeletionDestination.recentlyDeleted] }
        return Request(photoIds: photoIds, targets: targets, photosOnly: photosOnly,
                       plan: MixedDeletionPlan(photos: destinations, selection: selection))
    }

    /// Of `photoIds`, those a grid still shows after a deletion: a copy
    /// left that is present and not hidden.
    func stillShown(photoIds: [String]) throws -> Set<String> {
        guard !photoIds.isEmpty else { return [] }
        return try database.reader.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT DISTINCT photoId FROM photo_copies
                WHERE photoId IN (\(databaseQuestionMarks(count: photoIds.count))) AND missingSince IS NULL AND isHidden = 0
                """, arguments: StatementArguments(photoIds)))
        }
    }
}
