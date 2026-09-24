import CryptoKit
import Foundation

/// What an upload needs from a file server, whatever the protocol. Paths are
/// relative to the server's root — the share for SMB, the login's home for
/// SFTP — and use `/`.
///
/// A protocol so the session (and every failure it has to survive) runs in a
/// unit test against an in-memory server; the SMB and SFTP clients are thin
/// adapters over their libraries.
protocol RemoteFileClient: AnyObject, Sendable {
    func connect() async throws
    func disconnect() async
    /// Size of the file at `path`, nil when nothing is there.
    func fileSize(at path: String) async throws -> Int64?
    func directoryExists(_ path: String) async throws -> Bool
    /// Names in `directory`; empty when the directory does not exist.
    func fileNames(in directory: String) async throws -> Set<String>
    /// Creates `path` and every missing parent.
    func createDirectory(_ path: String) async throws
    /// Streams the local file up in chunks. `progress` receives bytes sent so
    /// far.
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws
    /// Reads the file back from the server in chunks and hashes it — the
    /// check that what landed is what was sent.
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String
    /// Writes the remote file to a local one (the conflict preview).
    func download(_ path: String, to localURL: URL) async throws
    /// Renames within the server. The destination must not exist.
    func move(_ source: String, to destination: String) async throws
    func remove(_ path: String) async throws
}

/// Why a server operation failed, in the terms the user can act on.
enum RemoteFileError: Error, Equatable, Sendable, LocalizedError {
    case unreachable(host: String)
    case authenticationFailed
    case folderMissing(String)
    case permissionDenied(String)
    case connectionLost
    case serverFull
    case localNetworkDenied
    /// SFTP, first connection: the key the user has to look at and trust.
    case hostKeyUntrusted(fingerprint: String)
    /// SFTP: the saved key and the one offered differ.
    case hostKeyChanged(host: String, fingerprint: String)
    case other(String)

    /// Failures that will fail every later file too, so the batch stops
    /// instead of grinding through them one timeout at a time.
    var stopsBatch: Bool {
        switch self {
        case .unreachable, .authenticationFailed, .connectionLost, .serverFull,
             .localNetworkDenied, .hostKeyUntrusted, .hostKeyChanged:
            true
        case .folderMissing, .permissionDenied, .other:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unreachable(let host):
            String(localized: "Can't reach \(host). Check that it's on and on the same network.", comment: "File server error")
        case .authenticationFailed:
            String(localized: "The username or password was rejected.", comment: "File server error")
        case .folderMissing(let path):
            String(localized: "The folder \(path) doesn't exist on the server.", comment: "File server error")
        case .permissionDenied(let path):
            String(localized: "You don't have permission to write to \(path).", comment: "File server error")
        case .connectionLost:
            String(localized: "The connection to the server was lost.", comment: "File server error")
        case .serverFull:
            String(localized: "The server is out of space.", comment: "File server error")
        case .localNetworkDenied:
            String(localized: "ShotDex needs Local Network access to reach this server.", comment: "File server error")
        case .hostKeyUntrusted:
            String(localized: "This server hasn't been trusted yet.", comment: "File server error: SFTP host key not yet confirmed")
        case .hostKeyChanged(let host, _):
            String(localized: "The identity of \(host) changed. If you didn't reinstall the server, someone may be intercepting the connection.", comment: "File server error: SFTP host key differs from the saved one")
        case .other(let message):
            message
        }
    }
}

/// SHA-256 of a local file, read in 1 MB chunks — never the whole RAW in
/// memory.
enum FileChecksum {
    static let chunkSize = 1 << 20

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data: data)
        }
        return hex(hasher.finalize())
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
