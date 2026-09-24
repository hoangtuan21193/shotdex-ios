import Citadel
import CryptoKit
import Foundation
import NIOCore
import NIOSSH

/// `RemoteFileClient` over SFTP (Citadel on SwiftNIO SSH, MIT / Apache 2).
/// Relative paths resolve against the login's home, which is what the
/// server does with them anyway.
///
/// The host key is checked on every connect (FS-15.01 §4): nothing saved →
/// the connect fails with the fingerprint for the user to trust; saved and
/// different → it fails and stays failed until the user forgets the key.
final class SFTPFileClient: RemoteFileClient, @unchecked Sendable {
    private let server: FileServer
    private let password: String
    private var ssh: SSHClient?
    private var sftp: SFTPClient?

    /// SFTP writes go out in slices of this size (Citadel caps a write
    /// request at 32 000 bytes anyway); reads ask for the same.
    private static let chunk = 32_000

    init(server: FileServer, password: String) {
        self.server = server
        self.password = password
    }

    func connect() async throws {
        let validator = HostKeyCheck(saved: server.hostKeyFingerprint, host: server.host)
        do {
            let ssh = try await withConnectTimeout(host: server.host) {
                try await SSHClient.connect(
                    host: self.server.host,
                    port: self.server.port,
                    authenticationMethod: .passwordBased(username: self.server.username, password: self.password),
                    hostKeyValidator: .custom(validator),
                    reconnect: .never,
                    connectTimeout: .seconds(10)
                )
            }
            self.ssh = ssh
            self.sftp = try await ssh.openSFTP()
        } catch {
            if let rejection = validator.rejection { throw rejection }
            throw Self.map(error, host: server.host, path: "")
        }
    }

    func disconnect() async {
        let sftp = sftp, ssh = ssh
        self.sftp = nil
        self.ssh = nil
        try? await sftp?.close()
        try? await ssh?.close()
    }

    private func connected() throws -> SFTPClient {
        guard let sftp else { throw RemoteFileError.connectionLost }
        return sftp
    }

    func fileSize(at path: String) async throws -> Int64? {
        do {
            let attributes = try await connected().getAttributes(at: path)
            if let permissions = attributes.permissions, permissions & 0o170000 == 0o040000 { return nil }
            return attributes.size.map { Int64($0) } ?? 0
        } catch {
            if Self.isNotFound(error) { return nil }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        do {
            let listing = try await connected().listDirectory(atPath: directory.isEmpty ? "." : directory)
            return Set(listing.flatMap(\.components).map(\.filename).filter { $0 != "." && $0 != ".." })
        } catch {
            if Self.isNotFound(error) { return [] }
            throw Self.map(error, host: server.host, path: directory)
        }
    }

    func createDirectory(_ path: String) async throws {
        let sftp = try connected()
        var current = ""
        for component in path.split(separator: "/") {
            current = ServerUploadPath.join(current, String(component))
            do {
                _ = try await sftp.getAttributes(at: current)
            } catch where Self.isNotFound(error) {
                do {
                    try await sftp.createDirectory(atPath: current)
                } catch {
                    throw Self.map(error, host: server.host, path: current)
                }
            } catch {
                throw Self.map(error, host: server.host, path: current)
            }
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        do {
            let file = try await connected().openFile(filePath: path, flags: [.write, .create, .truncate])
            var offset: UInt64 = 0
            do {
                while let data = try handle.read(upToCount: FileChecksum.chunkSize), !data.isEmpty {
                    try Task.checkCancellation()
                    try await file.write(ByteBuffer(data: data), at: offset)
                    offset += UInt64(data.count)
                    progress(Int64(offset))
                }
                try await file.close()
            } catch {
                try? await file.close()
                throw error
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        do {
            let file = try await connected().openFile(filePath: path, flags: .read)
            var hasher = SHA256()
            var offset: UInt64 = 0
            do {
                while true {
                    try Task.checkCancellation()
                    var buffer = try await file.read(from: offset, length: UInt32(Self.chunk * 8))
                    guard buffer.readableBytes > 0, let bytes = buffer.readBytes(length: buffer.readableBytes) else { break }
                    hasher.update(data: bytes)
                    offset += UInt64(bytes.count)
                    progress(Int64(offset))
                }
                try await file.close()
            } catch {
                try? await file.close()
                throw error
            }
            return FileChecksum.hex(hasher.finalize())
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func download(_ path: String, to localURL: URL) async throws {
        do {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: localURL)
            defer { try? out.close() }
            let file = try await connected().openFile(filePath: path, flags: .read)
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                var buffer = try await file.read(from: offset, length: UInt32(Self.chunk * 8))
                guard buffer.readableBytes > 0, let bytes = buffer.readBytes(length: buffer.readableBytes) else { break }
                try out.write(contentsOf: bytes)
                offset += UInt64(bytes.count)
            }
            try? await file.close()
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.map(error, host: server.host, path: path)
        }
    }

    func move(_ source: String, to destination: String) async throws {
        do {
            try await connected().rename(at: source, to: destination)
        } catch {
            throw Self.map(error, host: server.host, path: destination)
        }
    }

    func remove(_ path: String) async throws {
        do {
            try await connected().remove(at: path)
        } catch {
            if Self.isNotFound(error) { return }
            throw Self.map(error, host: server.host, path: path)
        }
    }

    // MARK: - Errors

    private static func isNotFound(_ error: Error) -> Bool {
        (error as? SFTPMessage.Status)?.errorCode == .noSuchFile
    }

    static func map(_ error: Error, host: String, path: String) -> Error {
        if error is CancellationError || error is RemoteFileError { return error }
        if let status = error as? SFTPMessage.Status {
            switch status.errorCode {
            case .noSuchFile: return RemoteFileError.folderMissing(path)
            case .permissionDenied: return RemoteFileError.permissionDenied(path)
            case .noConnection, .connectionLost: return RemoteFileError.connectionLost
            default:
                // OpenSSH reports a full disk as a plain failure with this text.
                if status.message.localizedCaseInsensitiveContains("space") { return RemoteFileError.serverFull }
                return RemoteFileError.other(status.message.isEmpty ? String(describing: status.errorCode) : status.message)
            }
        }
        if let client = error as? SSHClientError, case .allAuthenticationOptionsFailed = client {
            return RemoteFileError.authenticationFailed
        }
        if let sftp = error as? SFTPError, case .connectionClosed = sftp {
            return RemoteFileError.connectionLost
        }
        if error is ChannelError { return RemoteFileError.connectionLost }
        return mapNetworkError(error, host: host)
    }
}

/// Decides the host key during the handshake and remembers why it said no,
/// so the connect's error can be the one the user needs to see.
private final class HostKeyCheck: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let saved: String?
    let host: String
    private(set) var rejection: RemoteFileError?

    init(saved: String?, host: String) {
        self.saved = saved
        self.host = host
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        guard let offered = HostKeyTrust.fingerprint(ofOpenSSHKey: String(openSSHPublicKey: hostKey)) else {
            let error = RemoteFileError.other(String(localized: "The server offered a key ShotDex can't read.", comment: "SFTP: unreadable host key"))
            rejection = error
            validationCompletePromise.fail(error)
            return
        }
        switch HostKeyTrust.evaluate(offered: offered, saved: saved) {
        case .trusted:
            validationCompletePromise.succeed(())
        case .untrusted(let fingerprint):
            rejection = .hostKeyUntrusted(fingerprint: fingerprint)
            validationCompletePromise.fail(rejection!)
        case .changed(let fingerprint):
            rejection = .hostKeyChanged(host: host, fingerprint: fingerprint)
            validationCompletePromise.fail(rejection!)
        }
    }
}
