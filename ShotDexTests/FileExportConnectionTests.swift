import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §7–8 / FS-03.07c AC-14 (second half): Export… to a saved
/// connection goes up with the upload's guarantees and writes no upload
/// history; the server export sheet's Other Folder… has Folder in Files…
/// with Export…'s own recents.
extension FileExportRunnerTests {
    @Test func toAConnectionWritesNoUploadHistory() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let database = try AppDatabase.makeEmpty()
        let uploads = ServerUploadStore(database: database)
        let client = InMemoryRemoteFileClient()
        var items: [FileExportItem] = []
        for index in 1...3 {
            let file = try fixture.file("p\(index)", "IMG_000\(index).JPG", role: .photo,
                                        data: ExportFixture.image(width: 600, height: 400, gray: 0.4))
            items.append(FileExportItem(id: "p\(index)", filename: file.filename, captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file], pixelWidth: 600, pixelHeight: 400))
        }
        let writer = RemoteFolderWriter(access: DirectRemoteAccess(client), folder: "Trip/Exports",
                                        scratch: fixture.root.appendingPathComponent("remote"))
        let names = try await writer.existingNames(in: "")
        let plan = FileExportPlan.make(items: items, mode: .currentVersion, template: .originalName, policy: .keepBoth,
                                       dateFolders: false, includesLivePhotoVideo: true, renderExtension: { _ in "jpg" },
                                       existing: ["": names])
        let runner = FileExportRunner(source: fixture.source, writer: writer, rendering: KitExportRenderer(),
                                      workDirectory: fixture.root.appendingPathComponent("work"))

        let report = await runner.run(FileExportJob(plan: plan, mode: .currentVersion,
                                                    render: FileExportRenderOptions(preset: .original, format: .jpeg)))

        #expect(report.writtenCount == 3 && report.failed.isEmpty)
        #expect(Set(client.files.keys) == ["Trip/Exports/IMG_0001.jpg", "Trip/Exports/IMG_0002.jpg", "Trip/Exports/IMG_0003.jpg"])
        #expect(!client.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        // Nothing says these photos are backed up: no history row, so no
        // grid glyph and no offer to delete them.
        #expect(try uploads.count() == 0)
        #expect(try uploads.uploadedAssetIds().isEmpty)
        // The scratch copy of each render is gone.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("remote").path)) ?? []).isEmpty)
    }

    /// A connection that drops stops the batch like a pulled drive; one that
    /// refuses the write offers another folder.
    @Test func connectionFailuresStopTheBatch() {
        #expect(RemoteFolderWriter.failure(RemoteFileError.connectionLost) as? FileExportFailure == .disconnected)
        #expect(RemoteFolderWriter.failure(RemoteFileError.permissionDenied("x")) as? FileExportFailure == .permissionDenied)
        #expect(RemoteFolderWriter.failure(RemoteFileError.serverFull) as? FileExportFailure == .full)
    }
}

extension ServerExportSizeTests {
    /// Other Folder… → Folder in Files…: the folder joins Export…'s recents
    /// — the Export sheet lists it first — and the render lands there as
    /// `a_edited.jpg`, through the part name.
    @Test func folderInFilesUsesTheSameRecents() async throws {
        let fixture = ServerEditExportTests.Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")
        let defaults = try #require(UserDefaults(suiteName: "FolderInFiles-\(UUID().uuidString)"))
        let store = ExportFolderStore(defaults: defaults)
        let folder = fixture.directory.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var services = fixture.services()
        services.writeToFiles = { file, name, id in
            try await ServerExportModel.writeToFiles(file, name: name, folderId: id, store: store)
        }
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        let model = ServerExportModel(photos: [photo], originServer: server,
                                      renderDirectory: fixture.directory.appendingPathComponent("exports"), services: services)

        model.chooseFilesFolder(folder, in: store)

        #expect(ExportFolderStore(defaults: defaults).current?.name == "Client")
        #expect(model.resolvedDestinations.contains { if case .filesFolder = $0 { true } else { false } })
        model.export()
        for _ in 0..<3_000 where model.stage == .exporting { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.stage == .done)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a_edited.jpg"])
    }
}
