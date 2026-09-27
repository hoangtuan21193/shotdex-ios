import CryptoKit
import Foundation
import SMBClient

/// `RemoteFileClient` over SMB 2/3 (SMBClient, MIT). Paths start at the
/// machine: the first component is the shared folder (FS-15.01 §3a), so
/// one login browses every share and the root lists them.
///
/// `@unchecked Sendable` because SMBClient's session is a plain class: the
/// upload session calls one method at a time and awaits each, so nothing
/// here runs concurrently with itself.
final class SMBFileClient: RemoteFileClient, @unchecked Sendable {
    private let server: FileServer
    private let password: String
    private var client: SMBClient?
    /// The share the session's tree is connected to.
    private var connectedShare: String?

    init(server: FileServer, password: String) {
        self.server = server
        self.password = password
    }

    func connect() async throws {
        let client = SMBClient(host: server.host, port: server.port)
        do {
            _ = try await withConnectTimeout(host: server.host) {
                try await client.login(username: self.server.username, password: self.password)
            }
        } catch {
            throw Self.map(error, host: server.host, path: "")
        }
        self.client = client
        connectedShare = nil
    }

    /// The shares `host` offers this login, system shares left out.
    static func shareNames(host: String, port: Int, username: String, password: String) async throws -> [String] {
        let client = SMBClient(host: host, port: port)
        do {
            _ = try await withConnectTimeout(host: host) {
                try await client.login(username: username, password: password)
            }
            let shares = try await client.listShares()
            _ = try? await client.logoff()
            return SMBShareNames.visible(shares.map(\.name))
        } catch {
            _ = try? await client.logoff()
            throw map(error, host: host, path: "")
        }
    }

    func disconnect() async {
        guard let client else { return }
        self.client = nil
        if connectedShare != nil { _ = try? await client.disconnectShare() }
        connectedShare = nil
        _ = try? await client.logoff()
    }

    private func connected() throws -> SMBClient {
        guard let client else { throw RemoteFileError.connectionLost }
        return client
    }

    /// The client with `path`'s share connected, and the path inside that
    /// share; nil for the machine's root. Moving to another share swaps the
    /// tree within the same login.
    private func open(_ path: String) async throws -> (client: SMBClient, rest: String)? {
        let client = try connected()
        guard let (share, rest) = SMBPath.split(path) else { return nil }
        if share != connectedShare {
            if connectedShare != nil { _ = try? await client.disconnectShare() }
            connectedShare = nil
            do {
                try await client.connectShare(share)
            } catch {
                let mapped = Self.map(error, host: server.host, path: share)
                if case RemoteFileError.other = mapped { throw RemoteFileError.folderMissing(share) }
                throw mapped
            }
            connectedShare = share
        }
        return (client, rest)
    }

    /// Like `open`, for work that needs a share: nothing but the share list
    /// lives at the root, so a file there is refused.
    private func openInShare(_ path: String) async throws -> (client: SMBClient, rest: String) {
        guard let opened = try await open(path) else { throw RemoteFileError.permissionDenied("/") }
        return opened
    }

    private func shareEntries() async throws -> [RemoteEntry] {
        do {
            let shares = try await connected().listShares()
            return SMBShareNames.visible(shares.map(\.name)).map {
                RemoteEntry(name: $0, isDirectory: true, size: 0, modified: nil)
            }
        } catch {
            throw Self.map(error, host: server.host, path: "")
        }
    }

    func fileSize(at path: String) async throws -> Int64? {
        do {
            guard let (client, rest) = try await open(path), !rest.isEmpty else { return nil }
            let stat = try await client.fileStat(path: rest)
            return stat.isDirectory ? nil : Int64(stat.size)
        } catch {
            if Self.isNotFound(error) { return nil }
            if case RemoteFileError.folderMissing = error { return nil }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func directoryExists(_ path: String) async throws -> Bool {
        do {
            guard let (client, rest) = try await open(path) else { return true }
            if rest.isEmpty { return true }
            return try await client.existDirectory(path: rest)
        } catch {
            if Self.isNotFound(error) { return false }
            if case RemoteFileError.folderMissing = error { return false }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter { !$0.isDirectory }.map(\.name))
    }

    func folderNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter(\.isDirectory).map(\.name))
    }

    func createDirectory(_ path: String) async throws {
        // A share cannot be made from here; opening it proves it is there.
        guard let (client, rest) = try await open(path) else { return }
        var current = ""
        for component in rest.split(separator: "/") {
            current = ServerUploadPath.join(current, String(component))
            do {
                // A missing folder comes back as STATUS_NO_SUCH_FILE from some
                // servers rather than as `false` — measured against Samba-style
                // servers; either answer means "make it".
                let exists: Bool
                do {
                    exists = try await client.existDirectory(path: current)
                } catch where Self.isNotFound(error) {
                    exists = false
                }
                if exists { continue }
                try await client.createDirectory(path: current)
            } catch {
                throw Self.map(error, host: server.host, path: ServerUploadPath.join(SMBPath.split(path)?.share ?? "", current))
            }
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        let total = (try? handle.seekToEnd()).map { Int64($0) } ?? 0
        try handle.seek(toOffset: 0)
        do {
            let (client, rest) = try await openInShare(path)
            try await client.upload(fileHandle: handle, path: rest) { fraction in
                progress(Int64(fraction * Double(total)))
            }
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
        try Task.checkCancellation()
        progress(total)
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        do {
            let (client, rest) = try await openInShare(path)
            let size = try await client.fileStat(path: rest).size
            let reader = client.fileReader(path: rest)
            var hasher = SHA256()
            var offset: UInt64 = 0
            while offset < size {
                try Task.checkCancellation()
                let chunk = try await reader.read(offset: offset, length: UInt32(FileChecksum.chunkSize))
                guard !chunk.isEmpty else { break }
                hasher.update(data: chunk)
                offset += UInt64(chunk.count)
                progress(Int64(offset))
            }
            try? await reader.close()
            return FileChecksum.hex(hasher.finalize())
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func entries(in directory: String) async throws -> [RemoteEntry] {
        do {
            guard let (client, rest) = try await open(directory) else { return try await shareEntries() }
            let files = try await client.listDirectory(path: rest)
            return files
                .filter { $0.name != "." && $0.name != ".." }
                .map { RemoteEntry(name: $0.name, isDirectory: $0.isDirectory, size: Int64($0.size), modified: $0.lastWriteTime) }
        } catch {
            if Self.isNotFound(error) { return [] }
            throw Self.map(error, host: server.host, path: directory)
        }
    }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        do {
            let (client, rest) = try await openInShare(path)
            let reader = client.fileReader(path: rest)
            defer { Task { try? await reader.close() } }
            var result = Data()
            var position = UInt64(offset)
            while result.count < length {
                try Task.checkCancellation()
                let want = min(length - result.count, FileChecksum.chunkSize)
                let chunk = try await reader.read(offset: position, length: UInt32(want))
                guard !chunk.isEmpty else { break }
                result.append(chunk)
                position += UInt64(chunk.count)
            }
            return result
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        do {
            let (client, rest) = try await openInShare(path)
            let size = try await client.fileStat(path: rest).size
            let reader = client.fileReader(path: rest)
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: localURL)
            defer { try? out.close() }
            var hasher = SHA256()
            var offset: UInt64 = 0
            while offset < size {
                try Task.checkCancellation()
                let chunk = try await reader.read(offset: offset, length: UInt32(FileChecksum.chunkSize))
                guard !chunk.isEmpty else { break }
                try out.write(contentsOf: chunk)
                hasher.update(data: chunk)
                offset += UInt64(chunk.count)
                progress(Int64(offset))
            }
            try? await reader.close()
            return FileChecksum.hex(hasher.finalize())
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func move(_ source: String, to destination: String) async throws {
        guard let from = SMBPath.split(source), let to = SMBPath.split(destination),
              !from.rest.isEmpty, !to.rest.isEmpty else {
            throw RemoteFileError.permissionDenied(source)
        }
        guard from.share == to.share else {
            throw RemoteFileError.other(String(localized: "Items can't be moved between shared folders.", comment: "File server error: SMB rename across shares"))
        }
        do {
            let (client, _) = try await openInShare(source)
            try await client.move(from: from.rest, to: to.rest)
        } catch {
            throw Self.map(error, host: server.host, path: destination)
        }
    }

    func remove(_ path: String) async throws {
        do {
            let (client, rest) = try await openInShare(path)
            guard !rest.isEmpty else { throw RemoteFileError.permissionDenied(path) }
            try await client.deleteFile(path: rest)
        } catch {
            if Self.isNotFound(error) { return }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    /// The share's size and what this account may still write
    /// (`FileFsSizeInformation`); nil at the machine's root, where each share
    /// may be a different volume.
    func storageSpace(at path: String) async throws -> StorageSpace? {
        do {
            guard let (client, _) = try await open(path) else { return nil }
            // FileFsSizeInformation is class 3 of the file-system info
            // classes; SMBClient keeps that alias internal, and 3 is
            // `.fileBothDirectoryInformation` in its shared enum.
            let response = try await client.session.queryInfo(path: "", infoType: .fileSystem, fileInfoClass: .fileBothDirectoryInformation)
            let size = FileFsSizeInformation(data: response.buffer)
            return StorageSpaceReading.smb(
                totalUnits: size.totalAllocationUnits, freeUnits: size.availableAllocationUnits,
                sectorsPerUnit: size.sectorsPerAllocationUnit, bytesPerSector: size.bytesPerSector
            )
        } catch {
            return nil
        }
    }

    func removeEmptyDirectory(_ path: String) async throws {
        do {
            let (client, rest) = try await openInShare(path)
            // A share is the computer's to remove, not ShotDex's.
            guard !rest.isEmpty else { throw RemoteFileError.permissionDenied(path) }
            try await client.deleteDirectory(path: rest)
        } catch {
            if Self.isNotFound(error) { return }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    // MARK: - Errors

    /// `STATUS_DISK_FULL`; SMBClient's enum does not name it.
    private static let diskFull: UInt32 = 0xC000_007F

    private static func isNotFound(_ error: Error) -> Bool {
        guard let response = error as? ErrorResponse else { return false }
        let status = NTStatus(response.header.status)
        return status == .objectNameNotFound || status == .objectPathNotFound || status == .noSuchFile
    }

    static func map(_ error: Error, host: String, path: String) -> Error {
        if error is CancellationError || error is RemoteFileError { return error }
        if let response = error as? ErrorResponse {
            let status = NTStatus(response.header.status)
            if status == .logonFailure { return RemoteFileError.authenticationFailed }
            if status == .accessDenied { return RemoteFileError.permissionDenied(path) }
            if status == .badNetworkName || status == .objectPathNotFound || status == .objectNameNotFound || status == .noSuchFile {
                return RemoteFileError.folderMissing(path)
            }
            if response.header.status == diskFull { return RemoteFileError.serverFull }
            if status == .networkNameDeleted || status == .userSessionDeleted || status == .networkSessionExpired {
                return RemoteFileError.connectionLost
            }
            return RemoteFileError.other(response.localizedDescription)
        }
        if let connection = error as? ConnectionError {
            switch connection {
            case .cancelled: return CancellationError()
            case .disconnected, .unknown: return RemoteFileError.connectionLost
            }
        }
        return mapNetworkError(error, host: host)
    }
}

/// POSIX / Network framework errors from either library, in the user's terms.
func mapNetworkError(_ error: Error, host: String) -> Error {
    let nsError = error as NSError
    // The system refused local-network access (the user said Don't Allow).
    if nsError.domain == "NWErrorDomain" || nsError.domain == NSPOSIXErrorDomain {
        switch Int32(nsError.code) {
        case EPERM, EACCES: return RemoteFileError.localNetworkDenied
        case ECONNREFUSED, EHOSTUNREACH, ENETUNREACH, ETIMEDOUT, EHOSTDOWN: return RemoteFileError.unreachable(host: host)
        case ECONNRESET, EPIPE, ENOTCONN: return RemoteFileError.connectionLost
        default: break
        }
    }
    if nsError.domain == "kCFErrorDomainCFNetwork" || nsError.domain == NSURLErrorDomain {
        return RemoteFileError.unreachable(host: host)
    }
    return RemoteFileError.other(nsError.localizedDescription)
}

/// Ten seconds to reach a machine on the LAN, then "Can't reach". Neither
/// library bounds its own connect in a way the Settings test can wait on.
func withConnectTimeout<T>(
    host: String,
    seconds: Double = 10,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: Optional<T>.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw RemoteFileError.unreachable(host: host)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next(), let value = first else {
            throw RemoteFileError.unreachable(host: host)
        }
        return value
    }
}
