import Foundation
import GRDB

/// Orphans and their purge (`OrphanRetention`, FS-19.05 §5). Every sweep is
/// anchored on `photos`, never on `photo_metadata`, which Clear Local
/// Metadata Index empties.
struct PhotoOrphanStore: Sendable {
    let database: AppDatabase

    /// Photos gone from the library: their Photos copy goes, and a photo left
    /// with no copy anywhere is marked an orphan. A photo that still has a file
    /// or server copy is not one. Marking twice keeps the first date.
    func markGoneFromLibrary(ids: [String], at now: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        let stamp = Int(now.timeIntervalSince1970)
        try database.writer.write { db in
            for chunk in stride(from: 0, to: ids.count, by: 500) {
                let slice = Array(ids[chunk..<min(chunk + 500, ids.count)])
                let marks = databaseQuestionMarks(count: slice.count)
                try CopyFileStore.deletePhotosFiles(db, assetIds: slice)
                try db.execute(
                    sql: "DELETE FROM photo_copies WHERE kind = 'photos' AND photoKitId IN (\(marks))",
                    arguments: StatementArguments(slice)
                )
                try db.execute(
                    sql: """
                        UPDATE photos SET orphanedAt = ?
                        WHERE id IN (\(marks)) AND orphanedAt IS NULL
                          AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = photos.id AND c.missingSince IS NULL)
                        """,
                    arguments: StatementArguments([stamp] + slice)
                )
            }
        }
    }

    /// Removes every orphan older than `cutoff` and the user data that hung
    /// off it, in one transaction. Upload, download and card-import history
    /// outlive the photo (BD-02 §3) and are never touched. Returns how many
    /// photos went.
    @discardableResult
    func purge(orphanedBefore cutoff: Date) throws -> Int {
        let stamp = Int(cutoff.timeIntervalSince1970)
        return try database.writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM photos WHERE orphanedAt IS NOT NULL AND orphanedAt < ?",
                                          arguments: [stamp])
            guard !ids.isEmpty else { return 0 }
            for chunk in stride(from: 0, to: ids.count, by: 500) {
                let slice = Array(ids[chunk..<min(chunk + 500, ids.count)])
                let marks = databaseQuestionMarks(count: slice.count)
                let arguments = StatementArguments(slice)
                try db.execute(sql: "DELETE FROM content_hashes WHERE copyId IN (SELECT id FROM photo_copies WHERE photoId IN (\(marks)))",
                               arguments: arguments)
                for (table, column) in Self.userDataTables {
                    try db.execute(sql: "DELETE FROM \(table) WHERE \(column) IN (\(marks))", arguments: arguments)
                }
                try db.execute(sql: "DELETE FROM photo_aliases WHERE winnerId IN (\(marks))", arguments: arguments)
                try db.execute(sql: "DELETE FROM photos WHERE id IN (\(marks))", arguments: arguments)
            }
            return ids.count
        }
    }

    /// What goes with a purged photo — everything keyed by its id except the
    /// three histories.
    static let userDataTables: [(table: String, column: String)] = [
        ("photo_copies", "photoId"),
        ("photo_flag", "assetId"),
        ("pending_photo_rating", "assetId"),
        ("photo_user_marks", "photoId"),
        ("photo_user_keyword", "photoId"),
        ("photo_recipes", "photoId"),
        ("shotdex_album_members", "photoId"),
        ("pending_sidecar", "photoId"),
        ("perceptual_hash", "assetId"),
        ("subject_scan", "assetId"),
        ("raw_pair_assets", "assetId"),
    ]
}
