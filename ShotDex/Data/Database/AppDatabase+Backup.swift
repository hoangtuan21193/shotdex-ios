import Foundation
import GRDB

extension AppDatabase {
    /// FS-22.03: backup jobs, where each stands, and the per-file ledger. All
    /// three are user data in their own tables, so Clear Local Metadata Index
    /// and a re-index leave them alone.
    ///
    /// A job goes with its connection (the delete asks first, FS-22.03 §1);
    /// state and ledger go with their job. The ledger has no link to
    /// `photo_metadata` — the indexer rewrites those rows.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerBackup(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v33-backup") { db in
            try db.create(table: "backup_jobs") { t in
                t.primaryKey("id", .text)
                t.column("sourceId", .text).notNull()
                t.column("connectionId", .text).notNull()
                    .references("file_servers", onDelete: .cascade)
                t.column("folder", .text).notNull()
                // JSON, decoded leniently (BackupSettings).
                t.column("settings", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .integer).notNull()
                t.uniqueKey(["sourceId", "connectionId", "folder"])
            }

            try db.create(table: "backup_job_state") { t in
                t.primaryKey("jobId", .text)
                    .references("backup_jobs", onDelete: .cascade)
                t.column("changeToken", .blob)
                t.column("lastCheckedAt", .integer)
                t.column("status", .text).notNull()
                t.column("statusDone", .integer)
                t.column("statusTotal", .integer)
                t.column("hasFinishedFirstRun", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "backup_ledger") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("jobId", .text).notNull()
                    .references("backup_jobs", onDelete: .cascade)
                t.column("itemKey", .text).notNull()
                t.column("resourceKey", .text).notNull()
                t.column("sourceStamp", .text).notNull()
                t.column("remotePath", .text)
                t.column("byteCount", .integer)
                t.column("sha256", .text)
                // uploaded · found · failed
                t.column("outcome", .text).notNull()
                t.column("attempts", .integer).notNull()
                t.column("lastError", .text)
                t.column("recordedAt", .integer).notNull()
                t.uniqueKey(["jobId", "itemKey", "resourceKey", "sourceStamp"])
            }
            try db.create(index: "backup_ledger_job_outcome", on: "backup_ledger", columns: ["jobId", "outcome"])
        }

        // FS-22.01 §2: an FS-19 source backs up one folder inside it.
        migrator.registerMigration("v34-backupSourceFolder") { db in
            try db.alter(table: "backup_jobs") { t in
                t.add(column: "sourceFolder", .text).notNull().defaults(to: "")
            }
        }
    }
}
