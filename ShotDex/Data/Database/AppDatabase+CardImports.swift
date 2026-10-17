import Foundation
import GRDB

extension AppDatabase {
    /// FS-20 §9: what was imported from which memory card. User history the
    /// indexer can never read back, so a table of its own (BD-02 §1), no
    /// foreign key that could cascade it away: a source removed or a photo
    /// deleted leaves the row, and the import screen reads that as "the copy
    /// is gone, import it again" (AC-21). One row per file verified.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerCardImports(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v42-cardImports") { db in
            try db.create(table: "card_imports") { t in
                t.autoIncrementedPrimaryKey("id")
                // The card's volume UUID, or the camera's device id.
                t.column("cardId", .text).notNull()
                t.column("cardName", .text).notNull()
                // Relative to the card's root: DCIM/100CANON/IMG_5884.CR3.
                t.column("originalPath", .text).notNull()
                t.column("originalName", .text).notNull()
                t.column("byteCount", .integer).notNull()
                // The file's date on the card, in seconds (plan K6).
                t.column("capturedAt", .integer).notNull()
                // SHA-256 of the whole file, as copied and read back.
                t.column("sha256", .text).notNull()
                t.column("sourceId", .text).notNull()
                // Relative to the destination source's folder.
                t.column("destinationPath", .text).notNull()
                t.column("photoId", .text)
                // Empty until the backup copy is verified too (plan K7).
                t.column("backupPath", .text)
                t.column("importedAt", .integer).notNull()
            }
            try db.create(index: "card_imports_key", on: "card_imports", columns: ["originalName", "byteCount", "capturedAt"])
            try db.create(index: "card_imports_card", on: "card_imports", columns: ["cardId", "originalPath"])
        }
    }
}
