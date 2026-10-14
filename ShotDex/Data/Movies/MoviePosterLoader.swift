import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Posters for the Movies grid (FS-23.01 §4, AC-43), following the
/// resolver's order: the image beside the movie, then an MP4's own cover.
/// Fetched once into `Caches/MovieArt/<id>.jpg` (FS-23.05 §1 — a cache, so
/// the system may clear it and it is fetched again); a movie with nothing
/// is remembered for the session, so scrolling never asks twice. One
/// request at a time per connection.
actor MoviePosterLoader {
    private let movies: MovieStore
    private let servers: FileServerStore
    let directory: URL
    private var clients: [String: (client: any RemoteFileClient, gate: AsyncGate)] = [:]
    private var nothing: Set<String> = []
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    /// A sidecar image larger than this is not a poster.
    static let maxImageBytes: Int64 = 12 << 20

    init(movies: MovieStore, servers: FileServerStore, directory: URL? = nil) {
        self.movies = movies
        self.servers = servers
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "MovieArt", directoryHint: .isDirectory)
    }

    func cachedFile(for movieId: String) -> URL {
        directory.appending(path: "\(movieId).jpg")
    }

    /// The cache file of what was fetched, and for which identity.
    private func stampFile(for movieId: String) -> URL {
        directory.appending(path: "\(movieId).id")
    }

    /// What a poster depends on: a file replaced on the NAS (new size) or a
    /// new poster beside it is a new look.
    static func identity(_ movie: Movie) -> String {
        "\(movie.id)-\(movie.byteCount)-\(movie.posterPath ?? "")"
    }

    /// nil = draw the title tile.
    func poster(for movie: Movie, maxPixelSize: Int) async -> CGImage? {
        let identity = Self.identity(movie)
        let key = "\(identity)@\(maxPixelSize)"
        if nothing.contains(identity) { return nil }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await self.load(movie, maxPixelSize: maxPixelSize) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    /// A rescan found a new poster, or the user wants another try.
    func forget(_ movieId: String) {
        nothing = nothing.filter { !$0.hasPrefix(movieId + "-") }
        try? FileManager.default.removeItem(at: cachedFile(for: movieId))
        try? FileManager.default.removeItem(at: stampFile(for: movieId))
    }

    private func load(_ movie: Movie, maxPixelSize: Int) async -> CGImage? {
        let file = cachedFile(for: movie.id)
        let identity = Self.identity(movie)
        let stamp = stampFile(for: movie.id)
        if (try? String(contentsOf: stamp, encoding: .utf8)) == identity,
           let image = Self.thumbnail(at: file, maxPixelSize: maxPixelSize) { return image }
        guard let bytes = await fetch(movie) else {
            nothing.insert(identity)
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? bytes.write(to: file, options: .atomic)
        try? identity.write(to: stamp, atomically: true, encoding: .utf8)
        guard let image = Self.thumbnail(at: file, maxPixelSize: maxPixelSize) else {
            try? FileManager.default.removeItem(at: file)
            nothing.insert(identity)
            return nil
        }
        return image
    }

    private func fetch(_ movie: Movie) async -> Data? {
        guard let sourceId = movie.sourceId, let source = try? movies.source(id: sourceId),
              source.kind == .folder, let connectionId = source.connectionId,
              let (client, gate) = await connection(connectionId) else { return nil }
        let candidates = MoviePosterResolver.candidates(
            fileName: movie.originalFileName, siblings: [], canOpenFile: false, title: movie.displayTitle, palette: 1
        )
        await gate.enter()
        defer { Task { await gate.leave() } }
        if let path = movie.posterPath,
           let size = try? await client.fileSize(at: path), size > 0, size <= Self.maxImageBytes,
           let data = try? await client.readRange(path, offset: 0, length: Int(size)), !data.isEmpty {
            return data
        }
        if candidates.contains(.embeddedMP4), let path = movie.remotePath {
            return try? await MP4CoverArt.find(size: movie.byteCount) { offset, length in
                try await client.readRange(path, offset: offset, length: length)
            }
        }
        return nil
    }

    private func connection(_ id: String) async -> (any RemoteFileClient, AsyncGate)? {
        if let open = clients[id] { return (open.client, open.gate) }
        guard let server = try? servers.fetch(id: id) else { return nil }
        let client = RemoteFileClientFactory.make(for: server, password: servers.password(for: id) ?? "")
        do { try await client.connect() } catch { return nil }
        let gate = AsyncGate()
        clients[id] = (client, gate)
        return (client, gate)
    }

    /// Closes the connections; the next poster opens them again.
    func closeConnections() async {
        let open = clients.values.map(\.client)
        clients = [:]
        for client in open { await client.disconnect() }
    }

    /// Decoded straight to the grid's size — a 4 MB poster.jpg is never
    /// held at full size.
    static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
