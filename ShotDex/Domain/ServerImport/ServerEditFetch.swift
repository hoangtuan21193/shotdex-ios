import Foundation

/// One file of a server photo, downloaded and hashed.
struct FetchedFile: Sendable, Hashable {
    let file: RemoteEntry
    let url: URL
    let sha256: String
}

/// Downloads a server photo's files and checks each one (FS-17.02 §2) —
/// the part Import and the edit copy (FS-17.06 §4) share.
enum ServerPhotoFetch {
    enum Outcome: Sendable, Equatable {
        case fetched([FetchedFile])
        /// A file failed the check; the reason is for the user.
        case failed(String)
    }

    /// Every file of `item` into `folder`, then the check. Transport errors
    /// throw; a file that arrived but failed the check comes back as
    /// `.failed`, its bytes left for the caller to delete with the folder.
    static func fetch(
        _ item: ServerDownloadItem,
        client: any RemoteFileClient,
        into folder: URL,
        onChecking: @Sendable () -> Void = {},
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> Outcome {
        var local: [FetchedFile] = []
        var before: Int64 = 0
        for file in item.photo.files {
            let url = folder.appendingPathComponent(file.name)
            let offset = before
            let sha = try await client.download(item.path(of: file), to: url) { bytes in progress(offset + bytes) }
            local.append(FetchedFile(file: file, url: url, sha256: sha))
            before += file.size
        }
        onChecking()
        for fetched in local {
            if let reason = ServerDownloadSession.checkFailure(
                file: fetched.file, at: fetched.url, sha256: fetched.sha256, known: item.knownChecksums[fetched.file.name]
            ) {
                return .failed(reason)
            }
        }
        return .fetched(local)
    }
}

/// Room this device needs before a batch of originals comes down: their
/// bytes plus 1 GB, so the fetch never fills the disk the system also
/// writes to (FS-17.02 §1, FS-17.06 §4).
enum DeviceSpaceCheck {
    static let headroom: Int64 = 1_000_000_000

    /// Bytes short on this device for `bytes` plus the headroom, or nil when
    /// they fit — and when the free space is unknown.
    static func shortfall(for bytes: Int64, free: Int64?) -> Int64? {
        guard let free else { return nil }
        let needed = bytes + headroom
        return needed > free ? needed - free : nil
    }
}

/// Where the server calls of a browse run go through: one login, one call at
/// a time (`ServerBrowseSession`); a test hands it a plain client.
protocol RemoteFileAccess: Sendable {
    func perform<T: Sendable>(_ work: @Sendable (any RemoteFileClient) async throws -> T) async throws -> T
}

extension ServerBrowseSession: RemoteFileAccess {}

/// A server photo on this device, for the editor, a share or a copy
/// (FS-17.06 §4). The files stay until an export, a discard, or the launch
/// sweep.
struct FetchedServerPhoto: Sendable, Hashable, Identifiable {
    let serverId: String
    let folder: String
    let photo: ServerPhoto
    /// In `photo.files` order: the rendered twin first, then the RAW.
    let files: [FetchedFile]

    /// Names the photo across a run: connection, folder and file.
    var id: String { "\(serverId)|\(remotePath)" }

    /// The server path of the file an export lands next to.
    var remotePath: String { ServerUploadPath.join(folder, photo.primary.name) }

    var primaryURL: URL { files[0].url }

    var rawURL: URL? {
        guard let raw = photo.raw else { return nil }
        return files.first { $0.file == raw }?.url
    }
}

enum ServerEditFetchEvent: Sendable {
    case itemStarted(index: Int)
    case bytes(done: Int64, total: Int64)
}

struct ServerEditFetchResult: Sendable {
    /// Photos that arrived and passed the check, in the order asked.
    var photos: [FetchedServerPhoto]
    /// Photos that failed on their own, by index, with the reason.
    var failures: [Int: String]
    var stopReason: ServerUploadResult.StopReason?
}

/// Brings originals down to one work folder to edit them (FS-17.06 §4). The
/// same fetch and check as Import, but nothing is saved to Photos and the
/// files stay. Cancel, or a failure that will hit every later photo, deletes
/// the whole folder: there is nothing to edit from half a batch.
actor ServerEditFetch {
    let workDirectory: URL
    private let access: any RemoteFileAccess
    private let serverId: String
    private let onEvent: @Sendable (ServerEditFetchEvent) -> Void

    init(
        access: any RemoteFileAccess,
        serverId: String,
        workDirectory: URL,
        onEvent: @escaping @Sendable (ServerEditFetchEvent) -> Void = { _ in }
    ) {
        self.access = access
        self.serverId = serverId
        self.workDirectory = workDirectory
        self.onEvent = onEvent
    }

    func run(_ items: [ServerDownloadItem]) async -> ServerEditFetchResult {
        var result = ServerEditFetchResult(photos: [], failures: [:], stopReason: nil)
        let total = items.reduce(Int64(0)) { $0 + $1.photo.totalBytes }
        var done: Int64 = 0
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        } catch {
            result.stopReason = .error(.other(error.localizedDescription))
            return result
        }

        for (index, item) in items.enumerated() {
            if Task.isCancelled { return discard(result, .cancelled) }
            onEvent(.itemStarted(index: index))
            let folder = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let startedAt = done
            let onEvent = onEvent
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let outcome = try await access.perform { client in
                    try await ServerPhotoFetch.fetch(item, client: client, into: folder) { bytes in
                        onEvent(.bytes(done: startedAt + bytes, total: total))
                    }
                }
                try Task.checkCancellation()
                switch outcome {
                case .fetched(let files):
                    result.photos.append(FetchedServerPhoto(serverId: serverId, folder: item.folder, photo: item.photo, files: files))
                case .failed(let reason):
                    try? FileManager.default.removeItem(at: folder)
                    result.failures[index] = reason
                }
            } catch is CancellationError {
                return discard(result, .cancelled)
            } catch let error as RemoteFileError where error.stopsBatch {
                return discard(result, .error(error))
            } catch {
                try? FileManager.default.removeItem(at: folder)
                result.failures[index] = error.localizedDescription
            }
            done = startedAt + item.photo.totalBytes
            onEvent(.bytes(done: done, total: total))
        }
        return result
    }

    private func discard(_ result: ServerEditFetchResult, _ reason: ServerUploadResult.StopReason) -> ServerEditFetchResult {
        try? FileManager.default.removeItem(at: workDirectory)
        return ServerEditFetchResult(photos: [], failures: result.failures, stopReason: reason)
    }
}
