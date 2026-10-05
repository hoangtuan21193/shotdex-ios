import Foundation
import GRDB

/// The background half of identity (FS-19.02 §1): full hashes for file
/// copies — fast-hash collisions first — then one photo for every full hash
/// that more than one photo carries.
struct IdentityMergePass: Sendable {
    let database: AppDatabase
    /// Where a copy's file is now; nil when its source is offline.
    let fileURL: @Sendable (_ sourceId: String, _ relativePath: String) -> URL?

    struct Summary: Equatable, Sendable {
        var hashed = 0
        var merged = 0
        /// The photos others were folded into. Their copies may carry
        /// sidecars that disagree; the merged values go out to all of them
        /// (FS-19.02 §6) — the caller queues the write.
        var survivors: Set<String> = []
    }

    func run(limit: Int = 500) throws -> Summary {
        var summary = Summary()
        let pending = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.sourceId, c.relativePath, h.fastHash FROM photo_copies c
                JOIN content_hashes h ON h.copyId = c.id
                WHERE c.kind = 'file' AND c.isOnline = 1 AND h.fullHash IS NULL
                ORDER BY c.id LIMIT ?
                """, arguments: [limit]).map { (id: $0["id"] as String, sourceId: $0["sourceId"] as String,
                                                path: $0["relativePath"] as String, fast: $0["fastHash"] as String) }
        }
        let byId = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        let store = ContentHashStore(database: database)
        for id in ContentHash.fullHashOrder(pending.map { (id: $0.id, fast: $0.fast) }) {
            try Task.checkCancellation()
            guard let copy = byId[id], let url = fileURL(copy.sourceId, copy.path),
                  let hash = try? ContentHasher.hash(FileBytes(url: url), full: true) else { continue }
            try store.save(hash, copyId: copy.id)
            summary.hashed += 1
        }
        (summary.merged, summary.survivors) = try mergeSharedHashes()
        return summary
    }

    /// Folds every set of photos sharing a full hash into one; returns how
    /// many photos went and the ids they went into.
    func mergeSharedHashes() throws -> (merged: Int, survivors: Set<String>) {
        try database.writer.write { db in
            let groups = try Row.fetchAll(db, sql: """
                SELECT GROUP_CONCAT(DISTINCT c.photoId) AS ids FROM content_hashes h
                JOIN photo_copies c ON c.id = h.copyId
                WHERE h.fullHash IS NOT NULL AND h.algorithm = ? AND h.algorithmVersion = ?
                GROUP BY h.fullHash HAVING COUNT(DISTINCT c.photoId) > 1
                """, arguments: [ContentHash.algorithm, ContentHash.version])
            var merged = 0
            var survivors = Set<String>()
            let now = Int(Date().timeIntervalSince1970)
            for group in groups {
                var ids = (group["ids"] as String).split(separator: ",").map(String.init)
                guard var survivor = ids.popLast() else { continue }
                for other in ids {
                    survivor = try PhotoIdentityStore.merge(db, survivor, other, now: now).winnerId
                    merged += 1
                }
                survivors.insert(survivor)
            }
            return (merged, survivors)
        }
    }
}
