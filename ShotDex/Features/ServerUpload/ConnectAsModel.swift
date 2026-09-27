import Foundation
import Observation

/// Connect As for a server found on the network (FS-15.04 §3): pick how to
/// connect, type the login, sign in for real, then choose a folder.
@MainActor
@Observable
final class ConnectAsModel: Identifiable {
    let found: DiscoveredServer
    /// SMB, SFTP, WebDAV (HTTPS), WebDAV — the order the offers sort in.
    let offers: [DiscoveredServer.Offer]
    var offer: DiscoveredServer.Offer {
        didSet { if offer != oldValue { trustedFingerprint = nil; signIn.error = nil } }
    }
    /// What the connection is called; the machine's name to start with,
    /// numbered on save when taken (FS-15.01 §3).
    var name: String
    // Only a real edit clears the reason: SwiftUI writes a field's same
    // value back when focus returns to it, which wiped the error at once.
    var username = "" { didSet { if username != oldValue { signIn.error = nil } } }
    var password = "" { didSet { if password != oldValue { signIn.error = nil } } }
    private(set) var trustedFingerprint: String?
    let signIn: ServerSignIn

    nonisolated var id: String { found.id }

    init(found: DiscoveredServer, signIn: ServerSignIn? = nil) {
        self.found = found
        offers = found.offers.sorted { $0.service < $1.service }
        offer = offers[0]
        name = found.name
        self.signIn = signIn ?? ServerSignIn()
    }

    var showsProtocolChoice: Bool { offers.count > 1 }

    var canConnect: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !signIn.isConnecting
    }

    /// The form as this sign-in fills it — the name, where, and who; the
    /// folder comes from the picker.
    func draft(folder: String = "") -> FileServerDraft {
        var draft = FileServerDraft()
        draft.apply(offer, from: found)
        draft.server.name = name.trimmingCharacters(in: .whitespaces)
        draft.server.username = username.trimmingCharacters(in: .whitespaces)
        draft.server.trustedFingerprint = trustedFingerprint
        draft.server.folder = ServerUploadPath.normalizedFolder(folder)
        draft.password = password
        return draft
    }

    func connect() async -> ServerBrowseSession? {
        guard canConnect else { return nil }
        return await signIn.signIn(to: draft().normalized, password: password)
    }

    /// The Trust alert said yes: keep the fingerprint and sign in again.
    func trust(_ fingerprint: String) async -> ServerBrowseSession? {
        trustedFingerprint = fingerprint
        return await connect()
    }
}
