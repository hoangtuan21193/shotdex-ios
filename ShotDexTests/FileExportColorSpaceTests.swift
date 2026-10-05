import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §3a / FS-03.07c AC-17, AC-18: the Color Space row converts the
/// pixels and the file carries that profile; Quality reaches the encoder.
@Suite struct FileExportColorSpaceTests {
    /// Photo P of AC-17: a Display P3 JPEG, the left half a colour inside
    /// all three gamuts, the right half pure P3 red — outside sRGB.
    static let inGamut: [CGFloat] = [0.55, 0.45, 0.35]

    static func photoP(width: Int = 3_000, height: Int = 2_000, type: UTType = .jpeg) -> Data {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: p3, components: inGamut + [1])!)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(colorSpace: p3, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// One photo through the run, at Size Original, written in `space`.
    private func export(
        _ fixture: ExportFixture, data: Data, filename: String = "P3.JPG", suffix: String,
        space: ExportColorSpace, format: PhotoOutputFormat = .jpeg, quality: Double = 0.8, pixels: (Int, Int) = (3_000, 2_000)
    ) async throws -> URL {
        let file = try fixture.file("p-\(suffix)", filename, role: .photo, data: data)
        let item = FileExportItem(id: "p-\(suffix)", filename: filename, captureDate: ExportFixture.date(), kind: .photo,
                                  files: [file], pixelWidth: pixels.0, pixelHeight: pixels.1)
        let plan = try fixture.plan([item], mode: .currentVersion, template: FileNameTemplate("{original}_\(suffix)"),
                                    renderExtension: format.fileExtension)
        let job = FileExportJob(plan: plan, mode: .currentVersion, version: .original,
                                render: FileExportRenderOptions(preset: .original, format: format, quality: quality,
                                                                metadata: .all, colorSpace: space))
        let report = await fixture.runner().run(job)
        #expect(report.failed.isEmpty && report.stoppedBy == nil)
        let name = "\((filename as NSString).deletingPathExtension)_\(suffix).\(format.fileExtension)"
        return fixture.destination.appendingPathComponent(name)
    }

    static func profileName(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyProfileName] as? String
    }

    /// The colour at `(x, y)` of the decoded file, converted into `space`.
    static func pixel(_ url: URL, x: Int, y: Int, in space: CGColorSpace) -> [Int]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes.prefix(3).map(Int.init)
    }

    static let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// AC-17: Original keeps Display P3; sRGB, Display P3 and Adobe RGB
    /// write those profiles.
    @Test func everyChoiceWritesItsProfile() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let data = Self.photoP()
        let expected: [(ExportColorSpace, String)] = [
            (.original, "Display P3"), (.sRGB, "sRGB IEC61966-2.1"), (.displayP3, "Display P3"), (.adobeRGB, "Adobe RGB (1998)"),
        ]
        for (space, profile) in expected {
            let url = try await export(fixture, data: data, suffix: space.rawValue, space: space)
            #expect(Self.profileName(url) == profile, "\(space)")
        }
        // An sRGB photo at Original stays sRGB.
        let srgb = ExportFixture.image(width: 600, height: 400, gray: 0.5, gps: false)
        let url = try await export(fixture, data: srgb, filename: "S.JPG", suffix: "srgb", space: .original, pixels: (600, 400))
        #expect(Self.profileName(url) == "sRGB IEC61966-2.1")
    }

    /// AC-17: the in-gamut half, read back into Display P3, is within two
    /// levels of the Original file in every profile — the pixels were
    /// converted, not relabelled.
    @Test func inGamutColourSurvives() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let data = Self.photoP()
        let original = try await export(fixture, data: data, suffix: "o", space: .original)
        let reference = try #require(Self.pixel(original, x: 750, y: 1_000, in: Self.p3))
        for space in ExportColorSpace.allCases {
            let url = try await export(fixture, data: data, suffix: "c-\(space.rawValue)", space: space)
            let read = try #require(Self.pixel(url, x: 750, y: 1_000, in: Self.p3))
            #expect(zip(read, reference).allSatisfy { abs($0 - $1) <= 2 }, "\(space): \(read) vs \(reference)")
        }
        // Relabelling without converting would move it by tens of levels:
        // the sRGB file's own bytes differ from the P3 ones.
        let srgb = try await export(fixture, data: data, suffix: "bytes", space: .sRGB)
        let own = try #require(Self.pixel(srgb, x: 750, y: 1_000, in: Self.sRGB))
        #expect(zip(own, reference).contains { abs($0 - $1) > 2 })
    }

    /// AC-17: P3 red has no sRGB equivalent — the sRGB file clips it to the
    /// gamut's edge.
    @Test func outOfGamutClipsInSRGB() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let url = try await export(fixture, data: Self.photoP(), suffix: "red", space: .sRGB)
        let red = try #require(Self.pixel(url, x: 2_250, y: 1_000, in: Self.sRGB))
        #expect(red[0] >= 253 && red[1] <= 2 && red[2] <= 2, "\(red)")
    }

    /// AC-17: HEIC carries the profile too, where this device encodes HEIC
    /// (measured on macOS ImageIO 2026-10-05 for all three; the simulator on
    /// some Macs has no HEIC encoder).
    @Test(.enabled(if: KitExportRenderer.supportsHEICEncoding))
    func heicCarriesTheProfile() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let data = Self.photoP(width: 600, height: 400)
        for (space, profile) in [(ExportColorSpace.sRGB, "sRGB IEC61966-2.1"), (.adobeRGB, "Adobe RGB (1998)")] {
            let url = try await export(fixture, data: data, suffix: "h-\(space.rawValue)", space: space, format: .heic, pixels: (600, 400))
            #expect(Self.profileName(url) == profile)
        }
    }

    /// Same as Original keeps a HEIC as HEIC inside, not JPEG bytes under a
    /// `.heic` name.
    @Test(.enabled(if: KitExportRenderer.supportsHEICEncoding))
    func sameAsOriginalWritesHEICForHEIC() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let heic = ExportFixture.image(width: 600, height: 400, gray: 0.5, gps: false, type: .heic)
        let url = try await export(fixture, data: heic, filename: "IMG_0001.HEIC", suffix: "same", space: .original,
                                   format: .heic, pixels: (600, 400))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
    }

    /// AC-18: the quality the row holds is the one the encoder gets — a
    /// busy picture at 60% is smaller than at 85%.
    @Test func qualityReachesTheEncoder() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let data = Self.busy(width: 1_200, height: 800)
        let low = try await export(fixture, data: data, filename: "B.JPG", suffix: "60", space: .original, quality: 0.6, pixels: (1_200, 800))
        let high = try await export(fixture, data: data, filename: "B.JPG", suffix: "85", space: .original, quality: 0.85, pixels: (1_200, 800))
        let lowBytes = try #require(try low.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let highBytes = try #require(try high.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(lowBytes < highBytes * 9 / 10, "\(lowBytes) vs \(highBytes)")
    }

    /// Fine stripes and a gradient: something JPEG quality changes.
    static func busy(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in stride(from: 0, to: width, by: 3) {
            let t = CGFloat(x) / CGFloat(width)
            context.setFillColor(red: t, green: CGFloat((x / 3) % 2), blue: 1 - t, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 3, height: height))
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
