import Foundation

/// Where one frame's camera was pointing, as a rotation about the optical
/// centre. Row-major 3×3.
public struct PanoramaCamera: Sendable, Equatable {
    public var rotation: [Double]

    public init(rotation: [Double] = PanoramaRotation.identity) {
        self.rotation = rotation
    }
}

/// One pair of frames that were found to overlap, with the points that agreed.
public struct PanoramaPairObservation: Sendable {
    public var a: Int
    public var b: Int
    public var homography: PanoramaHomography
    /// Inlier correspondences in working-image pixels: the same world point
    /// seen in frame `a` at (ax, ay) and in frame `b` at (bx, by).
    public var correspondences: [(ax: Double, ay: Double, bx: Double, by: Double)]

    public init(
        a: Int,
        b: Int,
        homography: PanoramaHomography,
        correspondences: [(ax: Double, ay: Double, bx: Double, by: Double)]
    ) {
        self.a = a
        self.b = b
        self.homography = homography
        self.correspondences = correspondences
    }
}

/// The whole set, solved: one focal length for every frame and a rotation for
/// each, plus which frames made it into the panorama at all.
public struct PanoramaCameraSolution: Sendable {
    public var focal: Double
    /// Frame index → camera, for the frames in the largest connected group.
    public var cameras: [Int: PanoramaCamera]
    /// Frames that could not be connected to that group. The screen shows
    /// these as Not Placed rather than dropping them silently (FS-14.01 §2).
    public var unplaced: [Int]
    /// Root-mean-square reprojection error after the solve, in working pixels.
    public var reprojectionError: Double

    public init(
        focal: Double,
        cameras: [Int: PanoramaCamera],
        unplaced: [Int],
        reprojectionError: Double
    ) {
        self.focal = focal
        self.cameras = cameras
        self.unplaced = unplaced
        self.reprojectionError = reprojectionError
    }
}

/// Small rotation helpers. Rotations are carried as matrices and perturbed as
/// axis-angle vectors: a matrix is what the projection wants, and three numbers
/// with no constraint between them is what an optimiser wants.
public enum PanoramaRotation {
    public static let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    /// Rodrigues: an axis-angle vector to a rotation matrix.
    public static func matrix(fromAxisAngle v: (Double, Double, Double)) -> [Double] {
        let theta = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        guard theta > 1e-12 else { return identity }
        let (x, y, z) = (v.0 / theta, v.1 / theta, v.2 / theta)
        let c = Foundation.cos(theta), s = Foundation.sin(theta), t = 1 - c
        return [
            t * x * x + c, t * x * y - s * z, t * x * z + s * y,
            t * x * y + s * z, t * y * y + c, t * y * z - s * x,
            t * x * z - s * y, t * y * z + s * x, t * z * z + c,
        ]
    }

    public static func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += lhs[row * 3 + k] * rhs[k * 3 + column] }
                out[row * 3 + column] = sum
            }
        }
        return out
    }

    public static func transposed(_ m: [Double]) -> [Double] {
        [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
    }

    public static func apply(_ m: [Double], to v: (Double, Double, Double)) -> (Double, Double, Double) {
        (
            m[0] * v.0 + m[1] * v.1 + m[2] * v.2,
            m[3] * v.0 + m[4] * v.1 + m[5] * v.2,
            m[6] * v.0 + m[7] * v.1 + m[8] * v.2
        )
    }

    /// Nearest true rotation to a matrix that has drifted, by Gram–Schmidt.
    /// A rotation recovered from a homography is only approximately orthonormal,
    /// and feeding a not-quite-rotation into a chain of them compounds.
    public static func orthonormalised(_ m: [Double]) -> [Double] {
        func normalise(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
            let length = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
            guard length > 1e-12 else { return (1, 0, 0) }
            return (v.0 / length, v.1 / length, v.2 / length)
        }
        func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
            (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
        }
        func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            a.0 * b.0 + a.1 * b.1 + a.2 * b.2
        }
        let r0 = normalise((m[0], m[1], m[2]))
        var r1 = (m[3], m[4], m[5])
        let projection = dot(r0, r1)
        r1 = (r1.0 - projection * r0.0, r1.1 - projection * r0.1, r1.2 - projection * r0.2)
        let n1 = normalise(r1)
        let n2 = cross(r0, n1)
        return [r0.0, r0.1, r0.2, n1.0, n1.1, n1.2, n2.0, n2.1, n2.2]
    }

    /// Angle of the rotation between two orientations, in degrees. The number
    /// the acceptance criteria are written in.
    public static func angleBetween(_ a: [Double], _ b: [Double]) -> Double {
        let relative = multiply(transposed(a), b)
        let trace = relative[0] + relative[4] + relative[8]
        let cosine = min(1, max(-1, (trace - 1) / 2))
        return Foundation.acos(cosine) * 180 / .pi
    }
}

/// Turns pairwise overlaps into one consistent set of camera orientations.
///
/// Three steps, in the order the spike found necessary: guess a focal length
/// from the homographies, chain the frames together through the strongest
/// overlaps, then refine every orientation at once against every matched point.
/// Chaining alone drifts — each link carries its own error and the last frame
/// of a ten-frame row inherits all of them — and refining without a chain has
/// nowhere to start.
///
/// **Not** part of this: estimating lens distortion. The spike measured that
/// switching it on for a lens that is not distorted makes the answer worse
/// (0.03° → 0.12°), and ShotDex already corrects the lenses it has profiles
/// for. See the plan's §6.
public enum PanoramaCameraSolver {

    /// Focal lengths this solver will believe, as a multiple of the frame's
    /// long edge. Outside this a homography is telling a story about something
    /// other than a rotating camera.
    static let focalRange = 0.2...20.0

    public static func solve(
        frameCount: Int,
        imageWidth: Int,
        imageHeight: Int,
        pairs: [PanoramaPairObservation],
        knownFocal: Double? = nil
    ) -> PanoramaCameraSolution? {
        guard frameCount > 0 else { return nil }
        let centreX = Double(imageWidth) / 2, centreY = Double(imageHeight) / 2
        let longEdge = Double(max(imageWidth, imageHeight))

        let placed = largestGroup(frameCount: frameCount, pairs: pairs)
        guard placed.count >= 2 else { return nil }
        let placedSet = Set(placed)
        let usable = pairs.filter { placedSet.contains($0.a) && placedSet.contains($0.b) }

        let focal = knownFocal ?? estimateFocal(
            pairs: usable, centreX: centreX, centreY: centreY, longEdge: longEdge
        ) ?? longEdge
        var cameras = chainRotations(
            from: usable, placed: placed, focal: focal, centreX: centreX, centreY: centreY
        )

        let error = refine(
            cameras: &cameras,
            pairs: usable,
            focal: focal,
            centreX: centreX,
            centreY: centreY
        )
        levelHorizon(&cameras)

        let unplaced = (0..<frameCount).filter { !placedSet.contains($0) }
        return PanoramaCameraSolution(
            focal: focal, cameras: cameras, unplaced: unplaced, reprojectionError: error
        )
    }

    // MARK: Which frames belong together

    /// The largest set of frames connected to each other through overlaps.
    ///
    /// A photographer's selection routinely holds one frame from somewhere
    /// else; it has no overlap with anything, so it forms its own group and the
    /// big group wins. Ties go to the group holding the lowest frame index,
    /// only so the answer does not depend on dictionary order.
    static func largestGroup(frameCount: Int, pairs: [PanoramaPairObservation]) -> [Int] {
        var parent = Array(0..<frameCount)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current { current = parent[current] }
            var walk = index
            while parent[walk] != walk {
                let next = parent[walk]
                parent[walk] = current
                walk = next
            }
            return current
        }
        for pair in pairs where pair.a < frameCount && pair.b < frameCount {
            let (ra, rb) = (root(pair.a), root(pair.b))
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        var groups: [Int: [Int]] = [:]
        for index in 0..<frameCount { groups[root(index), default: []].append(index) }
        return groups.values.max { left, right in
            left.count != right.count ? left.count < right.count : (left.first ?? 0) > (right.first ?? 0)
        } ?? []
    }

    // MARK: Focal length

    /// One focal length for the whole set, taken as the median of what each
    /// overlap implies.
    ///
    /// Median, not mean: a single pair whose homography is a little off implies
    /// a wildly wrong focal length, and it should not move the answer at all.
    /// One shared value because a panorama is shot on one lens at one setting —
    /// letting each frame have its own invites the optimiser to explain a bad
    /// rotation as a zoom.
    static func estimateFocal(
        pairs: [PanoramaPairObservation],
        centreX: Double,
        centreY: Double,
        longEdge: Double
    ) -> Double? {
        var estimates: [Double] = []
        for pair in pairs {
            let centred = centred(pair.homography, centreX: centreX, centreY: centreY)
            estimates.append(contentsOf: focals(fromCentred: centred))
        }
        let sane = estimates
            .filter { $0.isFinite && focalRange.contains($0 / longEdge) }
            .sorted()
        guard !sane.isEmpty else { return nil }
        return sane[sane.count / 2]
    }

    /// The homography rewritten in coordinates measured from the principal
    /// point, which is what the focal formulas assume.
    static func centred(_ homography: PanoramaHomography, centreX: Double, centreY: Double) -> [Double] {
        let toCentre = [1.0, 0, -centreX, 0, 1, -centreY, 0, 0, 1]
        let fromCentre = [1.0, 0, centreX, 0, 1, centreY, 0, 0, 1]
        return PanoramaRotation.multiply(toCentre, PanoramaRotation.multiply(homography.m, fromCentre))
    }

    /// Focal candidates implied by one homography between two rotations of the
    /// same camera. Both frames' focals are recovered; for a panorama they are
    /// the same number twice, which is itself a weak check on the pair.
    static func focals(fromCentred h: [Double]) -> [Double] {
        var result: [Double] = []

        /// Each formula divides by a quantity that is **exactly zero** for the
        /// commonest panorama there is — a camera turned only left and right,
        /// with no tilt. Guarding each candidate separately rather than
        /// comparing the two blindly is what keeps that case answerable: with
        /// one denominator vanishing the other still carries the answer.
        func candidates(_ pairs: [(value: Double, denominator: Double)]) {
            let usable = pairs
                .filter { abs($0.denominator) > 1e-9 && $0.value > 0 && $0.value.isFinite }
            guard let best = usable.max(by: { abs($0.denominator) < abs($1.denominator) }) else { return }
            result.append(best.value.squareRoot())
        }

        // From the third row: how the transform moves the vanishing line.
        let rowDenominator1 = h[6] * h[7]
        let rowDenominator2 = (h[7] - h[6]) * (h[7] + h[6])
        candidates([
            (-(h[0] * h[1] + h[3] * h[4]) / rowDenominator1, rowDenominator1),
            ((h[0] * h[0] + h[3] * h[3] - h[1] * h[1] - h[4] * h[4]) / rowDenominator2, rowDenominator2),
        ])

        // From the third column, the same argument the other way round.
        let columnDenominator1 = h[0] * h[3] + h[1] * h[4]
        let columnDenominator2 = h[0] * h[0] + h[1] * h[1] - h[3] * h[3] - h[4] * h[4]
        candidates([
            (-h[2] * h[5] / columnDenominator1, columnDenominator1),
            ((h[5] * h[5] - h[2] * h[2]) / columnDenominator2, columnDenominator2),
        ])
        return result.filter(\.isFinite)
    }

    // MARK: Chaining

    /// Walks the frames in order of how well each overlap was supported, so
    /// every orientation is reached through the strongest chain of links
    /// available rather than through whichever pair happened to come first.
    static func chainRotations(
        from pairs: [PanoramaPairObservation],
        placed: [Int],
        focal: Double,
        centreX: Double,
        centreY: Double
    ) -> [Int: PanoramaCamera] {
        var edges: [Int: [(other: Int, rotation: [Double], strength: Int)]] = [:]
        for pair in pairs {
            guard let rotation = rotation(
                from: pair.homography, focal: focal, centreX: centreX, centreY: centreY
            ) else { continue }
            let strength = pair.correspondences.count
            edges[pair.a, default: []].append((pair.b, rotation, strength))
            edges[pair.b, default: []].append(
                (pair.a, PanoramaRotation.transposed(rotation), strength)
            )
        }

        // Start from the frame with the most support: the middle of the row,
        // usually, which is the frame everything else is nearest to.
        let root = placed.max { (edges[$0]?.count ?? 0) < (edges[$1]?.count ?? 0) } ?? placed[0]
        var cameras: [Int: PanoramaCamera] = [root: PanoramaCamera()]
        var frontier = edges[root]?.map { (root, $0) } ?? []

        while !frontier.isEmpty {
            frontier.sort { $0.1.strength > $1.1.strength }
            let (from, edge) = frontier.removeFirst()
            guard cameras[edge.other] == nil, let base = cameras[from] else { continue }
            let rotation = PanoramaRotation.orthonormalised(
                PanoramaRotation.multiply(base.rotation, edge.rotation)
            )
            cameras[edge.other] = PanoramaCamera(rotation: rotation)
            for next in edges[edge.other] ?? [] where cameras[next.other] == nil {
                frontier.append((edge.other, next))
            }
        }
        return cameras
    }

    /// The rotation a homography between two views of one rotating camera
    /// implies: K⁻¹ H K, straightened.
    static func rotation(
        from homography: PanoramaHomography,
        focal: Double,
        centreX: Double,
        centreY: Double
    ) -> [Double]? {
        guard focal > 0 else { return nil }
        let k = [focal, 0, centreX, 0, focal, centreY, 0, 0, 1]
        let kInverse = [1 / focal, 0, -centreX / focal, 0, 1 / focal, -centreY / focal, 0, 0, 1]
        let raw = PanoramaRotation.multiply(kInverse, PanoramaRotation.multiply(homography.m, k))
        guard raw.allSatisfy(\.isFinite) else { return nil }
        return PanoramaRotation.orthonormalised(raw)
    }

    // MARK: Refinement

    /// Levenberg–Marquardt over every camera's orientation at once, against
    /// every matched point in every pair.
    ///
    /// The Jacobian is taken by finite difference rather than derived. The
    /// parameter vector is three numbers per frame — forty for a big panorama —
    /// so the cost is a few hundred residual evaluations per step, and a
    /// hand-derived Jacobian for this projection is a long expression that is
    /// wrong in exactly one term for months. When the measured error is what
    /// the acceptance criteria check, the derivative not being analytic costs
    /// nothing.
    ///
    /// The first camera is held fixed. Without that the whole set can rotate
    /// together at no cost to the error, and the optimiser will happily wander.
    @discardableResult
    static func refine(
        cameras: inout [Int: PanoramaCamera],
        pairs: [PanoramaPairObservation],
        focal: Double,
        centreX: Double,
        centreY: Double,
        iterations: Int = 60
    ) -> Double {
        let indices = cameras.keys.sorted()
        guard indices.count >= 2 else { return 0 }
        let free = Array(indices.dropFirst())
        let parameterCount = free.count * 3
        guard parameterCount > 0 else { return 0 }

        var base = cameras
        var lambda = 1e-3
        var current = residuals(cameras: base, pairs: pairs, focal: focal, centreX: centreX, centreY: centreY)
        var currentCost = current.reduce(0) { $0 + $1 * $1 }

        for _ in 0..<iterations {
            // Numeric Jacobian: one column per free parameter.
            var jacobian = [[Double]](repeating: [], count: parameterCount)
            let step = 1e-6
            for (slot, frame) in free.enumerated() {
                for axis in 0..<3 {
                    var perturbed = base
                    var delta = (0.0, 0.0, 0.0)
                    switch axis {
                    case 0: delta.0 = step
                    case 1: delta.1 = step
                    default: delta.2 = step
                    }
                    let nudge = PanoramaRotation.matrix(fromAxisAngle: delta)
                    perturbed[frame] = PanoramaCamera(
                        rotation: PanoramaRotation.multiply(base[frame]!.rotation, nudge)
                    )
                    let moved = residuals(
                        cameras: perturbed, pairs: pairs, focal: focal, centreX: centreX, centreY: centreY
                    )
                    jacobian[slot * 3 + axis] = zip(moved, current).map { ($0 - $1) / step }
                }
            }

            // Normal equations with the damping term on the diagonal.
            var normal = [[Double]](
                repeating: [Double](repeating: 0, count: parameterCount + 1), count: parameterCount
            )
            for i in 0..<parameterCount {
                for j in i..<parameterCount {
                    var sum = 0.0
                    for r in current.indices { sum += jacobian[i][r] * jacobian[j][r] }
                    normal[i][j] = sum
                    normal[j][i] = sum
                }
                var gradient = 0.0
                for r in current.indices { gradient += jacobian[i][r] * current[r] }
                normal[i][parameterCount] = -gradient
            }
            for i in 0..<parameterCount { normal[i][i] *= (1 + lambda) }

            guard let stepVector = PanoramaMatcher.solve(normal) else { break }
            var candidate = base
            for (slot, frame) in free.enumerated() {
                let delta = (stepVector[slot * 3], stepVector[slot * 3 + 1], stepVector[slot * 3 + 2])
                candidate[frame] = PanoramaCamera(
                    rotation: PanoramaRotation.orthonormalised(
                        PanoramaRotation.multiply(
                            base[frame]!.rotation, PanoramaRotation.matrix(fromAxisAngle: delta)
                        )
                    )
                )
            }
            let candidateResiduals = residuals(
                cameras: candidate, pairs: pairs, focal: focal, centreX: centreX, centreY: centreY
            )
            let candidateCost = candidateResiduals.reduce(0) { $0 + $1 * $1 }
            if candidateCost < currentCost {
                let improvement = (currentCost - candidateCost) / max(currentCost, 1e-12)
                base = candidate
                current = candidateResiduals
                currentCost = candidateCost
                lambda = max(lambda / 3, 1e-9)
                if improvement < 1e-8 { break }
            } else {
                lambda *= 4
                if lambda > 1e7 { break }
            }
        }

        cameras = base
        let count = max(current.count, 1)
        return (currentCost / Double(count)).squareRoot()
    }

    /// Reprojection error of every matched point, as x and y residuals: take
    /// the point seen in `a`, ask where frame `b`'s camera would have put it,
    /// and compare with where `b` actually saw it.
    static func residuals(
        cameras: [Int: PanoramaCamera],
        pairs: [PanoramaPairObservation],
        focal: Double,
        centreX: Double,
        centreY: Double
    ) -> [Double] {
        var out: [Double] = []
        for pair in pairs {
            guard let ca = cameras[pair.a], let cb = cameras[pair.b] else { continue }
            // b's orientation relative to a, applied in camera coordinates.
            let relative = PanoramaRotation.multiply(
                PanoramaRotation.transposed(cb.rotation), ca.rotation
            )
            for point in pair.correspondences {
                let ray = (
                    (point.ax - centreX) / focal,
                    (point.ay - centreY) / focal,
                    1.0
                )
                let turned = PanoramaRotation.apply(relative, to: ray)
                guard abs(turned.2) > 1e-9 else {
                    out.append(0)
                    out.append(0)
                    continue
                }
                let x = centreX + focal * turned.0 / turned.2
                let y = centreY + focal * turned.1 / turned.2
                out.append(x - point.bx)
                out.append(y - point.by)
            }
        }
        return out
    }

    // MARK: Horizon

    /// Turns the whole set so the cameras' side-to-side axes lie in one
    /// horizontal plane.
    ///
    /// Without it a panorama comes out banked: the solve only knows the frames
    /// relative to each other, so nothing has told it which way is up, and a
    /// row of frames shot with the camera tilted two degrees renders as a
    /// two-degree slope across a picture several thousand pixels wide, which is
    /// the one geometric error everybody sees.
    ///
    /// The trick is Brown and Lowe's: a camera turning about a vertical axis
    /// keeps its x-axis in the horizontal plane, so the direction that all the
    /// x-axes are most nearly perpendicular to is up.
    static func levelHorizon(_ cameras: inout [Int: PanoramaCamera]) {
        guard cameras.count >= 2 else { return }
        // Covariance of the x-axes; its least significant direction is up.
        var covariance = [Double](repeating: 0, count: 9)
        for camera in cameras.values {
            let x = (camera.rotation[0], camera.rotation[1], camera.rotation[2])
            let v = [x.0, x.1, x.2]
            for row in 0..<3 {
                for column in 0..<3 {
                    covariance[row * 3 + column] += v[row] * v[column]
                }
            }
        }
        guard let up = smallestEigenvector(of: covariance) else { return }

        // Build a frame whose y-axis is that "up", keeping the average viewing
        // direction pointing the same way so the panorama does not spin.
        var forward = (0.0, 0.0, 0.0)
        for camera in cameras.values {
            forward.0 += camera.rotation[6]
            forward.1 += camera.rotation[7]
            forward.2 += camera.rotation[8]
        }
        func normalise(_ v: (Double, Double, Double)) -> (Double, Double, Double)? {
            let length = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
            guard length > 1e-9 else { return nil }
            return (v.0 / length, v.1 / length, v.2 / length)
        }
        func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
            (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
        }
        guard var y = normalise(up), let f = normalise(forward) else { return }
        // Point "up" the same way the cameras mostly consider up, not upside
        // down: the eigenvector has no sign of its own.
        var averageUp = (0.0, 0.0, 0.0)
        for camera in cameras.values {
            averageUp.0 += camera.rotation[3]
            averageUp.1 += camera.rotation[4]
            averageUp.2 += camera.rotation[5]
        }
        if y.0 * averageUp.0 + y.1 * averageUp.1 + y.2 * averageUp.2 < 0 {
            y = (-y.0, -y.1, -y.2)
        }
        guard let x = normalise(cross(y, f)) else { return }
        let z = cross(x, y)
        let global = [x.0, x.1, x.2, y.0, y.1, y.2, z.0, z.1, z.2]

        for (index, camera) in cameras {
            cameras[index] = PanoramaCamera(
                rotation: PanoramaRotation.orthonormalised(
                    PanoramaRotation.multiply(camera.rotation, PanoramaRotation.transposed(global))
                )
            )
        }
    }

    /// Eigenvector of the smallest eigenvalue of a 3×3 symmetric matrix.
    ///
    /// Solved in closed form rather than by iteration. The matrix here is a
    /// covariance of camera x-axes, and for a level panorama those axes all lie
    /// in one plane — so the matrix is very nearly singular, which is exactly
    /// the case an inverse-iteration loop cannot be trusted on. The closed form
    /// has no such trouble: the eigenvalues of a symmetric 3×3 are the roots of
    /// its characteristic cubic, and that cubic has a trigonometric solution.
    static func smallestEigenvector(of m: [Double]) -> (Double, Double, Double)? {
        let trace = m[0] + m[4] + m[8]
        let q = trace / 3
        let shifted = [
            m[0] - q, m[1], m[2],
            m[3], m[4] - q, m[5],
            m[6], m[7], m[8] - q,
        ]
        var sumSquares = 0.0
        for value in shifted { sumSquares += value * value }
        let p = (sumSquares / 6).squareRoot()
        let smallest: Double
        if p < 1e-15 {
            // Already a multiple of the identity: every direction is an
            // eigenvector, so there is no "up" to find here.
            return nil
        } else {
            let scaled = shifted.map { $0 / p }
            let determinant =
                scaled[0] * (scaled[4] * scaled[8] - scaled[5] * scaled[7])
                - scaled[1] * (scaled[3] * scaled[8] - scaled[5] * scaled[6])
                + scaled[2] * (scaled[3] * scaled[7] - scaled[4] * scaled[6])
            let r = min(1, max(-1, determinant / 2))
            let phi = Foundation.acos(r) / 3
            // The three roots, of which the last is the smallest.
            smallest = q + 2 * p * Foundation.cos(phi + 2 * .pi / 3)
        }

        // Null space of (M - λI): the cross product of two of its rows, taking
        // whichever pair is furthest from parallel so the product is not noise.
        let a = [m[0] - smallest, m[1], m[2]]
        let b = [m[3], m[4] - smallest, m[5]]
        let c = [m[6], m[7], m[8] - smallest]
        func cross(_ lhs: [Double], _ rhs: [Double]) -> (Double, Double, Double) {
            (
                lhs[1] * rhs[2] - lhs[2] * rhs[1],
                lhs[2] * rhs[0] - lhs[0] * rhs[2],
                lhs[0] * rhs[1] - lhs[1] * rhs[0]
            )
        }
        let options = [cross(a, b), cross(b, c), cross(c, a)]
        guard let best = options.max(by: { left, right in
            (left.0 * left.0 + left.1 * left.1 + left.2 * left.2)
                < (right.0 * right.0 + right.1 * right.1 + right.2 * right.2)
        }) else { return nil }
        let length = (best.0 * best.0 + best.1 * best.1 + best.2 * best.2).squareRoot()
        guard length > 1e-12 else { return nil }
        return (best.0 / length, best.1 / length, best.2 / length)
    }
}
