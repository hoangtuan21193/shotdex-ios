import Foundation
import Testing
@testable import ShotDex

/// FS-17.02 §1, §3, §4 — the sheet's model.
@Suite @MainActor struct ServerDownloadModelTests {
    private final class CountingHold: ScreenHolding {
        var holds = 0
        var maxHolds = 0
        func beginHold() { holds += 1; maxHolds = max(maxHolds, holds) }
        func endHold() { holds -= 1 }
    }

    private struct Setup {
        let model: ServerDownloadModel
        let client: InMemoryRemoteFileClient
        let creator: RecordingAssetCreator
        let hold: CountingHold
        let saved: SavedBox
    }

    final class SavedBox { var ids: Set<String> = [] }

    private func makeSetup(count: Int, inLibrary: Set<String> = [], limited: Bool = false, freeSpace: Int64? = nil) throws -> Setup {
        let client = InMemoryRemoteFileClient()
        var photos: [ServerPhoto] = []
        for n in 0..<count {
            let data = RemoteThumbnailTests.jpeg(width: 200 + n)
            client.put("Trip/P\(n).JPG", data)
            photos.append(ServerPhoto(files: [RemoteEntry(name: "P\(n).JPG", isDirectory: false, size: Int64(data.count), modified: nil)]))
        }
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        let creator = RecordingAssetCreator()
        let hold = CountingHold()
        let saved = SavedBox()
        let model = ServerDownloadModel(
            context: .init(server: server, folder: "Trip", photos: photos, inLibrary: inLibrary, known: []),
            password: "pw",
            isLimitedAccess: limited,
            makeClient: { _, _ in client },
            creator: creator,
            downloads: ServerDownloadStore(database: try AppDatabase.makeEmpty()),
            screenHold: hold,
            listAlbums: { [.init(id: "album-1", title: "Trip")] },
            createAlbumNamed: { _ in "album-2" },
            freeSpace: { freeSpace },
            onSaved: { saved.ids.formUnion($0) }
        )
        return Setup(model: model, client: client, creator: creator, hold: hold, saved: saved)
    }

    private func waitUntilFinished(_ model: ServerDownloadModel) async {
        for _ in 0..<500 where model.stage != .finished {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// AC-13.
    @Test func skipsInLibrary() async throws {
        let setup = try makeSetup(count: 4, inLibrary: ["P1.JPG"])
        #expect(setup.model.inLibraryCount == 1)
        #expect(setup.model.photosToDownload.count == 3)
        setup.model.start()
        await waitUntilFinished(setup.model)
        #expect(setup.creator.requests.count == 3)
        #expect(setup.model.summary.savedCount == 3)
        #expect(setup.model.summary.skippedCount == 1)
        #expect(setup.saved.ids == ["P0.JPG", "P2.JPG", "P3.JPG"])

        // Switch off: everything goes.
        let all = try makeSetup(count: 2, inLibrary: ["P1.JPG"])
        all.model.skipsInLibrary = false
        #expect(all.model.photosToDownload.count == 2)
    }

    /// AC-14.
    @Test func idleTimerRestoredOnEveryExit() async throws {
        let done = try makeSetup(count: 2)
        done.model.start()
        #expect(done.hold.holds == 1)
        await waitUntilFinished(done.model)
        #expect(done.hold.holds == 0)

        let closed = try makeSetup(count: 3)
        closed.model.start()
        closed.model.tearDown()
        #expect(closed.hold.holds == 0)
        await waitUntilFinished(closed.model)
        #expect(closed.hold.holds == 0)
        #expect(closed.hold.maxHolds == 1)
    }

    /// AC-16.
    @Test func limitedAccessOnlyLibrary() throws {
        let limited = try makeSetup(count: 1, limited: true)
        #expect(limited.model.albums.isEmpty)
        #expect(limited.model.destination == .library)
        let full = try makeSetup(count: 1)
        #expect(full.model.albums.map(\.title) == ["Trip"])
    }

    @Test func newAlbumBecomesTheDestination() async throws {
        let setup = try makeSetup(count: 1)
        await setup.model.createAlbum(named: "  Picks ")
        #expect(setup.model.destination == .album(id: "album-2"))
        setup.model.start()
        await waitUntilFinished(setup.model)
        #expect(setup.creator.requests.first?.albumId == "album-2")
    }

    @Test func notEnoughSpaceBlocksStart() throws {
        let setup = try makeSetup(count: 2, freeSpace: 500_000_000)
        #expect(setup.model.spaceShortfall != nil)
        #expect(!setup.model.canStart)
    }
}
