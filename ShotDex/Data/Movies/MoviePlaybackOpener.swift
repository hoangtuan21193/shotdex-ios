import Foundation

/// What Play opens (FS-23.01 §3): the file on the device, or a stream from
/// the movie's source over its saved connection — never a copy (AC-3).
struct MoviePlaybackOpener: Sendable {
    let store: MovieStore
    let servers: FileServerStore
    let files: MovieFileStore
    var plexClient = PlexClient()

    enum Opened {
        case file(URL)
        /// The client stays connected for the playback; `close` lets it go.
        case stream(RemoteMovieStream, fileName: String, close: @Sendable () async -> Void)
    }

    enum Failure: LocalizedError {
        case noSource
        /// The Plex server cannot be reached, or the token was refused.
        case plexUnavailable

        var errorDescription: String? {
            switch self {
            case .noSource: String(localized: "This movie has nowhere to play from.", comment: "Movie player: a stream with no source")
            case .plexUnavailable: String(localized: "The Plex server can't be reached.", comment: "Movie player: Plex out of reach")
            }
        }
    }

    func open(_ movie: Movie) async throws -> Opened {
        if movie.isOnDevice, let file = files.file(for: movie), FileManager.default.fileExists(atPath: file.path) {
            return .file(file)
        }
        if let sourceId = movie.sourceId, let source = try store.source(id: sourceId), source.kind == .plex {
            return try await openPlex(movie, source: source)
        }
        guard let sourceId = movie.sourceId, let source = try store.source(id: sourceId),
              let connectionId = source.connectionId, let server = try servers.fetch(id: connectionId),
              let path = movie.remotePath else { throw Failure.noSource }
        let client = RemoteFileClientFactory.make(for: server, password: servers.password(for: connectionId) ?? "")
        try await client.connect()
        let size = try await client.fileSize(at: path) ?? movie.byteCount
        let chunk = server.transferProtocol == .sftp ? 128_000 : 1 << 20
        let stream = RemoteMovieStream(client: client, path: path, size: size, chunk: chunk)
        return .stream(stream, fileName: movie.originalFileName, close: { await client.disconnect() })
    }

    /// FS-23.07 §2: the original file, never a transcode — the version
    /// chosen for it, else the sharpest of several (AC-56) — by Range over the
    /// way in that answered last; the token stays in headers.
    private func openPlex(_ movie: Movie, source: MovieSource) async throws -> Opened {
        guard let key = movie.plexRatingKey, let token = store.plexToken(for: source.id) else { throw Failure.noSource }
        guard let base = try? await PlexLibrarySync(store: store, client: plexClient).baseURL(for: source, token: token) else { throw Failure.plexUnavailable }
        let item = try await plexClient.item(server: base, token: token, ratingKey: key)
        // The version chosen on the movie page, else the sharpest (FS-23.08 §4).
        guard let best = item.versions.first(where: { $0.partKey == movie.plexPartKey }) ?? item.versions.first else { throw Failure.noSource }
        // Separate subtitle files join the panel as `From Plex`.
        // Each version lists the same files: once each.
        var seen = Set<String>()
        let subtitles = item.subtitles.filter { $0.key.map { seen.insert($0).inserted } ?? false }.compactMap { subtitle -> ScannedSubtitle? in
            guard let path = subtitle.key, let format = MovieSubtitle.Format(rawValue: subtitle.codec ?? "srt") ?? .some(.srt) else { return nil }
            return ScannedSubtitle(remotePath: path, language: MovieLanguage.code(subtitle.languageCode), format: format, origin: .plex)
        }
        try? store.syncPlexSubtitles(movieId: movie.id, subtitles)
        let client = PlexFileClient(base: base, token: token, session: plexClient.session, client: plexClient)
        let stream = RemoteMovieStream(client: client, path: best.partKey, size: best.size, chunk: 4 << 20)
        let name = (best.file as NSString).lastPathComponent
        return .stream(stream, fileName: name.isEmpty ? movie.originalFileName : name, close: {})
    }
}
