import Foundation
import GRDB

/// What the index already knows about one asset — input to the incremental
/// diff (`IndexPipeline.needsReindex`).
struct IndexedAssetState: Equatable, Sendable {
    var modificationDate: Int?
    var exifStatus: String
    /// Build that wrote the row; a value below `currentIndexerVersion` marks
    /// the row stale so it is re-read even when unchanged. Defaults to current
    /// so tests and callers that don't care about staleness stay terse.
    var indexerVersion: Int = PhotoMetadata.currentIndexerVersion
}

/// Writes indexed metadata and manages the index cursor.
struct MetadataStore: Sendable {
    let database: AppDatabase

    // MARK: Batch writes

    /// Upserts one indexing batch and advances the resume cursor atomically.
    func saveBatch(_ records: [PhotoMetadata], cursorAssetId: String?) throws {
        try database.writer.write { db in
            for record in records {
                try record.upsert(db)
            }
            var state = try IndexState.fetchOne(db, key: IndexState.singletonId) ?? .initial
            state.cursorAssetId = cursorAssetId
            state.lastIndexedAt = Int(Date().timeIntervalSince1970)
            try state.upsert(db)
        }
    }

    /// Upserts a single row **without touching the resume cursor** — used by
    /// the detail viewer to fill in an incomplete row after an iCloud download,
    /// so it must not disturb the batch pipeline's cursor/last-indexed state.
    func upsert(_ record: PhotoMetadata) throws {
        try database.writer.write { db in
            try record.upsert(db)
        }
    }

    /// The stored diff snapshot for one asset (nil when there's no row yet).
    func assetState(assetId: String) throws -> IndexedAssetState? {
        try database.reader.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT modificationDate, exifStatus, indexerVersion FROM photo_metadata WHERE assetId = ?",
                arguments: [assetId]
            ).map {
                IndexedAssetState(
                    modificationDate: $0["modificationDate"],
                    exifStatus: $0["exifStatus"],
                    indexerVersion: $0["indexerVersion"]
                )
            }
        }
    }

    /// Removes rows whose assets no longer exist in the photo library.
    func deleteAssets(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        _ = try database.writer.write { db in
            try PhotoMetadata.deleteAll(db, keys: ids)
        }
    }

    /// Updates the favorite flag mirrored from PhotoKit.
    func updateFavorite(assetId: String, isFavorite: Bool) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE photo_metadata SET isFavorite = ? WHERE assetId = ?",
                arguments: [isFavorite, assetId]
            )
        }
    }

    /// Clears the whole index (Settings → Clear local metadata index).
    func deleteAll() throws {
        try database.writer.write { db in
            _ = try PhotoMetadata.deleteAll(db)
            var state = try IndexState.fetchOne(db, key: IndexState.singletonId) ?? .initial
            state.cursorAssetId = nil
            state.lastIndexedAt = nil
            state.lastFullIndexAt = nil
            try state.upsert(db)
        }
    }

    // MARK: Index state

    func indexState() throws -> IndexState {
        try database.reader.read { db in
            try IndexState.fetchOne(db, key: IndexState.singletonId) ?? .initial
        }
    }

    func saveIndexState(_ state: IndexState) throws {
        try database.writer.write { db in
            try state.upsert(db)
        }
    }

    func indexedCount() throws -> Int {
        try database.reader.read { db in
            try PhotoMetadata.fetchCount(db)
        }
    }

    /// Rows with a finished EXIF read (`indexed`/`noExif`) — the baseline for
    /// cumulative index progress, so a run resumes the count from what's
    /// already done instead of restarting at zero each launch.
    func completedCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM photo_metadata WHERE exifStatus IN (?, ?)",
                arguments: [ExifStatus.indexed.rawValue, ExifStatus.noExif.rawValue]
            ) ?? 0
        }
    }

    /// Count of rows genuinely waiting on an iCloud/network read
    /// (`pendingICloud` only — **not** `error`). Drives the network-specific
    /// "iCloud not responding" auto-retry + card: local `error` rows are
    /// deterministic non-network failures handled by the give-up cap, so they
    /// must not trigger the iCloud UI.
    func pendingICloudReadCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM photo_metadata WHERE exifStatus = ?",
                arguments: [ExifStatus.pendingICloud.rawValue]
            ) ?? 0
        }
    }

    /// Assets whose EXIF read is incomplete (in iCloud or failed), for the
    /// Settings re-index action and its counter.
    func retryableAssetIds() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT assetId FROM photo_metadata WHERE exifStatus IN (?, ?)",
                arguments: [ExifStatus.pendingICloud.rawValue, ExifStatus.error.rawValue]
            )
        }
    }

    /// Failed-read counter for one asset (0 when there's no row yet). Read by
    /// the pipeline before writing an `error` row so the count climbs across
    /// runs toward `IndexPipeline.maxReadAttempts`.
    func readAttempts(assetId: String) throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT readAttempts FROM photo_metadata WHERE assetId = ?",
                arguments: [assetId]
            ) ?? 0
        }
    }

    /// Per-asset diff snapshot: modificationDate to detect edits, exifStatus
    /// so incomplete reads can be re-enqueued even when unchanged.
    func indexedAssetStates() throws -> [String: IndexedAssetState] {
        try database.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT assetId, modificationDate, exifStatus, indexerVersion FROM photo_metadata"
            )
            var result: [String: IndexedAssetState] = [:]
            result.reserveCapacity(rows.count)
            for row in rows {
                result[row["assetId"]] = IndexedAssetState(
                    modificationDate: row["modificationDate"],
                    exifStatus: row["exifStatus"],
                    indexerVersion: row["indexerVersion"]
                )
            }
            return result
        }
    }

    /// Camera models whose sensor format could not be resolved.
    func unknownCameraModels() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT normalizedCameraModel FROM photo_metadata
                    WHERE sensorFormat = ? AND normalizedCameraModel IS NOT NULL
                    ORDER BY normalizedCameraModel COLLATE NOCASE
                    """,
                arguments: [SensorFormat.unknown.rawValue]
            )
        }
    }

    /// Saves a manual mapping and rewrites the already-indexed rows of that
    /// camera: sensor format, crop factor, and equivalent focal lengths.
    func applyCustomMapping(_ mapping: CustomCameraMapping) throws {
        try database.writer.write { db in
            try mapping.upsert(db)
            try Self.rewriteRows(
                db,
                model: mapping.normalizedCameraModel,
                format: mapping.sensorFormat,
                crop: mapping.cropFactor
            )
        }
    }

    /// Rewrites rows whose camera was indexed as Unknown but is covered by
    /// the given lookup — after an app update ships new bundled database
    /// records, already-indexed photos pick them up without a reindex.
    /// Returns the number of camera models that were resolved.
    @discardableResult
    func resolveUnknownCameras(using lookup: SensorLookup) throws -> Int {
        let models = try unknownCameraModels()
        var resolved = 0
        try database.writer.write { db in
            for model in models {
                let info = lookup.lookup(normalizedModel: model)
                guard info.sensorFormat != .unknown else { continue }
                try Self.rewriteRows(db, model: model, format: info.sensorFormat.rawValue, crop: info.cropFactor)
                resolved += 1
            }
        }
        return resolved
    }

    /// Rewrites sensor format, crop factor, and equivalent focal lengths for
    /// every row of one camera model.
    private static func rewriteRows(_ db: Database, model: String, format: String, crop: Double?) throws {
        try db.execute(
            sql: """
                UPDATE photo_metadata SET
                    sensorFormat = :format,
                    cropFactor = :crop,
                    calculatedEquivalentFocalLength =
                        CASE WHEN focalLength IS NOT NULL AND :crop IS NOT NULL
                             THEN focalLength * :crop END,
                    equivalentFocalLength =
                        CASE WHEN focalLengthIn35mm IS NOT NULL AND focalLengthIn35mm BETWEEN 1 AND 3000
                             THEN focalLengthIn35mm
                             WHEN focalLength IS NOT NULL AND :crop IS NOT NULL
                             THEN focalLength * :crop END
                WHERE normalizedCameraModel = :model
                """,
            arguments: ["format": format, "crop": crop, "model": model]
        )
    }

    // MARK: Custom camera mappings

    func customMappings() throws -> [CustomCameraMapping] {
        try database.reader.read { db in
            try CustomCameraMapping.fetchAll(db)
        }
    }

    func saveCustomMapping(_ mapping: CustomCameraMapping) throws {
        try database.writer.write { db in
            try mapping.upsert(db)
        }
    }

    func deleteAllCustomMappings() throws {
        _ = try database.writer.write { db in
            try CustomCameraMapping.deleteAll(db)
        }
    }
}
