import CoreGraphics
import Foundation

/// One server call at a time per connection, shared by Backup, Upload and the
/// server-source index (FS-19.07 §5). Backup goes first when both wait; the
/// lock is taken per call, so it frees between files and is never held while
/// an original downloads from iCloud.
actor ConnectionLock {
    enum Priority: Int, Comparable, Sendable {
        case normal, backup

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Waiter {
        let priority: Priority
        let order: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var busy: Set<String> = []
    private var waiters: [String: [Waiter]] = [:]
    private var nextOrder = 0

    func acquire(_ connectionId: String, priority: Priority) async {
        guard busy.contains(connectionId) else {
            busy.insert(connectionId)
            return
        }
        nextOrder += 1
        let order = nextOrder
        await withCheckedContinuation { continuation in
            waiters[connectionId, default: []].append(Waiter(priority: priority, order: order, continuation: continuation))
        }
    }

    /// Hands the connection to the highest-priority waiter, oldest first.
    func release(_ connectionId: String) {
        guard var queue = waiters[connectionId], !queue.isEmpty else {
            busy.remove(connectionId)
            return
        }
        let next = queue.indices.max { a, b in
            queue[a].priority != queue[b].priority ? queue[a].priority < queue[b].priority : queue[a].order > queue[b].order
        }!
        let waiter = queue.remove(at: next)
        waiters[connectionId] = queue.isEmpty ? nil : queue
        waiter.continuation.resume()
    }

    /// Runs `work` holding the connection. A caller cancelled while waiting
    /// still takes its turn, then throws instead of working.
    func run<T: Sendable>(_ connectionId: String, priority: Priority,
                          _ work: @Sendable () async throws -> T) async throws -> T {
        await acquire(connectionId, priority: priority)
        do {
            try Task.checkCancellation()
            let value = try await work()
            release(connectionId)
            return value
        } catch {
            release(connectionId)
            throw error
        }
    }

    /// Callers queued behind the holder — for tests.
    func waitingCount(_ connectionId: String) -> Int { waiters[connectionId]?.count ?? 0 }

    func isHeld(_ connectionId: String) -> Bool { busy.contains(connectionId) }

    func runQuietly<T: Sendable>(_ connectionId: String, priority: Priority, _ work: @Sendable () async -> T) async -> T {
        await acquire(connectionId, priority: priority)
        let value = await work()
        release(connectionId)
        return value
    }
}

/// A client whose every call waits its turn on the connection's lock.
final class LockedRemoteFileClient: RemoteFileClient {
    private let base: any RemoteFileClient
    private let lock: ConnectionLock
    private let connectionId: String
    private let priority: ConnectionLock.Priority

    init(_ base: any RemoteFileClient, lock: ConnectionLock, connectionId: String, priority: ConnectionLock.Priority) {
        self.base = base
        self.lock = lock
        self.connectionId = connectionId
        self.priority = priority
    }

    private func locked<T: Sendable>(_ work: @Sendable (any RemoteFileClient) async throws -> T) async throws -> T {
        let base = base
        return try await lock.run(connectionId, priority: priority) { try await work(base) }
    }

    func connect() async throws { try await locked { try await $0.connect() } }

    func disconnect() async {
        let base = base
        await lock.runQuietly(connectionId, priority: priority) { await base.disconnect() }
    }

    func fileSize(at path: String) async throws -> Int64? { try await locked { try await $0.fileSize(at: path) } }
    func directoryExists(_ path: String) async throws -> Bool { try await locked { try await $0.directoryExists(path) } }
    func fileNames(in directory: String) async throws -> Set<String> { try await locked { try await $0.fileNames(in: directory) } }
    func folderNames(in directory: String) async throws -> Set<String> { try await locked { try await $0.folderNames(in: directory) } }
    func createDirectory(_ path: String) async throws { try await locked { try await $0.createDirectory(path) } }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await locked { try await $0.upload(localURL, to: path, progress: progress) }
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await locked { try await $0.sha256(of: path, progress: progress) }
    }

    func entries(in directory: String) async throws -> [RemoteEntry] { try await locked { try await $0.entries(in: directory) } }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        try await locked { try await $0.readRange(path, offset: offset, length: length) }
    }

    @discardableResult
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await locked { try await $0.download(path, to: localURL, progress: progress) }
    }

    func move(_ source: String, to destination: String) async throws { try await locked { try await $0.move(source, to: destination) } }
    func remove(_ path: String) async throws { try await locked { try await $0.remove(path) } }
    func removeEmptyDirectory(_ path: String) async throws { try await locked { try await $0.removeEmptyDirectory(path) } }
    func removeFolderTree(_ path: String) async throws { try await locked { try await $0.removeFolderTree(path) } }
    func storageSpace(at path: String) async throws -> StorageSpace? { try await locked { try await $0.storageSpace(at: path) } }

    var peeksWithSystemThumbnails: Bool { base.peeksWithSystemThumbnails }

    func systemThumbnail(at path: String, maxPixelSize: Int) async -> CGImage? {
        let base = base
        return await lock.runQuietly(connectionId, priority: priority) { await base.systemThumbnail(at: path, maxPixelSize: maxPixelSize) }
    }
}
