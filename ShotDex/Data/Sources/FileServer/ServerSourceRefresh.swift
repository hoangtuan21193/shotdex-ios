import Foundation
import GRDB

/// When a server source's listing is compared again (FS-19.03 §3): once
/// when the app opens, when its server comes back from Not reachable, and
/// on Rescan. Never on a timer — each pass lists the whole tree on the NAS,
/// and SMB, SFTP and WebDAV say nothing reliable about changes in between.
actor ServerSourceRefresh {
    let database: AppDatabase
    let servers: FileServerStore
    let composer: MetadataComposer
    let thumbnails: FolderThumbnails?
    let makeClient: @Sendable (FileServer, String) -> any RemoteFileClient

    private var hasRunAtLaunch = false
    /// Sources mid-pass: a second trigger while one runs is the same pass.
    private var running: Set<String> = []

    init(database: AppDatabase, servers: FileServerStore, composer: MetadataComposer, thumbnails: FolderThumbnails? = nil,
         makeClient: @escaping @Sendable (FileServer, String) -> any RemoteFileClient = { RemoteFileClientFactory.make(for: $0, password: $1) }) {
        self.database = database
        self.servers = servers
        self.composer = composer
        self.thumbnails = thumbnails
        self.makeClient = makeClient
    }

    /// The app opened: every server source once, however often the scene
    /// comes back to the foreground after that.
    @discardableResult
    func appLaunched() async -> [String: ServerSourceIndexer.Summary] {
        guard !hasRunAtLaunch else { return [:] }
        hasRunAtLaunch = true
        var out: [String: ServerSourceIndexer.Summary] = [:]
        for sourceId in (try? serverSourceIds()) ?? [] {
            out[sourceId] = await refresh(sourceId)
        }
        return out
    }

    /// The network or the server came back. Only a source that was offline
    /// is compared; one that never left is not.
    @discardableResult
    func serverReachable(sourceId: String) async -> ServerSourceIndexer.Summary? {
        let status = try? await database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM sources WHERE id = ? AND kind = 'server'", arguments: [sourceId])
        }
        guard status == "offline" else { return nil }
        return await refresh(sourceId)
    }

    /// Rescan in the source's browse toolbar.
    @discardableResult
    func rescan(sourceId: String) async -> ServerSourceIndexer.Summary? {
        await refresh(sourceId)
    }

    private func serverSourceIds() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM sources WHERE kind = 'server' ORDER BY createdAt, id")
        }
    }

    private func refresh(_ sourceId: String) async -> ServerSourceIndexer.Summary? {
        guard running.insert(sourceId).inserted else { return nil }
        defer { running.remove(sourceId) }
        let found: (connectionId: String?, pairs: Bool)? = try? await database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT connectionId, pairsRawAndJpeg FROM sources WHERE id = ?", arguments: [sourceId])
                .map { ($0["connectionId"], $0["pairsRawAndJpeg"]) }
        }
        guard let found, let connectionId = found.connectionId,
              let server = try? servers.fetch(id: connectionId)
        else { return nil }
        let client = makeClient(server, servers.password(for: server.id) ?? "")
        let indexer = ServerSourceIndexer(database: database, composer: composer, client: client, thumbnails: thumbnails)
        return try? await indexer.index(sourceId: sourceId, folder: server.folder, pairsRawAndJpeg: found.pairs)
    }
}
