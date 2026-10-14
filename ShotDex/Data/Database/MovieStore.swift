import Foundation
import GRDB

/// Reads and writes the Movies library (FS-23.05 §2): sources, movies, their
/// subtitles, the subtitle choice and unfinished translations. Plex tokens
/// live in the Keychain under the source id and go with the source.
struct MovieStore: Sendable {
    let database: AppDatabase
    let plexTokens: any ServerPasswordStoring

    // MARK: Sources

    func sources() throws -> [MovieSource] {
        try database.reader.read { db in
            try MovieSource.order(Column("createdAt")).fetchAll(db)
        }
    }

    func source(id: String) throws -> MovieSource? {
        try database.reader.read { db in try MovieSource.fetchOne(db, key: id) }
    }

    /// Saves the row and, for Plex, the token when one is given.
    func saveSource(_ source: MovieSource, plexToken: String? = nil) throws {
        try database.writer.write { db in try source.upsert(db) }
        if let plexToken {
            try plexTokens.setPassword(plexToken, for: source.id)
        }
    }

    func plexToken(for sourceId: String) -> String? {
        plexTokens.password(for: sourceId)
    }

    /// The Plex version to download (AC-56): its part and size.
    func setPlexVersion(id: String, partKey: String, byteCount: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET plexPartKey = ?, byteCount = ? WHERE id = ?", arguments: [partKey, byteCount, id])
        }
    }

    /// Plex refused the token, or a new sign-in fixed it (AC-51).
    func setNeedsSignIn(_ needsSignIn: Bool, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movie_sources SET needsSignIn = ? WHERE id = ?", arguments: [needsSignIn, sourceId])
        }
    }

    /// The connection that answered last, tried first next time.
    func setPlexAddress(_ address: String, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movie_sources SET plexAddress = ? WHERE id = ?", arguments: [address, sourceId])
        }
    }

    func setReachable(_ isReachable: Bool, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movie_sources SET isReachable = ? WHERE id = ?", arguments: [isReachable, sourceId])
        }
    }

    /// FS-23.01 §2: the source's streamed movies leave Movies; downloaded
    /// ones stay, with no source. Returns the ids of the movies removed, so
    /// the caller can drop their partial files and cached art. (The delete
    /// itself is the `movie_sources_streamed_cleanup` trigger, which also
    /// runs when the source goes with its FS-15 connection.)
    @discardableResult
    func removeSource(id: String) throws -> [String] {
        let removed = try database.writer.write { db -> [String] in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM movies WHERE sourceId = ? AND state NOT IN (?, ?)",
                arguments: [id, Movie.State.onDevice.rawValue, Movie.State.missing.rawValue]
            )
            _ = try MovieSource.deleteOne(db, key: id)
            return ids
        }
        plexTokens.removePassword(for: id)
        return removed
    }

    // MARK: Scans

    struct ScanMerge: Equatable, Sendable {
        var added = 0
        var updated = 0
        /// Rows that came back under a new path or key (renamed or moved on
        /// the source, or a download rejoining a re-added server).
        var adopted = 0
        /// Rows the source stopped listing — hidden (streamed) or labelled
        /// (downloaded), never deleted here.
        var markedRemoved = 0
    }

    /// Folds one listing of a source into the library. The source owns the
    /// file facts (name, year, size, Plex text); everything the user did —
    /// where they stopped, watched, Rename, subtitles, track picks, the
    /// download — survives, including a file renamed or moved on the source.
    ///
    /// `isComplete` is the caller saying the listing finished. Only then is
    /// a row the listing lacks marked removed, and an empty listing never
    /// marks anything: a NAS that answered with nothing is likelier asleep
    /// than empty.
    @discardableResult
    func mergeScan(sourceId: String, found: [ScannedMovie], isComplete: Bool, at date: Date = Date()) throws -> ScanMerge {
        let now = Int(date.timeIntervalSince1970)
        return try database.writer.write { db in
            var merge = ScanMerge()
            guard let source = try MovieSource.fetchOne(db, key: sourceId) else { return merge }
            let existing = try Movie.filter(Column("sourceId") == sourceId).fetchAll(db)
            var byKey: [String: Movie] = [:]
            for movie in existing {
                byKey[movie.plexRatingKey ?? movie.remotePath ?? movie.originalFileName] = movie
            }
            var unclaimed = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            var newFiles: [ScannedMovie] = []
            var seen = Set<String>()
            for file in found {
                guard seen.insert(file.key).inserted else { continue }
                if let movie = byKey[file.key] {
                    unclaimed[movie.id] = nil
                    if try Self.refresh(movie, from: file, source: source, db: db) { merge.updated += 1 }
                    try Self.syncSidecars(movieId: movie.id, file.subtitles, now: now, db: db)
                } else {
                    newFiles.append(file)
                }
            }
            for file in newFiles {
                // Same file under a new path or key: this source's row the
                // listing lost, else a download left behind when this server
                // was removed before.
                var match = unclaimed.values.first {
                    $0.originalFileName == file.originalFileName && $0.byteCount == file.byteCount
                }
                if match == nil { match = try Self.orphanedDownload(of: file, source: source, db: db) }
                if var movie = match {
                    unclaimed[movie.id] = nil
                    movie.sourceId = sourceId
                    movie.remotePath = file.plexRatingKey == nil ? file.remotePath : nil
                    movie.plexRatingKey = file.plexRatingKey
                    try movie.update(db)
                    _ = try Self.refresh(movie, from: file, source: source, db: db)
                    try Self.syncSidecars(movieId: movie.id, file.subtitles, now: now, db: db)
                    merge.adopted += 1
                } else {
                    let movie = Movie(
                        sourceId: sourceId, sourceName: source.name,
                        remotePath: file.plexRatingKey == nil ? file.remotePath : nil,
                        plexMachineId: source.plexMachineId, plexRatingKey: file.plexRatingKey,
                        title: file.title, year: file.year, season: file.season, episode: file.episode,
                        originalFileName: file.originalFileName, byteCount: file.byteCount,
                        durationMs: file.durationMs, summary: file.summary, genres: file.genres,
                        posterPath: file.posterPath, state: .stream, addedAt: now
                    )
                    try movie.insert(db)
                    try Self.syncSidecars(movieId: movie.id, file.subtitles, now: now, db: db)
                    merge.added += 1
                }
            }
            if isComplete && !found.isEmpty {
                for movie in unclaimed.values where movie.removedFromSourceAt == nil {
                    try db.execute(sql: "UPDATE movies SET removedFromSourceAt = ? WHERE id = ?", arguments: [now, movie.id])
                    merge.markedRemoved += 1
                }
            }
            try db.execute(sql: "UPDATE movie_sources SET lastScannedAt = ? WHERE id = ?", arguments: [now, sourceId])
            return merge
        }
    }

    /// Writes what the source says about a file onto its row; true when
    /// something changed. A row holding the user's copy keeps its own file
    /// name and size — those describe the file in `Movies/<id>/`.
    private static func refresh(_ movie: Movie, from file: ScannedMovie, source: MovieSource, db: Database) throws -> Bool {
        var row = movie
        row.title = file.title
        row.year = file.year
        row.season = file.season
        row.episode = file.episode
        row.durationMs = file.durationMs ?? row.durationMs
        row.summary = file.summary ?? row.summary
        row.genres = file.genres ?? row.genres
        row.posterPath = file.posterPath
        row.sourceName = source.name
        row.plexMachineId = source.plexMachineId ?? row.plexMachineId
        row.removedFromSourceAt = nil
        if !row.holdsLocalFile {
            row.originalFileName = file.originalFileName
            row.byteCount = file.byteCount
        }
        guard row != movie else { return false }
        try row.update(db)
        return true
    }

    /// Plex's separate subtitle files for one movie, read when it plays
    /// (the library listing does not carry them).
    func syncPlexSubtitles(movieId: String, _ found: [ScannedSubtitle], at date: Date = Date()) throws {
        try database.writer.write { db in
            try Self.syncSidecars(movieId: movieId, found, now: Int(date.timeIntervalSince1970), db: db)
        }
    }

    /// The subtitle files beside a movie on its source, as subtitle rows
    /// that fetch on first use: new ones added, gone ones dropped. Rows the
    /// user made (imported, translated, in-file) are not touched.
    private static func syncSidecars(movieId: String, _ found: [ScannedSubtitle], now: Int, db: Database) throws {
        let sourceOrigins = [MovieSubtitle.Origin.sidecar.rawValue, MovieSubtitle.Origin.plex.rawValue]
        let existing = try MovieSubtitle
            .filter(Column("movieId") == movieId && sourceOrigins.contains(Column("origin")))
            .fetchAll(db)
        let listed = Set(found.map(\.remotePath))
        for row in existing where !listed.contains(row.remotePath ?? "") {
            _ = try row.delete(db)
        }
        var have = Set(existing.compactMap(\.remotePath))
        // `insert` also drops a file listed twice.
        for subtitle in found where have.insert(subtitle.remotePath).inserted {
            try MovieSubtitle(
                movieId: movieId, language: subtitle.language, origin: subtitle.origin, remotePath: subtitle.remotePath,
                format: subtitle.format, fileName: "", addedAt: now
            ).insert(db)
        }
    }

    /// A downloaded movie whose source was removed, now listed again by the
    /// same Plex server or at the same path of a folder source.
    private static func orphanedDownload(of file: ScannedMovie, source: MovieSource, db: Database) throws -> Movie? {
        if let key = file.plexRatingKey, let machine = source.plexMachineId {
            return try Movie
                .filter(Column("sourceId") == nil && Column("plexMachineId") == machine && Column("plexRatingKey") == key)
                .fetchOne(db)
        }
        guard let path = file.remotePath else { return nil }
        return try Movie
            .filter(Column("sourceId") == nil && Column("plexRatingKey") == nil && Column("remotePath") == path)
            .filter(Column("originalFileName") == file.originalFileName)
            .fetchOne(db)
    }

    /// Streamed rows hidden for 30 days (FS-23.05 §1) go for good; returns
    /// their ids for the art cache. Run at launch.
    @discardableResult
    func purgeRemoved(olderThan days: Int = 30, now: Date = Date()) throws -> [String] {
        let cutoff = Int(now.timeIntervalSince1970) - days * 86_400
        return try database.writer.write { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM movies WHERE removedFromSourceAt < ? AND state NOT IN (?, ?)",
                arguments: [cutoff, Movie.State.onDevice.rawValue, Movie.State.missing.rawValue]
            )
            try db.execute(
                sql: "DELETE FROM movies WHERE removedFromSourceAt < ? AND state NOT IN (?, ?)",
                arguments: [cutoff, Movie.State.onDevice.rawValue, Movie.State.missing.rawValue]
            )
            return ids
        }
    }

    // MARK: Movies

    /// Newest first — the default sort (FS-23.01 §4); the screen sorts
    /// again. Streamed rows their source stopped listing are left out.
    func movies() throws -> [Movie] {
        try database.reader.read { db in
            try Movie
                .filter(Column("removedFromSourceAt") == nil || [Movie.State.onDevice.rawValue, Movie.State.missing.rawValue].contains(Column("state")))
                .order(Column("addedAt").desc, Column("title"))
                .fetchAll(db)
        }
    }

    func movie(id: String) throws -> Movie? {
        try database.reader.read { db in try Movie.fetchOne(db, key: id) }
    }

    /// A file copied straight in (Add Movie Files…, Share, AirDrop).
    func add(_ movie: Movie) throws {
        try database.writer.write { db in try movie.insert(db) }
    }

    /// Remove from Movies. Its subtitles, choice and unfinished translations
    /// go with it; the caller deletes `Movies/<id>/`.
    func delete(id: String) throws {
        _ = try database.writer.write { db in try Movie.deleteOne(db, key: id) }
    }

    /// Rename (FS-23.01 §4). Empty goes back to the source's name.
    func rename(id: String, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET customTitle = ? WHERE id = ?", arguments: [trimmed.isEmpty ? nil : trimmed, id])
        }
    }

    /// `error` is shown on the row; any token or key in it (a failing
    /// Plex URL carries `X-Plex-Token=`) is masked before it is stored.
    func setState(
        id: String, _ state: Movie.State, downloadedBytes: Int64? = nil, error: String? = nil, plexPartKey: String? = nil
    ) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE movies SET state = ?, downloadedBytes = COALESCE(?, downloadedBytes), downloadError = ?,
                    plexPartKey = COALESCE(?, plexPartKey)
                WHERE id = ?
                """,
                arguments: [state.rawValue, downloadedBytes, error.map(SecretRedaction.redact), plexPartKey, id]
            )
        }
    }

    /// Bytes fetched so far, only while the movie is still downloading — a
    /// late progress report never undoes a finished or stopped download.
    func setDownloadProgress(id: String, bytes: Int64) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE movies SET downloadedBytes = ? WHERE id = ? AND state IN (?, ?)",
                arguments: [bytes, id, Movie.State.downloading.rawValue, Movie.State.queued.rawValue]
            )
        }
    }

    /// Remove Download (FS-23.01 §6): back to Stream with where it stopped,
    /// watched and every choice kept. Subtitles fetched from the source go
    /// back to fetch-on-use; the user's own (imported, translated, in-file)
    /// stay. Returns the subtitle files the caller may delete.
    @discardableResult
    func removeDownload(id: String) throws -> [String] {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE movies SET state = ?, downloadedBytes = 0, downloadError = NULL, localFileName = NULL WHERE id = ?",
                arguments: [Movie.State.stream.rawValue, id]
            )
            let fetched = try MovieSubtitle
                .filter(Column("movieId") == id && Column("remotePath") != nil && Column("fileName") != "")
                .fetchAll(db)
            for var subtitle in fetched {
                subtitle.fileName = ""
                try subtitle.update(db)
            }
            return fetched.map(\.fileName)
        }
    }

    /// The download or copy finished under this name in `Movies/<id>/`.
    func setLocalFileName(_ name: String, id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET localFileName = ? WHERE id = ?", arguments: [name, id])
        }
    }

    func setFileHash(_ hash: String, id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET fileHash = ? WHERE id = ?", arguments: [hash, id])
        }
    }

    /// Where the player is (written every 10 s, on pause, on close). A Plex
    /// movie owes the server this position until `markPlexSynced`.
    func recordPosition(id: String, positionMs: Int64, at date: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE movies SET positionMs = ?, lastPlayedAt = ?,
                    plexSyncPending = (plexSyncPending OR (plexRatingKey IS NOT NULL AND sourceId IS NOT NULL))
                WHERE id = ?
                """,
                arguments: [positionMs, Int(date.timeIntervalSince1970), id]
            )
        }
    }

    /// Mark as Watched / Unwatched. Either way the movie starts from the top
    /// next time.
    func setWatched(_ isWatched: Bool, ids: [String], at date: Date = Date()) throws {
        try database.writer.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                    UPDATE movies SET isWatched = ?, positionMs = 0, lastPlayedAt = ?,
                        plexSyncPending = (plexSyncPending OR (plexRatingKey IS NOT NULL AND sourceId IS NOT NULL))
                    WHERE id = ?
                    """,
                    arguments: [isWatched, Int(date.timeIntervalSince1970), id]
                )
            }
        }
    }

    func setAudio(id: String, trackId: String?, delayMs: Int) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET audioTrackId = ?, audioDelayMs = ? WHERE id = ?", arguments: [trackId, delayMs, id])
        }
    }

    func setPlaybackRate(_ rate: Double, id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET playbackRate = ? WHERE id = ?", arguments: [rate, id])
        }
    }

    /// The length the player found, for the resume rule and the list
    /// (a scan only knows it for MP4 and Plex).
    func setDuration(_ durationMs: Int64, id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE movies SET durationMs = ? WHERE id = ?", arguments: [durationMs, id])
        }
    }

    /// Plex movies whose position or watched mark the server has not heard.
    func pendingPlexSync(sourceId: String) throws -> [Movie] {
        try database.reader.read { db in
            try Movie.filter(Column("sourceId") == sourceId && Column("plexSyncPending") == true).fetchAll(db)
        }
    }

    /// Plex's own watch state (FS-23.07 §4), taken where it is newer than
    /// what this device recorded and this device owes Plex nothing — when
    /// both changed, the latest viewing wins: this device's is sent first.
    func applyPlexProgress(sourceId: String, _ progress: [(ratingKey: String, positionMs: Int64, isWatched: Bool, viewedAt: Int?)]) throws {
        try database.writer.write { db in
            for item in progress {
                guard var movie = try Movie.filter(Column("sourceId") == sourceId && Column("plexRatingKey") == item.ratingKey).fetchOne(db),
                      !movie.plexSyncPending, let viewedAt = item.viewedAt, viewedAt > (movie.lastPlayedAt ?? 0) else { continue }
                movie.positionMs = item.isWatched ? 0 : item.positionMs
                movie.isWatched = item.isWatched
                movie.lastPlayedAt = viewedAt
                try movie.update(db)
            }
        }
    }

    /// Clears the flag only where nothing changed since the snapshot sent —
    /// a position recorded while the request was in flight still owes.
    func markPlexSynced(_ sent: [Movie]) throws {
        try database.writer.write { db in
            for movie in sent {
                try db.execute(
                    sql: "UPDATE movies SET plexSyncPending = 0 WHERE id = ? AND positionMs = ? AND isWatched = ? AND lastPlayedAt IS ?",
                    arguments: [movie.id, movie.positionMs, movie.isWatched, movie.lastPlayedAt]
                )
            }
        }
    }

    // MARK: Subtitles

    func subtitles(movieId: String) throws -> [MovieSubtitle] {
        try database.reader.read { db in
            try MovieSubtitle.filter(Column("movieId") == movieId).order(Column("addedAt")).fetchAll(db)
        }
    }

    func saveSubtitle(_ subtitle: MovieSubtitle) throws {
        try database.writer.write { db in try subtitle.upsert(db) }
    }

    /// The choice pointing at it falls back to none; a translation made from
    /// it that had not finished goes too.
    func removeSubtitle(id: String) throws {
        _ = try database.writer.write { db in try MovieSubtitle.deleteOne(db, key: id) }
    }

    func subtitleChoice(movieId: String) throws -> MovieSubtitleChoice? {
        try database.reader.read { db in try MovieSubtitleChoice.fetchOne(db, key: movieId) }
    }

    func saveSubtitleChoice(_ choice: MovieSubtitleChoice) throws {
        try database.writer.write { db in try choice.upsert(db) }
    }

    // MARK: Translations

    func translationJobs(movieId: String) throws -> [MovieTranslationJob] {
        try database.reader.read { db in
            try MovieTranslationJob.filter(Column("movieId") == movieId).order(Column("startedAt")).fetchAll(db)
        }
    }

    func saveTranslationJob(_ job: MovieTranslationJob) throws {
        try database.writer.write { db in try job.upsert(db) }
    }

    func removeTranslationJob(id: String) throws {
        _ = try database.writer.write { db in try MovieTranslationJob.deleteOne(db, key: id) }
    }
}

/// Masks secrets in text that is stored or shown — an error message can
/// carry the URL that failed (FS-08.07 §4: keys never reach the database,
/// logs or error messages).
enum SecretRedaction {
    nonisolated(unsafe) private static let parameter = #/(?i)((?:x-plex-token|token|access_token|api[_-]?key|key)=)[^&\s"']+/#

    static func redact(_ text: String) -> String {
        text.replacing(parameter) { match in "\(match.1)•••" }
    }
}
