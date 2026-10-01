import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
@testable import ShotDexKit

/// FS-01.11 §3–§6 through the screen's model — AC-5, AC-9, AC-10, AC-11,
/// AC-12, AC-15, AC-16, AC-17, AC-22 — on server photos written from the
/// bracket fixture, so no photo library is involved.
@MainActor
@Suite(.serialized) struct HDRStackModelTests {
    static let context = CIContext(options: [.workingFormat: CIFormat.RGBAh])

    /// One fixture frame as an sRGB JPEG with an AEB exposure in its EXIF:
    /// f/8, ISO 100, the shutter carrying the stops.
    static func writeJPEG(_ fixture: HDRBracketFixture, _ frame: [Float], stops: Double, name: String,
                          in folder: URL) throws -> PhotoEditOrigin {
        let url = folder.appendingPathComponent(name)
        let image = try #require(context.createCGImage(fixture.image(frame), from: CGRect(x: 0, y: 0, width: fixture.width, height: fixture.height),
                                                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.98,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R6"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: pow(2, stops) / 125, kCGImagePropertyExifISOSpeedRatings: [100],
                kCGImagePropertyExifFNumber: 8.0, kCGImagePropertyExifExposureBiasValue: stops,
                kCGImagePropertyExifLensModel: "RF24-105mm F4 L IS USM",
            ],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let entry = RemoteEntry(name: name, isDirectory: false, size: 1, modified: nil)
        return .serverFile(FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                              files: [FetchedFile(file: entry, url: url, sha256: "")]))
    }

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func model(_ photos: [PhotoEditOrigin], work: URL? = nil) -> PhotoStackModel {
        let dependencies = AppDependencies.preview()
        return PhotoStackModel(purpose: .hdr, photos: photos, photoLibrary: dependencies.photoLibrary,
                               indexPipeline: dependencies.indexPipeline, serverWorkDirectory: work)
    }

    /// A shuffled ±2 series of the fixture.
    static func series(_ folder: URL, stops: [Double] = [2, -2, 0], fixture: HDRBracketFixture = HDRBracketFixture())
        throws -> [PhotoEditOrigin] {
        let made = fixture.series(stops: stops)
        return try stops.indices.map { try writeJPEG(fixture, made.frames[$0], stops: stops[$0], name: "IMG_\(100 + $0).JPG", in: folder) }
    }

    /// AC-9, AC-10: the panel opens on Medium and 60; changing either
    /// re-renders without reading a frame again.
    @Test func optionsReRenderWithoutReadingFramesAgain() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.model(try Self.series(folder))
        #expect(model.hdrOptions == HDROptions(deghost: .medium, strength: 0.6))
        await model.loadFrames()
        let first = try #require(model.preview)
        let reads = try #require(model.hdr?.frameReads)
        #expect(reads == 3)
        // Darkest first, whatever the order picked.
        #expect(model.loadedPhotos.map(\.filename) == ["IMG_101.JPG", "IMG_102.JPG", "IMG_100.JPG"])
        model.hdrOptions.deghost = .high
        await model.settle()
        model.hdrOptions.strength = 0.2
        await model.settle()
        #expect(model.hdr?.frameReads == reads)
        #expect(model.preview !== first)
        #expect(model.failure == nil)
    }

    /// AC-11: five frames within half a stop still merge, and the panel says
    /// they are not a bracket.
    @Test func aSeriesAtOneExposureMergesAndSaysSo() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.model(try Self.series(folder, stops: [0, 0.1, 0.2, 0.05, 0.15]))
        await model.loadFrames()
        #expect(model.preview != nil)
        #expect(model.hdrNotes.contains { $0.hasPrefix("These photos have about the same exposure.") })
    }

    /// AC-12: where even the darkest frame clips over 1 % of the picture,
    /// the panel says so.
    @Test func highlightsClippedInEveryFrameAreNamed() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.model(try Self.series(folder, stops: [-1, 0, 1], fixture: HDRBracketFixture(dynamicRange: 10, highlightStops: 3)))
        await model.loadFrames()
        #expect(model.hdrNotes.contains("Some highlights are bright in every frame and can't be recovered."))
        let clean = Self.model(try Self.series(folder, stops: [-2, 0, 2], fixture: HDRBracketFixture(dynamicRange: 10, highlightStops: 1.5)))
        await clean.loadFrames()
        #expect(clean.hdrNotes.isEmpty)
    }

    /// AC-5: a frame of another scene is left out, and the panel counts it.
    @Test func aStrayFrameIsLeftOutAndCounted() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = HDRBracketFixture()
        var other = fixture
        other.seed = 4242
        var photos = try Self.series(folder, stops: [-4, -2, 0, 2, 4])
        photos.append(try Self.writeJPEG(other, other.frame(of: other.scene(), stops: 3, seed: 9), stops: 3,
                                         name: "STRAY.JPG", in: folder))
        let model = Self.model(photos)
        await model.loadFrames()
        #expect(model.excludedFrames.count == 1)
        #expect(model.hdrNotes.contains("1 of 6 frames couldn't be lined up and were left out."))
    }

    /// AC-16: a frame that will not load is counted with a Retry, and the
    /// rest still merge.
    @Test func aMissingFrameIsCountedNotDropped() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var photos = try Self.series(folder)
        let entry = RemoteEntry(name: "GONE.JPG", isDirectory: false, size: 1, modified: nil)
        photos.append(.serverFile(FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                                     files: [FetchedFile(file: entry, url: folder.appendingPathComponent("GONE.JPG"), sha256: "")])))
        let model = Self.model(photos)
        await model.loadFrames()
        #expect(model.missingFrameCount == 1)
        #expect(model.missingFramesMessage != nil)
        #expect(model.preview != nil)
    }

    /// AC-15, AC-22: a server run saves the merge as the format asked for,
    /// with the reference frame's gear and none of its exposure.
    @Test(arguments: [PhotoOutputFormat.jpeg, .heic]) func saveWritesTheFormatAndTheReferencesMetadata(format: PhotoOutputFormat) async throws {
        let folder = try Self.folder()
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: work) }
        let model = Self.model(try Self.series(folder), work: work)
        await model.loadFrames()
        model.save(format: format)
        await model.settle()
        #expect(model.failure == nil)
        let file = try #require(model.composedFile)
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == (format == .heic && model.canSaveHEIC ? UTType.heic : .jpeg).identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff?[kCGImagePropertyTIFFModel] as? String == "EOS R6")
        #expect(exif[kCGImagePropertyExifLensModel] as? String == "RF24-105mm F4 L IS USM")
        #expect(exif[kCGImagePropertyExifExposureTime] == nil)
        #expect(exif[kCGImagePropertyExifFNumber] == nil)
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] == nil)
        #expect(exif[kCGImagePropertyExifExposureBiasValue] == nil)
        #expect(model.composedTool == .hdr)
    }

    /// AC-17: Cancel during Save writes nothing and leaves no temporary file.
    @Test func cancellingTheSaveWritesNothing() async throws {
        let folder = try Self.folder()
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: work) }
        let model = Self.model(try Self.series(folder), work: work)
        await model.loadFrames()
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("HDR-") }
        model.save()
        model.cancel()
        await model.settle()
        #expect(model.composedFile == nil)
        #expect(model.failure == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("HDR-") }
        #expect(after.subtracting(before).isEmpty)
    }

    /// AC-21: a series mixing a RAW with JPEGs says it merges from the
    /// processed versions.
    @Test(.enabled(if: HDRExportTests.hasRawFixture)) func aMixedSeriesSaysItUsesTheProcessedVersions() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let entry = RemoteEntry(name: "IMG_6310.CR3", isDirectory: false, size: 1, modified: nil)
        let raw = PhotoEditOrigin.serverFile(FetchedServerPhoto(serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
                                                                files: [FetchedFile(file: entry, url: HDRExportTests.rawFixture, sha256: "")]))
        let model = Self.model([raw] + (try Self.series(folder)))
        await model.loadFrames()
        #expect(model.hdr?.order?.isMixedRAW == true)
        #expect(model.hdrNotes.contains("Some of these photos aren't RAW, so all of them are merged from their processed versions."))
    }
}
