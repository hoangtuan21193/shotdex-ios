import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShotDex

/// FS-17.06 §5b: Collage, Combine Photos and the Video Studio on server
/// photos — the tool reads the copies on this device and hands one file to
/// the export sheet; nothing reaches Photos or Creations on its own.
@Suite struct ServerComposeToolTests {
    /// Server photos fetched to a work directory, as flat-colour JPEGs.
    struct Run {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexServerEdit-tools-\(UUID().uuidString)", isDirectory: true)

        func photos(_ names: [String], width: Int = 1200, height: Int = 800, dates: [String?]? = nil) throws -> [FetchedServerPhoto] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try names.enumerated().map { index, name in
                let url = directory.appendingPathComponent(name)
                try ServerComposeSourceTests.writeJPEG(width: width, height: height, date: dates?[index] ?? nil, to: url)
                let entry = RemoteEntry(name: name, isDirectory: false, size: 1, modified: nil)
                return FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                          files: [FetchedFile(file: entry, url: url, sha256: "")])
            }
        }
    }

    @MainActor
    private func collage(_ photos: [FetchedServerPhoto], run: Run) -> CollageEditorModel {
        let dependencies = AppDependencies.preview()
        return CollageEditorModel(
            photos: photos.map(PhotoEditOrigin.serverFile),
            photoLibrary: dependencies.photoLibrary,
            indexPipeline: dependencies.indexPipeline,
            overlayFontRecents: dependencies.overlayFontRecents,
            presetStore: dependencies.collagePresets,
            creationStore: nil,
            serverWorkDirectory: run.directory
        )
    }

    /// AC-67: four server photos → Export… gives a file for the sheet, not
    /// an asset; the default name follows the first placed photo.
    @MainActor
    @Test func collageExportsToAFileNotToPhotos() async throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(["DSCF1000.JPG", "DSCF1001.JPG", "DSCF1002.JPG", "DSCF1003.JPG"])
        let model = collage(photos, run: run)
        #expect(model.isServerRun)
        #expect(model.recipe.cells.compactMap(\.assetID) == photos.map(\.id))

        await model.export(CollageExportOptions(size: .k2, quality: 80, format: .jpeg, keepFirstPhotoEXIF: true))

        let file = try #require(model.composedFile)
        #expect(file.path.hasPrefix(run.directory.path))
        #expect(file.pathExtension == "jpg")
        #expect(model.didSaveAssetID == nil)
        #expect(model.firstPlacedFilename == "DSCF1000.JPG")
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 1000)
    }

    /// AC-83: nothing done → Close asks nothing; a layout change → it asks.
    @MainActor
    @Test func collageAsksBeforeDiscardingOnlyAfterAChange() throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let model = collage(try run.photos(["a.JPG", "b.JPG", "c.JPG"]), run: run)
        #expect(!model.hasEdits)
        let other = try #require(model.availableTemplates.first { $0.id != model.recipe.templateID })
        model.selectTemplate(other.id)
        #expect(model.hasEdits)
    }

    /// AC-79: frames named in one order but shot in the other stack in
    /// shooting order — the EXIF date in each file decides.
    @MainActor
    @Test func focusStackOrdersByEXIF() throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(
            ["DSCF1000.JPG", "DSCF1001.JPG", "DSCF1002.JPG"], width: 64, height: 48,
            dates: ["2026:09:28 07:15:32", "2026:09:28 07:15:31", "2026:09:28 07:15:30"]
        )
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(
            purpose: .focusStack, photos: photos.map(PhotoEditOrigin.serverFile),
            photoLibrary: dependencies.photoLibrary, indexPipeline: dependencies.indexPipeline,
            serverWorkDirectory: run.directory
        )
        #expect(model.photos.map(\.filename) == ["DSCF1002.JPG", "DSCF1001.JPG", "DSCF1000.JPG"])
        #expect(model.composedTool == .focusStack)
    }

    /// AC-79: Stack Exposures on server copies saves a file for the export
    /// sheet, and nothing to Photos.
    @MainActor
    @Test func stackExposuresSavesAFileForTheSheet() async throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(["DSCF1000.JPG", "DSCF1001.JPG"], width: 320, height: 200)
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(
            purpose: .stackExposures, photos: photos.map(PhotoEditOrigin.serverFile),
            photoLibrary: dependencies.photoLibrary, indexPipeline: dependencies.indexPipeline,
            serverWorkDirectory: run.directory
        )
        #expect(model.composedTool == .stack)
        await model.loadFrames()
        for _ in 0..<3000 where !model.canSave { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.loadedPhotos.count == 2)
        model.save()
        for _ in 0..<3000 where model.composedFile == nil && model.failure == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let file = try #require(model.composedFile)
        #expect(file.path.hasPrefix(run.directory.path))
        #expect(model.savedAssetID == nil)
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 320)
    }

    /// AC-80: a panorama frame of a server photo comes from its file, and
    /// the stitched file lands in the run's work directory, not in Photos.
    @Test func panoramaReadsFilesAndKeepsTheResultInTheRun() async throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(["DSCF1000.JPG"], width: 640, height: 480, dates: ["2026:09:28 07:15:30"])

        let frame = try #require(await PanoramaStitchService.frame(for: .serverFile(photos[0])))
        #expect(frame.width == 640 && frame.height == 480)
        #expect(frame.properties[kCGImagePropertyPixelWidth] as? Int == 640)

        let stitched = run.directory.appendingPathComponent("scratch-panorama.jpg")
        try Data("panorama".utf8).write(to: stitched)
        let service = PanoramaStitchService.composing(into: run.directory)
        let identifier = try await service.saveFile(stitched, "panorama-640x480.jpg")
        #expect(identifier.hasPrefix(run.directory.path))
        #expect(identifier.hasSuffix("panorama-640x480.jpg"))
        #expect(FileManager.default.fileExists(atPath: identifier))
        #expect(!FileManager.default.fileExists(atPath: stitched.path))
    }

    /// AC-84: a 6000×4000 server original reaches the video compositor at
    /// the render size, never decoded whole.
    @Test func videoStillsDecodeAtTheRenderSize() throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photo = try run.photos(["DSCF1000.JPG"], width: 6000, height: 4000)[0]
        let store = StillFrameStore(targetLongEdge: 1280, files: [photo.id: photo.primaryURL])
        let image = try #require(store.image(for: photo.id))
        #expect(max(image.extent.width, image.extent.height) == 1280)
        #expect(store.image(for: "not-a-clip") == nil)
    }

    /// AC-81: three server photos make a project of photo clips that loads
    /// from the copies, exports to an .mp4 in the run's work directory for
    /// the export sheet, and leaves Photos and Creations alone.
    @MainActor
    @Test func videoOfServerPhotosExportsToAFile() async throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(["DSCF1000.JPG", "DSCF1001.JPG", "DSCF1002.JPG"], width: 640, height: 480)
        let dependencies = AppDependencies.preview()
        let model = VideoStudioModel(
            photos: photos.map(PhotoEditOrigin.serverFile),
            mode: .multiClip,
            service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary,
            overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages,
            creationStore: nil,
            serverWorkDirectory: run.directory
        )
        defer { model.close() }
        #expect(model.isServerRun)
        #expect(model.recipe.clips.map(\.assetID) == photos.map(\.id))
        #expect(model.recipe.clips.allSatisfy { $0.kind == .photo })
        #expect(model.serverFileURL(for: photos[0].id) == photos[0].primaryURL)

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.recipe.clips.count == 3)

        model.export()
        for _ in 0..<6000 where model.composedFile == nil {
            if case .failed = model.exportState { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let file = try #require(model.composedFile)
        #expect(file.path.hasPrefix(run.directory.path))
        #expect(file.pathExtension == "mp4")
        #expect(model.savedAssetID == nil)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0 > 0)
    }

    /// AC-82: a collage or video of server photos refuses files dropped from
    /// another app; a library one still takes them.
    @MainActor
    @Test func serverRunsRefuseFilesFromOtherApps() throws {
        let run = Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photos = try run.photos(["a.JPG", "b.JPG"], width: 64, height: 48)
        #expect(!collage(photos, run: run).acceptsFilesFromOtherApps)

        let dependencies = AppDependencies.preview()
        let library = CollageEditorModel(
            photos: [], photoLibrary: dependencies.photoLibrary, indexPipeline: dependencies.indexPipeline,
            overlayFontRecents: dependencies.overlayFontRecents, presetStore: dependencies.collagePresets
        )
        #expect(library.acceptsFilesFromOtherApps)

        let video = VideoStudioModel(
            photos: photos.map(PhotoEditOrigin.serverFile), mode: .multiClip,
            service: dependencies.videoStudio, photoLibrary: dependencies.photoLibrary,
            overlayFontRecents: dependencies.overlayFontRecents, overlayImages: dependencies.overlayImages,
            serverWorkDirectory: run.directory
        )
        defer { video.close() }
        #expect(!video.acceptsFilesFromOtherApps)
    }
}
