import Foundation
import Testing
@testable import ShotDex

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
        for _ in 0..<500 where model.stage == .downloading {
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

    /// The same room rule as Import (FS-17.02 §1): free space unknown is not a
    /// reason to refuse.
    @Test func unknownFreeSpaceDoesNotRefuse() {
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: nil) == nil)
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: 1_180_000_000) == nil)
        #expect(DeviceSpaceCheck.shortfall(for: 180_000_000, free: 1_179_999_999) == 1)
    }
}
