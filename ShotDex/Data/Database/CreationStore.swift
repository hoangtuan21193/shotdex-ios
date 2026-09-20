import Foundation
import GRDB

/// Reads and writes the collages and videos ShotDex has made.
struct CreationStore: Sendable {
    let database: AppDatabase

    /// Everything made, most recently edited first — the order the list shows
    /// and the order someone looking for "the one I was just working on"
    /// expects.
    func fetchAllOrdered() throws -> [Creation] {
        try database.reader.read { db in
            try Creation
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// Everything of one kind, most recently edited first.
    func fetchOrdered(kind: Creation.Kind) throws -> [Creation] {
        try database.reader.read { db in
            try Creation
                .filter(Column("kind") == kind.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try database.reader.read { db in
            try Creation.fetchCount(db)
        }
    }

    func count(kind: Creation.Kind) throws -> Int {
        try database.reader.read { db in
            try Creation.filter(Column("kind") == kind.rawValue).fetchCount(db)
        }
    }

    /// Inserts a new creation or updates the one with the same id, keeping the
    /// original `createdAt`. Re-exporting an edit is the *same* creation with a
    /// new output, not a second row.
    func upsert(_ creation: Creation) throws {
        try database.writer.write { db in
            var row = creation
            if let existing = try Creation.fetchOne(db, key: creation.id) {
                row.createdAt = existing.createdAt
            }
            try row.upsert(db)
        }
    }

    func delete(id: String) throws {
        _ = try database.writer.write { db in
            try Creation.deleteOne(db, key: id)
        }
    }

    /// Forgets the output photo of every creation whose asset is no longer in
    /// the library, keeping the recipe.
    ///
    /// A creation is not deleted along with its photo: the photos it was built
    /// from are usually still there, and "I deleted the export, let me redo
    /// it" is exactly when the recipe earns its keep.
    func clearMissingAssets(existingAssetIds: Set<String>) throws {
        try database.writer.write { db in
            let rows = try Creation.fetchAll(db)
            for var row in rows {
                guard let assetId = row.assetId, !existingAssetIds.contains(assetId) else { continue }
                row.assetId = nil
                try row.update(db)
            }
        }
    }
}
