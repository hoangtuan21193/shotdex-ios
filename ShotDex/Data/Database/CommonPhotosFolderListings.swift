import Foundation
import GRDB
import os

/// What each folder held when Common Photos last listed it, per connection
/// (`common_photo_folder_listings`, FS-19.08 §6e) — derived data, gone with
/// the connection (`FileServerStore.delete`) or after a week unused.
/// Fresh listings are kept in memory and written in one transaction by
/// `flush()`, not one per folder.
final class CommonPhotosFolderListings: Sendable {
    let database: AppDatabase
    let connectionId: String
    let now: @Sendable () -> Date
    private let pending = OSAllocatedUnfairLock(initialState: [String: CommonPhotosListingCache.Listed]())

    /// A folder written to less than this before its listing is not kept:
    /// a file added in the same second (two on FAT) leaves the time as it was.
    static let settle: TimeInterval = 5
    /// Rows not listed for this long go: past a day none is reused anyway.
    static let keep: TimeInterval = 7 * 24 * 60 * 60

    init(database: AppDatabase, connectionId: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.connectionId = connectionId
        self.now = now
    }

    /// The folder's entries: from the last listing when
    /// `CommonPhotosListingCache.reuses` says so, else from `client`, kept
    /// for next time when the parent gave the folder a settled write time.
    func entries(in path: String, folderModified: Date?, client: any RemoteFileClient) async throws -> [RemoteEntry] {
        let date = now()
        let cached = try? listed(path)
        if CommonPhotosListingCache.reuses(cached, folderModified: folderModified, now: date), let cached {
            return cached.entries
        }
        let entries = try await client.entries(in: path)
        if let folderModified, date.timeIntervalSince(folderModified) >= Self.settle {
            let listed = CommonPhotosListingCache.Listed(folderModified: Int(folderModified.timeIntervalSince1970),
                                                         hasSubfolders: entries.contains(where: \.isDirectory),
                                                         entries: entries, listedAt: date)
            pending.withLock { $0[path] = listed }
        }
        return entries
    }

    /// Writes what was listed since the last flush, and forgets rows a
    /// week old. A failed write only costs the next scan a listing.
    func flush() {
        let rows = pending.withLock { rows in
            defer { rows = [:] }
            return rows
        }
        let cutoff = Int(now().addingTimeInterval(-Self.keep).timeIntervalSince1970)
        try? database.writer.write { db in
            for (path, listed) in rows {
                // `RemoteEntry` stays additive: a field it gains must decode
                // from older rows (or they are listed again, never misread).
                let json = String(decoding: try JSONEncoder().encode(listed.entries), as: UTF8.self)
                try db.execute(sql: """
                    INSERT INTO common_photo_folder_listings (connectionId, path, folderModified, hasSubfolders, entries, listedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(connectionId, path) DO UPDATE SET folderModified = excluded.folderModified,
                        hasSubfolders = excluded.hasSubfolders, entries = excluded.entries, listedAt = excluded.listedAt
                    """, arguments: [connectionId, path, listed.folderModified, listed.hasSubfolders, json,
                                     Int(listed.listedAt.timeIntervalSince1970)])
            }
            try db.execute(sql: "DELETE FROM common_photo_folder_listings WHERE connectionId = ? AND listedAt < ?",
                           arguments: [connectionId, cutoff])
        }
    }

    func listed(_ path: String) throws -> CommonPhotosListingCache.Listed? {
        try database.reader.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT folderModified, hasSubfolders, entries, listedAt FROM common_photo_folder_listings
                WHERE connectionId = ? AND path = ?
                """, arguments: [connectionId, path]),
                let json = (row["entries"] as String?)?.data(using: .utf8),
                let entries = try? JSONDecoder().decode([RemoteEntry].self, from: json) else { return nil }
            return .init(folderModified: row["folderModified"], hasSubfolders: row["hasSubfolders"], entries: entries,
                         listedAt: Date(timeIntervalSince1970: TimeInterval(row["listedAt"] as Int)))
        }
    }
}
