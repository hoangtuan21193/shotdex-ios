import Foundation
import GRDB
import ShotDexKit

/// Import Lightroom Edits (FS-19.02 §4): Lightroom's develop settings in a
/// photo's sidecar become its recipe, through the same table as an imported
/// preset (FS-03.14b). Only on command — reading a source never does this,
/// because a recipe the user did not ask for would change every photo they
/// open.
struct LightroomEditsImport: Sendable {
    let database: AppDatabase
    /// Where a copy's file is now; nil when its source cannot be opened.
    let fileURL: @Sendable (_ sourceId: String, _ relativePath: String) -> URL?

    struct Report: Equatable, Sendable {
        /// Photos that got a recipe.
        var imported: [String] = []
        /// Photos with no online sidecar holding Lightroom settings.
        var skipped: [String] = []
    }

    func run(photoIds: [String], now: Date = Date()) throws -> Report {
        var report = Report()
        for photoId in photoIds {
            guard let recipe = try recipe(for: photoId) else {
                report.skipped.append(photoId)
                continue
            }
            let data = try JSONEncoder().encode(recipe)
            try database.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, ?, ?)
                    ON CONFLICT(photoId) DO UPDATE SET recipe = excluded.recipe, updatedAt = excluded.updatedAt
                    """, arguments: [photoId, data, Int(now.timeIntervalSince1970)])
            }
            report.imported.append(photoId)
        }
        return report
    }

    /// The recipe from the first online copy whose sidecar holds Lightroom
    /// settings.
    private func recipe(for photoId: String) throws -> PhotoEditRecipe? {
        let copies = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT sourceId, relativePath, pairedPath FROM photo_copies
                WHERE photoId = ? AND kind = 'file' AND isOnline = 1 AND missingSince IS NULL AND isCloudPlaceholder = 0
                ORDER BY id
                """, arguments: [photoId]).map { (sourceId: $0["sourceId"] as String, path: $0["relativePath"] as String,
                                                  isPaired: ($0["pairedPath"] as String?) != nil) }
        }
        for copy in copies {
            guard let image = fileURL(copy.sourceId, copy.path) else { continue }
            let sidecar = SidecarWriter.sidecarURL(forImageAt: image, isPaired: copy.isPaired)
            guard let data = try? Data(contentsOf: sidecar),
                  let settings = try? LightroomXMPReader.read(data), !settings.values.isEmpty else { continue }
            return LightroomMapping.map(settings).recipe
        }
        return nil
    }
}
