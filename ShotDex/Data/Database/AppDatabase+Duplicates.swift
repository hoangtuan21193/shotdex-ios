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

        // v3 groups once into kinds instead of three strictness levels
        // (FS-06.06 §4): one row per photo per source, tagged with its kind.
        // The cache is a scan result — rebuilt by the next scan, not moved.
        migrator.registerMigration("v41-duplicateKinds") { db in
            try db.drop(table: "duplicate_groups")
            try db.drop(table: "duplicate_scan_state")
            try db.create(table: "duplicate_groups") { t in
                t.column("sourceId", .text).notNull().defaults(to: PhotoLibrarySource.id)
                t.column("groupId", .text).notNull()
                t.column("assetId", .text).notNull()
                t.column("kind", .text).notNull()
                t.primaryKey(["sourceId", "assetId"])
            }
            try db.create(index: "idx_duplicate_groups_group", on: "duplicate_groups", columns: ["sourceId", "groupId"])
            try db.create(table: "duplicate_scan_state") { t in
                t.primaryKey("sourceId", .text)
                t.column("scannedAt", .integer).notNull()
                t.column("groupCount", .integer).notNull()
            }
        }
    }

    /// Vision feature prints for grouped photos (2026-11-10): the hash only
    /// nominates a look-alike, the print confirms it. A scan result, so the
    /// stored rows simply re-queue: every existing score lacks a print.
    static func registerDuplicateFeaturePrints(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v63-duplicateFeaturePrint") { db in
            try db.alter(table: "duplicate_quality") { t in
                // Archived `VNFeaturePrintObservation`; NULL until read.
                t.add(column: "featurePrint", .blob)
            }
        }
    }
}
