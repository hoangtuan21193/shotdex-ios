import Foundation
import GRDB

extension AppDatabase {
    /// FS-23.05 §2 and FS-08.07 §4: the Movies library and the AI providers.
    /// Nothing here touches `photo_metadata`, so a re-index or Clear Local
    /// Metadata Index leaves all of it alone.
    ///
    /// Links stay inside these tables: subtitles, the subtitle choice and
    /// unfinished translations go with their movie. A downloaded movie
    /// outlives its source (the id goes null) because the copy is the
    /// user's; a trigger deletes the source's streamed movies first, so
    /// removing a source — directly, or through the FS-15 connection it sits
    /// on — never leaves a row with nothing to play from.
    ///
    /// Do not edit once shipped to a device: DEBUG builds erase the database
    /// when a registered migration changes. A later change is a new migration.
    static func registerMovies(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v36-movies") { db in
            try db.create(table: "movie_sources") { t in
                t.primaryKey("id", .text)
                // folder · plex
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("connectionId", .text)
                    .references("file_servers", onDelete: .cascade)
                t.column("folder", .text).notNull()
                t.column("plexMachineId", .text)
                t.column("plexAddress", .text)
                t.column("plexLibraries", .text).notNull()
                t.column("lastScannedAt", .integer)
                t.column("isReachable", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .integer).notNull()
            }

            try db.create(table: "movies") { t in
                t.primaryKey("id", .text)
                t.column("sourceId", .text)
                    .references("movie_sources", onDelete: .setNull)
                t.column("sourceName", .text)
                // Folder rows only; Plex rows are keyed by plexRatingKey.
                t.column("remotePath", .text)
                t.column("plexMachineId", .text)
                t.column("plexRatingKey", .text)
                t.column("plexPartKey", .text)
                t.column("title", .text).notNull()
                t.column("customTitle", .text)
                t.column("year", .integer)
                t.column("season", .integer)
                t.column("episode", .integer)
                t.column("originalFileName", .text).notNull()
                t.column("localFileName", .text)
                t.column("byteCount", .integer).notNull()
                t.column("fileHash", .text)
                t.column("durationMs", .integer)
                t.column("summary", .text)
                t.column("genres", .text)
                // Folder: an image next to the movie; Plex: its thumb path.
                t.column("posterPath", .text)
                // stream · queued · downloading · onDevice · unplayable · missing
                t.column("state", .text).notNull()
                t.column("downloadedBytes", .integer).notNull().defaults(to: 0)
                t.column("downloadError", .text)
                t.column("removedFromSourceAt", .integer)
                t.column("addedAt", .integer).notNull()
                t.column("lastPlayedAt", .integer)
                t.column("positionMs", .integer).notNull().defaults(to: 0)
                t.column("isWatched", .boolean).notNull().defaults(to: false)
                t.column("playbackRate", .double).notNull().defaults(to: 1)
                t.column("audioTrackId", .text)
                t.column("audioDelayMs", .integer).notNull().defaults(to: 0)
                t.column("plexSyncPending", .boolean).notNull().defaults(to: false)
            }
            // One row per file of a source; NULLs (copied-in files) never clash.
            try db.execute(sql: """
                CREATE UNIQUE INDEX movies_source_path ON movies(sourceId, remotePath)
                WHERE plexRatingKey IS NULL AND remotePath IS NOT NULL
                """)
            try db.create(index: "movies_source_plex", on: "movies", columns: ["sourceId", "plexRatingKey"], unique: true)
            try db.create(index: "movies_plex_item", on: "movies", columns: ["plexMachineId", "plexRatingKey"])
            try db.create(index: "movies_hash", on: "movies", columns: ["fileHash"])
            try db.execute(sql: "CREATE INDEX movies_plex_pending ON movies(sourceId) WHERE plexSyncPending = 1")

            // A source going away — removeSource, or the cascade from its
            // FS-15 connection — takes the movies that only lived there.
            try db.execute(sql: """
                CREATE TRIGGER movie_sources_streamed_cleanup BEFORE DELETE ON movie_sources
                BEGIN
                    DELETE FROM movies WHERE sourceId = OLD.id AND state NOT IN ('onDevice', 'missing');
                END
                """)

            try db.create(table: "movie_subtitles") { t in
                t.primaryKey("id", .text)
                t.column("movieId", .text).notNull()
                    .references("movies", onDelete: .cascade)
                t.column("language", .text)
                // inFile · sidecar · imported · shared · plex · translated
                t.column("origin", .text).notNull()
                t.column("inFileTrack", .integer)
                // Sidecar or Plex: where it lives on the source until fetched.
                t.column("remotePath", .text)
                t.column("translatedFromId", .text)
                t.column("translationProviderId", .text)
                t.column("format", .text).notNull()
                t.column("encoding", .text)
                t.column("fileName", .text).notNull()
                t.column("offsetMs", .integer).notNull().defaults(to: 0)
                t.column("addedAt", .integer).notNull()
            }
            try db.create(index: "movie_subtitles_movie", on: "movie_subtitles", columns: ["movieId"])

            try db.create(table: "movie_subtitle_choices") { t in
                t.primaryKey("movieId", .text)
                    .references("movies", onDelete: .cascade)
                t.column("primaryId", .text)
                    .references("movie_subtitles", onDelete: .setNull)
                t.column("secondaryId", .text)
                    .references("movie_subtitles", onDelete: .setNull)
                // JSON, decoded leniently by the player.
                t.column("style", .text).notNull()
            }
            try db.create(index: "movie_subtitle_choices_primary", on: "movie_subtitle_choices", columns: ["primaryId"])
            try db.create(index: "movie_subtitle_choices_secondary", on: "movie_subtitle_choices", columns: ["secondaryId"])

            try db.create(table: "movie_translation_jobs") { t in
                t.primaryKey("id", .text)
                t.column("movieId", .text).notNull()
                    .references("movies", onDelete: .cascade)
                t.column("fromSubtitleId", .text).notNull()
                    .references("movie_subtitles", onDelete: .cascade)
                t.column("toLanguage", .text).notNull()
                t.column("providerId", .text).notNull()
                t.column("cuesDone", .integer).notNull()
                t.column("cueCount", .integer).notNull()
                t.column("partialFileName", .text).notNull()
                t.column("startedAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(index: "movie_translation_jobs_movie", on: "movie_translation_jobs", columns: ["movieId"])
            try db.create(index: "movie_translation_jobs_from", on: "movie_translation_jobs", columns: ["fromSubtitleId"])

            // FS-08.07 §4. No key column, by design.
            try db.create(table: "ai_providers") { t in
                t.primaryKey("id", .text)
                // homeServer · claude · chatGPT · openRouter · grok · gemini · openAICompatible
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("address", .text).notNull()
                t.column("model", .text).notNull()
                t.column("createdAt", .integer).notNull()
            }
        }
    }
}
