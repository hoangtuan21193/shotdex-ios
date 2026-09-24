import Foundation
import Testing
@testable import ShotDex

/// The upload sheet's model (FS-15.02 §6–§7): the screen hold is released on
/// every way out (AC-15), and the result offers exactly the verified photos.
@Suite @MainActor struct ServerUploadModelTests {
    private final class CountingHold: ScreenHolding {
        var holds = 0
        var maxHolds = 0
        func beginHold() { holds += 1; maxHolds = max(maxHolds, holds) }
        func endHold() { holds -= 1 }
    }

    private struct Setup {
        let model: ServerUploadModel
        let hold: CountingHold
        let client: InMemoryRemoteFileClient
        let deleted: DeletedBox
    }

    final class DeletedBox { var ids: [String] = [] }

    private func makeSetup(fixture: UploadFixture) throws -> Setup {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", share: "photo", folder: "Photos")
        try servers.save(nas, password: "pw")
        let hold = CountingHold()
        let client = InMemoryRemoteFileClient()
        let deleted = DeletedBox()
        let entries = fixture.items.map { item in
            AssetUploadEntry(
                assetId: item.assetId,
                captureDate: Date(timeIntervalSince1970: 1_790_000_000),
                files: [item.file]
            )
        }
        let model = ServerUploadModel(
            assetIds: entries.map(\.assetId),
            fileServers: servers,
            uploads: ServerUploadStore(database: database),
            index: nil,
            screenHold: hold,
            listEntries: { _ in entries },
            makeClient: { _, _ in client },
            exporter: fixture.exporter,
            deleteAssets: { deleted.ids = $0 }
        )
        return Setup(model: model, hold: hold, client: client, deleted: deleted)
    }

    private func waitUntilFinished(_ model: ServerUploadModel) async {
        for _ in 0..<500 where model.stage != .finished {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func idleTimerRestoredOnEveryExit() async throws {
        // Finished.
        let done = try makeSetup(fixture: UploadFixture(count: 2, bytes: 100))
        await done.model.load()
        done.model.start()
        #expect(done.hold.holds == 1)
        await waitUntilFinished(done.model)
        #expect(done.model.stage == .finished)
        #expect(done.hold.holds == 0)

        // Cancelled (the Cancel button, and the app going to the background).
        let cancelled = try makeSetup(fixture: UploadFixture(count: 3, bytes: 100))
        let model = cancelled.model
        cancelled.client.onUpload = { number in
            guard number == 2 else { return }
            Task { @MainActor in model.cancel() }
            // Hold upload 2 long enough for the cancel to land on the main
            // actor, as a real 50 MB upload would.
            Thread.sleep(forTimeInterval: 0.3)
        }
        await model.load()
        model.start()
        await waitUntilFinished(model)
        #expect(model.summary.stopMessage != nil)
        #expect(cancelled.hold.holds == 0)

        // Sheet closed mid-way.
        let closed = try makeSetup(fixture: UploadFixture(count: 3, bytes: 100))
        await closed.model.load()
        closed.model.start()
        closed.model.tearDown()
        #expect(closed.hold.holds == 0)
        await waitUntilFinished(closed.model)
        #expect(closed.hold.holds == 0)
        #expect(closed.hold.maxHolds == 1)
    }

    @Test func startsOnTheLastServerWithAllOriginals() async throws {
        let setup = try makeSetup(fixture: UploadFixture(count: 1, bytes: 10))
        await setup.model.load()
        #expect(setup.model.selectedServer?.name == "NAS")
        #expect(setup.model.fileKind == .allOriginals)
        #expect(setup.model.canStart)
    }

    @Test func resultOffersVerifiedPhotosForDeletion() async throws {
        let setup = try makeSetup(fixture: UploadFixture(count: 2, bytes: 100))
        await setup.model.load()
        setup.model.start()
        await waitUntilFinished(setup.model)
        #expect(Set(setup.model.summary.deletableAssetIds) == ["A0", "A1"])
        #expect(setup.model.summary.uploadedPhotoCount == 2)
        // Paths landed under the server's folder, by capture day.
        #expect(setup.client.files.keys.allSatisfy { $0.hasPrefix("Photos/20") })

        await setup.model.deleteUploaded()
        #expect(Set(setup.deleted.ids) == ["A0", "A1"])
        #expect(setup.model.summary.deletableAssetIds.isEmpty)
    }

    @Test func uploadRemainingRetriesOnlyWhatDidNotLand() async throws {
        let setup = try makeSetup(fixture: UploadFixture(count: 3, bytes: 100))
        setup.client.dropConnectionOnUpload = 2
        await setup.model.load()
        setup.model.start()
        await waitUntilFinished(setup.model)
        #expect(setup.model.hasRemaining)
        #expect(setup.model.summary.uploadedPhotoCount == 1)

        setup.client.dropConnectionOnUpload = nil
        setup.model.uploadRemaining()
        #expect(setup.model.stage == .uploading)
        await waitUntilFinished(setup.model)
        #expect(!setup.model.hasRemaining)
        #expect(setup.client.files.count == 3)
        // The photo the first run finished is still offered after the retry.
        #expect(Set(setup.model.summary.deletableAssetIds) == ["A0", "A1", "A2"])
    }
}
