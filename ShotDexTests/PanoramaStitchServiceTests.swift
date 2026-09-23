import CoreImage
import Foundation
import ImageIO
import Photos
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-14 — the whole chain, end to end: frames in, one saved panorama out.
///
/// The frames are synthesised and injected, so the test is about the order of
/// the steps and the things that can go wrong in them, not about PhotoKit's
/// ability to hand over an original. Everything downstream is real — the same
/// registration, the same solve, the same Core Image blend, the same streamed
/// write, and for the saving test the real photo library.
@Suite(.serialized)
struct PanoramaStitchServiceTests {

    private let frameWidth = 320
    private let frameHeight = 240

    // MARK: Building frames that really overlap

    /// Value noise at several frequencies: corners everywhere, no repeat.
    private func scene(width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height)
        var generator = SplitMix64(seed: 0x5354_4954_4348)
        for octave in 0..<5 {
            let cells = 4 << octave
            let amplitude = Float(1.0 / Double(1 << octave))
            var grid = [Float](repeating: 0, count: (cells + 1) * (cells + 1))
            for index in grid.indices {
                grid[index] = Float(Double(generator.next() % 1_000) / 1_000)
            }
            for y in 0..<height {
                for x in 0..<width {
                    let fx = Float(x) / Float(width) * Float(cells)
                    let fy = Float(y) / Float(height) * Float(cells)
                    let x0 = Int(fx), y0 = Int(fy)
                    let tx = fx - Float(x0), ty = fy - Float(y0)
                    let row = y0 * (cells + 1) + x0
                    let top = grid[row] * (1 - tx) + grid[row + 1] * tx
                    let bottom = grid[row + cells + 1] * (1 - tx) + grid[row + cells + 2] * tx
                    pixels[y * width + x] += amplitude * (top * (1 - ty) + bottom * ty)
                }
            }
        }
        let peak = pixels.max() ?? 1
        if peak > 0 { for index in pixels.indices { pixels[index] /= peak } }
        return pixels
    }

    /// Frames cut from one wide scene, which is how a sweep really overlaps.
    private func frames(count: Int, step: Int = 110) -> [PanoramaStitchFrame] {
        let sceneWidth = frameWidth + step * (count - 1) + 40
        let pixels = scene(width: sceneWidth, height: frameHeight + 20)
        return (0..<count).map { index in
            let originX = index * step
            var luminance = [Float](repeating: 0, count: frameWidth * frameHeight)
            var rgba = [Float](repeating: 0, count: 4 * frameWidth * frameHeight)
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let value = pixels[(y + 10) * sceneWidth + originX + x]
                    luminance[y * frameWidth + x] = value
                    // Core Image counts from the bottom.
                    let target = (frameHeight - 1 - y) * frameWidth + x
                    rgba[4 * target] = value
                    rgba[4 * target + 1] = value * 0.9
                    rgba[4 * target + 2] = value * 0.8
                    rgba[4 * target + 3] = 1
                }
            }
            let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
            return PanoramaStitchFrame(
                image: CIImage(
                    bitmapData: data,
                    bytesPerRow: frameWidth * 16,
                    size: CGSize(width: frameWidth, height: frameHeight),
                    format: .RGBAf,
                    colorSpace: nil
                ),
                width: frameWidth,
                height: frameHeight,
                working: PanoramaImage(width: frameWidth, height: frameHeight, pixels: luminance),
                properties: [
                    kCGImagePropertyTIFFDictionary: [
                        kCGImagePropertyTIFFMake: "Canon",
                        kCGImagePropertyTIFFModel: "EOS R6",
                    ] as [CFString: Any],
                    kCGImagePropertyExifDictionary: [
                        kCGImagePropertyExifLensModel: "RF 24mm F1.8 Macro IS STM",
                        kCGImagePropertyExifFNumber: 8,
                    ] as [CFString: Any],
                ]
            )
        }
    }

    /// Exactly `count` photos, or a failure that says how to get them.
    ///
    /// A `PHAsset` cannot be constructed, so these tests borrow whatever the
    /// simulator's library holds; the loader is stubbed, so the pixels never
    /// matter. A bare count check fails on a clean simulator with nothing to
    /// act on, which is how this suite greeted another session — hence the
    /// instructions in the message.
    private func requirePhotos(_ count: Int) throws -> [PHAsset] {
        let assets = libraryPhotos(count)
        guard assets.count == count else {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            throw PanoramaTestPrecondition(description: """
                needs \(count) photos in the simulator library, found \(assets.count) \
                (photo authorization status \(status.rawValue); 3 or 4 is access). Seed it with \
                `xcrun simctl addmedia <udid> <any three jpegs>`, grant photo access to \
                ShotDex on that simulator, then run again. Skipping would prove nothing.
                """)
        }
        return assets
    }

    /// Carries its own sentence so the failure reads as instructions rather
    /// than as a case name.
    private struct PanoramaTestPrecondition: Error, CustomStringConvertible {
        let description: String
    }

    /// Any images from the library — the service only reads their media type
    /// and capture date, because the loader is what actually provides pixels.
    private func libraryPhotos(_ count: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = count
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private func service(
        frames: [PanoramaStitchFrame],
        saved: @escaping @Sendable (URL, String) async throws -> String = { _, _ in "saved-id" },
        indexed: @escaping @Sendable (String) async -> Void = { _ in }
    ) -> PanoramaStitchService {
        let box = FrameBox(frames: frames)
        return PanoramaStitchService(
            loadFrame: { _ in box.next() },
            saveFile: saved,
            indexAsset: indexed
        )
    }

    /// Hands out the prepared frames in order, standing in for PhotoKit.
    private final class FrameBox: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [PanoramaStitchFrame]
        private var index = 0
        init(frames: [PanoramaStitchFrame]) { self.frames = frames }
        func next() -> PanoramaStitchFrame? {
            lock.lock(); defer { lock.unlock() }
            guard index < frames.count else { return nil }
            defer { index += 1 }
            return frames[index]
        }
    }

    // MARK: The chain

    @Test func fewerThanTwoPhotosIsNotAPanorama() async {
        let assets = libraryPhotos(1)
        guard !assets.isEmpty else { return }
        await #expect(throws: PanoramaStitchError.needsTwoImages) {
            _ = try await service(frames: frames(count: 1)).stitch(assets: assets)
        }
    }

    /// Frames that will not come down from iCloud are counted and named, never
    /// silently left out of the picture.
    @Test func framesThatWillNotLoadAreCountedNotDropped() async throws {
        let assets = try requirePhotos(3)
        let service = PanoramaStitchService(
            loadFrame: { _ in nil },
            saveFile: { _, _ in "unused" },
            indexAsset: { _ in }
        )
        await #expect(throws: PanoramaStitchError.framesUnavailable(count: 3)) {
            _ = try await service.stitch(assets: assets)
        }
    }

    /// Cancelling before anything is written produces nothing at all.
    @Test func cancellingStopsBeforeAnythingIsSaved() async throws {
        let assets = try requirePhotos(3)
        let saves = Counter()
        let service = service(frames: frames(count: 3), saved: { _, _ in
            saves.increment()
            return "should-not-happen"
        })
        await #expect(throws: PanoramaStitchError.cancelled) {
            _ = try await service.stitch(assets: assets, isCancelled: { true })
        }
        #expect(saves.value == 0)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// The whole way through: three overlapping frames become one file, with
    /// the panorama tag on it and the camera it was shot with, and the phases
    /// arrive in the order the screen shows them.
    @Test func threeFramesBecomeOneSavedPanorama() async throws {
        let assets = try requirePhotos(3)

        let phases = PhaseLog()
        let written = WrittenFile()
        let indexed = Counter()
        let service = service(
            frames: frames(count: 3),
            saved: { url, name in
                // Copy it out before the service tears its directory down, so
                // the test can look at what was actually produced.
                let kept = FileManager.default.temporaryDirectory
                    .appendingPathComponent("kept-\(UUID().uuidString)-\(name)")
                try? FileManager.default.copyItem(at: url, to: kept)
                written.set(kept)
                return "stitched-asset"
            },
            indexed: { _ in indexed.increment() }
        )

        let identifier = try await service.stitch(
            assets: assets,
            options: PanoramaStitchOptions(projection: .spherical, sizeScale: 1, autoCrop: true),
            progress: { phases.append($0) }
        )
        #expect(identifier == "stitched-asset")
        #expect(indexed.value == 1, "the new photo must be indexed before the viewer opens on it")

        let url = try #require(written.url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        #expect(width > frameWidth, "three overlapping frames make something wider than one of them")

        // It carries the tag, so the indexer will call it a panorama.
        #expect(PanoramaXMP.isStitchedPanorama(source))
        // And it kept the camera, which is what the library filters on.
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "EOS R6")

        // The phases the screen shows, in order.
        #expect(phases.values.contains(.findingOverlaps))
        #expect(phases.values.contains(.aligning))
        #expect(phases.values.contains(.saving))
        let loading = phases.values.firstIndex { if case .loading = $0 { return true } else { return false } }
        let saving = phases.values.firstIndex(of: .saving)
        #expect(loading != nil && saving != nil && loading! < saving!)
    }

    private final class PhaseLog: @unchecked Sendable {
        private let lock = NSLock()
        private var phases: [PanoramaStitchPhase] = []
        func append(_ phase: PanoramaStitchPhase) { lock.lock(); phases.append(phase); lock.unlock() }
        var values: [PanoramaStitchPhase] { lock.lock(); defer { lock.unlock() }; return phases }
    }

    private final class WrittenFile: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URL?
        func set(_ url: URL) { lock.lock(); stored = url; lock.unlock() }
        var url: URL? { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
