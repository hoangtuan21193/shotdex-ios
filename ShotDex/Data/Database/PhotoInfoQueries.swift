import Foundation
import GRDB

/// One photo's Get Info (board `MAC_GetInfoSingle`, FS-18.02 §8): its index
/// row, title and caption (a file photo's own, else Photos' mirrored
/// caption), place, keywords as spelled on it, and where its copies live —
/// one read off the main actor.
struct PhotoInfoQueries: Sendable {
    let database: AppDatabase

    struct ServerCopy: Equatable, Sendable {
        let serverName: String
        let path: String
    }

    struct Info: Equatable, Sendable {
        var metadata: PhotoMetadata?
        var title: String?
        var caption: String?
        var place: ResolvedPlace?
        /// One spelling per word, alphabetical.
        var keywords: [String] = []
        var isInPhotos = false
        /// The first file copy's name, for "Saved as you type to ‹name›.xmp".
        var fileName: String?
        var serverCopies: [ServerCopy] = []

        var hasFileCopy: Bool { fileName != nil }
    }

    func info(photoId: String) async throws -> Info {
        try await database.reader.read { db in
            var info = Info()
            info.metadata = try PhotoMetadata.fetchOne(db, key: photoId)
            let copies = try Row.fetchAll(db, sql: """
                SELECT c.kind, c.relativePath, s.name FROM photo_copies c LEFT JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.missingSince IS NULL ORDER BY s.createdAt, c.relativePath
                """, arguments: [photoId])
            for copy in copies {
                switch copy[0] as String? {
                case "photos": info.isInPhotos = true
                case "file":
                    if info.fileName == nil, let path: String = copy[1] { info.fileName = (path as NSString).lastPathComponent }
                case "server":
                    if let path: String = copy[1] { info.serverCopies.append(ServerCopy(serverName: copy[2] ?? "", path: path)) }
                default: break
                }
            }
            // No copy row at all (missing ones count — a drive unplugged is
            // still a file photo): a Photos asset the copy table has not caught up with.
            if copies.isEmpty, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE photoId = ?", arguments: [photoId]) == 0 {
                info.isInPhotos = true
            }
            let marks = try Row.fetchOne(db, sql: "SELECT title, caption FROM photo_user_marks WHERE photoId = ?", arguments: [photoId])
            info.title = marks?["title"]
            info.caption = marks?["caption"]
            if info.caption == nil {
                info.caption = try String.fetchOne(db, sql: "SELECT caption FROM photo_caption WHERE assetId = ?", arguments: [photoId])
            }
            info.keywords = try String.fetchAll(db, sql: """
                SELECT MIN(keyword) FROM (\(PhotoKeywordStore.everyKeywordSQL)) WHERE assetId = ? GROUP BY caseKey ORDER BY MIN(keyword) COLLATE NOCASE
                """, arguments: [photoId])
            if let row = try Row.fetchOne(db, sql: """
                SELECT placeName, placeSubLocality, placeLocality, placeAdminArea, placeCountry, placeCountryCode, placeAddress
                FROM photo_metadata WHERE assetId = ?
                """, arguments: [photoId]), row.containsNonNullValue {
                info.place = ResolvedPlace(name: row[0], subLocality: row[1], locality: row[2], adminArea: row[3],
                                           country: row[4], countryCode: row[5], address: row[6])
            }
            return info
        }
    }
}
