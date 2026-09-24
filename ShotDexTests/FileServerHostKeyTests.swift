import Foundation
import Testing
@testable import ShotDex

/// Trust-on-first-use for SFTP (FS-15.01 §4, AC-13).
@Suite struct FileServerHostKeyTests {
    /// Generated with `ssh-keygen -t ed25519`; the expected value is what
    /// `ssh-keygen -lf -E sha256` printed for it.
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAA5jjqiXB6AapMyWela6fr9SwNmSR/DZp2OPdfakWHq test"
    private let expected = "SHA256:jUMCJSXLnPdHeESygA0+h5iQYXenaTZnGUpEG0cgHD0"

    @Test func fingerprintMatchesOpenSSH() {
        #expect(HostKeyTrust.fingerprint(ofOpenSSHKey: key) == expected)
    }

    @Test func trustThenMismatchBlocks() {
        #expect(HostKeyTrust.evaluate(offered: expected, saved: nil) == .untrusted(fingerprint: expected))
        // The user tapped Trust: the fingerprint is saved and next time is silent.
        #expect(HostKeyTrust.evaluate(offered: expected, saved: expected) == .trusted)
        let other = "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        #expect(HostKeyTrust.evaluate(offered: other, saved: expected) == .changed(fingerprint: other))
        #expect(RemoteFileError.hostKeyChanged(host: "mac.local", fingerprint: other).stopsBatch)
        #expect(RemoteFileError.hostKeyChanged(host: "mac.local", fingerprint: other)
            .localizedDescription.contains("identity of mac.local changed"))
    }
}

/// Test Connection stops at the first step that fails (FS-15.01 §3).
@Suite struct FileServerConnectionCheckTests {
    @Test func missingFolderIsReportedAsTheFolder() async {
        let client = InMemoryRemoteFileClient()
        let outcome = await FileServerConnectionCheck.run(client: client, folder: "/Photos/RAW/")
        #expect(outcome == .failed(.folder, .folderMissing("Photos/RAW")))
    }

    @Test func existingFolderPassesAndLeavesNoProbe() async {
        let client = InMemoryRemoteFileClient()
        try? await client.createDirectory("Photos")
        let outcome = await FileServerConnectionCheck.run(client: client, folder: "Photos")
        #expect(outcome == .connected)
        #expect(client.files.isEmpty)
    }

    @Test func searchFindsServersByProtocolName() {
        for query in ["smb", "SFTP", "nas", "server"] {
            #expect(SettingsSearchIndex.results(for: query).contains { $0.label == .fileServers }, "\(query)")
        }
    }
}

/// The server form (FS-15.01 §3): an empty Port means the protocol's
/// default, and the saved row is trimmed.
@Suite struct FileServerDraftTests {
    @Test func emptyPortFollowsTheProtocol() {
        var draft = FileServerDraft()
        draft.server.host = " nas.local "
        draft.server.username = "me"
        draft.server.share = "photo"
        #expect(draft.canSave)
        #expect(draft.normalized.port == 445)
        draft.server.transferProtocol = .sftp
        #expect(draft.normalized.port == 22)
        #expect(draft.normalized.share == "")
        #expect(draft.normalized.host == "nas.local")
        #expect(draft.normalized.name == "nas.local")
    }

    @Test func typedPortIsKeptAndChecked() {
        var draft = FileServerDraft()
        draft.server.host = "127.0.0.1"
        draft.server.username = "tester"
        draft.server.share = "photos"
        draft.portText = "4450"
        #expect(draft.normalized.port == 4450)
        draft.portText = "4450445"
        #expect(!draft.canSave)
        draft.portText = "abc"
        #expect(!draft.canSave)
    }

    @Test func editingAServerOnItsDefaultPortShowsAnEmptyField() {
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas", username: "me", share: "s")
        #expect(FileServerDraft(server: server).portText == "")
        let custom = FileServer(name: "NAS", transferProtocol: .smb, host: "nas", port: 4450, username: "me", share: "s")
        #expect(FileServerDraft(server: custom).portText == "4450")
    }
}
