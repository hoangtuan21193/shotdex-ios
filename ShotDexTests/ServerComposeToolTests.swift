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
}
