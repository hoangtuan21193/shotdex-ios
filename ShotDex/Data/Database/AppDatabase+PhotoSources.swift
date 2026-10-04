import Foundation
import GRDB

/// The source every Photos asset belongs to. A string, not a row id, so the
/// migration and every query can name it without a lookup.
enum PhotoLibrarySource {
    static let id = "photos-library"
}

extension AppDatabase {
    /// FS-19.05 §3: a photo is an id with copies in sources — a Photos asset,
    /// a file in a folder or on a drive, a file on a server. Everything the
    /// user typed hangs off the photo id in tables the indexer never rewrites
    /// (BD-02 §1); everything a scan found hangs off the copy.
    ///
    /// Photos assets keep their library id as the photo id (FS-19.05 §1), so
    /// not one satellite row, saved setting or widget payload is rewritten:
    /// this migration only creates tables and fills `photos` and
    /// `photo_copies` from every id any table already holds — an asset under
    /// `.limited` access that was flagged but never indexed included.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerPhotoSources(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v30-photoSources") { db in
            try db.create(table: "sources") { t in
                t.primaryKey("id", .text)
                // photos · folder · drive · server
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("bookmark", .blob)
                t.column("volumeId", .text)
                t.column("connectionId", .text)
                t.column("subfolder", .text)
                t.column("pairsRawAndJpeg", .boolean).notNull().defaults(to: true)
                // keepPhotos · hidePhotos (FS-19.01 §1, when a drive is unplugged)
                t.column("whenUnplugged", .text).notNull().defaults(to: "keepPhotos")
                t.column("status", .text)
                t.column("resumeCursor", .text)
                t.column("createdAt", .integer).notNull()
            }

            try db.create(table: "photos") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .integer).notNull()
                // Set when the last copy went (FS-19.05 §5); NULL while any copy is known.
                t.column("orphanedAt", .integer)
            }
            try db.execute(sql: "CREATE INDEX photos_orphanedAt ON photos(orphanedAt) WHERE orphanedAt IS NOT NULL")

            // No foreign keys: a scan updates copies in place, and a cascade
            // is one `REPLACE` away from taking user data with it.
            try db.create(table: "photo_copies") { t in
                t.primaryKey("id", .text)
                t.column("photoId", .text).notNull()
                t.column("sourceId", .text).notNull()
                // photos · file · server
                t.column("kind", .text).notNull()
                t.column("photoKitId", .text)
                t.column("relativePath", .text)
                // NFC, case folded: what makes two paths the same file.
                t.column("relativePathKey", .text)
                t.column("size", .integer)
                t.column("modifiedAt", .integer)
                t.column("pairedPath", .text)
                t.column("sidecarStamp", .text)
                t.column("isOnline", .boolean).notNull().defaults(to: true)
                t.column("isHidden", .boolean).notNull().defaults(to: false)
                t.column("lastSeenAt", .integer)
            }
            try db.execute(sql: "CREATE UNIQUE INDEX photo_copies_path ON photo_copies(sourceId, relativePathKey) WHERE relativePathKey IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX photo_copies_photoKit ON photo_copies(photoKitId) WHERE photoKitId IS NOT NULL")
            try db.create(index: "photo_copies_source_photo", on: "photo_copies", columns: ["sourceId", "photoId"])
            try db.create(index: "photo_copies_photo_online", on: "photo_copies", columns: ["photoId", "isOnline"])

            // One row per copy. Two copies of one picture carry the same full
            // hash, so it is indexed, not unique; the merge keeps one photo
            // id per full hash (FS-19.05 §4).
            try db.create(table: "content_hashes") { t in
                t.primaryKey("copyId", .text)
                t.column("algorithm", .text).notNull()
                t.column("algorithmVersion", .integer).notNull()
                t.column("fastHash", .text).notNull()
                t.column("fullHash", .text)
                t.column("hashedAt", .integer).notNull()
            }
            try db.create(index: "content_hashes_fast", on: "content_hashes", columns: ["algorithm", "algorithmVersion", "fastHash"])
            try db.execute(sql: """
                CREATE INDEX content_hashes_full ON content_hashes(algorithm, algorithmVersion, fullHash)
                WHERE fullHash IS NOT NULL
                """)

            try db.create(table: "photo_aliases") { t in
                t.primaryKey("loserId", .text)
                t.column("winnerId", .text).notNull()
                t.column("mergedAt", .integer).notNull()
            }

            try db.create(table: "photo_recipes") { t in
                t.primaryKey("photoId", .text)
                t.column("recipe", .blob).notNull()
                t.column("updatedAt", .integer).notNull()
            }

            // Stars, favorite, title and caption of file photos, each with the
            // time it changed — the merge keeps the latest per field.
            try db.create(table: "photo_user_marks") { t in
                t.primaryKey("photoId", .text)
                t.column("rating", .integer)
                t.column("ratingAt", .integer)
                t.column("isFavorite", .boolean)
                t.column("favoriteAt", .integer)
                t.column("title", .text)
                t.column("titleAt", .integer)
                t.column("caption", .text)
                t.column("captionAt", .integer)
            }
            try db.create(table: "photo_user_keyword") { t in
                t.column("photoId", .text).notNull()
                t.column("keyword", .text).notNull()
                t.column("caseKey", .text).notNull()
                t.column("foldKey", .text).notNull()
                t.column("addedAt", .integer).notNull()
                t.primaryKey(["photoId", "keyword"])
            }
            try db.create(index: "photo_user_keyword_caseKey", on: "photo_user_keyword", columns: ["caseKey"])
            try db.create(index: "photo_user_keyword_foldKey", on: "photo_user_keyword", columns: ["foldKey"])

            try db.create(table: "pending_sidecar") { t in
                t.primaryKey("copyId", .text)
                t.column("photoId", .text).notNull()
                t.column("reason", .text).notNull()
                t.column("markedAt", .integer).notNull()
            }
            try db.create(index: "pending_sidecar_photo", on: "pending_sidecar", columns: ["photoId"])

            try db.create(table: "shotdex_albums") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("createdAt", .integer).notNull()
            }
            try db.create(table: "shotdex_album_members") { t in
                t.column("albumId", .text).notNull()
                t.column("photoId", .text).notNull()
                t.column("addedAt", .integer).notNull()
                t.primaryKey(["albumId", "photoId"])
            }
            try db.create(index: "shotdex_album_members_photo", on: "shotdex_album_members", columns: ["photoId"])

            // Backfill before the duplicate tables are rebuilt: their ids count too.
            let now = Int(Date().timeIntervalSince1970)
            try db.execute(
                sql: "INSERT INTO sources (id, kind, name, createdAt) VALUES (?, 'photos', 'Photos Library', ?)",
                arguments: [PhotoLibrarySource.id, now]
            )
            try db.execute(sql: """
                INSERT INTO photos (id, createdAt)
                SELECT id, ? FROM (\(Self.everyPhotoIdSQL)) WHERE id IS NOT NULL
                """, arguments: [now])
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, lastSeenAt)
                SELECT 'photos:' || id, id, ?, 'photos', id, ? FROM photos
                """, arguments: [PhotoLibrarySource.id, now])

            // Duplicates group within a source (FS-19.04 §4). The cached
            // groups are a scan result: they are rebuilt, not moved, and the
            // next scan fills the new tables.
            try db.drop(table: "duplicate_groups")
            try db.drop(table: "duplicate_scan_state")
            try db.create(table: "duplicate_groups") { t in
                t.column("strictness", .text).notNull()
                t.column("sourceId", .text).notNull().defaults(to: PhotoLibrarySource.id)
                t.column("groupId", .text).notNull()
                t.column("assetId", .text).notNull()
                t.primaryKey(["strictness", "sourceId", "assetId"])
            }
            try db.create(index: "idx_duplicate_groups_group", on: "duplicate_groups", columns: ["strictness", "sourceId", "groupId"])
            try db.create(table: "duplicate_scan_state") { t in
                t.column("strictness", .text).notNull()
                t.column("sourceId", .text).notNull().defaults(to: PhotoLibrarySource.id)
                t.column("scannedAt", .integer).notNull()
                t.column("groupCount", .integer).notNull()
                t.primaryKey(["strictness", "sourceId"])
            }
        }
    }

    /// Every photo id a table held before v30, once each. `creations` keeps
    /// NULL for a draft with no source photo; the caller drops it.
    static let everyPhotoIdSQL = """
        SELECT assetId AS id FROM photo_metadata
        UNION SELECT assetId FROM perceptual_hash
        UNION SELECT assetId FROM duplicate_groups
        UNION SELECT assetId FROM subject_scan
        UNION SELECT assetId FROM creations
        UNION SELECT assetId FROM server_uploads
        UNION SELECT assetId FROM server_downloads
        UNION SELECT assetId FROM raw_pair_assets
        UNION SELECT assetId FROM photo_flag
        UNION SELECT assetId FROM pending_photo_rating
        UNION SELECT assetId FROM photo_keyword
        UNION SELECT assetId FROM photo_caption
        """
}
