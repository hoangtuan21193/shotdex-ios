import Foundation
import GRDB

/// A server photo's original on this device while the viewer or editor has
/// it open (FS-19.03 §5). Leaving drops it; the launch sweep takes whatever
/// a crash left behind.
final class ServerOriginal: Sendable {
    let url: URL
    let directory: URL

    init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Brings one server copy's original down to a scratch folder — never into
/// Photos, never into the preview cache: originals are not kept (FS-19.03 §5).
struct ServerOriginalLoader: Sendable {
    let database: AppDatabase
    let servers: FileServerStore
    var makeClient: @Sendable (FileServer, String) -> any RemoteFileClient = { RemoteFileClientFactory.make(for: $0, password: $1) }
    var workDirectory = FileManager.default.temporaryDirectory
    /// Free bytes on this device; nil when unknown.
    var freeSpace: @Sendable () -> Int64? = {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    enum Failure: Error, Equatable {
        case notAServerCopy
        /// Bytes short, headroom included (`DeviceSpaceCheck`).
        case notEnoughSpace(Int64)
    }

    /// `progress` gets bytes so far; a RAW over 25 MB shows it with Cancel,
    /// and cancelling the task deletes what came down.
    func load(copyId: String, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> ServerOriginal {
        let found: (path: String?, size: Int64?, connectionId: String?)? = try await database.reader.read { db in
            try Row.fetchOne(db, sql: """
                SELECT c.relativePath, c.size, s.connectionId FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.id = ? AND c.kind = 'server'
                """, arguments: [copyId]).map { ($0["relativePath"], $0["size"], $0["connectionId"]) }
        }
        guard let found, let relativePath = found.path, let connectionId = found.connectionId,
              let server = try servers.fetch(id: connectionId)
        else { throw Failure.notAServerCopy }
        if let short = DeviceSpaceCheck.shortfall(for: found.size ?? 0, free: freeSpace()) {
            throw Failure.notEnoughSpace(short)
        }
        let directory = workDirectory.appendingPathComponent(TemporaryWorkspace.serverEditPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = ServerOriginal(url: directory.appendingPathComponent((relativePath as NSString).lastPathComponent), directory: directory)
        let client = makeClient(server, servers.password(for: server.id) ?? "")
        do {
            try await client.connect()
            try await client.download(ServerUploadPath.join(server.folder, relativePath), to: original.url, progress: progress)
            await client.disconnect()
            return original
        } catch {
            await client.disconnect()
            original.discard()
            throw error
        }
    }
}
