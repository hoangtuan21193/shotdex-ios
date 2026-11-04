import Foundation
import GRDB

/// FS-19.08 §6d: the photos the user left out of a set, by SHA-256 — kept
/// in `common_photo_left_out` so every later scan, Run Again and Keep
/// gathering of the set skips them until Include.
struct CommonPhotosLeftOutStore: Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let sha256: String
        let name: String
        let size: Int64
        let leftOutAt: Date
        var id: String { sha256 }
    }

    /// A photo to leave out, as the row shows it.
    struct Photo: Equatable, Sendable {
        let sha256: String
        let name: String
        let size: Int64
    }

    let database: AppDatabase

    /// The set's left-out photos, oldest first.
    func entries(setKey: String) throws -> [Entry] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT sha256, name, size, createdAt FROM common_photo_left_out WHERE setKey = ? ORDER BY createdAt, name
                """, arguments: [setKey]).map {
                Entry(sha256: $0["sha256"], name: $0["name"], size: $0["size"],
                      leftOutAt: Date(timeIntervalSince1970: TimeInterval($0["createdAt"] as Int)))
            }
        }
    }

    func leaveOut(_ photos: [Photo], setKey: String, connectionId: String, at date: Date = Date()) throws {
        guard !photos.isEmpty else { return }
        try database.writer.write { db in
            for photo in photos {
                // Left out again: the first time stays.
                try db.execute(sql: """
                    INSERT OR IGNORE INTO common_photo_left_out (setKey, connectionId, sha256, name, size, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [setKey, connectionId, photo.sha256, photo.name, photo.size, Int(date.timeIntervalSince1970)])
            }
        }
    }

    func include(_ sha256s: Set<String>, setKey: String) throws {
        guard !sha256s.isEmpty else { return }
        let all = Array(sha256s)
        try database.writer.write { db in
            // In chunks: SQLite caps the variables of one statement.
            for start in stride(from: 0, to: all.count, by: 500) {
                let chunk = Array(all[start..<min(start + 500, all.count)])
                try db.execute(sql: "DELETE FROM common_photo_left_out WHERE setKey = ? AND sha256 IN (\(databaseQuestionMarks(count: chunk.count)))",
                               arguments: StatementArguments([setKey] + chunk))
            }
        }
    }

    /// The set went (Remove from List).
    static func forget(setKey: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM common_photo_left_out WHERE setKey = ?", arguments: [setKey])
    }

    /// The connection went: every set on it.
    static func forget(connectionId: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM common_photo_left_out WHERE connectionId = ?", arguments: [connectionId])
    }
}
