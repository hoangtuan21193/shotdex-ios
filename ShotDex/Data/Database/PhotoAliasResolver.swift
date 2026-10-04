import Foundation
import GRDB

/// Finds a photo by any id it ever had (FS-19.05 §4). A widget, Recents or
/// an upload record may hold the id of a photo that was later merged into
/// another; the alias table leads to the survivor.
///
/// A merge never deletes a Photos asset, so a PhotoKit id stays fetchable
/// either way; what changes is which photo — and so which stars, keywords
/// and copies — it belongs to.
struct PhotoAliasResolver: Sendable {
    let database: AppDatabase
    /// Aliases form chains when a survivor is merged again; a loop is
    /// impossible by construction, the cap is belt and braces.
    static let maxHops = 16

    /// The surviving photo id for `id` (itself when it was never merged).
    func photoId(for id: String) throws -> String {
        try database.reader.read { db in try Self.photoId(db, for: id) }
    }

    /// A PhotoKit id that shows photo `id` today: its own when it is still a
    /// Photos copy, else the survivor's Photos copy; nil for a photo that
    /// only exists as files.
    func libraryAssetId(for id: String) throws -> String? {
        try database.reader.read { db in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM photo_copies WHERE photoKitId = ?)", arguments: [id]) == true {
                return id
            }
            let survivor = try Self.photoId(db, for: id)
            return try String.fetchOne(db, sql: """
                SELECT photoKitId FROM photo_copies WHERE photoId = ? AND kind = 'photos' ORDER BY id LIMIT 1
                """, arguments: [survivor])
        }
    }

    static func photoId(_ db: Database, for id: String) throws -> String {
        var current = id
        for _ in 0..<maxHops {
            guard let next = try String.fetchOne(db, sql: "SELECT winnerId FROM photo_aliases WHERE loserId = ?", arguments: [current])
            else { return current }
            current = next
        }
        return current
    }
}
