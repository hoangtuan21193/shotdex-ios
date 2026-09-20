import CoreImage
import Testing
@testable import ShotDex

/// The LUT actually reaching the GPU in the right order.
///
/// The parser's own tests say the numbers are read correctly; these say the
/// cube is *applied* correctly, which is a different failure. A `.cube`
/// whose axes are transposed parses cleanly, renders cleanly, and turns
/// every grade inside out — the only way to catch it is to push a colour
/// through and look at what comes back.
struct VideoLUTRendererTests {
    /// A 2³ cube that swaps red and blue. Red varies fastest, so the rows
    /// are (r, g, b) counting r, then g, then b — and each row's output is
    /// the input with its red and blue exchanged.
    private var swapRedAndBlue: String {
        var lines = ["LUT_3D_SIZE 2"]
        for blue in 0...1 {
            for green in 0...1 {
                for red in 0...1 {
                    lines.append("\(blue).0 \(green).0 \(red).0")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func write(_ text: String, id: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(id)
            .appendingPathExtension("cube")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Reads the single pixel a 1×1 image renders to, in sRGB bytes.
    private func pixel(_ image: CIImage) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                image,
                toBitmap: base,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func theCubeIsAppliedWithRedVaryingFastest() throws {
        let id = "swap-\(UUID().uuidString)"
        let url = try write(swapRedAndBlue, id: id)
        defer { try? FileManager.default.removeItem(at: url) }

        let out = VideoLUTRenderer.apply(
            VideoLUTReference(id: id, name: "Swap"),
            url: url,
            to: solid(red: 1, green: 0, blue: 0)
        )
        let result = pixel(out)
        // Red in, blue out. If the axes were transposed this would come
        // back red, or green.
        #expect(result.r < 20)
        #expect(result.b > 235)
    }

    @Test func strengthMixesTowardsTheOriginal() throws {
        let id = "swap-\(UUID().uuidString)"
        let url = try write(swapRedAndBlue, id: id)
        defer { try? FileManager.default.removeItem(at: url) }

        let half = VideoLUTRenderer.apply(
            VideoLUTReference(id: id, name: "Swap", intensity: 0.5),
            url: url,
            to: solid(red: 1, green: 0, blue: 0)
        )
        let result = pixel(half)
        // Not 128: Core Image mixes in its **linear** working space, so half
        // of sRGB 255 comes back at sRGB ~188, not at the midpoint of the
        // encoded codes. What the test is for is that the mix happened and
        // that it is even — red down off full, blue up off zero, and the two
        // meeting at the same value.
        #expect(result.r > 140 && result.r < 220)
        #expect(result.b > 140 && result.b < 220)
        #expect(abs(result.r - result.b) < 12)
    }

    @Test func zeroStrengthLeavesTheFrameAlone() throws {
        let id = "swap-\(UUID().uuidString)"
        let url = try write(swapRedAndBlue, id: id)
        defer { try? FileManager.default.removeItem(at: url) }

        let out = VideoLUTRenderer.apply(
            VideoLUTReference(id: id, name: "Swap", intensity: 0),
            url: url,
            to: solid(red: 1, green: 0, blue: 0)
        )
        let result = pixel(out)
        #expect(result.r > 235)
        #expect(result.b < 20)
    }

    /// A LUT the user deleted must degrade to no LUT, not to a black frame
    /// and not to a crash.
    @Test func aMissingFileLeavesTheFrameAlone() {
        let out = VideoLUTRenderer.apply(
            VideoLUTReference(id: "gone", name: "Gone"),
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("gone").appendingPathExtension("cube"),
            to: solid(red: 1, green: 0, blue: 0)
        )
        let result = pixel(out)
        #expect(result.r > 235)
        #expect(result.b < 20)
    }

    @Test func noReferenceIsNoWork() {
        let source = solid(red: 0.25, green: 0.5, blue: 0.75)
        let out = VideoLUTRenderer.apply(nil, url: nil, to: source)
        #expect(out === source)
    }
}
