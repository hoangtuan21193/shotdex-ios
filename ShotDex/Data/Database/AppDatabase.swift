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

        return migrator
    }
}
