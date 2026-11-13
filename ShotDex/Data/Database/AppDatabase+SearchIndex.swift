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
}
