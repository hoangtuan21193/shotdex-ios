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

    /// FS-19.07 §12: hashes another device worked out — over iCloud or from
    /// a ledger on the NAS. `copy_files.sharedFrom` names the device, so a
    /// random check that finds one wrong drops that device's hashes and
    /// nothing else. A ledger segment read is remembered by size, as Backup
    /// does; a device caught wrong is remembered with when.
    static func registerSharedHashes(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v48-sharedHashes") { db in
            try db.alter(table: "copy_files") { t in
                // The device whose hash this is, when it is not this one's.
                t.add(column: "sharedFrom", .text)
            }
            // A distrust drops one device's hashes without a full scan.
            try db.execute(sql: "CREATE INDEX copy_files_sharedFrom ON copy_files(sharedFrom) WHERE sharedFrom IS NOT NULL")
            try db.create(table: "hash_index_segments") { t in
                t.column("sourceId", .text).notNull()
                t.column("segment", .text).notNull()
                // The size read, so a segment grown since is read again.
                t.column("size", .integer).notNull()
                t.primaryKey(["sourceId", "segment"])
            }
            // Learned, not derived: Clear Local Metadata Index keeps it, or a
            // device caught wrong would be believed again.
            try db.create(table: "distrusted_hash_devices") { t in
                t.primaryKey("device", .text)
                // When a hash from it was found wrong: what it sent up to
                // then is never used again.
                t.column("since", .integer).notNull()
            }
        }
    }

    /// FS-19.07 §12.2: the lines of the NAS ledgers this device read, kept
    /// so a file listed later still finds its line, and this device's own
    /// lines, so what it already wrote is not written again — as Backup
    /// keeps its shared index (FS-22.05 §2).
    static func registerHashIndexLines(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v49-hashIndexLines") { db in
            try db.create(table: "hash_index_lines") { t in
                t.column("sourceId", .text).notNull()
                // `FolderSourceIndexer.pathKey` of the path under the source's root.
                t.column("pathKey", .text).notNull()
                t.column("device", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("modifiedAt", .integer)
                t.column("sha256", .text).notNull()
                t.column("recordedAt", .integer).notNull()
                t.primaryKey(["sourceId", "pathKey", "device"])
            }
        }
    }

    /// FS-19.07 §12.3: hashes that travel through iCloud — this device's
    /// own, queued for upload (`origin = local`), and other devices', as
    /// pulled (`origin = cloud`). One row per device and file, named as its
    /// CloudKit record.
    static func registerSharedHashCache(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v50-sharedHashCache") { db in
            try db.create(table: "shared_photo_hashes") { t in
                t.primaryKey("recordName", .text)
                t.column("cloudId", .text).notNull()
                // `type:name`, as Backup's ledger keys a resource.
                t.column("fileKey", .text).notNull()
                // The asset's modification date when hashed, seconds.
                t.column("assetModified", .integer)
                t.column("size", .integer)
                t.column("sha256", .text).notNull()
                t.column("device", .text).notNull()
                t.column("hashedAt", .integer).notNull()
                t.column("origin", .text).notNull()
            }
            try db.create(index: "shared_photo_hashes_cloud", on: "shared_photo_hashes", columns: ["cloudId"])
            try db.create(table: "shared_server_hashes") { t in
                t.primaryKey("recordName", .text)
                // `ServerIdentity.key`: the same files whatever the connection's name.
                t.column("serverKey", .text).notNull()
                // `FolderSourceIndexer.pathKey` of the path on the server.
                t.column("pathKey", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("modifiedAt", .integer)
                t.column("sha256", .text).notNull()
                t.column("device", .text).notNull()
                t.column("hashedAt", .integer).notNull()
                t.column("origin", .text).notNull()
            }
            try db.create(index: "shared_server_hashes_path", on: "shared_server_hashes", columns: ["serverKey", "pathKey"])
            // When this device's own hash was queued for the others; NULL =
            // not yet, and every new hash of the file clears it.
            try db.alter(table: "copy_files") { t in t.add(column: "sharedAt", .integer) }
        }
    }

    /// FS-19.07 §12.4: the names other devices sent with their hashes, so a
    /// mismatch can say whose hashes were wrong ("Tuấn's MacBook").
    static func registerHashDeviceNames(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v51-hashDeviceNames") { db in
            try db.create(table: "hash_device_names") { t in
                t.primaryKey("device", .text)
                t.column("name", .text).notNull()
            }
        }
    }
}

