import CoreImage
import Testing
@testable import ShotDex
import ShotDexKit

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

    /// Writes the cube where imported LUTs live, so the look bakes it the
    /// way the app does — by id, through `ImportedLUTFiles`.
    private func write(_ text: String, id: String) throws -> URL {
        let directory = ImportedLUTFiles.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ImportedLUTFiles.fileURL(for: id)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A LUT look rendered the way the compositor renders one: baked into a
    /// table, looked up per frame.
    private func render(_ look: VideoLook, exists: Bool = true, on image: CIImage) -> CIImage {
        guard let plan = VideoLookPlan(look, lutExists: { _ in exists }) else { return image }
        return VideoLookRenderer.apply(plan, to: image, cache: VideoLookTableCache(capacity: 4))
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

        let out = render(VideoLook(.lut(id: id, name: "Swap")), on: solid(red: 1, green: 0, blue: 0))
        let result = pixel(out)
        // Red in, blue out. If the axes were transposed this would come
        // back red, or green.
        #expect(result.r < 20)
        #expect(result.b > 235)
    }

    /// A LUT the user deleted must degrade to no LUT, not to a black frame
    /// and not to a crash (FS-12.06c §6).
    @Test func aMissingFileLeavesTheFrameAlone() {
        let out = render(VideoLook(.lut(id: "gone", name: "Gone")), exists: false, on: solid(red: 1, green: 0, blue: 0))
        let result = pixel(out)
        #expect(result.r > 235)
        #expect(result.b < 20)
        #expect(VideoLookPlan(VideoLook(.lut(id: "gone", name: "Gone")), lutExists: { _ in false }) == nil)
    }

    @Test func originalIsNoWork() {
        #expect(VideoLookPlan(.original, lutExists: { _ in true }) == nil)
    }
}
