import Foundation
import GRDB
import Photos

extension LibraryQueries {
    /// What the index has read, split into photos and videos, with the bytes
    /// it knows (Mac Settings › Sources › Index, FS-18.04 §3 AC-70). Only
    /// finished reads: a run writes a placeholder per asset first. Not the
    /// grid's items, which follow the sidebar's filter.
    func indexSummaryCounts() async throws -> IndexStatusLine.Counts {
        try await database.reader.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(mediaType = ?), 0) AS photos,
                       COALESCE(SUM(mediaType = ?), 0) AS videos,
                       COALESCE(SUM(fileSize), 0) AS bytes
                FROM photo_metadata
                WHERE exifStatus IN (?, ?)
                """, arguments: [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue,
                                 ExifStatus.indexed.rawValue, ExifStatus.noExif.rawValue])
            return IndexStatusLine.Counts(photos: row?["photos"] ?? 0, videos: row?["videos"] ?? 0, bytes: row?["bytes"] ?? 0)
        }
    }
}
