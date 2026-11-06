import Foundation

/// Whether two connections reach the same files, so a path on one is the
/// same file on the other — the upload history, a common-photos run and its
/// rescans follow paths across them (FS-19.08 §6). One protocol, host
/// (any case) and port; for SFTP also one login, whose home and rights the
/// paths are relative to; for WebDAV also one base path (`share`).
enum ServerIdentity {
    /// One string for the files a connection reaches, by the same rule as
    /// `sameFiles` — how another device names this server (FS-19.07 §12.3).
    /// Nil for a Files folder, which no other device can reach.
    static func key(_ server: FileServer) -> String? {
        guard server.transferProtocol.isNetwork else { return nil }
        var parts = [server.transferProtocol.rawValue, server.host.lowercased(), String(server.port)]
        switch server.transferProtocol {
        case .sftp: parts.append(server.username)
        // http and https on one port are not the same server.
        case .webdav: parts += [server.usesTLS ? "tls" : "plain", ServerUploadPath.normalizedFolder(server.share)]
        case .smb, .files: break
        }
        return parts.joined(separator: "|")
    }

    static func sameFiles(_ a: FileServer, _ b: FileServer) -> Bool {
        guard a.transferProtocol.isNetwork, b.transferProtocol.isNetwork else { return a.id == b.id }
        guard a.transferProtocol == b.transferProtocol, a.host.lowercased() == b.host.lowercased(), a.port == b.port else { return false }
        switch a.transferProtocol {
        case .sftp: return a.username == b.username
        case .webdav: return ServerUploadPath.normalizedFolder(a.share) == ServerUploadPath.normalizedFolder(b.share)
        case .smb, .files: return true
        }
    }
}
