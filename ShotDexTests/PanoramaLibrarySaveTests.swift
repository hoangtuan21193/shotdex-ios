import CoreGraphics
import Foundation
import ImageIO
import Photos
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
@testable import ShotDexKit

/// FS-14 — the last step of a save, against the real photo library.
///
/// This is the question the plan could not answer from a measurement alone:
/// **does PhotoKit take a picture this big at all.** A panorama of ten 24 MP
/// frames is a couple of hundred megapixels, and if the library refuses it then
/// AC-12 and the whole "no cap on size" decision mean something else.
///
/// Needs photo access. Where it is not granted the test says so and stops
/// rather than passing quietly, because a silent skip here would hide exactly
/// the answer it exists to get.
@Suite(.serialized)
struct PanoramaLibrarySaveTests {

    /// Writes a JPEG of the given size without ever holding it, the way the
    /// exporter does: rows are generated as the encoder asks for them.
    private func writeStreamedJPEG(width: Int, height: Int, to url: URL) throws {
        final class Rows {
            let total: Int
            var offset = 0
            private static let block: [UInt8] = {
                var state: UInt32 = 0x1234_5678
                return (0..<(64 * 1_024)).map { _ in
                    state ^= state << 13; state ^= state >> 17; state ^= state << 5
                    return UInt8(truncatingIfNeeded: state >> 9)
                }
            }()
            init(total: Int) { self.total = total }
            func fill(_ buffer: UnsafeMutableRawPointer, count: Int) -> Int {
                let n = min(count, total - offset)
                guard n > 0 else { return 0 }
                Self.block.withUnsafeBytes { block in
                    var written = 0
                    while written < n {
                        let chunk = min(block.count, n - written)
                        memcpy(buffer.advanced(by: written), block.baseAddress!, chunk)
                        written += chunk
                    }
                }
                offset += n
                return n
            }
        }

        let rows = Rows(total: width * 3 * height)
        var callbacks = CGDataProviderSequentialCallbacks(
            version: 0,
            getBytes: { info, buffer, count in
                guard let info else { return 0 }
                return Unmanaged<Rows>.fromOpaque(info).takeUnretainedValue().fill(buffer, count: count)
            },
            skipForward: { info, count in
                guard let info else { return 0 }
                let rows = Unmanaged<Rows>.fromOpaque(info).takeUnretainedValue()
                let skipped = max(off_t(0), min(count, off_t(rows.total - rows.offset)))
                rows.offset += Int(skipped)
                return skipped
            },
            rewind: { info in
                guard let info else { return }
                Unmanaged<Rows>.fromOpaque(info).takeUnretainedValue().offset = 0
            },
            releaseInfo: { info in
                guard let info else { return }
                Unmanaged<Rows>.fromOpaque(info).release()
            }
        )
        guard let provider = CGDataProvider(
            sequentialInfo: Unmanaged.passRetained(rows).toOpaque(), callbacks: &callbacks
        ), let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ), let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw PanoramaExportError.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PanoramaExportError.cannotEncode }
    }

    private func authorized() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        guard status == .notDetermined else { return false }
        let asked = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
        return asked == .authorized || asked == .limited
    }

    /// The real question: 300 megapixels, written the way the exporter writes,
    /// handed to PhotoKit as a file.
    @MainActor
    @Test func photoKitTakesAPanoramaSizedPicture() async throws {
        guard await authorized() else {
            Issue.record("no photo access — grant it on this simulator and run again; skipping proves nothing")
            return
        }
        let width = 30_000, height = 10_000
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPano-\(UUID().uuidString).jpg")
        try writeStreamedJPEG(width: width, height: height, to: url)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("wrote \(width)x\(height) = \(width * height / 1_000_000) MP, \(Double(bytes ?? 0) / 1_048_576) MB")

        let service = PhotoLibraryService()
        let identifier = try await service.saveImageFile(at: url, filename: url.lastPathComponent)
        let asset = try #require(
            PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
            "PhotoKit reported a save but the asset does not fetch back"
        )
        print("PhotoKit accepted it: \(asset.pixelWidth) x \(asset.pixelHeight)")
        #expect(asset.pixelWidth == width)
        #expect(asset.pixelHeight == height)

        // The file was moved, not copied: leaving a few hundred megabytes of
        // scratch behind is the difference between a tool and a disk leak.
        #expect(!FileManager.default.fileExists(atPath: url.path), "the scratch file should be gone")
    }
}
