import Foundation
import GRDB

extension AppDatabase {
    /// FS-19.07: one row per original file of a copy — a Photos asset's
    /// photo, RAW, Live Photo video, video and edit render; a server copy's
    /// file and its paired twin — with the whole-file SHA-256 once known.
    /// `content_hashes` keeps one hash per copy for identity; whether a photo
    /// is on a server needs every file, so it reads this table instead.
    ///
    /// A scan result, but hours of downloads to redo: it is not cleared by
    /// Clear Local Metadata Index, and has no foreign key that a `REPLACE`
    /// of a copy could cascade through.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerOnServerCheck(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v44-copyFiles") { db in
            try db.create(table: "copy_files") { t in
                t.column("copyId", .text).notNull()
                // Photos: the resource key Backup's ledger uses (`type:name`);
                // server: `primary` or `companion`.
                t.column("fileKey", .text).notNull()
                // CopyFile.Role
                t.column("role", .text).notNull()
                t.column("size", .integer)
                // Server: the listing's write time — a new date is a new file.
                t.column("modifiedAt", .integer)
                // Photos: Backup's source stamp, so the ledger's hash is reused
                // only for the same bytes.
                t.column("stamp", .text)
                t.column("sha256", .text)
                // backup · hashed
                t.column("origin", .text)
                t.column("hashedAt", .integer)
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
                t.column("triedAt", .integer)
                t.primaryKey(["copyId", "fileKey"])
            }
            try db.execute(sql: "CREATE INDEX copy_files_sha ON copy_files(sha256) WHERE sha256 IS NOT NULL")
            try db.create(index: "copy_files_size", on: "copy_files", columns: ["size"])

            // When a Photos asset's files were last read from PhotoKit: its
            // modification date then. An edit changes it and the files are
            // read again.
            try db.create(table: "copy_file_listings") { t in
                t.primaryKey("copyId", .text)
                t.column("stamp", .integer)
                t.column("listedAt", .integer).notNull()
            }
        }
    }
}
