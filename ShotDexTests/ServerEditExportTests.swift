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
                render: { photo, format, folder in
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
}
