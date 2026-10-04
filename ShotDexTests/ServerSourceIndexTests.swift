import Foundation
import Testing
@testable import ShotDex

/// FS-19 §3 (servers as sources). Locks what the server stack already does
/// before the source indexer is built on top of it.
@Suite struct ServerSourceIndexTests {
    private func photo(_ client: InMemoryRemoteFileClient, _ name: String) -> ServerDownloadItem {
        let data = RemoteThumbnailTests.jpeg(width: 200)
        client.put("Trip/\(name)", data)
        let entry = RemoteEntry(name: name, isDirectory: false, size: Int64(data.count), modified: nil)
        return ServerDownloadItem(photo: ServerPhoto(files: [entry]), folder: "Trip")
    }

    private func session(_ client: InMemoryRemoteFileClient) -> ServerDownloadSession {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexSourceIndex-test-\(UUID().uuidString)")
        return ServerDownloadSession(client: client, creator: RecordingAssetCreator(), serverId: "S1", serverName: "NAS Home",
                                     workDirectory: work, albumId: nil, record: { _ in })
    }

    /// AC-36, client half: a password changed on the NAS stops the batch at
    /// the first refusal — no retry per file, and nothing in the session can
    /// ask for a password (the row reports it; signing in is the user's move).
    @Test func passwordRejectedNoPrompts() async {
        #expect(RemoteFileError.authenticationFailed.stopsBatch)

        let refusedAtLogin = InMemoryRemoteFileClient()
        let items = (1...3).map { photo(refusedAtLogin, "IMG_\($0).JPG") }
        refusedAtLogin.connectError = .authenticationFailed
        let atLogin = await session(refusedAtLogin).run(items)
        #expect(atLogin.stopReason == .error(.authenticationFailed))
        #expect(atLogin.outcomes == [.notAttempted, .notAttempted, .notAttempted])
        #expect(refusedAtLogin.connectCount == 1)
        #expect(refusedAtLogin.downloadCount == 0)

        let refusedMidway = InMemoryRemoteFileClient()
        let more = (1...3).map { photo(refusedMidway, "IMG_\($0).JPG") }
        refusedMidway.refuseDownload = (number: 2, error: .authenticationFailed)
        let midway = await session(refusedMidway).run(more)
        #expect(midway.stopReason == .error(.authenticationFailed))
        #expect(midway.outcomes.dropFirst() == [.notAttempted, .notAttempted])
        #expect(refusedMidway.downloadCount == 2)
        #expect(refusedMidway.connectCount == 1)
    }
}
