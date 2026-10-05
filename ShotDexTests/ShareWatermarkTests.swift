import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import ShotDexKit
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-05.04 through the share pipeline (FS-08.06): a stamped photo is
/// rendered, stamped and written with its metadata at the share's level.
@MainActor
@Suite(.serialized) struct ShareWatermarkTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShareWatermarkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Photo A, 1200×800 as encoded, orientation 6 — upright 800×1200.
    func photoA() throws -> URL {
        var options = MetadataFixture.Options()
        options.width = 1200
        options.height = 800
        options.xmp = false
        let url = folder.appendingPathComponent("A.JPG")
        try MetadataFixture.encode(.jpeg, options: options).write(to: url)
        return url
    }

    static func credit() -> ShareWatermark {
        ShareWatermark(
            template: WatermarkStamp(preset: WatermarkFixture.credit(logo: nil), placement: WatermarkFixture.placementW),
            tokens: ["A": OverlayTokenValues(camera: "ILCE-7M4")]
        )
    }

    static let sourceA = ShareSource(id: "A", kind: .photo, filename: "A.JPG", uniformType: UTType.jpeg.identifier)

    /// Near-white pixels — the white credit line — inside `rect` (top-down).
    static func whitePixels(in url: URL, rect: CGRect) throws -> Int {
        let pixels = try #require(WatermarkFixture.pixels(of: url))
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * pixels.width + x) * 4
                if pixels.data[i] > 235, pixels.data[i + 1] > 235, pixels.data[i + 2] > 235 { count += 1 }
            }
        }
        return count
    }

    /// The stamp's box on an upright 800×1200 photo, and the same box in the
    /// opposite corner, where nothing was stamped.
    static func boxes() throws -> (stamped: CGRect, other: CGRect) {
        let stamp = credit().template.resolved(with: OverlayTokenValues(camera: "ILCE-7M4"))
        let box = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: CGSize(width: 800, height: 1200))).box.integral
        return (box, CGRect(x: 0, y: 0, width: box.width, height: box.height))
    }

    /// AC-4: Watermark When Sharing = Credit, No Location — the JPEG carries
    /// the stamp bottom right, no GPS, and still Make SONY, Model ILCE-7M4.
    @Test func noLocationWithWatermark() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try photoA()
        var pipeline = ShareExportPipeline(
            reader: LocalFileShareReader(files: ["A": original]),
            folder: try ShareExportPipeline.makeFolder(in: folder), level: .noLocation
        )
        pipeline.watermark = Self.credit()
        let result = await pipeline.export([Self.sourceA])
        #expect(result.failed.isEmpty)
        #expect(result.watermarked == 1)
        let file = try #require(result.files.first)
        #expect(file.lastPathComponent == "A.JPG")
        #expect(MetadataFixture.properties(of: file)[kCGImagePropertyGPSDictionary] == nil)
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: file))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "SONY")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7M4")
        // Upright: the pixels were turned, so the file says orientation 1.
        #expect(MetadataFixture.properties(of: file)[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(MetadataFixture.properties(of: file)[kCGImagePropertyPixelWidth] as? Int == 800)
        let boxes = try Self.boxes()
        #expect(try Self.whitePixels(in: file, rect: boxes.stamped) > 200)
        #expect(try Self.whitePixels(in: file, rect: boxes.other) < 20)
    }

    /// A drag at the Settings level stamps the same way (FS-08.06 §5).
    @Test func dragFollowsSettings() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try photoA()
        let plan = ShareDragPlan(source: Self.sourceA, level: .noLocation, stamps: true)
        #expect(plan.type == .jpeg)
        let url = try #require(await PhotoDragItem.fileURL(
            for: Self.sourceA, level: .noLocation, rawChoice: plan.rawChoice,
            watermark: Self.credit(), reader: LocalFileShareReader(files: ["A": original])
        ))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(try Self.whitePixels(in: url, rect: try Self.boxes().stamped) > 200)
    }

    /// A server photo's share follows Settings too: the context picks the
    /// preset, the gather stamps, the header names it.
    @Test func serverShareFollowsSettings() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try photoA()
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit])
        let context = ShareWatermarkContext(
            settings: stores.settings, presets: stores.presets, libraryQueries: nil, editing: nil, imageExists: { _ in true }
        )
        #expect(await context.watermark(for: [Self.sourceA]) == nil, "Off by default")
        stores.settings.setSharingPreset(credit.id)
        let watermark = try #require(await context.watermark(for: [Self.sourceA]))
        #expect(watermark.name == "Credit")
        let prepared = await PhotoShareSheet.gather(
            sources: [Self.sourceA], reader: LocalFileShareReader(files: ["A": original]),
            level: .noLocation, watermark: watermark
        )
        defer { prepared.removeFiles() }
        #expect(prepared.watermarkName == "Credit")
        #expect(PhotoShareSheet.headerNote(plan: prepared.plan) == "Watermark: Credit")
        let file = try #require(prepared.items.first as? URL)
        // No index for a server file: `{camera}` is empty, the literal stays.
        #expect(try Self.whitePixels(in: file, rect: try Self.boxes().stamped) > 100)
    }

    /// AC-6: a RAW iOS reads becomes a full-size stamped JPEG — at any level,
    /// with no RAW question; one iOS cannot read is left out by name, never
    /// sent unstamped; photo A goes stamped beside them.
    @Test func rawBecomesStampedJPEG() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let arw = RAWFixtures.available(RAWFixtures.sony) else {
            print("SKIP rawBecomesStampedJPEG: \(RAWFixtures.sony) is not on this machine")
            return
        }
        let broken = folder.appendingPathComponent("DSCF9999.RAF")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: broken)
        let sources = [
            ShareSource(id: "R", kind: .raw, filename: "DSC0001.ARW", uniformType: "com.sony.arw-raw-image"),
            ShareSource(id: "F", kind: .raw, filename: "DSCF9999.RAF", isReadable: false, uniformType: "com.fuji.raw-image"),
            Self.sourceA,
        ]
        var watermark = Self.credit()
        watermark.tokens["R"] = OverlayTokenValues(camera: "ILCE-7M3")
        var plan = ShareBatchPlan(sources: sources, level: .noLocation)
        plan.watermarkName = watermark.name
        #expect(!plan.asksAboutRAW)
        #expect(plan.notesRAWAsJPEG)
        #expect(PhotoShareSheet.headerNote(plan: plan)?.contains("RAW sent as JPEG") == true)

        var pipeline = ShareExportPipeline(
            reader: LocalFileShareReader(files: ["R": arw, "F": broken, "A": try photoA()]),
            folder: try ShareExportPipeline.makeFolder(in: folder), level: .noLocation
        )
        pipeline.watermark = watermark
        pipeline.rawChoice = .shareAsJPEG
        let result = await pipeline.export(sources)
        #expect(result.failed == ["DSCF9999.RAF"])
        #expect(result.files.count == 2)
        #expect(result.rawStampedAsJPEG == 1)
        let jpeg = try #require(result.files.first)
        #expect(jpeg.lastPathComponent == "DSC0001.jpg")
        let source = try #require(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let raw = try #require(CGImageSourceCreateWithURL(arw as CFURL, nil))
        let rawProps = CGImageSourceCopyPropertiesAtIndex(raw, 0, nil) as? [CFString: Any] ?? [:]
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        // Full size: the decoder's whole frame, upright.
        let rawLong = max(rawProps[kCGImagePropertyPixelWidth] as? Int ?? 0, rawProps[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let long = max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        #expect(long >= rawLong - 64, "\(long) vs \(rawLong)")
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    /// The batch names the RAW it could not stamp in the left-out modal.
    @Test func unreadableRAWIsLeftOutByName() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = folder.appendingPathComponent("DSCF9999.RAF")
        try Data(repeating: 7, count: 2048).write(to: broken)
        let sources = [
            ShareSource(id: "F", kind: .raw, filename: "DSCF9999.RAF", isReadable: false, uniformType: "com.fuji.raw-image"),
            Self.sourceA,
        ]
        let batch = LazyShareBatch(
            sources: sources, originals: [:], level: .noLocation, rawChoice: .shareAsJPEG,
            fetcher: FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher()),
            availableBytes: { 10_000_000_000 },
            reader: LocalFileShareReader(files: ["F": broken, "A": try photoA()]),
            directory: folder, watermark: Self.credit()
        )
        let start = Task { await batch.start() }
        for _ in 0..<200 {
            if case .leftOut = batch.stage { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(batch.stage == .leftOut(names: ["DSCF9999.RAF"], sharing: 1))
        batch.shareRest()
        await start.value
        #expect(batch.stage == .finished)
        batch.removeFiles()
    }

    /// AC-7: photo A and a 10 s MOV — A is stamped, the MOV arrives byte for
    /// byte the same, and the header says videos aren't watermarked.
    @Test func movieKeepsItsBytes() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("IMG_0003.MOV")
        try Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 7919) }).write(to: movie)
        let digest = SHA256.hash(data: try Data(contentsOf: movie))
        let sources = [Self.sourceA, ShareSource(id: "V", kind: .video, filename: "IMG_0003.MOV", uniformType: "com.apple.quicktime-movie")]
        var pipeline = ShareExportPipeline(
            reader: LocalFileShareReader(files: ["A": try photoA(), "V": movie]),
            folder: try ShareExportPipeline.makeFolder(in: folder), level: .noLocation
        )
        pipeline.watermark = Self.credit()
        let result = await pipeline.export(sources)
        #expect(result.files.count == 2)
        #expect(result.watermarked == 1)
        let shared = try #require(result.files.last)
        #expect(SHA256.hash(data: try Data(contentsOf: shared)) == digest)
        #expect(try Self.whitePixels(in: try #require(result.files.first), rect: try Self.boxes().stamped) > 200)
    }
}
