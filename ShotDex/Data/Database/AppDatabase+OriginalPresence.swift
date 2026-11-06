import Foundation
import GRDB

extension AppDatabase {
    /// Whether each Photos item has every original on this device
    /// (FS-06.10 §5). The result of a slow offline check, so a table of its
    /// own (BD-02): the indexer rewrites whole `photo_metadata` rows and would
    /// otherwise throw every answer away. Keyed by the PhotoKit identifier —
    /// what the check reads — with no foreign key; a row for a photo that has
    /// left the library matches nothing, because the rule joins through
    /// `photo_copies`.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerOriginalPresence(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v58-originalPresence") { db in
            try db.create(table: "original_presence") { t in
                t.primaryKey("photoKitId", .text)
                // `OriginalPresence` raw value; NULL while not checked — never
                // checked, marked for a recheck, or the check could not tell.
                t.column("state", .text)
                // When the item was last looked at; NULL once marked for a
                // recheck. A pass re-reads every row older than its start.
                t.column("checkedAt", .integer)
            }
            // A pass asks for the rows marked for a recheck and the oldest.
            try db.create(index: "original_presence_checkedAt", on: "original_presence", columns: ["checkedAt"])
            // One row: when the current pass started and when the last one
            // finished — what lets a pass carry on after the app was killed,
            // and what the line under a smart album reads (§3).
            try db.create(table: "original_presence_pass") { t in
                t.primaryKey("id", .integer).check { $0 == 1 }
                t.column("startedAt", .integer).notNull()
                t.column("finishedAt", .integer)
            }
        }
    }
}
