import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-17.06 §6: rendered edits land on the server beside their originals,
/// in Photos, or in a share — and the originals stay unless replaced on
/// purpose.
@Suite struct ServerEditExportTests {
    /// A photo as the fetch leaves it: its bytes on the server, a copy on
    /// this device.
    struct Fixture {
        let client = InMemoryRemoteFileClient()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexServerEdit-test-\(UUID().uuidString)", isDirectory: true)

        func photo(_ name: String, in folder: String = "Trip", bytes: Data? = nil) throws -> FetchedServerPhoto {
            let data = bytes ?? Data("original \(name)".utf8)
            client.put(ServerUploadPath.join(folder, name), data)
            let local = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            let url = local.appendingPathComponent(name)
            try data.write(to: url)
            let entry = RemoteEntry(name: name, isDirectory: false, size: Int64(data.count), modified: nil)
            return FetchedServerPhoto(serverId: "S1", folder: folder, photo: ServerPhoto(files: [entry]),
                                      files: [FetchedFile(file: entry, url: url, sha256: "")])
        }

        /// Renders write "edited <name>" in the asked format.
        func services(
            access: [String: any RemoteFileAccess] = [:],
            saved: SavedBox = SavedBox()
        ) -> ServerExportServices {
            ServerExportServices(
                render: { photo, format, _, folder in
                    let url = folder.appendingPathComponent("render.\(format.fileExtension)")
                    try Data("edited \(photo.photo.primary.name) \(format.rawValue)".utf8).write(to: url)
                    return url
                },
                originAccess: DirectRemoteAccess(client),
                access: { id in
                    guard let found = access[id] else { throw RemoteFileError.unreachable(host: id) }
                    return found
                },
                saveToPhotos: { url, name in saved.add(name, try Data(contentsOf: url)) }
            )
        }

        func exporter(_ services: ServerExportServices) -> ServerEditExporter {
            ServerEditExporter(services: services, renderDirectory: directory.appendingPathComponent("exports"))
        }
    }

    final class SavedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [(name: String, data: Data)] = []
        var items: [(name: String, data: Data)] { lock.withLock { _items } }
        func add(_ name: String, _ data: Data) -> String {
            lock.withLock { _items.append((name, data)); return "asset-\(_items.count)" }
        }
    }

    /// AC-60: Original Folder + Save as New File — `a_edited.jpg` beside
    /// `a.JPG`, checked, and `a.JPG` byte for byte as it was.
    @Test func newFileBesideOriginal() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let original = fixture.client.files["Trip/a.JPG"]

        let report = await fixture.exporter(fixture.services()).run(.init(
            photos: [photo], destinations: [.originalFolder], placement: .newFile, format: .jpeg
        ))

        #expect(report.outcome(.originalFolder, photo.id) == .done("Trip/a_edited.jpg"))
        #expect(report.isComplete(photos: [photo], destinations: [.originalFolder]))
        #expect(fixture.client.files["Trip/a_edited.jpg"] == Data("edited a.JPG jpeg".utf8))
        #expect(fixture.client.files["Trip/a.JPG"] == original)
        #expect(!fixture.client.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// AC-61: `a_edited.jpg` is already there — the second export is
    /// `a_edited (2).jpg`, and the first is left alone.
    @Test func nameCollisionNumbers() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        fixture.client.put("Trip/a_edited.jpg", Data("earlier".utf8))

        let report = await fixture.exporter(fixture.services()).run(.init(
            photos: [photo], destinations: [.originalFolder], placement: .newFile, format: .jpeg
        ))

        #expect(report.outcome(.originalFolder, photo.id) == .done("Trip/a_edited (2).jpg"))
        #expect(fixture.client.files["Trip/a_edited.jpg"] == Data("earlier".utf8))
        #expect(fixture.client.files["Trip/a_edited (2).jpg"] == Data("edited a.JPG jpeg".utf8))
    }

    /// AC-62: Replace Original — `a.JPG` carries the edit under its own name,
    /// rendered in its own format even when HEIC was picked, and no
    /// `_edited` file appears.
    @Test func replaceNeedsConfirm() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")

        let report = await fixture.exporter(fixture.services()).run(.init(
            photos: [photo], destinations: [.originalFolder], placement: .replaceOriginal, format: .heic
        ))

        #expect(report.outcome(.originalFolder, photo.id) == .done("Trip/a.JPG"))
        #expect(fixture.client.files["Trip/a.JPG"] == Data("edited a.JPG jpeg".utf8))
        #expect(fixture.client.files.keys.sorted() == ["Trip/a.JPG"])
    }

    /// A replacement that fails its read-back leaves the original where it
    /// was: the original goes only after the new file checked out.
    @Test func replaceKeepsOriginalWhenTheCheckFails() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let original = fixture.client.files["Trip/a.JPG"]
        fixture.client.corruptReadBack = ["Trip/a.JPG"]

        let report = await fixture.exporter(fixture.services()).run(.init(
            photos: [photo], destinations: [.originalFolder], placement: .replaceOriginal, format: .jpeg
        ))

        guard case .failed = report.outcome(.originalFolder, photo.id) else {
            Issue.record("expected the checksum to fail the write")
            return
        }
        #expect(fixture.client.files["Trip/a.JPG"] == original)
        #expect(!fixture.client.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// AC-63: an original in RAW, or a RAW+JPEG pair, cannot be replaced; a
    /// lone JPEG or HEIC can.
    @Test func rawCannotBeReplaced() {
        func photo(_ names: String...) -> ServerPhoto {
            ServerPhoto(files: names.map { RemoteEntry(name: $0, isDirectory: false, size: 1, modified: nil) })
        }
        #expect(!ServerExportRules.canReplaceOriginal(photo("b.CR3")))
        #expect(!ServerExportRules.canReplaceOriginal(photo("c.JPG", "c.NEF")))
        #expect(!ServerExportRules.canReplaceOriginal(photo("d.PNG")))
        #expect(ServerExportRules.canReplaceOriginal(photo("a.JPG")))
        #expect(ServerExportRules.canReplaceOriginal(photo("e.heic")))
        #expect(ServerExportRules.replacementFormat(for: photo("e.heic")) == .heic)
    }

    /// AC-64: Photos Library + another connection's `/sel` + Share, in one
    /// run — one new asset, `sel/a_edited.jpg` on the other server, and the
    /// share handed the same render last.
    @Test func multipleDestinations() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let other = InMemoryRemoteFileClient()
        other.addDirectory("sel")
        let saved = SavedBox()
        let destinations: Set<ServerExportDestination> = [
            .photosLibrary, .otherFolder(serverId: "S2", serverName: "Mac", path: "sel"), .share,
        ]

        let report = await fixture.exporter(fixture.services(access: ["S2": DirectRemoteAccess(other)], saved: saved))
            .run(.init(photos: [photo], destinations: destinations, placement: .newFile, format: .jpeg))

        #expect(report.isComplete(photos: [photo], destinations: destinations))
        #expect(saved.items.map(\.name) == ["a_edited.jpg"])
        #expect(saved.items.first?.data == Data("edited a.JPG jpeg".utf8))
        #expect(other.files["sel/a_edited.jpg"] == Data("edited a.JPG jpeg".utf8))
        #expect(report.shareFiles.count == 1)
        #expect(try Data(contentsOf: try #require(report.shareFiles.first)) == Data("edited a.JPG jpeg".utf8))
        // The origin server was not written to.
        #expect(fixture.client.uploadCount == 0)
    }

    /// A server that refuses writes, whatever the path.
    final class RefusingClient: RemoteFileClient, @unchecked Sendable {
        let inner = InMemoryRemoteFileClient()
        func connect() async throws {}
        func disconnect() async {}
        func fileSize(at path: String) async throws -> Int64? { try await inner.fileSize(at: path) }
        func directoryExists(_ path: String) async throws -> Bool { true }
        func fileNames(in directory: String) async throws -> Set<String> { try await inner.fileNames(in: directory) }
        func folderNames(in directory: String) async throws -> Set<String> { [] }
        func createDirectory(_ path: String) async throws {}
        func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
            throw RemoteFileError.permissionDenied(path)
        }
        func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { "" }
        func entries(in directory: String) async throws -> [RemoteEntry] { [] }
        func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data { Data() }
        func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { "" }
        func move(_ source: String, to destination: String) async throws {}
        private(set) var removed: [String] = []
        func remove(_ path: String) async throws { removed.append(path) }
        func removeEmptyDirectory(_ path: String) async throws {}
    }

    /// A server that is gone.
    final class OfflineAccess: RemoteFileAccess, @unchecked Sendable {
        var isOffline = true
        let client: InMemoryRemoteFileClient
        init(_ client: InMemoryRemoteFileClient) { self.client = client }
        func perform<T: Sendable>(_ work: @Sendable (any RemoteFileClient) async throws -> T) async throws -> T {
            if isOffline { throw RemoteFileError.connectionLost }
            return try await work(client)
        }
    }

    @MainActor
    private func model(_ fixture: Fixture, photos: [FetchedServerPhoto], services: ServerExportServices) -> ServerExportModel {
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        return ServerExportModel(photos: photos, originServer: server,
                                 renderDirectory: fixture.directory.appendingPathComponent("exports"), services: services)
    }

    @MainActor
    private func waitWhileExporting(_ model: ServerExportModel) async {
        for _ in 0..<3000 where model.stage == .exporting {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// AC-69: the server drops while Original Folder is written, Photos has
    /// already worked — Photos is done, Original Folder failed, the copies
    /// and the edit stay; Retry Failed sends only what is missing.
    @Test @MainActor func failedDestinationKeepsDraft() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let offline = OfflineAccess(fixture.client)
        let saved = SavedBox()
        var services = fixture.services(saved: saved)
        services.originAccess = offline
        let model = model(fixture, photos: [photo], services: services)
        model.toggle(.originalFolder)
        model.toggle(.photosLibrary)

        model.export()
        await waitWhileExporting(model)

        #expect(model.stage == .finishedWithFailures)
        #expect(model.report.outcome(.photosLibrary, photo.id) == .done("asset-1"))
        #expect(model.report.failedDestinations == [.originalFolder])
        #expect(FileManager.default.fileExists(atPath: photo.primaryURL.path))

        offline.isOffline = false
        model.retryFailed()
        await waitWhileExporting(model)

        #expect(model.stage == .done)
        #expect(saved.items.count == 1)
        #expect(fixture.client.files["Trip/a_edited.jpg"] != nil)
    }

    /// AC-65: the folder refuses the write — that destination says so and
    /// offers another folder; nothing half-written is left; Choose Another
    /// Folder finishes the run there.
    @Test @MainActor func permissionDeniedOffersAnotherFolder() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let refusing = RefusingClient()
        let other = InMemoryRemoteFileClient()
        var services = fixture.services(access: ["S2": DirectRemoteAccess(other)])
        services.originAccess = DirectRemoteAccess(refusing)
        let model = model(fixture, photos: [photo], services: services)
        model.toggle(.originalFolder)

        model.export()
        await waitWhileExporting(model)

        #expect(model.stage == .finishedWithFailures)
        #expect(model.report.outcome(.originalFolder, photo.id) == .permissionDenied)
        #expect(model.hasPermissionDenied)
        #expect(refusing.removed == ["Trip/a_edited.jpg\(ServerUploadPath.partSuffix)"])
        #expect(FileManager.default.fileExists(atPath: photo.primaryURL.path))

        var mac = FileServer(name: "Mac", transferProtocol: .sftp, host: "mac.local", username: "u")
        mac.id = "S2"
        model.chooseAnotherFolder(.init(server: mac, path: ""))
        await waitWhileExporting(model)

        #expect(model.stage == .done)
        #expect(other.files["a_edited.jpg"] == Data("edited a.JPG jpeg".utf8))
    }
}
