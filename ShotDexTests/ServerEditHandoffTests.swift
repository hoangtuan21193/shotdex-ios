import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
import ShotDexKit

/// FS-17.06 §3–4: Share, Copy, Paste Edits, Resize and Export EXIF on
/// server photos.
@Suite @MainActor struct ServerEditHandoffTests {
    /// A striped JPEG, optionally with a GPS position.
    static func jpeg(width: Int, height: Int, gps: Bool = false) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:00:00",
                                             kCGImagePropertyExifISOSpeedRatings: [200]],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "X-T5"],
        ]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 35.68, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.76, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func entry(_ name: String, _ size: Int) -> RemoteEntry {
        RemoteEntry(name: name, isDirectory: false, size: Int64(size), modified: nil)
    }

    /// Photos on a fake server, fetched as a command fetches them.
    private func fetch(_ files: [(String, Data)]) async throws -> (ServerPhotoCommandRun, InMemoryRemoteFileClient) {
        let client = InMemoryRemoteFileClient()
        for (name, data) in files { client.put("Trip/\(name)", data) }
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip",
            photos: files.map { ServerPhoto(files: [entry($0.0, $0.1.count)]) },
            access: DirectRemoteAccess(client), freeSpace: { nil }, screenHold: ServerEditSessionTests.NoHold()
        )
        model.start()
        for _ in 0..<3000 where model.stage == .downloading { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.stage == .fetched)
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        return (ServerPhotoCommandRun(command: .share, server: server, access: DirectRemoteAccess(client), fetch: model), client)
    }

    private func gps(of url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    }

    private func pixelSize(of url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// AC-74 / FS-08.06 AC-13: Share at No Location hands over the
    /// original's pixels minus GPS, under its own name; at All Metadata the
    /// bytes as they are. The copies go when the share closes.
    @Test func shareHandsOriginalAndCleansUp() async throws {
        let (run, client) = try await fetch([("a.JPG", Self.jpeg(width: 300, height: 200, gps: true))])
        let directory = try #require(run.fetch.workDirectory)
        let (sources, reader) = ServerPhotoHandoff.shareSources(for: run.photos)

        let stripped = await ShareExportPipeline(
            reader: reader, folder: try ShareExportPipeline.makeFolder(in: directory), level: .noLocation
        ).export(sources)
        let kept = await ShareExportPipeline(
            reader: reader, folder: try ShareExportPipeline.makeFolder(in: directory), level: .all
        ).export(sources)

        #expect(stripped.files.map(\.lastPathComponent) == ["a.JPG"])
        let shared = try #require(stripped.files.first)
        #expect(gps(of: shared) == nil)
        #expect(try Data(contentsOf: try #require(kept.files.first)) == Data(contentsOf: run.photos[0].primaryURL))
        #expect(gps(of: run.photos[0].primaryURL) != nil)
        #expect(client.uploadCount == 0)

        run.discardCopies()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!FileManager.default.fileExists(atPath: shared.path))
    }

    /// FS-08.06 AC-13: a RAF + JPG pair at No Location — the RAF is a RAW,
    /// so the share asks; on Skip the JPG goes without GPS and the RAF does
    /// not go at all. Never the RAF with its location by default.
    @Test func rafNeverLeaves() async throws {
        let raf = RAWFixtures.available(RAWFixtures.fuji).flatMap { try? Data(contentsOf: $0) }
            ?? Data(repeating: 0x46, count: 4096)
        let jpg = Self.jpeg(width: 300, height: 200, gps: true)
        let client = InMemoryRemoteFileClient()
        client.put("Trip/DSCF1000.JPG", jpg)
        client.put("Trip/DSCF1000.RAF", raf)
        let model = ServerEditFetchModel(
            serverId: "S1", folder: "Trip",
            photos: [ServerPhoto(files: [entry("DSCF1000.JPG", jpg.count), entry("DSCF1000.RAF", raf.count)])],
            access: DirectRemoteAccess(client), freeSpace: { nil }, screenHold: ServerEditSessionTests.NoHold()
        )
        model.start()
        for _ in 0..<3000 where model.stage == .downloading { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.stage == .fetched)
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        let run = ServerPhotoCommandRun(command: .share, server: server, access: DirectRemoteAccess(client), fetch: model)
        let directory = try #require(run.fetch.workDirectory)

        let (sources, reader) = ServerPhotoHandoff.shareSources(for: run.photos)
        #expect(sources.map(\.kind) == [.photo, .raw])
        #expect(ShareBatchPlan(sources: sources, level: .noLocation).asksAboutRAW)

        // No answer given is Skip: the pipeline's default.
        let result = await ShareExportPipeline(
            reader: reader, folder: try ShareExportPipeline.makeFolder(in: directory), level: .noLocation
        ).export(sources)
        #expect(result.files.map(\.lastPathComponent) == ["DSCF1000.JPG"])
        #expect(result.skipped == ["DSCF1000.RAF"])
        #expect(gps(of: try #require(result.files.first)) == nil)

        run.discardCopies()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// AC-75: Copy of a 6000-px-wide frame puts at most 4096 px on the
    /// pasteboard.
    @Test func copyBoundsAndCleansUp() async throws {
        let (run, _) = try await fetch([("wide.JPG", Self.jpeg(width: 6000, height: 400))])
        let directory = try #require(run.fetch.workDirectory)

        let photo = try #require(run.photos.first)
        let image = try #require(ServerPhotoHandoff.pasteboardImage(for: photo))

        #expect(max(image.width, image.height) == ServerPhotoHandoff.copyMaxPixelSize)
        run.discardCopies()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// AC-72: Paste Edits puts the clipboard's look on every photo and opens
    /// the export, with nothing written anywhere until Export.
    @Test func pasteEditsGoesToExportSheet() async throws {
        let (run, client) = try await fetch([("a.JPG", Self.jpeg(width: 300, height: 200)),
                                             ("b.JPG", Self.jpeg(width: 300, height: 200))])
        defer { run.discardCopies() }
        let defaults = try #require(UserDefaults(suiteName: "ServerEditHandoffTests-\(UUID().uuidString)"))
        let clipboard = EditClipboard(defaults: defaults)
        var look = PhotoEditRecipe.identity
        look.adjustments.exposure = 1
        clipboard.copy(from: look)

        let recipes = ServerPhotoHandoff.pastedRecipes(for: run.photos, clipboard: clipboard)
        let context = try #require(run.exportContext)
        let model = ServerExportModel.make(photos: run.photos, recipes: recipes, context: context,
                                           dependencies: AppDependencies.preview())

        #expect(recipes.count == 2)
        #expect(recipes.values.allSatisfy { $0.adjustments.exposure == 1 })
        #expect(model.photos.count == 2)
        #expect(model.stage == .choosing)
        #expect(client.uploadCount == 0)
    }

    /// AC-73: Resize to a long side of 300 on a 600×400 photo — the export to
    /// the original folder is `a_edited.jpg` at 300×200, and `a.JPG` keeps
    /// its size.
    @Test func resizeExportsThroughSheet() async throws {
        let original = Self.jpeg(width: 600, height: 400)
        let (run, client) = try await fetch([("a.JPG", original)])
        defer { run.discardCopies() }
        let photo = try #require(run.photos.first)
        let service = PhotoEditingService()
        defer { service.releaseCachedSessions() }
        let preset = ResizePreset(name: "300 px", kind: .longEdge, longEdge: 300)
        let render = try await EditorBatchSaver.renderToFile(
            photo, recipe: .identity, service: service, format: .jpeg, metadata: .all,
            resize: preset, into: try #require(run.fetch.workDirectory)
        )
        #expect(render.lastPathComponent == "a_edited.jpg")
        #expect(pixelSize(of: render).map { [$0.0, $0.1] } == [300, 200])

        let report = await ServerEditExporter(
            services: ServerExportServices(
                render: { _, _, _, _ in render },
                originAccess: DirectRemoteAccess(client),
                access: { _ in throw RemoteFileError.connectionLost },
                saveToPhotos: { _, _ in "" }
            ),
            renderDirectory: try #require(run.fetch.workDirectory).appendingPathComponent("Exports")
        ).run(.init(photos: [photo], destinations: [.originalFolder], placement: .newFile, format: .jpeg, resize: preset))

        #expect(report.outcome(.originalFolder, photo.id) == .done("Trip/a_edited.jpg"))
        #expect(client.files["Trip/a.JPG"] == original)
    }

    /// AC-68: Export EXIF on two 3 MB files reads their first megabyte and
    /// nothing else, and still names the camera.
    @Test func readsHeadOnly() async throws {
        let client = InMemoryRemoteFileClient()
        var photos: [ServerPhoto] = []
        for name in ["a.JPG", "b.JPG"] {
            var data = Self.jpeg(width: 400, height: 300)
            data.append(Data(repeating: 0, count: 3_000_000))
            client.put("Trip/\(name)", data)
            photos.append(ServerPhoto(files: [entry(name, data.count)]))
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ServerExifTest-\(UUID().uuidString)")

        let rows = try await ServerExifExport.rows(
            for: photos, in: "Trip", access: DirectRemoteAccess(client),
            composer: MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: [])), scratch: scratch
        )

        #expect(rows.map(\.originalFilename) == ["a.JPG", "b.JPG"])
        #expect(rows.allSatisfy { $0.cameraModel?.contains("X-T5") == true })
        #expect(client.bytesRead <= 2 * ServerExifExport.headBytes)
        #expect(client.downloadCount == 0)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }
}
