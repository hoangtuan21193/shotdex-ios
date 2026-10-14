import Foundation
import Observation

/// Keeps Movies in step with its sources (FS-23.01 §2, FS-23.07): adds one,
/// and rescans them all when Movies opens — folders through their
/// connection, Plex servers through `PlexLibrarySync`.
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
        // Named after the connection: rows and alerts say where a movie
        // lives ("NAS Home · 2:04:01", "The movie stays on NAS Home").
        let source = MovieSource(kind: .folder, name: server.name, connectionId: server.id, folder: normalized)
        try movies.saveSource(source)
        return try await refresh(source)
    }

    /// Every folder source, one after another (one connection is one
    /// session; two sources on one NAS should not race it).
    func refreshAll() async {
        for source in (try? movies.sources()) ?? [] {
            switch source.kind {
            case .folder: _ = try? await refresh(source)
            case .plex: await refreshPlex(source)
            }
        }
    }

    /// Saves a Plex server as a source with its token, and lists it.
    @discardableResult
    func addPlex(_ server: PlexClient.Server, address: URL?, libraries: [String]) async -> MovieStore.ScanMerge {
        let encoded = (try? String(decoding: JSONEncoder().encode(libraries), as: UTF8.self)) ?? "[]"
        let source = MovieSource(
            kind: .plex, name: server.name, plexMachineId: server.machineId,
            plexAddress: address?.absoluteString, plexLibraries: encoded
        )
        try? movies.saveSource(source, plexToken: server.accessToken)
        return await refreshPlex(source)
    }

    @discardableResult
    func refreshPlex(_ source: MovieSource) async -> MovieStore.ScanMerge {
        scanning.insert(source.id)
        defer { scanning.remove(source.id) }
        return await PlexLibrarySync(store: movies).refresh(source)
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
    @discardableResult nonisolated static func scan(_ source: MovieSource, client: any RemoteFileClient, store: MovieStore) async throws -> MovieStore.ScanMerge {
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
