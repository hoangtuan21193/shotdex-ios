import Foundation
import GRDB

extension AppDatabase {
    /// Keep in Photos (FS-06.12 §5): which smart album keeps which real album
    /// in Photos. A choice the user made, so a table of its own (BD-02), with
    /// no foreign key — deleting a smart album deletes its row in the same
    /// transaction (`SmartAlbumStore.delete`).
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerPhotosAlbumSync(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v61-smartAlbumPhotosAlbum") { db in
            try db.create(table: "smart_album_photos_album") { t in
                t.primaryKey("smartAlbumId", .text)
                // The album ShotDex made in Photos; kept while the switch is
                // off so turning it back on reuses it (FS-06.12 §4).
                t.column("collectionLocalId", .text)
                t.column("isEnabled", .boolean).notNull()
                t.column("lastSyncedAt", .integer)
                t.column("assetCount", .integer).notNull().defaults(to: 0)
                // `PhotosAlbumSyncState` raw value: what the line under the
                // smart album says (§3).
                t.column("state", .text).notNull().defaults(to: "idle")
            }
        }
    }
}
