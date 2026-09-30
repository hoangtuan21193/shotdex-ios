import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// A server's calls straight to one client — no gate, no login. `onPerform`
/// runs before each call with its 1-based number: where a test cancels.
final class DirectRemoteAccess: RemoteFileAccess, @unchecked Sendable {
    let client: any RemoteFileClient
    var onPerform: (@Sendable (Int) async throws -> Void)?
    private let lock = NSLock()
    private var count = 0

    init(_ client: any RemoteFileClient) { self.client = client }

    func perform<T: Sendable>(_ work: @Sendable (any RemoteFileClient) async throws -> T) async throws -> T {
        let number = lock.withLock { count += 1; return count }
        try await onPerform?(number)
        return try await work(client)
    }
}

/// FS-17.06 §4–5: the original comes down to a work folder, and nothing is
/// written to the server on the way.
@Suite @MainActor struct ServerEditSessionTests {
    final class NoHold: ScreenHolding {
        var holds = 0
        func beginHold() { holds += 1 }
        func endHold() { holds -= 1 }
    }

    private func entry(_ name: String, _ size: Int) -> RemoteEntry {
        RemoteEntry(name: name, isDirectory: false, size: Int64(size), modified: nil)
    }

    private func waitUntilSettled(_ model: ServerEditFetchModel) async {
        for _ in 0..<3000 where model.stage == .downloading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// AC-55: 3 RAW × 60 MB with 1.1 GB free — 1.18 GB needed — so no byte is
    /// read and the sheet says how much more is needed.
    @Test func spaceCheckBeforeDownload() async throws {
        let client = InMemoryRemoteFileClient()
        let photos = (0..<3).map { n -> ServerPhoto in
            client.put("Trip/R\(n).CR3", Data(repeating: 1, count: 16))
            return ServerPhoto(files: [entry("R\(n).CR3", 60_000_000)])
        }
        let hold = NoHold()
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip", photos: photos,
            access: DirectRemoteAccess(client), freeSpace: { 1_100_000_000 }, screenHold: hold
        )

        #expect(model.spaceShortfall == 80_000_000)
        model.start()

        guard case .failed(let message) = model.stage else {
            Issue.record("expected the space check to refuse, got \(model.stage)")
            return
        }
        #expect(message.contains(ByteCountFormatter.string(fromByteCount: 80_000_000, countStyle: .file)))
        #expect(client.bytesRead == 0)
        #expect(client.downloadCount == 0)
        #expect(model.workDirectory == nil)
        #expect(hold.holds == 0)
    }

    /// AC-56: Cancel while the second of three photos is on its way — the
    /// work folder, with the first photo already in it, is deleted and no
    /// editor opens.
    @Test func cancelRemovesTemp() async throws {
        let client = InMemoryRemoteFileClient()
        let photos = (0..<3).map { n -> ServerPhoto in
            let data = RemoteThumbnailTests.jpeg(width: 200 + n)
            client.put("Trip/P\(n).JPG", data)
            return ServerPhoto(files: [entry("P\(n).JPG", data.count)])
        }
        let access = DirectRemoteAccess(client)
        let hold = NoHold()
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip", photos: photos,
            access: access, freeSpace: { nil }, screenHold: hold
        )
        access.onPerform = { number in
            guard number == 2 else { return }
            await MainActor.run { model.cancel() }
            try await Task.sleep(for: .seconds(5))
        }

        model.start()
        let directory = try #require(model.workDirectory)
        await waitUntilSettled(model)

        #expect(model.stage == .cancelled)
        #expect(model.fetched.isEmpty)
        #expect(client.downloadCount == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(hold.holds == 0)
    }

    /// AC-54: Edit on one photo brings down exactly its one file, writes
    /// nothing to the server, and the editor's session reads that file in
    /// place — no second copy, no PhotoKit input.
    @Test func downloadsOriginalOnly() async throws {
        let client = InMemoryRemoteFileClient()
        let data = RemoteThumbnailTests.jpeg(width: 640, date: "2024:05:01 10:00:00")
        client.put("Trip/a.JPG", data)
        client.put("Trip/b.JPG", RemoteThumbnailTests.jpeg(width: 300))
        let before = client.files
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip", photos: [ServerPhoto(files: [entry("a.JPG", data.count)])],
            access: DirectRemoteAccess(client), freeSpace: { 2_000_000_000 }, screenHold: NoHold()
        )

        model.start()
        await waitUntilSettled(model)

        #expect(model.stage == .fetched)
        let fetched = try #require(model.fetched.first)
        defer { if let directory = model.workDirectory { try? FileManager.default.removeItem(at: directory) } }
        #expect(client.downloadCount == 1)
        #expect(client.uploadCount == 0)
        #expect(client.removed.isEmpty)
        #expect(client.files == before)
        #expect(try Data(contentsOf: fetched.primaryURL) == data)
        #expect(fetched.id == "S1|Trip/a.JPG")

        let service = PhotoEditingService()
        let session = try await service.beginSession(for: .serverFile(fetched))
        defer { service.releaseCachedSessions() }
        #expect(session.contentInput == nil)
        #expect(session.asset == nil)
        let option = try #require(session.preferredSource(for: nil))
        #expect(option.filename == "a.JPG")
        let loaded = try await service.loadSource(option, in: session)
        #expect(loaded.info.persistentIdentity?.hasPrefix("S1|Trip/a.JPG|") == true)
        // Read where it lies: nothing was copied into the session's folder.
        let copies = try FileManager.default.contentsOfDirectory(atPath: session.temporaryDirectory.path)
        #expect(copies.isEmpty)
    }

    /// One photo fetched through the model, as the browser's Edit does.
    private func fetchedRun(_ name: String = "a.JPG") async throws -> (ServerPhotoCommandRun, InMemoryRemoteFileClient) {
        let client = InMemoryRemoteFileClient()
        let data = RemoteThumbnailTests.jpeg(width: 400)
        client.put("Trip/\(name)", data)
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip", photos: [ServerPhoto(files: [entry(name, data.count)])],
            access: DirectRemoteAccess(client), freeSpace: { nil }, screenHold: NoHold()
        )
        model.start()
        await waitUntilSettled(model)
        #expect(model.stage == .fetched)
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        return (ServerPhotoCommandRun(command: .edit, server: server, access: DirectRemoteAccess(client), fetch: model), client)
    }

    /// AC-57: Exposure +1 on a server photo, then Discard — the editor asks
    /// first, the copy is deleted, and opening the photo again starts from
    /// nothing: a server photo never recalls a recipe.
    @Test func discardDropsDraft() async throws {
        let (run, client) = try await fetchedRun()
        let photo = try #require(run.photos.first)
        let directory = try #require(run.fetch.workDirectory)
        let editor = EditorSession(photos: [.serverFile(photo)])
        var edited = PhotoEditRecipe.identity
        edited.adjustments.exposure = 1
        editor.store(edited, for: .serverFile(photo))
        #expect(editor.hasUnsavedWork(canvasHasChanges: false))
        #expect(editor.isServerRun)

        run.discardCopies()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(client.uploadCount == 0 && client.removed.isEmpty)
        let (again, _) = try await fetchedRun()
        defer { again.discardCopies() }
        let service = PhotoEditingService()
        let session = try await service.beginSession(for: .serverFile(try #require(again.photos.first)))
        defer { service.releaseCachedSessions() }
        #expect(session.recalledRecipe == nil)
        #expect(EditorSession(photos: [.serverFile(photo)]).draft(for: .serverFile(photo)) == nil)
    }

    /// AC-58: nothing edited — the editor closes without asking, and the
    /// copy still goes.
    @Test func cleanLeaveNoPrompt() async throws {
        let (run, _) = try await fetchedRun()
        let photo = try #require(run.photos.first)
        let directory = try #require(run.fetch.workDirectory)
        let editor = EditorSession(photos: [.serverFile(photo)])
        #expect(!editor.hasUnsavedWork(canvasHasChanges: false))
        #expect(editor.hasUnsavedWork(canvasHasChanges: true))

        run.discardCopies()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// The same room rule as Import (FS-17.02 §1): free space unknown is not a
    /// reason to refuse.
    @Test func unknownFreeSpaceDoesNotRefuse() {
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: nil) == nil)
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: 1_180_000_000) == nil)
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: 1_179_999_999) == 1)
    }

    /// AC-66: five photos, three edited — Export… sends those three with
    /// their own edits, not the two left alone.
    @Test func batchExportsEditedOnly() throws {
        let photos = (0..<5).map { n -> FetchedServerPhoto in
            let entry = entry("P\(n).JPG", 10)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("P\(n).JPG")
            return FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                      files: [FetchedFile(file: entry, url: url, sha256: "")])
        }
        let editor = EditorSession(photos: photos.map(PhotoEditOrigin.serverFile), startIndex: 4)
        func edit(_ exposure: Double) -> PhotoEditRecipe {
            var recipe = PhotoEditRecipe.identity
            recipe.adjustments.exposure = exposure
            return recipe
        }
        editor.store(edit(0.5), for: .serverFile(photos[0]))
        editor.store(edit(1), for: .serverFile(photos[2]))

        let selection = editor.exportSelection(canvasRecipe: edit(-1))

        #expect(selection.map(\.photo.photo.primary.name) == ["P0.JPG", "P2.JPG", "P4.JPG"])
        #expect(selection.map(\.recipe.adjustments.exposure) == [0.5, 1, -1])
    }

    /// Alone in its run and untouched, the photo still exports — a RAW
    /// turned into a JPEG with no slider moved.
    @Test func singleUntouchedPhotoStillExports() {
        let entry = entry("R.CR3", 10)
        let photo = FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                       files: [FetchedFile(file: entry, url: URL(fileURLWithPath: "/tmp/R.CR3"), sha256: "")])
        let editor = EditorSession(photos: [.serverFile(photo)])
        #expect(editor.exportSelection(canvasRecipe: .identity).map(\.photo.id) == [photo.id])
    }
}
