import Foundation
import Observation

/// Keeps Movies in step with its folder sources (FS-23.01 §2): adds one,
/// and rescans them all when Movies opens. Plex sources join in plan task
/// 30.
@MainActor
@Observable
final class MovieSourceSync {
    private let movies: MovieStore
    private let servers: FileServerStore
    /// Sources being listed now.
    private(set) var scanning: Set<String> = []

    init(movies: MovieStore, servers: FileServerStore) {
        self.movies = movies
        self.servers = servers
    }

    /// Saves a folder on `server` as a source and lists it.
    @discardableResult
    func addFolder(_ folder: String, on server: FileServer) async throws -> MovieStore.ScanMerge {
        let normalized = ServerUploadPath.normalizedFolder(folder)
        let last = ServerUploadPath.lastComponent(of: normalized)
        let source = MovieSource(
            kind: .folder,
            name: last.isEmpty ? server.name : String(localized: "\(last) on \(server.name)", comment: "Movies source name: a folder on a connection"),
            connectionId: server.id, folder: normalized
        )
        try movies.saveSource(source)
        return try await refresh(source)
    }

    /// Every folder source, one after another (one connection is one
    /// session; two sources on one NAS should not race it).
    func refreshAll() async {
        let sources = ((try? movies.sources()) ?? []).filter { $0.kind == .folder }
        for source in sources {
            _ = try? await refresh(source)
        }
    }

    @discardableResult
    func refresh(_ source: MovieSource) async throws -> MovieStore.ScanMerge {
        guard source.kind == .folder, let connectionId = source.connectionId,
              let server = try servers.fetch(id: connectionId) else { return MovieStore.ScanMerge() }
        scanning.insert(source.id)
        defer { scanning.remove(source.id) }
        let client = RemoteFileClientFactory.make(for: server, password: servers.password(for: server.id) ?? "")
        return try await Self.scan(source, client: client, store: movies)
    }

    /// The part a test drives with an in-memory server.
    nonisolated static func scan(_ source: MovieSource, client: any RemoteFileClient, store: MovieStore) async throws -> MovieStore.ScanMerge {
        do {
            try await client.connect()
        } catch {
            try store.setReachable(false, sourceId: source.id)
            return MovieStore.ScanMerge()
        }
        let result = await MovieFolderScanner.scan(client, folder: source.folder)
        await client.disconnect()
        try store.setReachable(result.reachedRoot, sourceId: source.id)
        guard result.reachedRoot else { return MovieStore.ScanMerge() }
        return try store.mergeScan(sourceId: source.id, found: result.movies, isComplete: result.isComplete)
    }
}
