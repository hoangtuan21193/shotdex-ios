import Foundation

/// The one place that knows which library speaks which protocol.
enum RemoteFileClientFactory {
    static func make(for server: FileServer, password: String) -> any RemoteFileClient {
        switch server.transferProtocol {
        case .smb: SMBFileClient(server: server, password: password)
        case .sftp: SFTPFileClient(server: server, password: password)
        case .webdav: WebDAVFileClient(server: server, password: password)
        case .ftps, .ftp: UnavailableFileClient(transferProtocol: server.transferProtocol)
        }
    }

    /// Whether a real client stands behind `transferProtocol` yet.
    static func supports(_ transferProtocol: FileServer.TransferProtocol) -> Bool {
        switch transferProtocol {
        case .smb, .sftp, .webdav: true
        case .ftps, .ftp: false
        }
    }
}

/// Stands in for a protocol whose client has not landed; the form does not
/// offer it, so only a row saved by a newer build could reach this.
final class UnavailableFileClient: RemoteFileClient, @unchecked Sendable {
    let transferProtocol: FileServer.TransferProtocol

    init(transferProtocol: FileServer.TransferProtocol) {
        self.transferProtocol = transferProtocol
    }

    private var error: RemoteFileError {
        .other(String(localized: "This version of ShotDex can't connect over \(transferProtocol.title) yet.", comment: "File server error: protocol not supported by this build"))
    }

    func connect() async throws { throw error }
    func disconnect() async {}
    func fileSize(at path: String) async throws -> Int64? { throw error }
    func directoryExists(_ path: String) async throws -> Bool { throw error }
    func fileNames(in directory: String) async throws -> Set<String> { throw error }
    func folderNames(in directory: String) async throws -> Set<String> { throw error }
    func entries(in directory: String) async throws -> [RemoteEntry] { throw error }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data { throw error }
    func createDirectory(_ path: String) async throws { throw error }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws { throw error }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { throw error }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { throw error }
    func move(_ source: String, to destination: String) async throws { throw error }
    func remove(_ path: String) async throws { throw error }
}
