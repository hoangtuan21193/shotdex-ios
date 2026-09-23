import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PanoramaExportError: Error, Equatable, Sendable {
    case cancelled
    case cannotEncode
    case emptyCanvas
}

/// Writes a finished panorama to a file without ever holding it.
///
/// The whole feature lives or dies here. A ten-frame set of 24 MP frames makes
/// a picture of a couple of hundred megapixels, and a float canvas that size is
/// several gigabytes — the app would be killed long before it finished. So the
/// picture is never assembled: the JPEG writer pulls rows, each pull renders the
/// strip it needs and nothing else, and the strip is thrown away as soon as it
/// has been written.
///
/// Task 0 measured the two halves of that separately: a streamed JPEG stays
/// flat to 720 MP (+0.1 MB), and Core Image can be asked for one slab of canvas
/// at a time because `PanoramaCIBlender` answers which part of each frame that
/// slab needs.
public enum PanoramaExporter {

    /// Rows rendered per pull. Big enough that the per-strip overhead of
    /// setting up a Core Image render is amortised, small enough that a strip
    /// of a very wide panorama is still a few tens of megabytes.
    public static let stripHeight = 256

    /// JPEG quality. 0.95 rather than 1: the last five points of quality cost
    /// about half the file again on a picture this size, and nobody can see
    /// them.
    public static let jpegQuality = 0.95

    /// The widest a JPEG may be, in either direction. Not a choice — it is the
    /// format's own field width, and a panorama can genuinely reach it.
    public static let maximumEdge = 65_535

    public static func write(
        canvas: PanoramaCanvas,
        sources: [PanoramaCISource],
        focal: Double,
        quality: PanoramaBlendQuality = .sharp,
        crop: PanoramaCropRect? = nil,
        to url: URL,
        properties: [CFString: Any] = [:],
        metadata: CGImageMetadata? = nil,
        context: CIContext? = nil,
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws {
        let region = crop ?? PanoramaCropRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        guard region.width > 0, region.height > 0 else { throw PanoramaExportError.emptyCanvas }
        guard region.width <= maximumEdge, region.height <= maximumEdge else {
            throw PanoramaExportError.cannotEncode
        }

        let blended: CIImage?
        switch quality {
        case .draft: blended = PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)
        case .sharp: blended = PanoramaCIBlender.sharp(canvas: canvas, sources: sources, focal: focal)
        }
        guard let blended else { throw PanoramaExportError.cannotEncode }

        // A float working space: band detail is a difference and is routinely
        // negative, and in an eight-bit context every one of those is silently
        // clamped to zero.
        let renderContext = context ?? CIContext(options: [
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
        ])

        let feeder = StripFeeder(
            image: blended,
            canvasHeight: canvas.height,
            region: region,
            context: renderContext,
            progress: progress,
            isCancelled: isCancelled
        )
        guard let image = feeder.makeImage() else { throw PanoramaExportError.cannotEncode }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw PanoramaExportError.cannotEncode }

        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        if let metadata {
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, options as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
        }
        let finalized = CGImageDestinationFinalize(destination)

        if feeder.wasCancelled {
            try? FileManager.default.removeItem(at: url)
            throw PanoramaExportError.cancelled
        }
        guard finalized else {
            try? FileManager.default.removeItem(at: url)
            throw PanoramaExportError.cannotEncode
        }
        progress?(1)
    }

    /// Serves the encoder its rows, rendering one strip at a time.
    ///
    /// A class because `CGDataProvider`'s callbacks are C function pointers with
    /// an opaque context: there is nowhere to put state except an object whose
    /// pointer is handed across.
    private final class StripFeeder {
        let image: CIImage
        let canvasHeight: Int
        let region: PanoramaCropRect
        let context: CIContext
        let progress: (@Sendable (Double) -> Void)?
        let isCancelled: (@Sendable () -> Bool)?

        /// Bytes already handed over.
        private var offset = 0
        /// The strip currently in hand, and which rows of the output it covers.
        private var strip: [UInt8] = []
        private var stripFirstRow = -1
        private(set) var wasCancelled = false

        var bytesPerRow: Int { region.width * 3 }
        var totalBytes: Int { bytesPerRow * region.height }

        init(
            image: CIImage,
            canvasHeight: Int,
            region: PanoramaCropRect,
            context: CIContext,
            progress: (@Sendable (Double) -> Void)?,
            isCancelled: (@Sendable () -> Bool)?
        ) {
            self.image = image
            self.canvasHeight = canvasHeight
            self.region = region
            self.context = context
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
                width: region.width,
                height: region.height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
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
                    memcpy(
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
            let bottom = region.y + first + rows
            let rect = CGRect(
                x: region.x,
                y: canvasHeight - bottom,
                width: region.width,
                height: rows
            )
            var buffer = [UInt8](repeating: 0, count: region.width * rows * 4)
            buffer.withUnsafeMutableBytes { raw in
                context.render(
                    image,
                    toBitmap: raw.baseAddress!,
                    rowBytes: region.width * 4,
                    bounds: rect,
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
            }

            // Drop alpha, and turn it the right way up.
            var packed = [UInt8](repeating: 0, count: region.width * rows * 3)
            for y in 0..<rows {
                let sourceRow = (rows - 1 - y) * region.width * 4
                let targetRow = y * region.width * 3
                for x in 0..<region.width {
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
            min(stripHeight, region.height - first)
        }
    }
}
