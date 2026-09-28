import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16a §1 — the maker's lens data read out of RAW files. Fixtures are
/// the correction blocks cut from CC0 samples (raw.pixls.us, no faces) or
/// rebuilt from their decoded values; no full RAW is in the repo.
struct LensEmbeddedDataTests {

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/LensData")

    static func fixture(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: fixtures.appendingPathComponent(name)))
    }

    // MARK: Little TIFF builder

    /// A little-endian TIFF: IFD0 pointing at one SubIFD holding `tags`
    /// (tag, type, values as Int16 or raw bytes).
    static func tiff(subIFD tags: [(tag: UInt16, type: UInt16, int16: [Int16])]) -> [UInt8] {
        var out: [UInt8] = [0x49, 0x49, 42, 0]
        func u16(_ v: UInt16) { out += [UInt8(v & 0xff), UInt8(v >> 8)] }
        func u32(_ v: UInt32) { out += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)] }
        u32(8)
        // IFD0: one entry 0x014a → SubIFD at 26.
        u16(1); u16(0x014a); u16(4); u32(1); u32(26); u32(0)
        let subStart = 26
        let dataStart = subStart + 2 + tags.count * 12 + 4
        var data: [UInt8] = []
        u16(UInt16(tags.count))
        for entry in tags {
            u16(entry.tag); u16(entry.type); u32(UInt32(entry.int16.count))
            let bytes = entry.int16.flatMap { v -> [UInt8] in let u = UInt16(bitPattern: v); return [UInt8(u & 0xff), UInt8(u >> 8)] }
            if bytes.count <= 4 {
                out += bytes + [UInt8](repeating: 0, count: 4 - bytes.count)
            } else {
                u32(UInt32(dataStart + data.count))
                data += bytes
            }
        }
        u32(0)
        return out + data
    }

    // MARK: DNG

    /// 16a AC-a2. A Leica Q DNG's WarpRectilinear has its own coefficients
    /// per plane: red and blue land at different radii from green, by the
    /// ratio of their polynomials, and the frame's centre is the optical one.
    @Test func dngRedBlueCoefficientsGiveSeparateRadii() throws {
        let correction = try #require(EmbeddedLensDataReader.dng(try Self.fixture("leica-q-warprectilinear.bin")))
        #expect(correction.unit == .farthestCorner)
        let red = try #require(correction.red), blue = try #require(correction.blue)
        let redAtCorner = red.value(at: 1), blueAtCorner = blue.value(at: 1)
        #expect(abs(redAtCorner - blueAtCorner) > 1e-4, "red \(redAtCorner) blue \(blueAtCorner)")
        // In pixels on a 6000×4000 frame (farthest corner 3606 px).
        let apart = abs(redAtCorner - blueAtCorner) * 3606
        #expect(apart > 0.25 && apart < 20, "\(apart) px between red and blue at the corner")
        // Barrel corrected: the corner samples from further in.
        let green = try #require(correction.distortion)
        #expect(green.value(at: 1) < 0.99)

        let pixel = try #require(EmbeddedLensDataReader.dng(try Self.fixture("pixel7pro-warprectilinear.bin")))
        #expect(pixel.red == nil && pixel.distortion != nil)
        #expect(abs(pixel.center.x - 0.4998) < 0.001)
    }

    // MARK: Sony

    /// The A7 IV + FE 50mm F2.5 G sample's SubIFD, as the camera wrote it.
    static let sonyTags: [(tag: UInt16, type: UInt16, int16: [Int16])] = [
        (0x7032, 8, [16, 0, 0, 128, 416, 800, 1248, 1760, 2304, 2848, 3424, 4000, 4544, 5312, 6496, 8288, 9856]),
        (0x7035, 8, [32, -128, -128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 128, -128, -128, -128, -128, 0, 0, 0, 0, 0, 0, 0, 0, -128, -128, -128, -384]),
        (0x7037, 8, [16, -2, 0, 3, 5, 9, 13, 17, 21, 25, 29, 32, 34, 36, 36, 35, 34]),
    ]

    /// 16a AC-a1. Sony's three parameter blocks decode: distortion to the
    /// knot the file wrote (within half a pixel at the corner of a 3504 px
    /// frame), CA both channels, vignetting the gain that matched the
    /// camera's own preview (1.22 at 0.8 of the half-diagonal).
    @Test func sonyThreeParamsDecodeWithinHalfPixel() throws {
        let correction = try #require(EmbeddedLensDataReader.read(bytes: Self.tiff(subIFD: Self.sonyTags)))
        #expect(correction.unit == .halfDiagonal)
        let d = try #require(correction.distortion)
        let halfDiagonal = (3504.0 * 3504 + 2336 * 2336).squareRoot() / 2
        #expect(abs((d.value(at: 1) - 1) * halfDiagonal - 34 * pow(2, -14) * halfDiagonal) <= 0.5)
        #expect(correction.red != nil && correction.blue != nil)
        let v = try #require(correction.vignetting)
        #expect(abs(v.value(at: 0) - 1) < 1e-9)
        #expect(abs(v.value(at: 0.8) - 1.217) < 0.01, "\(v.value(at: 0.8))")
    }

    /// 16a AC-a4. A Sony block cut short, or knots past the trust limits,
    /// is no data: the reader says nothing rather than a wrong correction.
    @Test func truncatedSonyBlockFallsBack() {
        var bytes = Self.tiff(subIFD: Self.sonyTags)
        bytes.removeLast(40)
        #expect(EmbeddedLensDataReader.read(bytes: bytes)?.distortion == nil)
        let wild: [(tag: UInt16, type: UInt16, int16: [Int16])] = [(0x7037, 8, [4, 0, 9000, 16000, 30000])]
        #expect(EmbeddedLensDataReader.read(bytes: Self.tiff(subIFD: wild)) == nil)
    }

    // MARK: Panasonic

    /// The G9's IFD0 0x0119 block, as the camera wrote it.
    static let panasonicBlock: [UInt8] = [
        0x4d, 0xa5, 0x35, 0x66, 0xde, 0x00, 0xaa, 0x00, 0x66, 0xff, 0x4b, 0xfe, 0xc2, 0x01, 0x01, 0x25,
        0x9d, 0xfe, 0x95, 0x00, 0xd5, 0x00, 0x68, 0x00, 0x50, 0x19, 0x89, 0x02, 0x05, 0x1f, 0xec, 0x4e,
    ]

    /// 16a AC-a13 (the reader). The G9 block decodes to its distortion —
    /// the scale term exiftool reads as 1.0135 — and has no vignetting or CA,
    /// which Lensfun has to fill.
    @Test func panasonicDistortionDecodes() throws {
        let correction = try #require(EmbeddedLensDataReader.panasonic(Self.panasonicBlock))
        #expect(correction.unit == .halfLongSide)
        let d = try #require(correction.distortion)
        #expect(abs(d.value(at: 0) - (1 - 437.0 / 32768)) < 1e-9)
        #expect(!correction.hasVignetting && !correction.hasChromaticAberration)
    }

    // MARK: Fujifilm

    /// 16a AC-a12. Fujifilm's rational blocks: nine knots, distortion in
    /// percent, CA red then blue, vignetting as percent brightness.
    @Test func fujiThreeParamsDecode() throws {
        let knots = [0.3535211268, 0.5, 0.6126760563, 0.7070422535, 0.7908450704, 0.8661971831, 0.9352112676, 1, 1.06056338]
        var ifd: [Int: IFDEntry] = [:]
        var bytes = [UInt8](repeating: 0, count: 16)
        func add(_ tag: Int, _ values: [Double]) {
            let start = bytes.count
            for v in values {
                let n = Int32(v * 1_000_000), d: Int32 = 1_000_000
                for x in [n, d] { let u = UInt32(bitPattern: x); bytes += [UInt8(u & 0xff), UInt8(u >> 8 & 0xff), UInt8(u >> 16 & 0xff), UInt8(u >> 24)] }
            }
            // The entry's value field holds the pointer, relative to 0.
            let field = bytes.count
            let p = UInt32(start); bytes += [UInt8(p & 0xff), UInt8(p >> 8 & 0xff), UInt8(p >> 16 & 0xff), UInt8(p >> 24)]
            ifd[tag] = IFDEntry(type: 10, count: values.count, valueFieldOffset: field)
        }
        add(0xf00b, [515.89] + knots + [0, -0.2, -0.4, -0.6, -0.8, -1, -1.2, -1.4, -1.6])
        add(0xf00f, [515.89] + knots + Array(repeating: 0.0001, count: 9) + Array(repeating: -0.0001, count: 9) + [515.89])
        add(0xf010, [515.89] + knots + [100, 99, 97, 95, 92, 88, 84, 80, 76])
        let reader = try #require(TIFFReader(bytes: bytes, base: 0, isLittleEndian: true, firstIFDOffset: 0))
        let correction = try #require(EmbeddedLensDataReader.fuji(ifd, reader: reader, offsetBase: 0))
        #expect(abs(try #require(correction.distortion).value(at: 1) - 0.986) < 1e-6)
        #expect(abs(try #require(correction.red).value(at: 0.5) - 1.0001) < 1e-6)
        #expect(abs(try #require(correction.vignetting).value(at: 1) - 100.0 / 80) < 1e-6)
    }

    // MARK: Resolver and render

    /// 16a AC-a13. A G9 RAW: distortion from the file, vignetting from
    /// Lensfun where the file has none, CA from neither — its slider dims;
    /// Apple's correction off.
    @Test func panasonicDistortionFillsRestFromLensfun() throws {
        let panasonic = try #require(EmbeddedLensDataReader.panasonic(Self.panasonicBlock))
        var aspects: Set<LensCorrectionAspect> = []
        if panasonic.hasDistortion { aspects.insert(.distortion) }
        let resolution = LensCorrectionResolver.resolve(LensCorrectionInputs(
            isRAW: true,
            embeddedAspects: aspects,
            embeddedLensName: "LUMIX G VARIO 12-60",
            lensfunLens: LensCorrectionResolverTests.lens(distortion: true, vignetting: true, tca: false),
            decoderSupportsLensCorrection: true
        ))
        #expect(resolution.choice.distortionSource == .embedded)
        #expect(resolution.choice.vignettingSource == .lensfun)
        #expect(resolution.choice.chromaticAberrationSource == .none)
        #expect(!resolution.liveAspects.contains(.chromaticAberration))
        #expect(!resolution.usesAppleBuiltIn)
    }

    /// 16a AC-a1 in the render: an ARW whose source is the file's data
    /// corrects by the file's knots at 100, twice the displacement at 200.
    @Test func sonyEmbeddedDataDrivesTheRender() throws {
        let correction = try #require(EmbeddedLensDataReader.read(bytes: Self.tiff(subIFD: Self.sonyTags)))
        let url = URL(fileURLWithPath: "/tmp/embedded-\(UUID().uuidString).arw")
        EmbeddedLensDataCache.shared.store(correction, for: url)
        let source = PhotoRenderSourceInfo(url: url, type: .image, pixelWidth: 3504, pixelHeight: 2336,
                                           orientation: .up, isRAW: true, properties: [:])
        var recipe = PhotoEditRecipe.identity
        recipe.lensProfile = PhotoLensProfileChoice(
            lensID: nil, cameraCropFactor: 1, isAutomatic: true,
            distortionSource: .embedded, vignettingSource: .embedded, chromaticAberrationSource: .embedded
        )
        let extent = CGRect(x: 0, y: 0, width: 3504, height: 2336)
        let halfDiagonal = (3504.0 * 3504 + 2336 * 2336).squareRoot() / 2
        let one = try #require(PhotoRenderService.lensCorrectionTable(of: recipe, source: source, extent: extent))
        let atCorner = one.table.scales(at: halfDiagonal).green
        #expect(abs((atCorner - 1) - 34 * pow(2, -14)) * halfDiagonal <= 0.5)
        recipe.adjustments.lensDistortionScale = 2
        let two = try #require(PhotoRenderService.lensCorrectionTable(of: recipe, source: source, extent: extent))
        #expect(abs((two.table.scales(at: halfDiagonal).green - 1) - 2 * (atCorner - 1)) * halfDiagonal <= 0.5)
        #expect(PhotoRenderService.profileVignettingFilter(of: recipe, source: source) is LensVignetteCurveFilter)
    }

    // MARK: Sony JPEG

    /// A Sony JPEG's Exif with MakerNote 0x2013 set to `setting`.
    static func sonyJPEG(setting: UInt16) -> [UInt8] {
        var tiff: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0]
        func u16(_ v: UInt16) { tiff += [UInt8(v & 0xff), UInt8(v >> 8)] }
        func u32(_ v: UInt32) { tiff += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)] }
        // IFD0 at 8: Make (ASCII "SONY", inline), ExifIFD pointer → 38.
        u16(2)
        u16(0x010f); u16(2); u32(4); tiff += Array("SONY".utf8)
        u16(0x8769); u16(4); u32(1); u32(38)
        u32(0)
        // ExifIFD at 38: MakerNote (undefined, 12 + 18 bytes) at 56.
        u16(1)
        u16(0x927c); u16(7); u32(30); u32(56)
        u32(0)
        // MakerNote at 56: "SONY DSC \0\0\0", then an IFD: 0x2013 short.
        tiff += Array("SONY DSC ".utf8) + [0, 0, 0]
        u16(1)
        u16(0x2013); u16(3); u32(1); u16(setting); u16(0)
        u32(0)
        let app1 = Array("Exif".utf8) + [0, 0] + tiff
        let length = UInt16(app1.count + 2)
        return [0xFF, 0xD8, 0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xff)] + app1 + [0xFF, 0xD9]
    }

    /// 16a AC-a15. A Sony JPEG the camera corrected is read as such, and
    /// the resolver does not match a lens on its own.
    @Test func sonyJPEGCorrectedInCameraSkipsAutoMatch() {
        #expect(EmbeddedLensDataReader.isCorrectedInCamera(bytes: Self.sonyJPEG(setting: 2)) == true)
        let resolution = LensCorrectionResolver.resolve(LensCorrectionInputs(
            isRAW: false, lensfunLens: LensCorrectionResolverTests.lens(), isJPEGCorrectedInCamera: true
        ))
        #expect(resolution.panel == .correctedInCamera && resolution.liveAspects.isEmpty)
    }

    /// 16a AC-a16. The tag saying "not corrected" matches as usual.
    @Test func uncorrectedTagMatchesAsUsual() {
        #expect(EmbeddedLensDataReader.isCorrectedInCamera(bytes: Self.sonyJPEG(setting: 0)) == false)
        let resolution = LensCorrectionResolver.resolve(LensCorrectionInputs(
            isRAW: false, lensfunLens: LensCorrectionResolverTests.lens(), isJPEGCorrectedInCamera: false
        ))
        #expect(resolution.panel == .found(lensName: "Canon EF 24-70mm f/2.8L II USM"))
    }
}
