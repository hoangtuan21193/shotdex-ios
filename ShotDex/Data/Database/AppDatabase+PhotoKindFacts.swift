import Foundation
import GRDB

extension AppDatabase {
    /// *Photo is edited* / *Photo is burst* (FS-06.08 §3c): two PhotoKit facts
    /// the indexer writes alongside `mediaSubtypes`. NULL = not read yet; the
    /// launch backfill fills rows from before the columns.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerPhotoKindFacts(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v64-photoKindFacts") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "hasAdjustments", .boolean)
                t.add(column: "isBurst", .boolean)
            }
        }
    }
}
