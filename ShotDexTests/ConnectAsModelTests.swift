import Foundation
import Testing
@testable import ShotDex

private func found(_ services: [(DiscoveredServer.Service, Int)]) -> DiscoveredServer {
    DiscoveredServer(
        name: "ShotDex Test", kind: .nas,
        offers: services.reversed().map { .init(service: $0.0, host: "shotdex-test.local", port: $0.1) }
    )
}

/// FS-15.04 §3 — FS-15 AC-42, 43, 44.
@Suite @MainActor struct ConnectAsModelTests {
    /// AC-42: a real sign-in, then the form filled from it plus the folder.
    @Test func successOpensFolderPickerAndFillsDraft() async throws {
        let client = InMemoryRemoteFileClient()
        var madeFor: FileServer?
        let model = ConnectAsModel(found: found([(.smb, 4450)]), signIn: ServerSignIn { server, _ in
            madeFor = server
            return client
        })
        model.username = "tester"
        model.password = "secret"

        let session = await model.connect()

        #expect(session != nil)
        #expect(client.connectCount == 1)
        #expect(madeFor?.host == "shotdex-test.local")
        #expect(madeFor?.port == 4450)
        let draft = model.draft(folder: "/photos/")
        #expect(draft.server.name == "ShotDex Test")
        #expect(draft.server.transferProtocol == .smb)
        #expect(draft.server.username == "tester")
        #expect(draft.portText == "4450")
        #expect(draft.password == "secret")
        #expect(draft.normalized.folder == "photos")
        #expect(draft.normalized.share == "")
        #expect(draft.canSave)
    }

    /// AC-43: the reason under the password; nothing opens.
    @Test func wrongPasswordStaysWithReason() async {
        let client = InMemoryRemoteFileClient()
        client.connectError = .authenticationFailed
        let model = ConnectAsModel(found: found([(.smb, 445)]), signIn: ServerSignIn { _, _ in client })
        model.username = "tester"
        model.password = "wrong"

        let session = await model.connect()

        #expect(session == nil)
        #expect(model.signIn.error == "The username or password was rejected.")
        #expect(model.password == "wrong")
        // Focus coming back writes the same value: the reason stays.
        model.password = "wrong"
        #expect(model.signIn.error == "The username or password was rejected.")
        // Typing again clears it.
        model.password = "secret"
        #expect(model.signIn.error == nil)
    }

    /// AC-44.
    @Test func protocolChoiceFollowsOffers() {
        let both = ConnectAsModel(found: found([(.smb, 445), (.sftp, 22)]))
        #expect(both.showsProtocolChoice)
        #expect(both.offers.map(\.service) == [.smb, .sftp])
        #expect(both.offer.service == .smb)
        #expect(!ConnectAsModel(found: found([(.sftp, 22)])).showsProtocolChoice)
    }

    /// A first SFTP connection asks to trust the key, then signs in with it.
    @Test func untrustedKeyAsksThenConnects() async {
        let client = InMemoryRemoteFileClient()
        client.connectError = .hostKeyUntrusted(fingerprint: "SHA256:abc")
        var trusted: String?
        let model = ConnectAsModel(found: found([(.sftp, 22)]), signIn: ServerSignIn { server, _ in
            trusted = server.trustedFingerprint
            return client
        })
        model.username = "me"
        model.password = "p"
        #expect(await model.connect() == nil)
        #expect(model.signIn.untrustedFingerprint == "SHA256:abc")

        client.connectError = nil
        #expect(await model.trust("SHA256:abc") != nil)
        #expect(trusted == "SHA256:abc")
        #expect(model.draft().server.trustedFingerprint == "SHA256:abc")
    }
}

/// FS-15.04 §5 — FS-15 AC-45: Choose… in the form signs in first.
@Suite @MainActor struct ServerSignInTests {
    @Test func failureStaysUnderTheRow() async {
        let client = InMemoryRemoteFileClient()
        client.connectError = .authenticationFailed
        let signIn = ServerSignIn { _, _ in client }
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", folder: "photos")

        #expect(await signIn.signIn(to: server, password: "wrong") == nil)
        #expect(signIn.error == "The username or password was rejected.")
        #expect(!signIn.isConnecting)

        client.connectError = nil
        #expect(await signIn.signIn(to: server, password: "right") != nil)
        #expect(signIn.error == nil)
    }
}
