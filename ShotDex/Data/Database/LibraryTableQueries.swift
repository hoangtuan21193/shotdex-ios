import Foundation
import GRDB

/// The columns the Mac's list view (FS-18.02 §3) shows beyond a grid row —
/// camera, lens, current rating, first source — and the marks on a grid
/// tile (favorite, stars, flag), read for the whole library
/// in one query off the main actor, never per cell.
struct LibraryTableQueries: Sendable {
    let database: AppDatabase

    struct Details: Equatable, Sendable {
        var camera: String?
        var lens: String?
        /// The current stars (FS-01.12, K4): a pending change, then a file
        /// photo's own, then Photos'.
        var rating: Int
        var sourceName: String?
        var sourceKind: String?
        /// The grid's marks on a tile (board `MAC_LibrarySelected`).
        var isFavorite = false
        var flag: PhotoFlag?
    }

    func details() async throws -> [String: Details] {
        try await database.reader.read { db in try Self.read(db, ids: nil) }
    }

    /// Just these photos — after a star, flag or favorite changed — so the
    /// whole library is not read again for one click.
    func details(ids: [String]) async throws -> [String: Details] {
        var details: [String: Details] = [:]
        for start in stride(from: 0, to: ids.count, by: 900) {
            try Task.checkCancellation()
            let chunk = Array(ids[start..<min(ids.count, start + 900)])
            details.merge(try await database.reader.read { db in try Self.read(db, ids: chunk) }) { $1 }
        }
        return details
    }

    private static func read(_ db: Database, ids: [String]?) throws -> [String: Details] {
        let only = ids.map { "IN (\(databaseQuestionMarks(count: $0.count)))" }
        // Each photo's first-added connected copy, found once (not once
        // per column), and the rows read as a cursor into the dictionary.
        let rows = try Row.fetchCursor(db, sql: """
            WITH firstCopy AS (
                SELECT c.photoId, s.name, s.kind,
                       ROW_NUMBER() OVER (PARTITION BY c.photoId ORDER BY s.createdAt, s.id) AS place
                FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.missingSince IS NULL\(only.map { " AND c.photoId \($0)" } ?? "")
            )
            SELECT m.assetId,
                   COALESCE(m.normalizedCameraModel, m.cameraModel),
                   COALESCE(m.normalizedLensModel, m.lensModel),
                   COALESCE(p.rating, u.rating, m.rating, 0),
                   f.name, f.kind, (m.isFavorite = 1 OR u.isFavorite = 1), g.flag
            FROM photo_metadata m
            LEFT JOIN pending_photo_rating p ON p.assetId = m.assetId
            LEFT JOIN photo_user_marks u ON u.photoId = m.assetId
            LEFT JOIN photo_flag g ON g.assetId = m.assetId
            LEFT JOIN firstCopy f ON f.photoId = m.assetId AND f.place = 1
            \(only.map { "WHERE m.assetId \($0)" } ?? "")
            """, arguments: ids.map { StatementArguments($0 + $0) } ?? StatementArguments())
        var details: [String: Details] = [:]
        while let row = try rows.next() {
            details[row[0]] = Details(camera: row[1], lens: row[2], rating: row[3] ?? 0,
                                      sourceName: row[4], sourceKind: row[5], isFavorite: row[6] ?? false,
                                      flag: (row[7] as String?).flatMap(PhotoFlag.init(rawValue:)))
        }
        return details
    }
}
