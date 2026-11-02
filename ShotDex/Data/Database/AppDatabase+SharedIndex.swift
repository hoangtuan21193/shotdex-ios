import Foundation
import GRDB

extension AppDatabase {
    /// Index results shared between the devices of one iCloud account
    /// (intent 2026-11-02-icloud-shared-index).
    ///
    /// `shared_exif` holds one file read per photo, keyed by the photo's
    /// iCloud identifier — the one id every device agrees on — with the
    /// modification date it was read at and the raw EXIF as JSON. Rows read
    /// here and rows pulled from iCloud live side by side; the pipeline reuses
    /// either. Its own table because `photo_metadata` is rewritten whole by the
    /// indexer.
    ///
    /// `cloud_outbox` lists what is waiting to go up: a `PhotoExif` row by
    /// iCloud identifier, a `PlaceCell` row by cell key. Pushing drains it.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerSharedIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v45-sharedIndex") { db in
            try db.create(table: "shared_exif") { t in
                t.primaryKey("cloudIdentifier", .text)
                t.column("modificationDate", .integer)
                t.column("payload", .blob).notNull()
                // local · cloud
                t.column("origin", .text).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(table: "cloud_outbox") { t in
                t.column("recordType", .text).notNull()
                t.column("recordName", .text).notNull()
                t.column("queuedAt", .integer).notNull()
                t.primaryKey(["recordType", "recordName"])
            }
        }
    }
}
