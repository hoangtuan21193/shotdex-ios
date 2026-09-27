import Foundation
import Observation

/// Signs in once and hands the login on to the folder picker (FS-15.04 §3,
/// §5): Connect As and the form's Choose… both start here, and both show a
/// failure where the user typed, not on a screen further in.
@MainActor
@Observable
final class ServerSignIn {
    private(set) var isConnecting = false
    /// The reason in the user's terms; cleared when they edit what caused it.
    var error: String?
    /// SFTP or a self-signed WebDAV certificate, first time: the fingerprint
    /// to show in the Trust alert before trying again.
    var untrustedFingerprint: String?

    private let makeClient: (FileServer, String) -> any RemoteFileClient

    init(makeClient: @escaping (FileServer, String) -> any RemoteFileClient = RemoteFileClientFactory.make(for:password:)) {
        self.makeClient = makeClient
    }

    /// A session that is already logged in, or nil with `error` or
    /// `untrustedFingerprint` set.
    func signIn(to server: FileServer, password: String) async -> ServerBrowseSession? {
        isConnecting = true
        error = nil
        untrustedFingerprint = nil
        defer { isConnecting = false }
        let session = ServerBrowseSession(server: server, client: makeClient(server, password))
        do {
            try await session.perform { _ in }
            return session
        } catch RemoteFileError.hostKeyUntrusted(let fingerprint) {
            untrustedFingerprint = fingerprint
        } catch {
            self.error = ((error as? RemoteFileError) ?? .other(error.localizedDescription)).localizedDescription
        }
        await session.close()
        return nil
    }
}
