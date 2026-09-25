import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// FS-16 — golden images for the Core Image kernels.
///
/// Every kernel's output was captured once, with the string kernels, before
/// any of them moved to Metal. A port passes when it reproduces that output to
/// 1/255 a channel. Goldens live next to this file under `Fixtures/` and are
/// read and written through `#filePath`: the tests run on a simulator, which
/// sees the host's disk.
///
/// To capture: `touch build/record-kernel-golden`, run the suite, delete the
/// marker. A recording run always fails, so it can never pass the gate.
enum KernelGolden {
    /// Side of every kernel-level input and output.
    static let size = 48

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    static let directory = fixtures.appendingPathComponent("KernelGolden")
    static let referencePhoto = fixtures.appendingPathComponent("kernel-reference.jpg")

    private static let marker = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/record-kernel-golden")

    static var isRecording: Bool { FileManager.default.fileExists(atPath: marker.path) }

    /// No colour management anywhere, float all the way: the numbers the
    /// kernel wrote are the numbers compared.
    static let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf,
        .cacheIntermediates: false,
    ])

    static var extent: CGRect { CGRect(x: 0, y: 0, width: size, height: size) }

    // MARK: Comparing

    /// 1/255 a channel, relative above 1 — accumulators and signed
    /// differences run outside 0…1, where an 8-bit step means nothing.
    static func withinTolerance(_ actual: Float, _ expected: Float) -> Bool {
        abs(actual - expected) <= max(1, abs(expected)) / 255 + 1e-6
    }

    /// Records the golden, or checks `values` against it.
    static func check(
        _ values: [Float],
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = directory.appendingPathComponent("\(name).rgbah.zlib")
        if isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encode(values).write(to: url)
            Issue.record("recorded \(name) — delete build/record-kernel-golden", sourceLocation: sourceLocation)
            return
        }
        let expected = try expectedValues(named: name)
        try #require(expected.count == values.count, "\(name): size changed", sourceLocation: sourceLocation)
        var worst: Float = 0
        var worstIndex = 0
        var failures = 0
        for index in values.indices where !withinTolerance(values[index], expected[index]) {
            failures += 1
            let delta = abs(values[index] - expected[index])
            if delta > worst { worst = delta; worstIndex = index }
        }
        let pixel = worstIndex / 4
        #expect(
            failures == 0,
            """
            \(name): \(failures) channels off; worst \(worst * 255)/255 at \
            (\(pixel % size), \(pixel / size)) channel \(worstIndex % 4): \
            \(values[worstIndex]) vs \(expected[worstIndex])
            """,
            sourceLocation: sourceLocation
        )
    }

    /// The golden's values. A missing golden is a failure, never a skip.
    static func expectedValues(named name: String) throws -> [Float] {
        let url = directory.appendingPathComponent("\(name).rgbah.zlib")
        guard let data = try? Data(contentsOf: url) else { throw MissingGolden(name: name) }
        return try decode(data)
    }

    struct MissingGolden: Error, CustomStringConvertible {
        let name: String
        var description: String { "no golden for \(name) — capture with build/record-kernel-golden" }
    }

    /// Half floats, zlib-compressed: small enough to keep in the repo, exact
    /// enough (11 bits) to sit well under the tolerance.
    static func encode(_ values: [Float]) throws -> Data {
        let halves = values.map { Float16($0) }
        let raw = halves.withUnsafeBufferPointer { Data(buffer: $0) }
        return try (raw as NSData).compressed(using: .zlib) as Data
    }

    static func decode(_ data: Data) throws -> [Float] {
        let raw = try (data as NSData).decompressed(using: .zlib) as Data
        let halves = raw.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        return halves.map(Float.init)
    }

    // MARK: Reading back

    static func pixels(of image: CIImage) -> [Float] {
        var values = [Float](repeating: 0, count: size * size * 4)
        values.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: size * 4 * MemoryLayout<Float>.size,
                bounds: extent,
                format: .RGBAf,
                colorSpace: nil
            )
        }
        return values
    }

    // MARK: Inputs

    static func image(_ values: [Float], width: Int = size, height: Int = size) -> CIImage {
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    /// Sixteen 12-pixel tiles: the extremes every kernel must survive — black,
    /// white, the six saturated primaries and secondaries, transparent, half
    /// transparent, near-black, near-white — plus ramps in grey, hue and
    /// saturation, and a checker. Premultiplied, as Core Image hands them in.
    /// `phase` rotates the tiles so a kernel's second input differs from its first.
    static func patches(phase: Int) -> [Float] {
        let tile = size / 4
        var values = [Float](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let index = ((y / tile) * 4 + x / tile + phase * 5) % 16
                let u = Float(x % tile) / Float(tile - 1)
                let v = Float(y % tile) / Float(tile - 1)
                let rgba: (Float, Float, Float, Float) = switch index {
                case 0: (0, 0, 0, 1)
                case 1: (1, 1, 1, 1)
                case 2: (1, 0, 0, 1)
                case 3: (0, 1, 0, 1)
                case 4: (0, 0, 1, 1)
                case 5: (0, 1, 1, 1)
                case 6: (1, 0, 1, 1)
                case 7: (1, 1, 0, 1)
                case 8: (0, 0, 0, 0)
                case 9: (0.5, 0.25, 0, 0.5)
                case 10: (0.02, 0.02, 0.02, 1)
                case 11: (0.98, 0.98, 0.98, 1)
                case 12: (u, u, u, 1)
                case 13: hueRamp(u, value: 0.4 + 0.6 * v)
                case 14: (0.9, 0.9 - 0.8 * u, 0.9 - 0.8 * u * v, 1)
                default: ((x + y) % 2 == 0 ? (0.8, 0.6, 0.3, 1) : (0.1, 0.2, 0.4, 1))
                }
                let offset = (y * size + x) * 4
                values[offset] = rgba.0
                values[offset + 1] = rgba.1
                values[offset + 2] = rgba.2
                values[offset + 3] = rgba.3
            }
        }
        return values
    }

    private static func hueRamp(_ hue: Float, value: Float) -> (Float, Float, Float, Float) {
        let h = hue * 6
        let f = h - h.rounded(.down)
        let rgb: (Float, Float, Float) = switch Int(h) % 6 {
        case 0: (1, f, 0)
        case 1: (1 - f, 1, 0)
        case 2: (0, 1, f)
        case 3: (0, 1 - f, 1)
        case 4: (f, 0, 1)
        default: (1, 0, 1 - f)
        }
        return (rgb.0 * value, rgb.1 * value, rgb.2 * value, 1)
    }

    /// `kernel-reference.jpg` shrunk to the kernel size on the CPU, so the
    /// input does not depend on Core Image's resampler. `phase` mirrors it.
    static func photo(phase: Int) throws -> [Float] {
        let base = try photoBase()
        var values = [Float](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let sx = phase & 1 == 0 ? x : size - 1 - x
                let sy = phase & 2 == 0 ? y : size - 1 - y
                let from = (sy * size + sx) * 4
                let to = (y * size + x) * 4
                for channel in 0..<4 { values[to + channel] = base[from + channel] }
            }
        }
        return values
    }

    private static func photoBase() throws -> [Float] {
        let bytes = try referenceBytes(width: size, height: size)
        return bytes.map { Float($0) / 255 }
    }

    /// The reference photo drawn into 8-bit sRGB at the given size.
    static func referenceBytes(width: Int, height: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(referencePhoto as CFURL, nil))
        let photo = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.interpolationQuality = .high
            context.draw(photo, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    // MARK: Whole-picture goldens

    /// 8-bit sRGB pixels of a rendered picture, top row first.
    static func bytes(of image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// Records the picture as a PNG, or checks it to one 8-bit step a channel.
    static func checkPicture(
        _ image: CGImage,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = directory.appendingPathComponent("\(name).png")
        if isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = try #require(
                CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            )
            // Stored as the 8-bit sRGB pixels compared, not the render's own
            // colour space, so reading it back is the identity.
            let pixels = try bytes(of: image)
            let stored = try picture(pixels, width: image.width, height: image.height)
            CGImageDestinationAddImage(destination, stored, nil)
            try #require(CGImageDestinationFinalize(destination))
            Issue.record("recorded \(name) — delete build/record-kernel-golden", sourceLocation: sourceLocation)
            return
        }
        let source = try #require(
            CGImageSourceCreateWithURL(url as CFURL, nil),
            "no golden for \(name) — capture with build/record-kernel-golden",
            sourceLocation: sourceLocation
        )
        let golden = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try #require(
            golden.width == image.width && golden.height == image.height,
            "\(name): size changed",
            sourceLocation: sourceLocation
        )
        let expected = try bytes(of: golden)
        let actual = try bytes(of: image)
        var failures = 0
        var worst = 0
        for index in actual.indices {
            let delta = abs(Int(actual[index]) - Int(expected[index]))
            if delta > 1 { failures += 1 }
            worst = max(worst, delta)
        }
        #expect(failures == 0, "\(name): \(failures) channels off, worst \(worst)/255", sourceLocation: sourceLocation)
    }

    static func picture(_ bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
