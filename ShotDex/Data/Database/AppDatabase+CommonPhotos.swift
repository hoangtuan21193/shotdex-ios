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

    /// FS-19.08 §6b: undo. An undo is a run of its own (`undoOf` names the
    /// run it takes back), so it pauses, resumes and shows in Activity like
    /// any run. A photo records the sidecar this run put in the destination,
    /// since only that one may go on undo; and a Move records which history
    /// row it moved from which copy, so undo puts each back where it was.
    static func registerCommonPhotosUndo(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v47-commonPhotosUndo") { db in
            try db.alter(table: "common_photo_runs") { t in
                // The run this one undoes; its undo runs go with it.
                t.add(column: "undoOf", .text).references("common_photo_runs", onDelete: .cascade)
            }
            try db.alter(table: "common_photo_items") { t in
                // The `.xmp` this run wrote beside the photo, recorded before
                // the write, and its SHA-256.
                t.add(column: "sidecarPlaced", .text)
                t.add(column: "sidecarSHA256", .text)
                // The destination held these bytes before the run: that
                // file is not the run's, and undo leaves it.
                t.add(column: "destinationWasThere", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "common_photo_history_moves") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("runId", .text).notNull()
                    .references("common_photo_runs", onDelete: .cascade)
                // server_shortcuts · server_uploads · server_downloads · backup_ledger
                t.column("historyTable", .text).notNull()
                // The history row's id, as text (shortcut ids are text).
                t.column("rowId", .text).notNull()
                // The copy whose removal moved the row.
                t.column("sourcePath", .text).notNull()
                t.column("pathBefore", .text).notNull()
                t.column("pathAfter", .text).notNull()
            }
            try db.create(index: "common_photo_history_moves_run", on: "common_photo_history_moves", columns: ["runId"])
        }
    }

    /// FS-19.08 §6c: what a common-photos scan read of each file — its
    /// SHA-256 and capture key — so the next scan of the same files reads
    /// nothing again. Any folder, source or not; one row per path on a
    /// connection, valid while size and write time stay the same.
    static func registerCommonPhotosScanRecords(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v52-commonPhotosScanRecords") { db in
            try db.create(table: "common_photo_scan_records") { t in
                t.column("connectionId", .text).notNull()
                // The exact path on the server: two names that differ only
                // in case are two files on WebDAV and SFTP.
                t.column("path", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("modifiedAt", .integer).notNull()
                t.column("sha256", .text)
                t.column("captureKey", .text)
                t.column("readAt", .integer).notNull()
                t.primaryKey(["connectionId", "path"])
            }
        }
    }

    /// FS-19.08 §6c: the sets the helper gathers on its own (Keep gathering)
    /// — one row per set, its action, whether it is on, when it last
    /// checked, and why it waits or stopped.
    static func registerCommonPhotosWatches(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v53-commonPhotosWatches") { db in
            try db.create(table: "common_photo_watches") { t in
                t.primaryKey("id", .text)
                // `CommonPhotosIncremental.setKey`: one row per set.
                t.column("setKey", .text).notNull().unique()
                t.column("connectionId", .text).notNull()
                t.column("folders", .text).notNull()
                t.column("destination", .text).notNull()
                t.column("action", .text).notNull()
                t.column("isOn", .boolean).notNull()
                t.column("checkedAt", .integer)
                // What the last pass waited for (`OnServerSchedule.Wait`
                // as a code), or why gathering stopped.
                t.column("waiting", .text)
                t.column("stoppedBecause", .text)
                t.column("createdAt", .integer).notNull()
            }
        }
    }

    /// FS-19.08 §6c: a run Keep gathering made belongs to its set and its
    /// day — every pass of a day adds its photos to that one run.
    static func registerCommonPhotosDayRuns(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v54-commonPhotosDayRuns") { db in
            try db.alter(table: "common_photo_runs") { t in
                t.add(column: "watchId", .text)
                // `yyyy-MM-dd`, the Mac's time zone when the pass started.
                t.add(column: "day", .text)
            }
            try db.create(index: "common_photo_runs_day", on: "common_photo_runs", columns: ["watchId", "day"])
        }
    }

    /// FS-19.08 §6c: the set's run the server cut off mid-way — the next
    /// pass carries it on. Not a run the user paused: that one waits for
    /// the user.
    static func registerCommonPhotosWatchResume(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v55-commonPhotosWatchResume") { db in
            try db.alter(table: "common_photo_watches") { t in
                t.add(column: "resumeRunId", .text)
            }
        }
    }
}
