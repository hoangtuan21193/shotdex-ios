import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ImageIO
import Testing
@testable import ShotDexKit

/// Peak memory of a full-resolution focus stack, sampled while it runs.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peakBytes: UInt64 = 0
    private var running = true

    static func current() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock(); let go = running; lock.unlock()
                guard go else { return }
                let now = Self.current()
                lock.lock(); peakBytes = max(peakBytes, now); lock.unlock()
                usleep(5_000)
            }
        }
    }

    func stop() -> UInt64 {
        lock.lock(); running = false; let peak = peakBytes; lock.unlock()
        return peak
    }
}

/// Serialized: footprint is per process, and two stacks measured at once
/// would each count the other's buffers.
@Suite(.serialized)
struct FocusStackExportTests {
    /// A textured frame written as a JPEG, `width`×`height`.
    static func writeFrames(count: Int, width: Int, height: Int, to folder: URL) throws -> [URL] {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var generator = SplitMix64(seed: 11)
        func unit() -> CGFloat { CGFloat(generator.next() % 10_000) / 10_000 }
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for _ in 0..<3_000 {
            context.setFillColor(CGColor(srgbRed: unit(), green: unit(), blue: unit(), alpha: 1))
            let rect = CGRect(x: unit() * CGFloat(width), y: unit() * CGFloat(height), width: 10 + unit() * 120, height: 10 + unit() * 120)
            if generator.next() % 2 == 0 { context.fill(rect) } else { context.fillEllipse(in: rect) }
        }
        let image = context.makeImage()!
        var urls: [URL] = []
        for index in 0..<count {
            let url = folder.appendingPathComponent("frame-\(index).jpg")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            CGImageDestinationFinalize(destination)
            urls.append(url)
        }
        return urls
    }

    static func peakFootprint(frames count: Int, width: Int, height: Int, method: FocusStackOptions.Method, streamed: Bool) async throws -> UInt64 {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FootprintTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try writeFrames(count: count, width: width, height: height, to: folder)
        let baseline = FootprintSampler.current()
        let sampler = FootprintSampler()
        sampler.start()
        let renderer = PhotoStackRenderer()
        if streamed {
            let result = try await renderer.streamedFocusStack(
                frameCount: urls.count,
                frame: { CIImage(contentsOf: urls[$0], options: [.applyOrientationProperty: true]) },
                options: .defaults(for: method)
            )
            _ = result.image.width
        } else {
            let frames = urls.compactMap { CIImage(contentsOf: $0, options: [.applyOrientationProperty: true]) }
            let prepared = try await renderer.prepareFocusStack(images: frames)
            _ = try await renderer.render(renderer.focusStack(prepared, options: .defaults(for: method))).width
        }
        let peak = sampler.stop()
        return peak > baseline ? peak - baseline : 0
    }

    /// FS-01.10 AC-11, the part a simulator can measure: memory does not grow
    /// with the number of frames. 12 MP frames; the 24 MP, 100-frame budget is
    /// measured on a device.
    @Test(arguments: [FocusStackOptions.Method.weighted, .depthMap])
    func memoryDoesNotGrowWithTheNumberOfFrames(method: FocusStackOptions.Method) async throws {
        // Warm-up: the first stack compiles kernels and builds Metal
        // pipelines, which is not memory a longer bracket costs.
        _ = try await Self.peakFootprint(frames: 2, width: 4000, height: 3000, method: method, streamed: true)
        let few = try await Self.peakFootprint(frames: 4, width: 4000, height: 3000, method: method, streamed: true)
        let many = try await Self.peakFootprint(frames: 12, width: 4000, height: 3000, method: method, streamed: true)
        print("FOOTPRINT streamed \(method) 4 frames: \(few / 1_048_576) MB, 12 frames: \(many / 1_048_576) MB")
        // The in-memory stack grew by 200–280 MB over the same eight extra
        // frames; 64 MB of slack absorbs other suites running alongside.
        #expect(Double(many) <= Double(few) * 1.10 + 64 * 1_048_576, "\(method): \(few / 1_048_576) MB → \(many / 1_048_576) MB")
    }
}

extension FocusStackExportTests {
    /// FS-01.10 AC-11's budget, as far as a simulator can say it: a 24 MP
    /// stack under 500 MB. The simulator's GPU memory is not a phone's, so the
    /// number that closes AC-11 is still the one measured on a device.
    @Test(arguments: [FocusStackOptions.Method.weighted, .depthMap])
    func a24MegapixelStackStaysUnderBudget(method: FocusStackOptions.Method) async throws {
        _ = try await Self.peakFootprint(frames: 2, width: 6000, height: 4000, method: method, streamed: true)
        let peak = try await Self.peakFootprint(frames: 4, width: 6000, height: 4000, method: method, streamed: true)
        print("FOOTPRINT streamed \(method) 24 MP × 4: \(peak / 1_048_576) MB")
        #expect(peak <= 500 * 1_048_576, "\(method): \(peak / 1_048_576) MB")
    }
}

/// The streamed stack is the same picture as the in-memory one.
struct FocusStackStreamingTests {
    /// Taller than one 512-row strip, so the strip seams are in the picture.
    let side = 1100

    /// Three frames, each sharp in its own band — rendered to 8-bit first,
    /// because that is what a decoded JPEG or HEIC is, and a float frame
    /// would compare the two paths on precision neither has in real use.
    private func bracket() -> [CIImage] {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var generator = SplitMix64(seed: 5)
        for i in 0..<(side * side) {
            let v = UInt8(truncatingIfNeeded: generator.next() >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v &+ 40; bytes[i * 4 + 2] = v / 2
        }
        let truth = CIImage(cgImage: CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!)
        let soft = truth.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: truth.extent)
        func frame(_ band: ClosedRange<CGFloat>) -> CIImage {
            let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: band.lowerBound, width: CGFloat(side), height: band.upperBound - band.lowerBound))
                .composited(over: CIImage(color: .black).cropped(to: truth.extent))
            return truth.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: mask])
        }
        let s = CGFloat(side)
        let context = CIContext()
        return [frame(0...(s * 0.45)), frame((s * 0.3)...(s * 0.75)), frame((s * 0.6)...s)].map { image in
            CIImage(cgImage: context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!)
        }
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &out, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return out
    }

    private func meanAndWorst(_ a: [UInt8], _ b: [UInt8]) -> (mean: Double, worst: Int) {
        var total = 0, worst = 0, n = 0
        for i in stride(from: 0, to: a.count, by: 4) { for c in 0..<3 {
            let d = abs(Int(a[i + c]) - Int(b[i + c])); total += d; worst = max(worst, d); n += 1
        } }
        return (Double(total) / Double(n), worst)
    }

    @Test(arguments: FocusStackOptions.Method.allCases)
    func streamedMatchesInMemory(method: FocusStackOptions.Method) async throws {
        let frames = bracket()
        let renderer = PhotoStackRenderer()
        let options = FocusStackOptions.defaults(for: method)
        let prepared = try await renderer.prepareFocusStack(images: frames)
        let reference = bytes(try await renderer.render(renderer.focusStack(prepared, options: options)))
        let streamed = try await renderer.streamedFocusStack(frameCount: frames.count, frame: { frames[$0] }, options: options)
        let (mean, worst) = meanAndWorst(bytes(streamed.image), reference)
        #expect(mean < 0.5 && worst <= 3, "\(method): mean \(mean), worst \(worst)")
    }

    @Test func streamedReplaysRetouchStrokes() async throws {
        let frames = bracket()
        let renderer = PhotoStackRenderer()
        let strokes = [FocusStackRetouchStroke(
            frame: 2,
            brush: BrushStroke(points: [NormalizedPoint(x: 0.5, y: 0.8)], size: 0.2, feather: 0, flow: 1, isEraser: false)
        )]
        let prepared = try await renderer.prepareFocusStack(images: frames)
        let reference = bytes(try await renderer.render(
            renderer.retouched(renderer.focusStack(prepared, options: .standard), prepared: prepared, strokes: strokes)))
        let streamed = try await renderer.streamedFocusStack(frameCount: 3, frame: { frames[$0] }, options: .standard, strokes: strokes)
        let (mean, worst) = meanAndWorst(bytes(streamed.image), reference)
        #expect(mean < 0.5 && worst <= 3, "mean \(mean), worst \(worst)")
    }

    @Test func aCancelledStackStopsBeforeItFinishes() async throws {
        // AC-13 at the renderer: cancelling throws instead of handing back a picture.
        let frames = bracket()
        let task = Task {
            try await PhotoStackRenderer().streamedFocusStack(frameCount: 3, frame: { frames[$0] }, options: .standard)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
