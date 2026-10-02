import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDexKit

/// FS-01.11 §6 — AC-14, AC-17, AC-22: the full-resolution save, its memory,
/// its format, and Cancel.
@Suite(.serialized) struct HDRExportTests {
    /// A 24 MP RAW kept out of the repo: `build/fixtures/IMG_6310.CR3`
    /// (6000 × 4000, Canon). Tests that need it skip when it is absent.
    static let rawFixture: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/fixtures/IMG_6310.CR3")
    static var hasRawFixture: Bool { FileManager.default.fileExists(atPath: rawFixture.path) }

    /// The footprint measurements decode five 24 MP RAWs at once and read the
    /// whole process's memory, so they mean something only alone — and in the
    /// full suite they hold the GPU while other render tests wait on it (the
    /// gate hung on 2026-10-02 with `rawDecoderFloor` among the stuck). Run
    /// on demand: `touch build/measure-memory`, then
    /// `-only-testing:ShotDexTests/HDRExportTests`.
    static var measuresMemory: Bool {
        hasRawFixture && FileManager.default.fileExists(
            atPath: rawFixture.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("measure-memory").path)
    }

    /// Task 1 of the plan: the floor the RAW decoder itself costs, before any
    /// merging — one decoder and five alive together, read band by band the
    /// way a merge reads them. The numbers gate the rest of the save path.
    @Test(.enabled(if: HDRExportTests.measuresMemory)) func rawDecoderFloor() async throws {
        _ = await FootprintSampler.waitForQuietProcess(quietSeconds: 3, timeout: .seconds(60))
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        for (decoders, band) in [(1, 256), (5, 256), (5, 128)] {
            let baseline = FootprintSampler.current()
            let sampler = FootprintSampler()
            sampler.start()
            let started = Date()
            try autoreleasepool {
                let images: [CIImage] = try (0..<decoders).map { k in
                    let raw = try #require(CIRAWFilter(imageURL: Self.rawFixture))
                    raw.boostAmount = 0
                    raw.exposure = Float(k) * 0.001 // five distinct decodes, not one cached
                    return try #require(raw.outputImage)
                }
                let width = Int(images[0].extent.width), height = Int(images[0].extent.height)
                var buffers = (0..<decoders).map { _ in [UInt16](repeating: 0, count: width * band * 4) }
                var row = 0
                while row < height {
                    let rows = min(band, height - row)
                    let rect = CGRect(x: 0, y: CGFloat(height - row - rows), width: CGFloat(width), height: CGFloat(rows))
                    for k in images.indices {
                        buffers[k].withUnsafeMutableBytes { bytes in
                            context.render(images[k], toBitmap: bytes.baseAddress!, rowBytes: width * 8,
                                           bounds: rect, format: .RGBAh, colorSpace: linear)
                        }
                    }
                    row += rows
                }
            }
            let seconds = Date().timeIntervalSince(started)
            let peak = sampler.stop()
            let deltaMB = Double(peak > baseline ? peak - baseline : 0) / 1_048_576
            print(String(format: "HDR raw floor: %d decoder(s), bands of %d rows — peak +%.0f MB over %.0f MB, %.1f s",
                         decoders, band, deltaMB, Double(baseline) / 1_048_576, seconds))
            // The save's whole budget is 700 MB (FS-01.11 §6); the decoders
            // must leave room for the merge and the tone map.
            #expect(deltaMB < 600)
        }
    }

    /// A prepared series of `count` frames on the fixture, lined up as the
    /// preview would.
    static func prepared(_ fixture: HDRBracketFixture, _ series: HDRBracketFixture.Series) async throws -> PreparedHDR {
        try await PhotoStackRenderer().prepareHDR(images: series.frames.map(fixture.image), stops: series.stops,
                                                  reference: series.reference, noise: .raw, pixelScale: 1)
    }

    /// AC-22: the save writes the format asked for, at the picture's size,
    /// with the properties it was given.
    @Test(arguments: [UTType.jpeg, .heic]) func writesTheFormatAskedFor(type: UTType) async throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-2, 0, 2])
        let prepared = try await Self.prepared(fixture, series)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try HDRExporter.write(frame: { fixture.image(series.frames[$0]) }, prepared: prepared, previewScale: 1,
                              options: .standard, type: type, to: url,
                              properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon"]])
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == type.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == fixture.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == fixture.height)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "Canon")
    }

    /// The saved file matches the merge it was asked for: the fixture's
    /// tone map, rendered in one piece, against the file read back.
    @Test func theSavedFileIsTheToneMappedMerge() async throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-2, 0, 2])
        let prepared = try await Self.prepared(fixture, series)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try HDRExporter.write(frame: { fixture.image(series.frames[$0]) }, prepared: prepared, previewScale: 1,
                              options: .standard, type: .jpeg, to: url, properties: [:])
        let radiance = try #require(HDRMerge.radiance(prepared.series, deghost: .medium))
        let whole = try #require(HDRMerge.toneMapped(radiance, stops: prepared.series.stops, strength: 0.6))
        let saved = try #require(CIImage(contentsOf: url))
        let psnr = HDRBracketFixture.psnr(fixture.displayPixels(saved), fixture.displayPixels(whole))
        print(String(format: "HDR save against one-piece render %.1f dB", psnr))
        #expect(psnr >= 38)   // JPEG at 0.95 and 8 bits
    }

    /// AC-17, the renderer half: Cancel mid-save throws and leaves no file.
    @Test func cancellingLeavesNoFile() async throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-2, 0, 2])
        let prepared = try await Self.prepared(fixture, series)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString).jpg")
        let calls = Counter()
        #expect(throws: StripImageWriter.Failure.cancelled) {
            try HDRExporter.write(frame: { fixture.image(series.frames[$0]) }, prepared: prepared, previewScale: 1,
                                  options: .standard, type: .jpeg, to: url, properties: [:],
                                  isCancelled: { calls.increment() > 1 })
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }

    /// AC-14 on the simulator: five (and three) 24 MP RAW frames saved — the
    /// peak footprint over the quiet process, and the time. The ceiling is
    /// the iPhone 12's; the simulator's number is the one this machine can
    /// give.
    @Test(.enabled(if: HDRExportTests.measuresMemory), arguments: [(5, UTType.jpeg), (3, .jpeg), (5, .heic)])
    func aFullSizeRAWSaveStaysUnderTheCeiling(frames count: Int, type: UTType) async throws {
        let stops: [Double] = count == 5 ? [-4, -2, 0, 2, 4] : [-2, 0, 2]
        let prepared = PreparedHDR(
            series: HDRSeries(frames: [], stops: stops, reference: count / 2, noise: .raw, pixelScale: 1),
            excludedFrames: [], inputIndices: Array(0..<count), maps: Array(repeating: .identity, count: count))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = await FootprintSampler.waitForQuietProcess(quietSeconds: 3, timeout: .seconds(60))
        let baseline = FootprintSampler.current()
        let sampler = FootprintSampler()
        sampler.start()
        let started = Date()
        try autoreleasepool {
            try HDRExporter.write(
                frame: { k in
                    let raw = CIRAWFilter(imageURL: Self.rawFixture)
                    raw?.boostAmount = 0
                    raw?.exposure = Float(stops[k])   // one file, five exposures
                    return raw?.outputImage
                },
                prepared: prepared, previewScale: 1600.0 / 6000, options: .standard, type: type, to: url, properties: [:])
        }
        let seconds = Date().timeIntervalSince(started)
        let peak = sampler.stop()
        let deltaMB = Double(peak > baseline ? peak - baseline : 0) / 1_048_576
        print(String(format: "HDR AC-14 %d × 24 MP RAW to %@: peak +%.0f MB over %.0f MB, %.1f s",
                     count, type.preferredFilenameExtension ?? "?", deltaMB, Double(baseline) / 1_048_576, seconds))
        #expect(deltaMB <= 700)
        #expect(seconds <= 60)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 6000)
    }
}
