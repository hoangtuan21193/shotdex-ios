import Foundation

/// The one place that knows which library speaks which protocol.
enum RemoteFileClientFactory {
    static func make(for server: FileServer, password: String) -> any RemoteFileClient {
        switch server.transferProtocol {
        case .smb: SMBFileClient(server: server, password: password)
        case .sftp: SFTPFileClient(server: server, password: password)
        }
    }
}
