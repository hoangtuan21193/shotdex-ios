import Foundation
import GRDB

/// Whether a connection kept the dates of the files written through it, as
/// its last run found (FS-19.08 §6e) — so the next one says so before it
/// starts ("This server does not keep file dates…") instead of only in the
/// log after. Derived: each run writes it again, and it goes with the
/// connection (`FileServerStore.delete`).
enum ServerFileInfoSupport {
    /// What a run's outcomes say about the server: it keeps dates unless
    /// every file it wrote lost them; nil when it wrote none.
    static func keepsDates(from outcomes: [FileInfoOutcome]) -> Bool? {
        guard !outcomes.isEmpty else { return nil }
        return !outcomes.allSatisfy { $0 == .datesNotKept }
    }

    static func record(connectionId: String, keepsDates: Bool, in database: AppDatabase,
                       at date: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO server_file_info_support (connectionId, keepsDates, checkedAt) VALUES (?, ?, ?)
                ON CONFLICT(connectionId) DO UPDATE SET keepsDates = excluded.keepsDates, checkedAt = excluded.checkedAt
                """, arguments: [connectionId, keepsDates, Int(date.timeIntervalSince1970)])
        }
    }

    /// Nil until a run has written through the connection.
    static func keepsDates(connectionId: String, in database: AppDatabase) throws -> Bool? {
        try database.reader.read { db in
            try Bool.fetchOne(db, sql: "SELECT keepsDates FROM server_file_info_support WHERE connectionId = ?",
                              arguments: [connectionId])
        }
    }
}
