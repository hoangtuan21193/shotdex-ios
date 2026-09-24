import CryptoKit
import Foundation
import SMBClient

/// `RemoteFileClient` over SMB 2/3 (SMBClient, MIT). Paths are relative to
/// the share.
///
/// `@unchecked Sendable` because SMBClient's session is a plain class: the
/// upload session calls one method at a time and awaits each, so nothing
/// here runs concurrently with itself.
final class SMBFileClient: RemoteFileClient, @unchecked Sendable {
    private let server: FileServer
    private let password: String
    private var client: SMBClient?

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
        do {
            try await client.connectShare(server.share)
        } catch {
            throw RemoteFileError.folderMissing(server.share)
        }
        self.client = client
    }

    func disconnect() async {
        guard let client else { return }
        self.client = nil
        _ = try? await client.disconnectShare()
        _ = try? await client.logoff()
    }

    private func connected() throws -> SMBClient {
        guard let client else { throw RemoteFileError.connectionLost }
        return client
    }

    func fileSize(at path: String) async throws -> Int64? {
        do {
            let stat = try await connected().fileStat(path: path)
            return stat.isDirectory ? nil : Int64(stat.size)
        } catch {
            if Self.isNotFound(error) { return nil }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        do {
            let files = try await connected().listDirectory(path: directory)
            return Set(files.filter { !$0.isDirectory && $0.name != "." && $0.name != ".." }.map(\.name))
        } catch {
            if Self.isNotFound(error) { return [] }
            throw Self.map(error, host: server.host, path: directory)
        }
    }

    func createDirectory(_ path: String) async throws {
        let client = try connected()
        var current = ""
        for component in path.split(separator: "/") {
            current = ServerUploadPath.join(current, String(component))
            do {
                if try await client.existDirectory(path: current) { continue }
                try await client.createDirectory(path: current)
            } catch {
                throw Self.map(error, host: server.host, path: current)
            }
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        let total = (try? handle.seekToEnd()).map { Int64($0) } ?? 0
        try handle.seek(toOffset: 0)
        do {
            try await connected().upload(fileHandle: handle, path: path) { fraction in
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
            let client = try connected()
            let size = try await client.fileStat(path: path).size
            let reader = client.fileReader(path: path)
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

    func download(_ path: String, to localURL: URL) async throws {
        do {
            try await connected().download(path: path, localPath: localURL, overwrite: true)
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func move(_ source: String, to destination: String) async throws {
        do {
            try await connected().move(from: source, to: destination)
        } catch {
            throw Self.map(error, host: server.host, path: destination)
        }
    }

    func remove(_ path: String) async throws {
        do {
            try await connected().deleteFile(path: path)
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
            if status == .badNetworkName || status == .objectPathNotFound || status == .objectNameNotFound {
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
            case .disconnected, .noData, .unknown: return RemoteFileError.connectionLost
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
