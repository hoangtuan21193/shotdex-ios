import Foundation
import GRDB

extension AppDatabase {
    /// The search index (FS-01.03c §1): one row per searchable value with its
    /// photo count, and an FTS5 table over the folded names for prefix
    /// matching — Photos' `groups` + `prefix` tables, minus the per-photo join
    /// (a token's photos come from its rule, compiled like a smart album's).
    ///
    /// Derived data only: `SearchIndexStore.rebuild()` recreates every row from
    /// `photo_metadata` and the keyword mirror, so nothing here needs keeping
    /// across a rebuild — or a migration.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerSearchIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v65-searchIndex") { db in
            try db.execute(sql: """
                CREATE TABLE search_group (
                    id INTEGER PRIMARY KEY,
                    category TEXT NOT NULL,
                    name TEXT NOT NULL,
                    folded TEXT NOT NULL,
                    count INTEGER NOT NULL,
                    keyAssetId TEXT,
                    rule TEXT NOT NULL
                );
                CREATE VIRTUAL TABLE search_group_fts USING fts5(
                    folded,
                    content='search_group',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                );
                """)
        }
    }

    /// Free text through an index (FS-01.03c §7, A6): an FTS5 trigram table
    /// over the six columns plain text search reads, so `contains "mg_12"`
    /// is an index lookup instead of six `LIKE '%…%'` scans of every photo.
    /// It runs on every keystroke of a half-typed word, which is why it is
    /// worth its own table.
    ///
    /// External content: the text stays in `photo_metadata`; triggers keep
    /// the index in step, and the update trigger fires only when one of the
    /// six columns really changes — the indexer rewrites whole rows, and
    /// re-indexing unchanged text would slow every batch.
    static func registerFreeTextIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v66-freeTextIndex") { db in
            // Spelled out, not read from `SmartAlbumSQLBuilder.anyTextColumns`:
            // a registered migration must never change under a database.
            let columns = [
                "cameraModel", "lensModel", "normalizedCameraModel", "normalizedLensModel",
                "normalizedCameraManufacturer", "originalFilename",
            ]
            let list = columns.joined(separator: ", ")
            let newValues = columns.map { "new.\($0)" }.joined(separator: ", ")
            let oldValues = columns.map { "old.\($0)" }.joined(separator: ", ")
            let changed = columns.map { "old.\($0) IS NOT new.\($0)" }.joined(separator: " OR ")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE photo_text_fts USING fts5(
                    \(list),
                    content='photo_metadata',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                CREATE TRIGGER photo_text_fts_insert AFTER INSERT ON photo_metadata BEGIN
                    INSERT INTO photo_text_fts(rowid, \(list)) VALUES (new.rowid, \(newValues));
                END;
                CREATE TRIGGER photo_text_fts_delete AFTER DELETE ON photo_metadata BEGIN
                    INSERT INTO photo_text_fts(photo_text_fts, rowid, \(list)) VALUES ('delete', old.rowid, \(oldValues));
                END;
                CREATE TRIGGER photo_text_fts_update AFTER UPDATE ON photo_metadata
                WHEN \(changed) BEGIN
                    INSERT INTO photo_text_fts(photo_text_fts, rowid, \(list)) VALUES ('delete', old.rowid, \(oldValues));
                    INSERT INTO photo_text_fts(rowid, \(list)) VALUES (new.rowid, \(newValues));
                END;
                INSERT INTO photo_text_fts(photo_text_fts) VALUES ('rebuild');
                """)
        }
    }
}
