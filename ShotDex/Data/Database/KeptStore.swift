import Foundation
import GRDB

/// Reads and writes what is kept on this device. Every state change goes
/// through `setState`, so the screens and the runner agree on one story.
struct KeptStore: Sendable {
    let database: AppDatabase

    // MARK: Items

    func items() throws -> [KeptItem] {
        try database.reader.read { db in
            try KeptItem.order(Column("addedAt").desc, Column("id")).fetchAll(db)
        }
    }

    func item(id: String) throws -> KeptItem? {
        try database.reader.read { db in try KeptItem.fetchOne(db, key: id) }
    }

    /// Ids of every kept item, whatever its state — the set the grid glyph and
    /// the Keep menu ask about.
    func keptIds() throws -> Set<String> {
        try database.reader.read { db in
            Set(try String.fetchAll(db, sql: "SELECT id FROM kept_items"))
        }
    }

    /// Adds what is not kept yet, queued. An item already kept is left as it
    /// is: keeping it again must not throw away a finished file.
    @discardableResult
    func add(_ items: [KeptItem]) throws -> [KeptItem] {
        try database.writer.write { db in
            var added: [KeptItem] = []
            for item in items where try KeptItem.fetchOne(db, key: item.id) == nil {
                try item.insert(db)
                added.append(item)
            }
            return added
        }
    }

    func setState(id: String, _ state: KeptItem.State, error: String? = nil) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE kept_items SET state = ?, error = ? WHERE id = ?",
                           arguments: [state.rawValue, error, id])
        }
    }

    func finish(id: String, fileName: String, byteCount: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE kept_items SET state = ?, error = NULL, fileName = ?, byteCount = ? WHERE id = ?",
                           arguments: [KeptItem.State.onDevice.rawValue, fileName, byteCount, id])
        }
    }

    func remove(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            _ = try KeptItem.deleteAll(db, keys: ids)
        }
    }

    /// Bytes of every finished kept file.
    func totalBytes() throws -> Int64 {
        try database.reader.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byteCount), 0) FROM kept_items") ?? 0
        }
    }

    // MARK: Albums

    func albums() throws -> [KeptAlbum] {
        try database.reader.read { db in
            try KeptAlbum.order(Column("addedAt").desc).fetchAll(db)
        }
    }

    func album(id: String) throws -> KeptAlbum? {
        try database.reader.read { db in try KeptAlbum.fetchOne(db, key: id) }
    }

    func save(_ album: KeptAlbum) throws {
        try database.writer.write { db in try album.save(db) }
    }

    /// The album and the items it brought in. Items kept on their own, or by
    /// another album first, stay.
    func removeAlbum(id: String) throws -> [String] {
        try database.writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM kept_items WHERE albumId = ?", arguments: [id])
            _ = try KeptAlbum.deleteOne(db, key: id)
            _ = try KeptItem.deleteAll(db, keys: ids)
            return ids
        }
    }

    /// Per album: how many items it brought in, and how many are here.
    func albumProgress() throws -> [String: (onDevice: Int, total: Int)] {
        try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT albumId, COUNT(*) AS total, SUM(state = 'onDevice') AS done
                FROM kept_items WHERE albumId IS NOT NULL GROUP BY albumId
                """)
            var result: [String: (onDevice: Int, total: Int)] = [:]
            for row in rows {
                result[row["albumId"]] = (row["done"] ?? 0, row["total"])
            }
            return result
        }
    }

    // MARK: Estimate

    /// What keeping these photos would take, from the index. Ids the index
    /// has no row for (a photo still being read) count as photos of unknown
    /// size.
    func estimate(ids: [String]) throws -> KeepEstimate {
        guard !ids.isEmpty else { return KeepEstimate() }
        let json = String(data: try JSONEncoder().encode(ids), encoding: .utf8) ?? "[]"
        return try database.reader.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT SUM(mediaType = 2) AS videos, COUNT(*) AS indexed,
                       COALESCE(SUM(CASE WHEN mediaType = 2 THEN 0 ELSE fileSize END), 0) AS photoBytes,
                       COALESCE(SUM(CASE WHEN mediaType = 2 THEN fileSize ELSE 0 END), 0) AS videoBytes
                FROM photo_metadata WHERE assetId IN (SELECT value FROM json_each(?))
                """, arguments: [json])
            let videos: Int = row?["videos"] ?? 0
            let indexed: Int = row?["indexed"] ?? 0
            return KeepEstimate(
                photos: ids.count - videos,
                videos: videos,
                photoBytes: row?["photoBytes"] ?? 0,
                videoBytes: row?["videoBytes"] ?? 0,
                unindexed: ids.count - indexed
            )
        }
    }
}

/// The two sizes the Keep sheet shows. A viewing copy is drawn, so its size
/// is a rule of thumb: about 1.2 MB a photo at 2732 px, and a 1080p video
/// about 40 % of a phone's 4K original.
struct KeepEstimate: Sendable, Equatable {
    var photos = 0
    var videos = 0
    var photoBytes: Int64 = 0
    var videoBytes: Int64 = 0
    var unindexed = 0

    static let viewingPhotoBytes: Int64 = 1_200_000

    var originalBytes: Int64 { photoBytes + videoBytes }

    var viewingCopyBytes: Int64 {
        Int64(photos) * Self.viewingPhotoBytes + videoBytes * 2 / 5
    }

    func bytes(for quality: KeepQuality) -> Int64 {
        quality == .original ? originalBytes : viewingCopyBytes
    }
}
