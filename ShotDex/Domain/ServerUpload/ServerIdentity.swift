import Foundation

/// Whether two connections reach the same files, so a path on one is the
/// same file on the other — the upload history, a common-photos run and its
/// rescans follow paths across them (FS-19.08 §6). One protocol, host
/// (any case) and port; for SFTP also one login, whose home and rights the
/// paths are relative to; for WebDAV also one base path (`share`).
enum ServerIdentity {
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
