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

        // Archived `PHPersistentChangeToken` from the end of the last complete
        // run. With it an incremental run asks Photos for exactly what changed
        // instead of walking (and materializing) every asset in the library —
        // the difference between a 7 s no-op run and a few milliseconds. Null
        // until the first full walk completes.
        migrator.registerMigration("v6-changeToken") { db in
            try db.alter(table: "index_state") { t in
                t.add(column: "changeToken", .blob)
            }
        }

        // Where each photo was taken, in words. `latitude`/`longitude` have been
        // stored since v1 but coordinates are not something anyone types into a
        // search field, so a reverse-geocoding pass fills these in and search
        // matches `placeSearchText` — every component lowercased, folded free of
        // diacritics and joined, so "da nang" finds "Đà Nẵng".
        //
        // `placeCellKey` is the ~100 m grid cell the coordinates fall in, and
        // `place_cells` caches one resolved address per cell. Photos cluster
        // heavily in space, so this is what turns "one geocoding request per
        // photo" — hopeless against Apple's rate limits — into one per place
        // visited, kept across re-indexes and app launches.
        migrator.registerMigration("v7-places") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "placeName", .text)
                t.add(column: "placeSubLocality", .text)
                t.add(column: "placeLocality", .text)
                t.add(column: "placeAdminArea", .text)
                t.add(column: "placeCountry", .text)
                t.add(column: "placeCountryCode", .text)
                t.add(column: "placeAddress", .text)
                t.add(column: "placeSearchText", .text)
                t.add(column: "placeCellKey", .text)
                t.add(column: "placeResolvedAt", .integer)
            }
            // The geocoding pass scans for rows that have coordinates and no
            // resolved place yet, then groups them by cell.
            try db.create(
                index: "idx_photo_metadata_placeCellKey",
                on: "photo_metadata",
                columns: ["placeCellKey"]
            )
            try db.create(
                index: "idx_photo_metadata_placeResolvedAt",
                on: "photo_metadata",
                columns: ["placeResolvedAt"]
            )
            try db.create(table: "place_cells") { t in
                t.primaryKey("cellKey", .text)
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("name", .text)
                t.column("subLocality", .text)
                t.column("locality", .text)
                t.column("adminArea", .text)
                t.column("country", .text)
                t.column("countryCode", .text)
                t.column("address", .text)
                t.column("searchText", .text)
                // Addresses come back in the user's language, so a locale change
                // invalidates the words without invalidating the coordinates.
                t.column("localeIdentifier", .text).notNull()
                t.column("resolvedAt", .integer)
                // Counts genuine "no data here" answers. A cell that fails this
                // many times stops being retried; a network failure does not
                // count, so going offline never poisons the cache.
                t.column("failureCount", .integer).notNull().defaults(to: 0)
            }
        }

        // Photo-vs-video is a filter of its own (Library filter sheet and the
        // `mediaType` smart-album rule), and a library that is overwhelmingly
        // one kind makes "videos only" worth an index despite the column's two
        // values.
        migrator.registerMigration("v8-mediaTypeIndex") { db in
            try db.create(
                index: "idx_photo_metadata_mediaType",
                on: "photo_metadata",
                columns: ["mediaType"]
            )
        }

        // Perceptual hashes for the duplicate finder (§7.3 Utilities). A table
        // of its own, like `place_cells`: the indexer upserts whole
        // `PhotoMetadata` rows and would blank a hash column on every re-index.
        // `hash` is nullable — NULL records a thumbnail that could not be read
        // (iCloud-only, network disallowed) so the scan skips it until network
        // is allowed again. `modificationDate` mirrors the photo's at hash time;
        // a mismatch re-queues the photo after an edit.
        migrator.registerMigration("v9-perceptualHash") { db in
            try db.create(table: "perceptual_hash") { t in
                t.primaryKey("assetId", .text)
                t.column("hash", .integer)
                t.column("modificationDate", .integer)
                t.column("computedAt", .integer).notNull()
            }
        }

        // Cached duplicate groups, one row per member per strictness, plus when
        // each strictness was last grouped. Opening the Duplicates screen reads
        // these instead of re-hashing and regrouping — the user rescans on demand.
        migrator.registerMigration("v10-duplicateCache") { db in
            try db.create(table: "duplicate_groups") { t in
                t.column("strictness", .text).notNull()
                t.column("groupId", .text).notNull()
                t.column("assetId", .text).notNull()
                t.primaryKey(["strictness", "assetId"])
            }
            try db.create(
                index: "idx_duplicate_groups_group",
                on: "duplicate_groups",
                columns: ["strictness", "groupId"]
            )
            try db.create(table: "duplicate_scan_state") { t in
                t.primaryKey("strictness", .text)
                t.column("scannedAt", .integer).notNull()
                t.column("groupCount", .integer).notNull()
            }
        }

        // Sorting the whole library by "Date Modified" scans this column, the
        // same way the date-taken orders scan `creationDate`.
        migrator.registerMigration("v11-modificationDateIndex") { db in
            try db.create(
                index: "idx_photo_metadata_modificationDate",
                on: "photo_metadata",
                columns: ["modificationDate"]
            )
        }

        // PhotoKit's media subtypes (screenshot, Live Photo, portrait,
        // panorama, …) are a bitmask on `PHAsset`. Storing them lets the
        // library be filtered by kind without walking PhotoKit, and lets a
        // smart album rule say "screenshots only". Existing rows get NULL and
        // are filled by the next index pass.
        migrator.registerMigration("v12-mediaSubtypes") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "mediaSubtypes", .integer)
            }
        }

        return migrator
    }
}
