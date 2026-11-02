import Foundation
import GRDB

extension AppDatabase {
    /// FS-19.08 §8: a common-photos run and its photos, so a run stopped by
    /// a lost connection or a quit resumes where it was (AC-128) and the log
    /// window can show every file after the fact.
    ///
    /// Derived, not typed by the user, but never cleared with the metadata
    /// index: an unfinished Move must not forget which sources it still has
    /// to remove.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerCommonPhotos(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v46-commonPhotos") { db in
            try db.create(table: "common_photo_runs") { t in
                t.primaryKey("id", .text)
                // FS-15 connection; the run stays if the connection goes.
                t.column("connectionId", .text).notNull()
                // JSON array of server folders, in the order chosen.
                t.column("folders", .text).notNull()
                t.column("destination", .text).notNull()
                // CommonPhotosRun.Action: copy · move
                t.column("action", .text).notNull()
                // CommonPhotosRun.State
                t.column("state", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                // Server path of the CSV written at the end.
                t.column("csvPath", .text)
            }
            try db.create(table: "common_photo_items") { t in
                t.column("runId", .text).notNull()
                    .references("common_photo_runs", onDelete: .cascade)
                // Order the photos run in.
                t.column("position", .integer).notNull()
                t.column("sha256", .text).notNull()
                t.column("size", .integer).notNull()
                // JSON array of CommonPhotosItem.Source: every source path
                // holding these bytes, its size and write time at the scan,
                // its sidecar, and whether this run removed it.
                t.column("sources", .text).notNull()
                // CommonPhotosItem.Status
                t.column("status", .text).notNull()
                // The final path in the destination, written before the step
                // that creates it, so a resume knows what to look for.
                t.column("destinationPath", .text)
                // Copy: the part file being written, written before the upload.
                t.column("partPath", .text)
                // Move: the source being renamed into the destination, written
                // before the rename.
                t.column("movedFrom", .text)
                t.column("reason", .text)
                t.column("updatedAt", .integer).notNull()
                t.primaryKey(["runId", "position"])
            }
        }
    }
}
