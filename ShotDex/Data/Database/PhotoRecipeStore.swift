import Foundation
import GRDB
import ShotDexKit

/// The recipe of a photo edited through a file copy (FS-19.02 §8): saved as
/// it changes, under the photo's id, so every copy shows the same edit and
/// the sidecars carry it on (D16). A Photos copy keeps its edit in Photos.
struct PhotoRecipeStore: Sendable {
    let database: AppDatabase

    /// Nil when the photo was never edited, or its row does not decode.
    func recipe(photoId: String) throws -> PhotoEditRecipe? {
        let data = try database.reader.read { db in
            try Data.fetchOne(db, sql: "SELECT recipe FROM photo_recipes WHERE photoId = ?", arguments: [photoId])
        }
        return data.flatMap { try? JSONDecoder().decode(PhotoEditRecipe.self, from: $0) }
    }

    /// Saves `recipe`; an identity recipe removes the row, so the photo
    /// reads as unedited again.
    func save(_ recipe: PhotoEditRecipe, photoId: String, now: Date = Date()) throws {
        if recipe.isIdentity {
            try database.writer.write { db in
                try db.execute(sql: "DELETE FROM photo_recipes WHERE photoId = ?", arguments: [photoId])
            }
            return
        }
        let data = try JSONEncoder().encode(recipe)
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(photoId) DO UPDATE SET recipe = excluded.recipe, updatedAt = excluded.updatedAt
                """, arguments: [photoId, data, Int(now.timeIntervalSince1970)])
        }
    }
}
