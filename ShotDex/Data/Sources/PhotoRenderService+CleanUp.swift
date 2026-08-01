import CoreGraphics
import CoreImage
import Foundation

/// The Clean Up stage: Clone, Heal and Remove.
///
/// Every mode ends up in the same shape — replacement pixels over a tile, blended
/// through a feathered matte with `CIBlendWithMask` — so the whole stage rests on
/// the same primitives the mask code already uses. Clone's pixels are the image
/// translated by the offset the user placed, Remove's come from
/// `PatchMatchInpainter` or the inpainting model, and Heal is Clone with the low
/// frequencies matched back to where they landed.
///
/// The first version instead cached a per-pixel *offset field* and gathered
/// through it with a general `CIKernel`, so a removal would follow later tone
/// changes for free. On device that kernel sampled outside its region of interest
/// and filled every stroke with transparent black. The tone match below buys the
/// same behaviour — a cached patch tracks later exposure and white-balance moves —
/// without a float offset image, an ROI callback, or a kernel dialect that only
/// misbehaves once it is off the Mac.
extension PhotoRenderService {
    /// Replacement pixels for one stroke, plus where they go.
    struct CleanUpFill: Sendable {
        enum Payload: Sendable {
            /// Clone / Heal: read the image this far away, in points, already
            /// y-flipped into image space.
            case translation(CGPoint)
            /// Remove: pixels from the inpainter, at whatever size it solved at.
            case patch(CIImage)
        }

        var payload: Payload
        /// Region of the image the fill covers, in image coordinates.
        var tile: CGRect
        /// Re-match the fill's low frequencies to its surroundings on the way in.
        var matchesTone: Bool
    }

    // MARK: - Kernel

    /// Keeps the fill's detail but takes its brightness and colour from where it
    /// landed: `patch − blur(patch) + blur(destination)`.
    ///
    /// This is what separates Heal from Clone, and it is also what lets a solved
    /// Remove survive later tone edits: the patch is fixed pixels, but its low
    /// frequencies are replaced by the current image's every time it is composited,
    /// so moving Exposure carries the fill along instead of stranding it.
    static let cleanUpMatchKernel = CIColorKernel(source: """
    kernel vec4 cleanUpMatch(__sample patch, __sample patchLow, __sample destinationLow) {
        vec3 matched = patch.rgb - patchLow.rgb + destinationLow.rgb;
        return vec4(clamp(matched, 0.0, 1.0), patch.a);
    }
    """)

    // MARK: - Coverage

    /// The stroke rasterized over `tile` at `size`, one byte per pixel.
    ///
    /// Same geometry as `brushMask` — line width from the image's short edge, core
    /// from the feather, y flipped through `imagePoint` — so `EditorBrushCursor` on
    /// the photo outlines the area that actually changes. Drawn over the tile
    /// rather than the whole frame: at export the frame is tens of megapixels and
    /// this runs per stroke per render.
    ///
    /// `hardEdged` drops the feather for the binary hole an inpainter needs. Both
    /// that hole and the tile's pixels come out of top-down buffers, so the two
    /// agree row for row without anyone having to think about it.
    static func cleanUpCoverageBytes(
        _ stroke: CleanUpStroke,
        extent: CGRect,
        tile: CGRect,
        size: (width: Int, height: Int),
        hardEdged: Bool
    ) -> [UInt8]? {
        guard !stroke.points.isEmpty,
              size.width > 0, size.height > 0,
              tile.width > 0, tile.height > 0
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        let scaleX = CGFloat(size.width) / tile.width
        let scaleY = CGFloat(size.height) / tile.height
        let shortEdge = min(extent.width, extent.height)
        let width = max(1, CGFloat(stroke.size) * shortEdge)
        let core = hardEdged ? 1 : max(0.08, 1 - CGFloat(stroke.feather) * 0.8)

        var drew = false
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: size.width,
                      height: size.height,
                      bitsPerComponent: 8,
                      bytesPerRow: size.width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setLineWidth(width * core * scaleX)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            func mapped(_ point: NormalizedPoint) -> CGPoint {
                let image = Self.imagePoint(point, extent: extent)
                return CGPoint(
                    x: (image.x - tile.minX) * scaleX,
                    y: (image.y - tile.minY) * scaleY
                )
            }
            let first = mapped(stroke.points[0])
            context.move(to: first)
            for point in stroke.points.dropFirst() {
                context.addLine(to: mapped(point))
            }
            if stroke.points.count == 1 {
                // A tap has to leave a dot, and a path with one point strokes
                // nothing.
                context.addLine(to: first)
            }
            context.strokePath()
            drew = true
        }
        return drew ? bytes : nil
    }

    /// Coverage as an image, at the tile's own resolution and feathered.
    static func cleanUpMatte(
        _ stroke: CleanUpStroke,
        extent: CGRect,
        tile: CGRect
    ) -> CIImage? {
        let size = (width: max(1, Int(tile.width)), height: max(1, Int(tile.height)))
        guard let bytes = cleanUpCoverageBytes(
            stroke,
            extent: extent,
            tile: tile,
            size: size,
            hardEdged: false
        ), let image = grayImage(bytes, size: size) else { return nil }
        let matte = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(translationX: tile.minX, y: tile.minY))
        guard stroke.feather > 0 else { return matte }
        let width = max(1, CGFloat(stroke.size) * min(extent.width, extent.height))
        return blurred(matte, radius: Double(width) * stroke.feather * 0.45)
            .cropped(to: tile)
    }

    static func grayImage(_ bytes: [UInt8], size: (width: Int, height: Int)) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: size.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Application

    /// Applies every stroke in order, so a later stroke reads the pixels the
    /// earlier ones produced.
    static func applyCleanUp(
        _ strokes: [CleanUpStroke],
        fills: [UUID: CleanUpFill],
        mattes: [UUID: CIImage],
        to input: CIImage
    ) -> CIImage {
        guard !strokes.isEmpty else { return input }
        var image = input
        for stroke in strokes where stroke.hasVisibleEffect {
            guard let fill = fills[stroke.id], let matte = mattes[stroke.id] else { continue }
            image = applyCleanUpFill(fill, stroke: stroke, matte: matte, to: image)
        }
        return image.cropped(to: input.extent)
    }

    static func applyCleanUpFill(
        _ fill: CleanUpFill,
        stroke: CleanUpStroke,
        matte: CIImage,
        to input: CIImage
    ) -> CIImage {
        let extent = input.extent
        let tile = fill.tile.intersection(extent)
        guard !tile.isEmpty else { return input }

        var patch: CIImage
        switch fill.payload {
        case let .translation(offset):
            patch = input
                .clampedToExtent()
                .transformed(
                    by: CGAffineTransform(translationX: -offset.x, y: -offset.y)
                )
                .cropped(to: tile)
        case let .patch(image):
            patch = fitted(image, in: tile)
        }

        if fill.matchesTone {
            let radius = Double(cleanUpMatchRadius(stroke: stroke, extent: extent))
            patch = matchedTone(patch, to: input, in: tile, radius: radius)
        }

        let coverage = stroke.opacity >= 0.999
            ? matte
            : filtered(
                "CIColorMatrix",
                image: matte,
                values: [
                    "inputRVector": CIVector(x: CGFloat(stroke.opacity), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: CGFloat(stroke.opacity), z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(stroke.opacity), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ]
            )

        return filtered(
            "CIBlendWithMask",
            image: patch,
            values: [
                kCIInputBackgroundImageKey: input,
                kCIInputMaskImageKey: coverage,
            ]
        ).cropped(to: extent)
    }

    /// Takes the fill's detail and the destination's tone. Blurring both sides by
    /// the same radius and swapping the low frequencies is a cheap stand-in for a
    /// gradient-domain solve, and it is enough to make copied pixels sit inside a
    /// brightness gradient without a visible edge.
    static func matchedTone(
        _ patch: CIImage,
        to destination: CIImage,
        in tile: CGRect,
        radius: Double
    ) -> CIImage {
        guard let kernel = cleanUpMatchKernel else { return patch }
        let patchLow = lowFrequency(patch, in: tile, radius: radius)
        let destinationLow = lowFrequency(destination, in: tile, radius: radius)
        return kernel.apply(
            extent: tile,
            arguments: [patch, patchLow, destinationLow]
        ) ?? patch
    }

    /// Blurs at reduced resolution and scales back up.
    ///
    /// The radius this stage wants is a fair fraction of the brush — 75px on a
    /// 2400pt render — and a Gaussian that wide, twice per stroke per frame, was
    /// the second thing making the tool feel heavy. Only the low frequencies
    /// survive the blur anyway, so computing them on a small copy is the same
    /// answer for a fraction of the work.
    static func lowFrequency(_ image: CIImage, in tile: CGRect, radius: Double) -> CIImage {
        let cropped = image.cropped(to: tile)
        guard radius > 1 else { return cropped }
        let target = 12.0
        let scale = min(1, target / radius)
        guard scale < 0.9 else { return blurred(cropped, radius: radius).cropped(to: tile) }
        let small = cropped.transformed(
            by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        )
        return blurred(small, radius: radius * scale)
            .transformed(by: CGAffineTransform(scaleX: 1 / CGFloat(scale), y: 1 / CGFloat(scale)))
            .cropped(to: tile)
    }

    /// Wide enough to carry a brightness gradient across the stroke, narrow enough
    /// to leave the fill's own texture alone.
    static func cleanUpMatchRadius(stroke: CleanUpStroke, extent: CGRect) -> CGFloat {
        let shortEdge = min(extent.width, extent.height)
        return max(2, CGFloat(stroke.size) * shortEdge * 0.35)
    }

    /// Stretches an image solved at working resolution onto its tile in image
    /// coordinates.
    static func fitted(_ image: CIImage, in tile: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(
                by: CGAffineTransform(
                    scaleX: tile.width / extent.width,
                    y: tile.height / extent.height
                )
            )
            .transformed(by: CGAffineTransform(translationX: tile.minX, y: tile.minY))
            .cropped(to: tile)
    }
}
