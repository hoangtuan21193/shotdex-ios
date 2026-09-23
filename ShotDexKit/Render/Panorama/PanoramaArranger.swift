import Foundation

public enum PanoramaArrangeError: Error, Equatable, Sendable {
    /// Nothing the frame was dropped next to agreed with it, or the alignment
    /// that came back put the frame somewhere else entirely.
    case cannotAlign
    /// Taking this frame out would leave fewer than two in the picture.
    case wouldEmptyThePanorama
}

/// A solution and the overlaps it was built from, carried together because
/// arranging changes both.
public struct PanoramaArrangement: Sendable {
    public var solution: PanoramaCameraSolution
    public var pairs: [PanoramaPairObservation]

    public init(solution: PanoramaCameraSolution, pairs: [PanoramaPairObservation]) {
        self.solution = solution
        self.pairs = pairs
    }
}

/// Putting a frame where the photographer says it goes (FS-14.01 §5).
///
/// The automatic pass places frames by matching every candidate pair; when it
/// gets one wrong, or leaves one out, the drop is the correction. It is a
/// **hint, not an answer**: the frame still has to earn its place by matching
/// the frames it lands among, because a panorama assembled from where a finger
/// stopped would have seams at every join. What the drop buys is which frames
/// to compare against and a sanity check on the result.
public enum PanoramaArranger {

    /// How far the re-aligned frame may sit from where it was dropped, as a
    /// multiple of the frame's own angular width, before the alignment is
    /// treated as disagreeing with the user.
    ///
    /// Half a frame: a photographer aiming at a gap is accurate to well within
    /// that, and anything further means the matcher found a different part of
    /// the scene that happens to look alike — exactly the mistake Arrange
    /// exists to correct.
    public static let dropTolerance = 0.5

    /// How far around the drop to look for frames worth matching against, in
    /// the same units. Wide enough that a frame dropped a little short still
    /// finds its neighbour.
    public static let neighbourhood = 2.0

    // MARK: Placing

    /// Re-aligns `frame` using `direction` as the starting guess, and returns
    /// the whole solution rebuilt around it.
    ///
    /// `images` are the working-size frames the registration was run on, in
    /// frame order; `direction` is a world direction, which is what
    /// `PanoramaCanvas.direction(atX:y:)` gives for a point on the stage.
    public static func place(
        frame: Int,
        towards direction: (Double, Double, Double),
        images: [PanoramaImage],
        pairs: [PanoramaPairObservation],
        solution: PanoramaCameraSolution
    ) throws -> PanoramaArrangement {
        guard frame >= 0, frame < images.count, let first = images.first else {
            throw PanoramaArrangeError.cannotAlign
        }
        let width = first.width, height = first.height
        let candidates = neighbours(
            of: frame,
            towards: direction,
            solution: solution,
            imageWidth: width,
            imageHeight: height
        )
        guard !candidates.isEmpty else { throw PanoramaArrangeError.cannotAlign }

        // Only the frames in play are described again: features are the
        // expensive part, and the rest of the panorama has not moved.
        var features: [Int: [PanoramaFeature]] = [:]
        for index in candidates + [frame] where features[index] == nil {
            features[index] = PanoramaFeatureDetector.features(in: images[index])
        }

        var found: [PanoramaPairObservation] = []
        for other in candidates {
            let (a, b) = frame < other ? (frame, other) : (other, frame)
            guard let fa = features[a], let fb = features[b] else { continue }
            let matches = PanoramaMatcher.matches(fa, fb)
            guard let fit = PanoramaMatcher.fit(matches: matches, a: fa, b: fb) else { continue }
            found.append(
                PanoramaPairObservation(
                    a: a,
                    b: b,
                    homography: fit.homography,
                    correspondences: fit.inliers.map { match in
                        (
                            ax: Double(fa[match.a].x), ay: Double(fa[match.a].y),
                            bx: Double(fb[match.b].x), by: Double(fb[match.b].y)
                        )
                    }
                )
            )
        }
        guard !found.isEmpty else { throw PanoramaArrangeError.cannotAlign }

        // Everything that was already known, plus what the drop just bought.
        // The focal length is not re-estimated: it is a property of the lens,
        // and one frame arriving is no reason to doubt it.
        let merged = merge(pairs.filter { $0.a != frame && $0.b != frame }, found)
        guard let solved = PanoramaCameraSolver.solve(
            frameCount: images.count,
            imageWidth: width,
            imageHeight: height,
            pairs: merged,
            knownFocal: solution.focal
        ), let placed = solved.cameras[frame] else {
            throw PanoramaArrangeError.cannotAlign
        }

        let landed = centreDirection(of: placed)
        let apart = angle(between: landed, and: normalised(direction))
        guard apart <= dropTolerance * angularWidth(
            focal: solution.focal, imageWidth: width, imageHeight: height
        ) else {
            throw PanoramaArrangeError.cannotAlign
        }
        return PanoramaArrangement(solution: solved, pairs: merged)
    }

    // MARK: Removing

    /// Takes a frame out of the picture, the way dragging it to Not Placed
    /// does. The rest is re-solved rather than left with a hole, because the
    /// frames that leant on it have to stand on the others now.
    public static func remove(
        frame: Int,
        images: [PanoramaImage],
        pairs: [PanoramaPairObservation],
        solution: PanoramaCameraSolution
    ) throws -> PanoramaArrangement {
        guard let first = images.first else { throw PanoramaArrangeError.cannotAlign }
        let kept = pairs.filter { $0.a != frame && $0.b != frame }
        guard let solved = PanoramaCameraSolver.solve(
            frameCount: images.count,
            imageWidth: first.width,
            imageHeight: first.height,
            pairs: kept,
            knownFocal: solution.focal
        ), solved.cameras.count >= 2, solved.cameras[frame] == nil else {
            throw PanoramaArrangeError.wouldEmptyThePanorama
        }
        return PanoramaArrangement(solution: solved, pairs: kept)
    }

    // MARK: Geometry

    /// A rotation whose frame centre looks along `direction`, with the roll
    /// that keeps world up as near up as it can.
    ///
    /// Not what places a frame — matching does that — but what the stage draws
    /// the outline with while a finger is still moving, so the frame follows
    /// the drag instead of jumping when it lands.
    public static func seedRotation(towards direction: (Double, Double, Double)) -> [Double] {
        let z = normalised(direction)
        // World up, unless the frame is pointing straight at it, in which case
        // any perpendicular will do and forward is the least surprising.
        let up = abs(z.1) > 0.999 ? (0.0, 0.0, 1.0) : (0.0, 1.0, 0.0)
        var x = cross(up, z)
        let length = (x.0 * x.0 + x.1 * x.1 + x.2 * x.2).squareRoot()
        guard length > 1e-9 else { return PanoramaRotation.identity }
        x = (x.0 / length, x.1 / length, x.2 / length)
        let y = cross(z, x)
        // Rows, because the projection takes a camera ray to the world with
        // the transpose: Rᵀ·(0,0,1) is this matrix's third row.
        return [x.0, x.1, x.2, y.0, y.1, y.2, z.0, z.1, z.2]
    }

    /// Where a camera is looking, in world directions.
    public static func centreDirection(of camera: PanoramaCamera) -> (Double, Double, Double) {
        normalised(PanoramaRotation.apply(PanoramaRotation.transposed(camera.rotation), to: (0, 0, 1)))
    }

    /// The placed frames near enough to `direction` to be worth matching, in
    /// order of how near — nearest first, because the first agreement is the
    /// one most likely to be right.
    public static func neighbours(
        of frame: Int,
        towards direction: (Double, Double, Double),
        solution: PanoramaCameraSolution,
        imageWidth: Int,
        imageHeight: Int
    ) -> [Int] {
        let target = normalised(direction)
        let reach = neighbourhood * angularWidth(
            focal: solution.focal, imageWidth: imageWidth, imageHeight: imageHeight
        )
        let near = solution.cameras
            .filter { $0.key != frame }
            .map { (index: $0.key, apart: angle(between: centreDirection(of: $0.value), and: target)) }
            .filter { $0.apart <= reach }
            .sorted { $0.apart < $1.apart }
            .map(\.index)
        // A drop into open sky finds nothing near it; rather than refuse on
        // geometry alone, try everything placed, and let the matcher be the
        // one to say no.
        return near.isEmpty ? solution.cameras.keys.sorted().filter { $0 != frame } : near
    }

    /// How much sky one frame covers, corner to corner, in radians.
    static func angularWidth(focal: Double, imageWidth: Int, imageHeight: Int) -> Double {
        guard focal > 0 else { return .pi }
        let half = (Double(imageWidth * imageWidth + imageHeight * imageHeight)).squareRoot() / 2
        return 2 * atan(half / focal)
    }

    /// Pair observations from both sides, the new ones winning: a frame that
    /// has just been placed by hand is better described by the match that
    /// placed it than by whatever the automatic pass thought.
    static func merge(
        _ existing: [PanoramaPairObservation],
        _ found: [PanoramaPairObservation]
    ) -> [PanoramaPairObservation] {
        let replaced = Set(found.map { Pair(a: $0.a, b: $0.b) })
        return existing.filter { !replaced.contains(Pair(a: $0.a, b: $0.b)) } + found
    }

    private struct Pair: Hashable { let a: Int; let b: Int }

    static func angle(between a: (Double, Double, Double), and b: (Double, Double, Double)) -> Double {
        let dot = max(-1, min(1, a.0 * b.0 + a.1 * b.1 + a.2 * b.2))
        return acos(dot)
    }

    static func normalised(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let length = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        guard length > 1e-12 else { return (0, 0, 1) }
        return (v.0 / length, v.1 / length, v.2 / length)
    }

    static func cross(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
    }
}
