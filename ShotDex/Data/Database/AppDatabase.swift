import Foundation
import GRDB

/// Owns the GRDB database pool and its migrations.
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    /// Opens (or creates) the on-disk database in Application Support.
    static func makeShared() throws -> AppDatabase {
        let folderURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Database", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let databaseURL = folderURL.appendingPathComponent("shotdex.sqlite")
        let pool = try DatabasePool(path: databaseURL.path)
        return try AppDatabase(pool)
    }

    /// In-memory database for tests and previews.
    static func makeEmpty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "photo_metadata") { t in
                t.primaryKey("assetId", .text)
                t.column("creationDate", .integer)
                t.column("modificationDate", .integer)
                t.column("mediaType", .integer).notNull()

                t.column("cameraManufacturer", .text)
                t.column("cameraModel", .text)
                t.column("normalizedCameraModel", .text)
                t.column("normalizedCameraManufacturer", .text)

                t.column("lensManufacturer", .text)
                t.column("lensModel", .text)
                t.column("normalizedLensModel", .text)

                t.column("originalFilename", .text)

                t.column("iso", .integer)
                t.column("aperture", .double)
                t.column("shutterSpeedSeconds", .double)
                t.column("shutterSpeedDisplay", .text)

                t.column("focalLength", .double)
                t.column("focalLengthIn35mm", .double)
                t.column("calculatedEquivalentFocalLength", .double)
                t.column("equivalentFocalLength", .double)

                t.column("sensorFormat", .text)
                t.column("cropFactor", .double)

                t.column("width", .integer)
                t.column("height", .integer)
                t.column("fileSize", .integer)

                t.column("latitude", .double)
                t.column("longitude", .double)

                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("indexedAt", .integer).notNull()
                t.column("exifStatus", .text).notNull()
            }

            let indexedColumns = [
                "normalizedCameraModel", "normalizedLensModel", "iso", "aperture",
                "shutterSpeedSeconds", "focalLength", "equivalentFocalLength",
                "sensorFormat", "creationDate",
            ]
            for column in indexedColumns {
                try db.create(
                    index: "idx_photo_metadata_\(column)",
                    on: "photo_metadata",
                    columns: [column]
                )
            }

            try db.create(table: "custom_camera_mappings") { t in
                t.primaryKey("normalizedCameraModel", .text)
                t.column("sensorFormat", .text).notNull()
                t.column("cropFactor", .double)
            }

            try db.create(table: "index_state") { t in
                t.primaryKey("id", .integer)
                t.column("cursorAssetId", .text)
                t.column("lastIndexedAt", .integer)
                t.column("lastFullIndexAt", .integer)
            }
        }

        // Records which build of the indexer wrote each row (see
        // `PhotoMetadata.currentIndexerVersion`). Existing rows default to 0,
        // so bumping the current version re-reads them on the next incremental
        // run — the mechanism for backfilling any newly-indexed field onto
        // already-indexed photos without a full re-index.
        migrator.registerMigration("v2-indexerVersion") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "indexerVersion", .integer).notNull().defaults(to: 0)
            }
        }

        // User-created smart albums: named saved filters. `criteria` holds a
        // JSON-encoded `FilterCriteria` (GRDB serializes the nested Codable).
        migrator.registerMigration("v3-smartAlbums") { db in
            try db.create(table: "smart_albums") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("criteria", .text).notNull()
                t.column("createdAt", .integer).notNull()
            }
        }

        // Dashboard chart specs for the Statistics screen. `config` holds a
        // JSON-encoded `ChartSpec` string (like `smart_albums.criteria`);
        // `position` is the display order. Seeded with defaults on first use.
        migrator.registerMigration("v4-statCharts") { db in
            try db.create(table: "stat_charts") { t in
                t.primaryKey("id", .text)
                t.column("config", .text).notNull()
                t.column("position", .integer).notNull()
            }
        }

        // Counts consecutive failed EXIF reads (`exifStatus = error`) for a
        // row. After `IndexPipeline.maxReadAttempts` genuine failures the row
        // is downgraded to `noExif` — an unreadable original (corrupt/truncated
        // file, or one PhotoKit refuses to serve) stops being re-enqueued every
        // run and simply shows in the library without camera metadata. Reset to
        // 0 whenever a row is written with any non-error status.
        migrator.registerMigration("v5-readAttempts") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "readAttempts", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }
}
