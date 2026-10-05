import Foundation
import ImageIO
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §8 / FS-03.07c AC-14 (first half): the server export sheet
/// offers the Resize presets — the user's own included, Original first — on
/// every per-photo export, and a preset renders at its own size and format.
@Suite @MainActor struct ServerExportSizeTests {
    static let client3000 = ResizePreset(name: "Client 3000", kind: .longEdge, longEdge: 3_000, quality: 0.9, format: .jpeg)

    private func model(
        _ fixture: ServerEditExportTests.Fixture,
        photos: [FetchedServerPhoto],
        services: ServerExportServices? = nil,
        startingSize: ResizePreset = .original,
        composed: ServerExportModel.ComposedSource? = nil
    ) -> ServerExportModel {
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        return ServerExportModel(
            photos: photos, originServer: server,
            renderDirectory: fixture.directory.appendingPathComponent("exports"),
            services: services ?? fixture.services(),
            sizePresets: ResizePreset.builtIns + [Self.client3000],
            startingSize: startingSize,
            composed: composed
        )
    }

    /// Edit and Paste Edits (no Resize) offer every preset, Original first
    /// and picked; one file a tool made offers none.
    @Test func everyNonComposedExportOffersAllPresets() throws {
        let fixture = ServerEditExportTests.Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")

        let edit = model(fixture, photos: [photo])
        #expect(edit.sizePresets.map(\.name) == ["Original", "4K", "2048 px", "1080 px", "Client 3000"])
        #expect(edit.sizePreset.id == ResizePreset.original.id)
        // Original at full size renders as it always did: no resize pass.
        #expect(edit.resize == nil)

        // The store's list already starts with Original; it is listed once.
        #expect(ServerExportSizes.offered(ResizePreset.builtIns).map(\.name) == ["Original", "4K", "2048 px", "1080 px"])

        let file = fixture.directory.appendingPathComponent("collage.jpg")
        let composed = model(fixture, photos: [photo], composed: .init(file: file, tool: .collage, firstFilename: "a.JPG"))
        #expect(composed.sizePresets.isEmpty)
    }

    /// Resize starts at 2048 px, not at the first preset.
    @Test func resizeStartsAt2048() throws {
        let fixture = ServerEditExportTests.Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photo = try fixture.photo("a.JPG")

        let resize = model(fixture, photos: [photo], startingSize: .twoK)

        #expect(resize.sizePreset.name == "2048 px")
        #expect(resize.resize?.longEdge == 2_048)
        #expect(resize.sizePresets.first?.name == "Original")
    }

    /// AC-14: *Client 3000* (long side 3000, JPEG 90%) on `a.JPG` 6000×4000
    /// — Format follows the preset, and the server gets `a_edited.jpg` at
    /// 3000×2000 through the part name and the checksum; `a.JPG` untouched.
    @Test func customPresetRendersAtItsSize() async throws {
        let fixture = ServerEditExportTests.Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = ServerEditHandoffTests.jpeg(width: 6_000, height: 4_000)
        let photo = try fixture.photo("a.JPG", bytes: original)
        let service = PhotoEditingService()
        defer { service.releaseCachedSessions() }
        var services = fixture.services()
        let resizes = ResizeBox()
        services.render = { photo, format, resize, _, folder in
            resizes.add(resize)
            return try await EditorBatchSaver.renderToFile(
                photo, recipe: .identity, service: service, format: format == .heic ? .heic : .jpeg,
                metadata: .all, resize: resize, into: folder
            )
        }
        let model = model(fixture, photos: [photo], services: services)
        model.format = .heic

        model.chooseSize(try #require(model.sizePresets.first { $0.name == "Client 3000" }))
        #expect(model.format == .jpeg)
        model.toggle(.originalFolder)
        model.export()
        for _ in 0..<6000 where model.stage == .exporting { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(model.stage == .done)
        #expect(resizes.items.map { $0?.name } == ["Client 3000"])
        let edited = try #require(fixture.client.files["Trip/a_edited.jpg"])
        let source = try #require(CGImageSourceCreateWithData(edited as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 3_000)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2_000)
        #expect(fixture.client.files["Trip/a.JPG"] == original)
        #expect(!fixture.client.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    final class ResizeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [ResizePreset?] = []
        var items: [ResizePreset?] { lock.withLock { _items } }
        func add(_ preset: ResizePreset?) { lock.withLock { _items.append(preset) } }
    }
}
