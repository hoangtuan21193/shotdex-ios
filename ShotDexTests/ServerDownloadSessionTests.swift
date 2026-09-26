import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// Records what PhotoKit would be asked to create; can refuse a format.
final class RecordingAssetCreator: AssetCreating, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [AssetCreationRequest] = []
    /// Extensions Photos "refuses".
    var refuses: Set<String> = []
    /// Byte counts of the files at the moment they were handed over — the
    /// session deletes them right after.
    private(set) var sizes: [[Int]] = []

    var requests: [AssetCreationRequest] { lock.withLock { _requests } }

    func createAsset(_ request: AssetCreationRequest) async throws -> String {
        if let first = request.resources.first,
           refuses.contains((first.originalFilename as NSString).pathExtension.lowercased()) {
            throw AssetCreationError.unsupportedFormat((first.originalFilename as NSString).pathExtension.uppercased())
        }
        return lock.withLock {
            _requests.append(request)
            sizes.append(request.resources.map { (try? Data(contentsOf: $0.url).count) ?? -1 })
            return "asset-\(_requests.count)"
        }
    }
}

/// FS-17.02 §2: download, check, save as one asset, record.
@Suite struct ServerDownloadSessionTests {
    private struct Setup {
        let client: InMemoryRemoteFileClient
        let creator: RecordingAssetCreator
        let records: RecordBox
        let work: URL
    }

    final class RecordBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _rows: [ServerDownloadRecord] = []
        var rows: [ServerDownloadRecord] { lock.withLock { _rows } }
        func add(_ row: ServerDownloadRecord) { lock.withLock { _rows.append(row) } }
    }

    private func setup() -> Setup {
        Setup(client: InMemoryRemoteFileClient(), creator: RecordingAssetCreator(), records: RecordBox(),
              work: FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexDownload-test-\(UUID().uuidString)"))
    }

    private func session(_ setup: Setup, albumId: String? = nil) -> ServerDownloadSession {
        let records = setup.records
        return ServerDownloadSession(client: setup.client, creator: setup.creator, serverId: "S1", serverName: "NAS",
                                     workDirectory: setup.work, albumId: albumId, record: { records.add($0) })
    }

    private func put(_ setup: Setup, _ name: String, _ data: Data, modified: Date? = nil) -> RemoteEntry {
        setup.client.put("Trip/\(name)", data)
        if let modified { setup.client.modified["Trip/\(name)"] = modified }
        return RemoteEntry(name: name, isDirectory: false, size: Int64(data.count), modified: modified)
    }

    /// AC-8.
    @Test func pairBecomesOneAsset() async throws {
        let setup = setup()
        let jpg = put(setup, "A.JPG", RemoteThumbnailTests.jpeg(width: 600, date: "2022:10:10 16:23:07"))
        // A JPEG named .DNG: a RAW by extension that ImageIO still opens.
        let raw = put(setup, "A.DNG", RemoteThumbnailTests.jpeg(width: 800))
        let photo = ServerPhoto(files: [jpg, raw])
        let result = await session(setup).run([ServerDownloadItem(photo: photo, folder: "Trip")])

        #expect(result.outcomes == [.saved(assetId: "asset-1")])
        let request = try #require(setup.creator.requests.first)
        #expect(request.resources.map(\.role) == [.photo, .alternatePhoto])
        #expect(request.resources.map(\.originalFilename) == ["A.JPG", "A.DNG"])
        #expect(setup.creator.sizes.first == [Int(jpg.size), Int(raw.size)])
        let expected = try #require(EmbeddedPreview.parseEXIFDate("2022:10:10 16:23:07", timeZone: .current))
        #expect(request.creationDate == expected)
        #expect(request.albumId == nil)
        #expect(setup.records.rows.map(\.remotePath) == ["Trip/A.JPG", "Trip/A.DNG"])
        #expect(setup.records.rows.allSatisfy { $0.assetId == "asset-1" && $0.sha256.count == 64 })
        #expect(!FileManager.default.fileExists(atPath: setup.work.path))
    }

    /// AC-9.
    @Test func sizeMismatchFails() async throws {
        let setup = setup()
        let a = put(setup, "A.JPG", RemoteThumbnailTests.jpeg(width: 300))
        let b = put(setup, "B.JPG", RemoteThumbnailTests.jpeg(width: 300))
        setup.client.truncateDownload = ["Trip/A.JPG"]
        let result = await session(setup).run([a, b].map { ServerDownloadItem(photo: ServerPhoto(files: [$0]), folder: "Trip") })
        guard case .failed(let reason) = result.outcomes[0] else { Issue.record("expected failure"); return }
        #expect(reason.contains("incomplete"))
        #expect(result.outcomes[1] == .saved(assetId: "asset-1"))
        #expect(setup.creator.requests.count == 1)
    }

    /// AC-10.
    @Test func knownChecksumMustMatch() async throws {
        let setup = setup()
        let a = put(setup, "A.JPG", RemoteThumbnailTests.jpeg(width: 300))
        let item = ServerDownloadItem(photo: ServerPhoto(files: [a]), folder: "Trip", knownChecksums: ["A.JPG": String(repeating: "0", count: 64)])
        let result = await session(setup).run([item])
        guard case .failed = result.outcomes[0] else { Issue.record("expected failure"); return }
        #expect(setup.creator.requests.isEmpty)
    }

    /// AC-11.
    @Test func connectionLossStops() async throws {
        let setup = setup()
        let items = (0..<5).map { n in
            ServerDownloadItem(photo: ServerPhoto(files: [put(setup, "P\(n).JPG", RemoteThumbnailTests.jpeg(width: 200 + n))]), folder: "Trip")
        }
        setup.client.dropConnectionOnDownload = 3
        let result = await session(setup).run(items)
        #expect(result.outcomes == [.saved(assetId: "asset-1"), .saved(assetId: "asset-2"), .notAttempted, .notAttempted, .notAttempted])
        #expect(result.stopReason == .error(.connectionLost))
        #expect(setup.records.rows.count == 2)
    }

    /// AC-12 (session half): the album travels with every request.
    @Test func savesIntoAlbum() async throws {
        let setup = setup()
        let a = put(setup, "A.JPG", RemoteThumbnailTests.jpeg(width: 300))
        let b = put(setup, "B.JPG", RemoteThumbnailTests.jpeg(width: 300))
        _ = await session(setup, albumId: "album-trip").run([a, b].map { ServerDownloadItem(photo: ServerPhoto(files: [$0]), folder: "Trip") })
        #expect(setup.creator.requests.map(\.albumId) == ["album-trip", "album-trip"])
    }

    @Test func refusedFormatFailsThatPhotoOnly() async throws {
        let setup = setup()
        let webp = put(setup, "A.webp", RemoteThumbnailTests.jpeg(width: 300))
        let jpg = put(setup, "B.JPG", RemoteThumbnailTests.jpeg(width: 300))
        setup.creator.refuses = ["webp"]
        let result = await session(setup).run([webp, jpg].map { ServerDownloadItem(photo: ServerPhoto(files: [$0]), folder: "Trip") })
        #expect(result.outcomes[0] == .failed("Photos can't store this format (WEBP)."))
        #expect(result.outcomes[1] == .saved(assetId: "asset-1"))
    }

    @Test func noExifFallsBackToWriteDate() async throws {
        let setup = setup()
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        let a = put(setup, "A.png", RemoteThumbnailTests.jpeg(width: 300), modified: written)
        _ = await session(setup).run([ServerDownloadItem(photo: ServerPhoto(files: [a]), folder: "Trip")])
        #expect(setup.creator.requests.first?.creationDate == written)
    }
}
