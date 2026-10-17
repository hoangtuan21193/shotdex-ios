import Foundation
import GRDB

extension AppDatabase {
    /// Duplicates v3 (FS-06.06 §10): two tables of their own, never columns
    /// of `photo_metadata` — the indexer upserts whole rows there (BD-02 §1).
    static func registerDuplicatesV3(_ migrator: inout DatabaseMigrator) {
        // `duplicate_review` is user data: what the user marked, kept whole,
        // picked as the keeper, folded, or said are not duplicates. Marks and
        // keeper picks are per photo (`setId` is empty); the rest name a set of
        // photos, one row per member under one `setId`, so they survive a
        // regroup that hands the group a new id (FS-06.06b §1).
        //
        // `duplicate_quality` is an expensive scan result: what the scoring
        // pass measured on a grouped photo, stamped with the photo's
        // `modificationDate` so an edit re-queues it (FS-06.06 §6).
        migrator.registerMigration("v40-duplicatesV3") { db in
            try db.create(table: "duplicate_review") { t in
                // mark · keeper · keepAll · collapsed · notDuplicates
                t.column("role", .text).notNull()
                t.column("setId", .text).notNull().defaults(to: "")
                t.column("assetId", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.primaryKey(["role", "setId", "assetId"])
            }
            try db.create(index: "idx_duplicate_review_asset", on: "duplicate_review", columns: ["assetId"])

            try db.create(table: "duplicate_quality") { t in
                t.primaryKey("assetId", .text)
                t.column("modificationDate", .integer)
                // Variance of the Laplacian on the 512px thumbnail; NULL when
                // the thumbnail could not be read.
                t.column("sharpness", .double)
                // 0…1, NULL when Vision found no face it trusts.
                t.column("eyesOpen", .double)
                t.column("eyeConfidence", .double)
                // Share of pixels at ≥250 / ≤5 luma.
                t.column("highlightClip", .double)
                t.column("shadowClip", .double)
                // Normalized "x,y,w,h" of the largest face, for Zoom to face.
                t.column("faceRect", .text)
                t.column("exposureBias", .double)
                t.column("software", .text)
                t.column("scoredAt", .integer).notNull()
            }
        }
    }
}
