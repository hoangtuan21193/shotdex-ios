import Foundation
import GRDB

extension AppDatabase {
    /// Editor snapshots (FS-03.18 §5): a named recipe the user kept for one
    /// photo. User data, so its own table — never `photo_metadata`, which the
    /// indexer rewrites.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerEditorSnapshots(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v67-editorSnapshots") { db in
            try db.create(table: "editor_snapshot") { t in
                t.primaryKey("id", .text)
                t.column("photoId", .text).notNull().indexed()
                t.column("name", .text).notNull()
                t.column("recipe", .blob).notNull()
                t.column("createdAt", .double).notNull()
            }
        }
    }
}
