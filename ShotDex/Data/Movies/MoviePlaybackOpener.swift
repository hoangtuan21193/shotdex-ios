import Foundation

/// What Play opens (FS-23.01 §3): the file on the device, or a stream from
/// the movie's source over its saved connection — never a copy (AC-3).
struct MoviePlaybackOpener: Sendable {
    let store: MovieStore
    let servers: FileServerStore
    let files: MovieFileStore

    enum Opened {
        case file(URL)
        /// The client stays connected for the playback; `close` lets it go.
        case stream(RemoteMovieStream, fileName: String, close: @Sendable () async -> Void)
    }

    enum Failure: LocalizedError {
        case noSource

        var errorDescription: String? {
            String(localized: "This movie has nowhere to play from.", comment: "Movie player: a stream with no source")
        }
    }

    func open(_ movie: Movie) async throws -> Opened {
        if movie.isOnDevice, let file = files.file(for: movie), FileManager.default.fileExists(atPath: file.path) {
            return .file(file)
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
}
