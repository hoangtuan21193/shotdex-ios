import Foundation
import GRDB

/// Whether a Photos item is on a folder of a server source (FS-19.07 §3, §7),
/// as SQL over `photo_metadata`: read straight from the per-file hashes in
/// `copy_files`, so it holds whether or not the photo was merged with its
/// server copy (AC-75).
///
/// A Photos item is **present** on folder F of source S when its files were
/// listed since it last changed, and every one of them — photo, RAW, Live
/// Photo video, video, and the edit renders of an edited item — has a file
/// with the same SHA-256 somewhere under F. It is **checked and missing**
/// when it is not present and no file of it can still match: no hash yet and
/// no file of its size under F, or a hash and no unhashed file of its size
/// under F. Everything else is still being checked and is in neither.
enum OnServerPresenceSQL {
    /// The files a photo needs on the server. Audio and adjustment data are
    /// not files a person would miss.
    static let requiredRoles: [CopyFile.Role] = [
        .photo, .raw, .video, .pairedVideo, .editedPhoto, .editedVideo, .editedPairedVideo,
    ]

    /// `is` — present on the folder.
    static func present(sourceId: String, folder: String?) -> (sql: String, values: [DatabaseValueConvertible]) {
        let (match, matchValues) = matched(file: "f", sourceId: sourceId, folder: folder)
        return ("""
            assetId IN (SELECT pc.photoId FROM photo_copies pc \(listedNow)
                WHERE pc.kind = 'photos'
                  AND EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles))
                  AND NOT EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles)
                                  AND NOT \(match)))
            """, matchValues)
    }

    /// `is not` — checked, and at least one file is not on the folder.
    static func missing(sourceId: String, folder: String?) -> (sql: String, values: [DatabaseValueConvertible]) {
        let (open, openValues) = unsettled(file: "f", sourceId: sourceId, folder: folder)
        let (match, matchValues) = matched(file: "f", sourceId: sourceId, folder: folder)
        return ("""
            assetId IN (SELECT pc.photoId FROM photo_copies pc \(listedNow)
                WHERE pc.kind = 'photos'
                  AND NOT EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles) AND \(open))
                  AND (NOT EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles))
                       OR EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles)
                                  AND NOT \(match))))
            """, openValues + matchValues)
    }

    /// The file `f` has a file of the same bytes under the folder.
    static func matched(file f: String, sourceId: String, folder: String?) -> (sql: String, values: [DatabaseValueConvertible]) {
        let (scope, values) = serverScope(sourceId: sourceId, folder: folder)
        return ("""
            (\(f).sha256 IS NOT NULL AND EXISTS (SELECT 1 FROM copy_files s JOIN photo_copies sc ON sc.id = s.copyId
                WHERE s.sha256 = \(f).sha256 AND \(scope)))
            """, values)
    }

    /// The file `f` could still match: not matched, and a file of its size
    /// under the folder with a hash still to come on one side.
    static func unsettled(file f: String, sourceId: String, folder: String?) -> (sql: String, values: [DatabaseValueConvertible]) {
        let (match, matchValues) = matched(file: f, sourceId: sourceId, folder: folder)
        let (scope, scopeValues) = serverScope(sourceId: sourceId, folder: folder)
        return ("""
            (NOT \(match) AND EXISTS (SELECT 1 FROM copy_files s JOIN photo_copies sc ON sc.id = s.copyId
                WHERE \(scope) AND (\(f).size IS NULL OR s.size = \(f).size)
                  AND (\(f).sha256 IS NULL OR s.sha256 IS NULL)))
            """, matchValues + scopeValues)
    }

    /// A server copy `sc` that is there now, on the source, under the folder
    /// (any depth). An empty folder is the whole source.
    static func serverScope(sourceId: String, folder: String?) -> (sql: String, values: [DatabaseValueConvertible]) {
        let base = "sc.sourceId = ? AND sc.kind = 'server' AND sc.missingSince IS NULL"
        guard let prefix = folderPrefix(folder) else { return (base, [sourceId]) }
        return (base + " AND substr(sc.relativePathKey, 1, ?) = ?", [sourceId, prefix.unicodeScalars.count, prefix])
    }

    /// `shared/2025/` for `Shared/2025` — the path key every copy under the
    /// folder starts with. Nil for the whole source.
    static func folderPrefix(_ folder: String?) -> String? {
        let trimmed = (folder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty else { return nil }
        return FolderSourceIndexer.pathKey(trimmed) + "/"
    }

    /// Joins a Photos copy `pc` to a listing made since the asset last
    /// changed: an edit made after the listing may have added a render the
    /// server does not have.
    private static let listedNow = """
        JOIN copy_file_listings l ON l.copyId = pc.id
        JOIN photo_metadata pm ON pm.assetId = pc.photoKitId AND l.stamp IS pm.modificationDate
        """

    private static let roles = "(" + requiredRoles.map { "'\($0.rawValue)'" }.joined(separator: ", ") + ")"
}
