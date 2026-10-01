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
        warp: PanoramaWarpMesh? = nil,
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
        case .draft:
            blended = PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)
        case .sharp:
            // The joins are found here and not in the draft: the search costs
            // more than one frame of a slider is worth, and this is the
            // picture that gets kept (FS-14.02 §5).
            let seams = PanoramaSeamPlanner.masks(
                canvas: canvas,
                sources: sources,
                focal: focal,
                context: context ?? CIContext(options: [.cacheIntermediates: false])
            )
            blended = PanoramaCIBlender.sharp(
                canvas: canvas, sources: sources, focal: focal, seamMasks: seams
            )
        }
        guard var blended else { throw PanoramaExportError.cannotEncode }
        if let warp, let stretched = PanoramaBoundaryWarp.apply(
            warp, to: blended, width: canvas.width, height: canvas.height
        ) {
            blended = stretched
        }

        // A float working space: band detail is a difference and is routinely
        // negative, and in an eight-bit context every one of those is silently
        // clamped to zero.
        let renderContext = context ?? CIContext(options: [
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
        ])

        // The crop counts rows from the top; Core Image from the bottom.
        let rect = CGRect(x: region.x, y: canvas.height - region.y - region.height,
                          width: region.width, height: region.height)
        do {
            try StripImageWriter.write(
                blended, rect: rect, to: url, type: .jpeg, quality: jpegQuality,
                properties: properties, metadata: metadata, context: renderContext,
                stripHeight: stripHeight, progress: progress, isCancelled: isCancelled
            )
        } catch StripImageWriter.Failure.cancelled {
            throw PanoramaExportError.cancelled
        } catch {
            throw PanoramaExportError.cannotEncode
        }
        progress?(1)
    }
}
