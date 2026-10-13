import Foundation

/// The one place that knows which library speaks which protocol.
enum RemoteFileClientFactory {
    /// A `.local` connection goes through `RoutedRemoteFileClient`, so it
    /// still reaches home over a VPN another app set up (FS-15.04 §7).
    static func make(for server: FileServer, password: String) -> any RemoteFileClient {
        guard server.transferProtocol != .files, LocalHostRoute.isMulticastDNS(server.host) else {
            return direct(for: server, password: password)
        }
        return RoutedRemoteFileClient(server: server, addresses: DefaultsServerAddressBook()) { routed in
            direct(for: routed, password: password)
        }
    }

    private static func direct(for server: FileServer, password: String) -> any RemoteFileClient {
        switch server.transferProtocol {
        case .smb: SMBFileClient(server: server, password: password)
        case .sftp: SFTPFileClient(server: server, password: password)
        case .webdav: WebDAVFileClient(server: server, password: password)
        case .files: FilesFolderClient(server: server)
        }
    }
}
