import Foundation
import GRDB

extension AppDatabase {
    /// Get Info's Creator and Copyright (FS-18.02 §8): typed by the user, so
    /// in `photo_user_marks` with the other user fields, each with the time it
    /// changed — a sidecar's `dc:creator` / `dc:rights` and a change made in
    /// ShotDex settle by time (FS-19.02 §6). File photos send them on to the
    /// sidecar; a Photos photo keeps them in ShotDex (Photos has no such field).
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerCreatorRights(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v62-creatorRights") { db in
            try db.alter(table: "photo_user_marks") { t in
                t.add(column: "creator", .text)
                t.add(column: "creatorAt", .integer)
                t.add(column: "copyright", .text)
                t.add(column: "copyrightAt", .integer)
            }
        }
    }
}
