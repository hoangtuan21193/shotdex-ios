import Foundation
import GRDB
import ShotDexKit

/// A recipe kept under a name for one photo (FS-03.18 §5) — Lightroom's
/// Snapshots. Outlives the editing session, unlike History.
struct EditorSnapshot: Identifiable, Equatable, Sendable {
    var id: String
    var photoId: String
    var name: String
    var recipe: PhotoEditRecipe
    var createdAt: Date
}

struct EditorSnapshotStore: Sendable {
    let database: AppDatabase

    /// Newest first. A row whose recipe no longer decodes is skipped, not fatal.
    func snapshots(photoId: String) throws -> [EditorSnapshot] {
        let decoder = JSONDecoder()
        return try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, photoId, name, recipe, createdAt FROM editor_snapshot
                WHERE photoId = ? ORDER BY createdAt DESC
                """, arguments: [photoId]).compactMap { row in
                guard let data: Data = row["recipe"],
                      let recipe = try? decoder.decode(PhotoEditRecipe.self, from: data) else { return nil }
                return EditorSnapshot(id: row["id"], photoId: row["photoId"], name: row["name"], recipe: recipe,
                                      createdAt: Date(timeIntervalSince1970: row["createdAt"]))
            }
        }
    }

    @discardableResult
    func add(name: String, recipe: PhotoEditRecipe, photoId: String, at date: Date = Date()) throws -> EditorSnapshot {
        let snapshot = EditorSnapshot(id: UUID().uuidString, photoId: photoId, name: name, recipe: recipe, createdAt: date)
        let data = try JSONEncoder().encode(recipe)
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO editor_snapshot (id, photoId, name, recipe, createdAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [snapshot.id, photoId, name, data, date.timeIntervalSince1970])
        }
        return snapshot
    }

    func delete(id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM editor_snapshot WHERE id = ?", arguments: [id])
        }
    }
}
