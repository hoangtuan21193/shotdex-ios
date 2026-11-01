import Foundation
import GRDB

extension AppDatabase {
    /// Keep on This iPhone (intent 2026-10-19-keep-offline): what the user
    /// chose to have on the device without a connection. User data, so tables
    /// of their own with no foreign key that could cascade it away — a photo
    /// leaving the library leaves its row, and the kept file stays until the
    /// user removes it.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerKept(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v43-keptItems") { db in
            try db.create(table: "kept_items") { t in
                t.primaryKey("id", .text)
                t.column("isVideo", .boolean).notNull()
                t.column("quality", .text).notNull()
                t.column("state", .text).notNull()
                t.column("fileName", .text)
                t.column("byteCount", .integer).notNull().defaults(to: 0)
                t.column("albumId", .text)
                t.column("error", .text)
                t.column("addedAt", .integer).notNull()
            }
            try db.create(index: "kept_items_album", on: "kept_items", columns: ["albumId"])
            try db.create(table: "kept_albums") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("quality", .text).notNull()
                t.column("keepsNewPhotos", .boolean).notNull()
                t.column("addedAt", .integer).notNull()
            }
        }
    }
}
