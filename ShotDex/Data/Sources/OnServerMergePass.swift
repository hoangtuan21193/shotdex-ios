import Foundation
import GRDB

/// Shows a Photos item and its byte-identical server copy as one photo
/// (FS-19.07 §3, phase 2): once every file of a server photo has the same
/// SHA-256 as a file of a Photos item, the server photo is folded into the
/// Photos item — which keeps its asset id. The check never depends on this
/// (it reads the per-file hashes), and nothing is written to the server:
/// a merge made by the check queues no sidecar.
struct OnServerMergePass: Sendable {
    let database: AppDatabase

    /// Returns how many server photos were folded in.
    @discardableResult
    func run(now: Date = Date()) throws -> Int {
        try database.writer.write { db in
            // A server photo with nothing but server copies, each of whose
            // files is a file of one Photos item.
            let pairs = try Row.fetchAll(db, sql: """
                SELECT DISTINCT sc.photoId AS serverPhoto, pc.photoId AS photosPhoto
                FROM photo_copies sc
                JOIN copy_files sf ON sf.copyId = sc.id AND sf.fileKey = 'primary' AND sf.sha256 IS NOT NULL
                JOIN copy_files pf ON pf.sha256 = sf.sha256
                JOIN photo_copies pc ON pc.id = pf.copyId AND pc.kind = 'photos'
                WHERE sc.kind = 'server' AND sc.missingSince IS NULL AND sc.photoId <> pc.photoId
                  AND NOT EXISTS (SELECT 1 FROM photo_copies o WHERE o.photoId = sc.photoId AND o.kind <> 'server')
                  AND NOT EXISTS (
                    SELECT 1 FROM photo_copies s2 JOIN copy_files f2 ON f2.copyId = s2.id
                    WHERE s2.photoId = sc.photoId
                      AND (f2.sha256 IS NULL OR NOT EXISTS (
                        SELECT 1 FROM copy_files p2 WHERE p2.copyId = pc.id AND p2.sha256 = f2.sha256)))
                """).map { (server: $0["serverPhoto"] as String, photos: $0["photosPhoto"] as String) }
            var merged = 0
            var gone = Set<String>()
            let time = Int(now.timeIntervalSince1970)
            for pair in pairs where !gone.contains(pair.server) {
                _ = try PhotoIdentityStore.merge(db, pair.photos, pair.server, keeping: pair.photos, now: time)
                gone.insert(pair.server)
                merged += 1
            }
            return merged
        }
    }
}
