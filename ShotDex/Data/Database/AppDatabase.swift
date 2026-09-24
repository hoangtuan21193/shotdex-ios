import Foundation
import GRDB

/// Owns the GRDB database pool and its migrations.
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
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

    /// Static, and not private, so a test can migrate a database **to a
    /// chosen version**, write the rows an older build would have left, and
    /// then run the next migration over them. A migration that rewrites data
    /// is only proven by being run against data.
    static var migrator: DatabaseMigrator {
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

        // People and pets, from the opt-in Vision pass.
        //
        // Its own table for the same reason `perceptual_hash` has one: the
        // indexer upserts a whole `PhotoMetadata` record, so any column it
        // does not know about is blanked on every re-index — and this is the
        // one result in the app that costs a full image decode to rebuild.
        //
        // A row existing means "this photo was looked at"; zero counts are a
        // real answer, and the work list is every photo with no row.
        migrator.registerMigration("v13-subjectScan") { db in
            try db.create(table: "subject_scan") { t in
                t.column("assetId", .text).primaryKey()
                t.column("faceCount", .integer).notNull()
                t.column("animalCount", .integer).notNull()
                t.column("scannedAt", .integer).notNull()
            }
        }

        // Picks, rejects and star ratings.
        //
        // Its own table, like `subject_scan` above and for the same reason: the
        // indexer upserts whole `photo_metadata` rows, so a column it does not
        // know about is blanked on every re-index. Losing a background index
        // run's worth of *user-entered* culling would be the worst version of
        // that bug, so this data never shares a row with the indexed fields.
        migrator.registerMigration("v14-cull") { db in
            try db.create(table: "photo_cull") { t in
                t.column("assetId", .text).primaryKey()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("flag", .integer).notNull().defaults(to: 0)
                t.column("updatedAt", .integer).notNull()
            }
            // Culling is read as a filter over the whole library — "show me the
            // picks" — so both columns are indexed rather than scanned.
            try db.create(index: "photo_cull_rating", on: "photo_cull", columns: ["rating"])
            try db.create(index: "photo_cull_flag", on: "photo_cull", columns: ["flag"])
        }

        // The pick/reject flag is gone: a rating and PhotoKit's favorite
        // already answered "is this one good", and a third axis over the same
        // judgement only widened Compare and the viewer menu.
        //
        // Three things have to happen together, or a library that used flags
        // comes back wrong:
        //
        // 1. Rows that carried *only* a flag are now empty — `photo_cull`'s
        //    contract is that a row means "the user touched this photo", and
        //    `culledCount()` counts rows. They are deleted before the column
        //    goes, not left as rating-0 ghosts.
        // 2. The column and its index are dropped.
        // 3. Smart albums holding a `flag` rule are rewritten without it.
        //    `RuleField` no longer decodes `"flag"`, and `SmartAlbum`'s decoder
        //    falls back to an *empty* query when the JSON will not parse — an
        //    empty query matches the whole library, so leaving the rule in
        //    place would silently turn "my picks" into "everything". Dropping
        //    the rule widens the album by one condition; turning it into the
        //    entire library does not.
        migrator.registerMigration("v15-dropCullFlag") { db in
            try db.execute(sql: "DELETE FROM photo_cull WHERE rating = 0")
            try db.drop(index: "photo_cull_flag")
            try db.alter(table: "photo_cull") { t in
                t.drop(column: "flag")
            }
            try stripSmartAlbumRules(db, field: "flag")
        }

        // Star ratings are gone too, and with them the whole culling table.
        //
        // The flag went first because a rating and PhotoKit's favorite already
        // answered the same question; what is left is that a rating answers it
        // a *third* way, on a scale nobody reconciles with the heart. ShotDex
        // keeps the one bit Photos keeps, and Compare does the choosing.
        //
        // Same three-part shape as `v15`, minus the column surgery: the table
        // goes whole, and the smart albums that referenced it are rewritten so
        // a stale `rating` rule cannot collapse an album into "match
        // everything" (see `v15` for why that is the failure mode).
        migrator.registerMigration("v16-dropCull") { db in
            try db.drop(table: "photo_cull")
            try stripSmartAlbumRules(db, field: "rating")
        }

        // What ShotDex has made: one row per collage or video, holding the
        // recipe that produced it.
        //
        // Its own table for the reason `subject_scan` and the old `photo_cull`
        // had theirs — the indexer upserts whole `photo_metadata` rows, so
        // anything it does not know about is blanked on the next run — and
        // because this is keyed by the *creation*, not by a photo: a collage
        // draws on four assets and outputs a fifth, and none of those five
        // rows is the right home for it.
        //
        // `recipe` is JSON text rather than columns: it is an opaque payload
        // to SQL, nothing queries inside it, and the two recipe types it holds
        // evolve with the editors.
        migrator.registerMigration("v17-creations") { db in
            try db.create(table: "creations") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                // Null once the exported photo is deleted. The recipe stays:
                // the photos it was built from usually do too.
                t.column("assetId", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("recipeJSON", .text).notNull()
            }
            // The list is "most recently edited first", which is the only sort
            // this table is ever read in.
            try db.create(index: "creations_updatedAt", on: "creations", columns: ["updatedAt"])
        }

        // Whether the app treats this photo as a panorama (FS-14 §7). Two
        // things can make it true and they do not live in the same place: the
        // system's own pano flag, which is already in `mediaSubtypes`, and
        // ShotDex's XMP tag in the file, which only the EXIF pass can read.
        // One column answers both, so the filter, the viewer and the
        // Panoramas collection all ask the same question.
        //
        // Not a bit OR'd into `mediaSubtypes`: that column is documented as
        // PhotoKit's mask straight off the asset, and writing a value the app
        // invented into it would make every later reader wrong about what it
        // holds.
        //
        // The system half backfills here, in SQL, off the mask already
        // indexed — no PhotoKit walk and no reindex. The XMP half arrives
        // when a row is next read: photos ShotDex stitches are indexed at
        // save time, and nothing else writes that tag.
        migrator.registerMigration("v18-panoramaFlag") { db in
            try db.alter(table: "photo_metadata") { t in
                t.add(column: "isPanorama", .boolean)
            }
            // 4 is `PHAssetMediaSubtype.photoPanorama`, written as a literal
            // on purpose: a migration has to keep meaning the same thing for
            // ever, and a named constant is free to change under it.
            try db.execute(sql: """
                UPDATE photo_metadata
                SET isPanorama = ((mediaSubtypes & 4) != 0)
                WHERE mediaSubtypes IS NOT NULL
                """)
        }

        // File servers and what reached them (FS-15). Two tables of their
        // own: both are things the user made — a server they typed in, a file
        // they sent — and the indexer blanks anything in `photo_metadata` it
        // does not know about.
        //
        // An upload row keeps the server's *name* and lets its id go null
        // when the server is deleted: the row is the evidence that a file is
        // safe elsewhere, and forgetting a server in Settings does not make
        // the files on it any less there. No foreign key to `photo_metadata`
        // either, for the same reason in the other direction.
        migrator.registerMigration("v19-fileServers") { db in
            try db.create(table: "file_servers") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("transferProtocol", .text).notNull()
                t.column("host", .text).notNull()
                t.column("port", .integer).notNull()
                t.column("username", .text).notNull()
                t.column("share", .text).notNull()
                t.column("folder", .text).notNull()
                t.column("hostKeyFingerprint", .text)
                t.column("lastUsedAt", .integer)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(table: "server_uploads") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("assetId", .text).notNull()
                t.column("fileKey", .text).notNull()
                t.column("serverId", .text)
                    .references("file_servers", onDelete: .setNull)
                t.column("serverName", .text).notNull()
                t.column("remotePath", .text).notNull()
                t.column("byteCount", .integer).notNull()
                t.column("sha256", .text).notNull()
                t.column("uploadedAt", .integer).notNull()
            }
            try db.create(index: "server_uploads_assetId", on: "server_uploads", columns: ["assetId"])
        }

        return migrator
    }
}

/// Rewrites every stored smart album, dropping rules that name a `RuleField`
/// this build no longer has. Runs inside the migration that removes the field.
///
/// Done with `JSONSerialization` rather than the `SmartAlbum` model on purpose:
/// a migration has to read the shape the *old* build wrote, and decoding through
/// a model that has since lost a case is exactly the failure this is preventing.
private func stripSmartAlbumRules(_ db: Database, field removed: String) throws {
    let rows = try Row.fetchAll(db, sql: "SELECT id, criteria FROM smart_albums")
    for row in rows {
        let id: String = row["id"]
        let json: String = row["criteria"] ?? ""
        guard let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [[String: Any]]
        else { continue }

        let kept = rules.filter { ($0["field"] as? String) != removed }
        guard kept.count != rules.count else { continue }

        object["rules"] = kept
        guard let rewritten = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: rewritten, encoding: .utf8)
        else { continue }

        try db.execute(
            sql: "UPDATE smart_albums SET criteria = ? WHERE id = ?",
            arguments: [text, id]
        )
    }
}
