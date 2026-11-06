import Foundation
import GRDB

/// The columns the Mac's list view (FS-18.02 §3) shows beyond a grid row —
/// camera, lens, current rating, first source — read for the whole library
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
    }

    func details() async throws -> [String: Details] {
        try await database.reader.read { db in
            // Each photo's first-added connected copy, found once (not once
            // per column), and the rows read as a cursor into the dictionary.
            let rows = try Row.fetchCursor(db, sql: """
                WITH firstCopy AS (
                    SELECT c.photoId, s.name, s.kind,
                           ROW_NUMBER() OVER (PARTITION BY c.photoId ORDER BY s.createdAt, s.id) AS place
                    FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                    WHERE c.missingSince IS NULL
                )
                SELECT m.assetId,
                       COALESCE(m.normalizedCameraModel, m.cameraModel),
                       COALESCE(m.normalizedLensModel, m.lensModel),
                       COALESCE(p.rating, u.rating, m.rating, 0),
                       f.name, f.kind
                FROM photo_metadata m
                LEFT JOIN pending_photo_rating p ON p.assetId = m.assetId
                LEFT JOIN photo_user_marks u ON u.photoId = m.assetId AND u.rating IS NOT NULL
                LEFT JOIN firstCopy f ON f.photoId = m.assetId AND f.place = 1
                """)
            var details: [String: Details] = [:]
            while let row = try rows.next() {
                details[row[0]] = Details(camera: row[1], lens: row[2], rating: row[3] ?? 0,
                                          sourceName: row[4], sourceKind: row[5])
            }
            return details
        }
    }
}
