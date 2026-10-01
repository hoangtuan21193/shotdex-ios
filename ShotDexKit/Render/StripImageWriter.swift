import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a Core Image picture to a file without ever holding it: the encoder
/// pulls rows, each pull renders the strip it needs and nothing else, and the
/// strip is thrown away once written. Panoramas (FS-14) and HDR merges
/// (FS-01.11) are saved this way.
///
/// FS-14 task 0 measured it: a streamed JPEG stays flat to 720 MP (+0.1 MB).
public enum StripImageWriter {
    public enum Failure: Error, Equatable, Sendable {
        case cancelled
        case cannotEncode
    }

    /// Writes `image` over `rect` (Core Image coordinates, whole pixels) to
    /// `url` as `type`. A cancelled or failed write leaves no file.
    public static func write(
        _ image: CIImage,
        rect: CGRect,
        to url: URL,
        type: UTType,
        quality: Double,
        properties: [CFString: Any] = [:],
        metadata: CGImageMetadata? = nil,
        context: CIContext,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB(),
        stripHeight: Int = 256,
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws {
        try write(rect: rect, to: url, type: type, quality: quality, properties: properties, metadata: metadata,
                  context: context, colorSpace: colorSpace, stripHeight: stripHeight, progress: progress,
                  isCancelled: isCancelled, strip: { _ in image })
    }

    /// Like `write(_:rect:…)`, with the picture built per strip: `strip`
    /// gets the strip's rectangle and hands back an image covering it, so a
    /// picture backed by a big buffer can hand over only the rows near it.
    public static func write(
        rect: CGRect,
        to url: URL,
        type: UTType,
        quality: Double,
        properties: [CFString: Any] = [:],
        metadata: CGImageMetadata? = nil,
        context: CIContext,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB(),
        stripHeight: Int = 256,
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil,
        strip: @escaping (CGRect) -> CIImage?
    ) throws {
        let region = rect.integral
        guard region.width > 0, region.height > 0 else { throw Failure.cannotEncode }
        let feeder = StripFeeder(image: strip, region: region, context: context, colorSpace: colorSpace,
                                 stripHeight: stripHeight, progress: progress, isCancelled: isCancelled)
        guard let rows = feeder.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.cannotEncode }

        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = quality
        if let metadata {
            CGImageDestinationAddImageAndMetadata(destination, rows, metadata, options as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, rows, options as CFDictionary)
        }
        let finalized = CGImageDestinationFinalize(destination)
        if feeder.wasCancelled {
            try? FileManager.default.removeItem(at: url)
            throw Failure.cancelled
        }
        guard finalized else {
            try? FileManager.default.removeItem(at: url)
            throw Failure.cannotEncode
        }
    }

    /// Serves the encoder its rows, rendering one strip at a time.
    ///
    /// A class because `CGDataProvider`'s callbacks are C function pointers with
    /// an opaque context: there is nowhere to put state except an object whose
    /// pointer is handed across.
    private final class StripFeeder {
        let image: (CGRect) -> CIImage?
        /// Core Image coordinates.
        let region: CGRect
        let context: CIContext
        let colorSpace: CGColorSpace
        let stripHeight: Int
        let progress: (@Sendable (Double) -> Void)?
        let isCancelled: (@Sendable () -> Bool)?

        /// Bytes already handed over.
        private var offset = 0
        /// The strip currently in hand, and which rows of the output it covers.
        private var strip: [UInt8] = []
        private var stripFirstRow = -1
        private(set) var wasCancelled = false

        var width: Int { Int(region.width) }
        var height: Int { Int(region.height) }
        var bytesPerRow: Int { width * 3 }
        var totalBytes: Int { bytesPerRow * height }

        init(
            image: @escaping (CGRect) -> CIImage?,
            region: CGRect,
            context: CIContext,
            colorSpace: CGColorSpace,
            stripHeight: Int,
            progress: (@Sendable (Double) -> Void)?,
            isCancelled: (@Sendable () -> Bool)?
        ) {
            self.image = image
            self.region = region
            self.context = context
            self.colorSpace = colorSpace
            self.stripHeight = stripHeight
            self.progress = progress
            self.isCancelled = isCancelled
        }

        func makeImage() -> CGImage? {
            var callbacks = CGDataProviderSequentialCallbacks(
                version: 0,
                getBytes: { info, buffer, count in
                    guard let info else { return 0 }
                    return Unmanaged<StripFeeder>.fromOpaque(info).takeUnretainedValue()
                        .fill(buffer, count: count)
                },
                skipForward: { info, count in
                    guard let info else { return 0 }
                    let feeder = Unmanaged<StripFeeder>.fromOpaque(info).takeUnretainedValue()
                    return feeder.skip(count)
                },
                rewind: { info in
                    guard let info else { return }
                    Unmanaged<StripFeeder>.fromOpaque(info).takeUnretainedValue().rewind()
                },
                releaseInfo: { info in
                    guard let info else { return }
                    Unmanaged<StripFeeder>.fromOpaque(info).release()
                }
            )
            guard let provider = CGDataProvider(
                sequentialInfo: Unmanaged.passRetained(self).toOpaque(),
                callbacks: &callbacks
            ) else { return nil }
            return CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        func fill(_ buffer: UnsafeMutableRawPointer, count: Int) -> Int {
            guard !wasCancelled else { return 0 }
            if isCancelled?() == true {
                wasCancelled = true
                return 0
            }
            let wanted = min(count, totalBytes - offset)
            guard wanted > 0 else { return 0 }

            var written = 0
            let output = buffer.assumingMemoryBound(to: UInt8.self)
            while written < wanted {
                let row = (offset + written) / bytesPerRow
                guard ensureStrip(containing: row) else { break }
                let rowInStrip = row - stripFirstRow
                let columnByte = (offset + written) % bytesPerRow
                let available = bytesPerRow - columnByte
                let chunk = min(available, wanted - written)
                strip.withUnsafeBufferPointer { source in
                    _ = memcpy(
                        output.advanced(by: written),
                        source.baseAddress!.advanced(by: rowInStrip * bytesPerRow + columnByte),
                        chunk
                    )
                }
                written += chunk
            }
            offset += written
            progress?(Double(offset) / Double(totalBytes))
            return written
        }

        func skip(_ count: off_t) -> off_t {
            let remaining = off_t(totalBytes - offset)
            let skipped = max(0, min(count, remaining))
            offset += Int(skipped)
            return skipped
        }

        func rewind() {
            offset = 0
            strip = []
            stripFirstRow = -1
        }

        /// Renders the strip holding `row` if it is not the one in hand.
        ///
        /// The encoder reads forward, so this normally renders each strip once.
        /// It is written to survive a rewind anyway, because the format is
        /// entitled to ask.
        private func ensureStrip(containing row: Int) -> Bool {
            if stripFirstRow >= 0, row >= stripFirstRow, row < stripFirstRow + stripRows(at: stripFirstRow) {
                return true
            }
            let first = (row / stripHeight) * stripHeight
            let rows = stripRows(at: first)
            guard rows > 0 else { return false }

            // Core Image counts from the bottom; the output counts from the top.
            let rect = CGRect(x: region.minX, y: region.maxY - CGFloat(first + rows),
                              width: region.width, height: CGFloat(rows))
            guard let picture = image(rect) else { return false }
            var buffer = [UInt8](repeating: 0, count: width * rows * 4)
            buffer.withUnsafeMutableBytes { raw in
                context.render(picture, toBitmap: raw.baseAddress!, rowBytes: width * 4,
                               bounds: rect, format: .RGBA8, colorSpace: colorSpace)
            }

            // Drop alpha. Core Image writes the strip's top row first — the
            // file's order already. (Turning each strip over, as this code did
            // in the panorama exporter until 2026-10-01, mirrored every
            // 256-row band of a saved panorama; its tests only had pictures
            // that read the same upside down.)
            var packed = [UInt8](repeating: 0, count: width * rows * 3)
            for y in 0..<rows {
                let sourceRow = y * width * 4
                let targetRow = y * width * 3
                for x in 0..<width {
                    packed[targetRow + 3 * x] = buffer[sourceRow + 4 * x]
                    packed[targetRow + 3 * x + 1] = buffer[sourceRow + 4 * x + 1]
                    packed[targetRow + 3 * x + 2] = buffer[sourceRow + 4 * x + 2]
                }
            }
            strip = packed
            stripFirstRow = first
            return true
        }

        private func stripRows(at first: Int) -> Int {
            min(stripHeight, height - first)
        }
    }
}
