import CoreImage
import Foundation

/// Decides which frame owns which pixel of the panorama, with the joins put
/// where the frames agree (FS-14.02 §5).
///
/// The blend's own answer is "whichever frame saw this most squarely", which
/// is right for a still scene and blind to a person walking through the
/// overlap. This runs the pairwise seam finder over a small copy of the
/// panorama and hands back one mask per frame, in the blend's own shape, so
/// the multi-band blend still does the fading — only the question of *who*
/// changes.
/// **Not yet wired into the blend.** Measured on the simulator, 2026-09-24:
/// with these masks a three-frame sweep comes out with four visible vertical
/// steps that the blend's own weighting does not have. Two leads, neither
/// chased yet: the greedy pass lets a barely-overlapping pair (the first and
/// last frame of a sweep) re-assign a strip in the middle of a region another
/// frame already owns, and the ramp boundary the blend uses sits where the
/// frames agree on exposure while a seam boundary can land next to a frame
/// edge where they do not. Until that is understood the export and the
/// preview keep the old weighting — a panorama with a soft join through a
/// moving subject is a better picture than one with four hard steps in the
/// sky.
public enum PanoramaSeamPlanner {

    /// The long edge the joins are found at.
    ///
    /// Joins are decided at this size and used at full size, which sounds
    /// careless until you count: the multi-band blend fades across a band far
    /// wider than the error, so a join half a percent out is a join inside its
    /// own feather. The measurement in the plan's Task 0 is why it is not
    /// found at full size — a 7 MP overlap took 1.5 s on its own.
    public static let workingEdge = 512

    /// How much of one frame's area has to be shared with another before the
    /// two are worth finding a join between. Below this the frames touch at a
    /// corner and the join is the coverage edge anyway.
    static let minimumSharedPixels = 64

    /// One mask per source, in the same order: 1 where that frame owns the
    /// pixel, 0 where it does not.
    ///
    /// Returns nil when the joins cannot be found — the blend then falls back
    /// to its own weighting, which is a worse picture of a moving subject and
    /// a perfectly good picture of everything else.
    public static func masks(
        canvas: PanoramaCanvas,
        sources: [PanoramaCISource],
        focal: Double,
        context: CIContext
    ) -> [CIImage]? {
        guard sources.count >= 2, canvas.width > 0, canvas.height > 0 else { return nil }
        let scale = min(1, Double(workingEdge) / Double(max(canvas.width, canvas.height)))
        // A smaller copy of *this* canvas, not a smaller canvas built from the
        // cameras: the canvas handed in has already had the Size control and
        // the preview's own scale applied, and rebuilding would throw both
        // away and put the masks somewhere else entirely.
        guard let small = canvas.scaled(by: scale) else { return nil }

        let width = small.width, height = small.height
        let count = width * height
        var luminance: [[Float]] = []
        var coverage: [[Float]] = []
        for source in sources {
            guard let pair = PanoramaCIBlender.warped(canvas: small, source: source, focal: focal),
                  let read = read(pair.colour, pair.weight, width: width, height: height, context: context)
            else { return nil }
            luminance.append(read.luminance)
            coverage.append(read.coverage)
        }

        // Start from the blend's own answer, then let each overlapping pair
        // move the join it is responsible for. Greedy rather than a joint
        // labelling of every frame at once: a sweep's frames overlap their
        // neighbours and nothing else, so the pairs barely interact, and the
        // honest version of the joint problem is a graph cut this app has no
        // reason to carry.
        var owner = [Int](repeating: -1, count: count)
        for index in 0..<count {
            var best: Float = 0
            for frame in sources.indices where coverage[frame][index] > best {
                best = coverage[frame][index]
                owner[index] = frame
            }
        }

        for a in 0..<sources.count {
            for b in (a + 1)..<sources.count {
                // The join is only allowed to rule on pixels these two share
                // *and* are arguing over; anything a third frame already owns
                // stays its.
                let coverageA = coverage[a], coverageB = coverage[b]
                var contested: [Int] = []
                for index in 0..<count where coverageA[index] > 0.01 && coverageB[index] > 0.01 {
                    if owner[index] == a || owner[index] == b { contested.append(index) }
                }
                guard contested.count >= minimumSharedPixels else { continue }

                var maskA = [Float](repeating: 0, count: count)
                var maskB = [Float](repeating: 0, count: count)
                for index in contested {
                    maskA[index] = coverageA[index]
                    maskB[index] = coverageB[index]
                }
                guard let owned = PanoramaSeamFinder.ownership(
                    a: luminance[a],
                    b: luminance[b],
                    coverageA: maskA,
                    coverageB: maskB,
                    width: width,
                    height: height,
                    axis: axis(for: contested, width: width)
                ) else { continue }
                for index in contested { owner[index] = owned[index] ? a : b }
            }
        }

        return sources.indices.compactMap { frame in
            image(owner: owner, frame: frame, width: width, height: height)?
                .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
                .cropped(to: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        }
    }

    /// Which way the join across this overlap should run, from the shape of
    /// the overlap itself rather than from the canvas.
    static func axis(for contested: [Int], width: Int) -> PanoramaSeamFinder.Axis {
        var minX = Int.max, maxX = 0, minY = Int.max, maxY = 0
        for index in contested {
            let x = index % width, y = index / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        guard minX <= maxX, minY <= maxY else { return .vertical }
        return PanoramaSeamFinder.Axis.across(width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Reading Core Image back into arrays

    /// The warped frame and its say, as two float buffers the seam finder can
    /// walk. Eight bits is enough: this decides which side of a join a pixel
    /// is on, not what colour it is.
    private static func read(
        _ colour: CIImage,
        _ weight: CIImage,
        width: Int,
        height: Int,
        context: CIContext
    ) -> (luminance: [Float], coverage: [Float])? {
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        var colourBytes = [UInt8](repeating: 0, count: width * height * 4)
        var weightBytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        colourBytes.withUnsafeMutableBytes { buffer in
            context.render(
                colour, toBitmap: buffer.baseAddress!, rowBytes: width * 4,
                bounds: extent, format: .RGBA8, colorSpace: space
            )
        }
        weightBytes.withUnsafeMutableBytes { buffer in
            context.render(
                weight, toBitmap: buffer.baseAddress!, rowBytes: width * 4,
                bounds: extent, format: .RGBA8, colorSpace: space
            )
        }
        var luminance = [Float](repeating: 0, count: width * height)
        var coverage = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            // Core Image renders bottom-up; the seam finder, like everything
            // else here that indexes rows, counts from the top.
            let source = (height - 1 - y) * width
            for x in 0..<width {
                let from = 4 * (source + x)
                let to = y * width + x
                luminance[to] = (
                    0.2126 * Float(colourBytes[from])
                        + 0.7152 * Float(colourBytes[from + 1])
                        + 0.0722 * Float(colourBytes[from + 2])
                ) / 255
                coverage[to] = Float(weightBytes[from]) / 255
            }
        }
        return (luminance, coverage)
    }

    /// One frame's ownership as an image the blend can multiply by.
    private static func image(
        owner: [Int],
        frame: Int,
        width: Int,
        height: Int
    ) -> CIImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            // Back to Core Image's bottom-up rows.
            let destination = (height - 1 - y) * width
            for x in 0..<width {
                let on: UInt8 = owner[y * width + x] == frame ? 255 : 0
                let at = 4 * (destination + x)
                bytes[at] = on
                bytes[at + 1] = on
                bytes[at + 2] = on
                bytes[at + 3] = 255
            }
        }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }
}
