import Foundation

/// Two features, one in each frame, believed to be the same point in the world.
public struct PanoramaMatch: Sendable, Equatable {
    /// Index into the first frame's features.
    public var a: Int
    /// Index into the second frame's.
    public var b: Int
    public var distance: Int

    public init(a: Int, b: Int, distance: Int) {
        self.a = a
        self.b = b
        self.distance = distance
    }
}

/// A 3×3 projective transform taking points of one frame into another.
///
/// Stored row-major and always normalised so `m[8] == 1`, which makes two
/// homographies comparable without deciding what scale each was found at.
public struct PanoramaHomography: Sendable, Equatable {
    public var m: [Double]

    public init?(_ values: [Double]) {
        guard values.count == 9, values[8] != 0, values.allSatisfy(\.isFinite) else { return nil }
        m = values.map { $0 / values[8] }
    }

    public static let identity = PanoramaHomography([1, 0, 0, 0, 1, 0, 0, 0, 1])!

    /// Maps one point. Returns nil where the point falls on the horizon of the
    /// transform — behind the camera, or at infinity — which is a real answer
    /// and not an error.
    public func map(x: Double, y: Double) -> (x: Double, y: Double)? {
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-12 else { return nil }
        return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w)
    }
}

/// How well two frames were lined up.
public struct PanoramaPairFit: Sendable {
    public var homography: PanoramaHomography
    /// Matches the homography agrees with.
    public var inliers: [PanoramaMatch]
    /// Median reprojection error of those, in working-image pixels.
    public var medianError: Double

    public init(homography: PanoramaHomography, inliers: [PanoramaMatch], medianError: Double) {
        self.homography = homography
        self.inliers = inliers
        self.medianError = medianError
    }
}

/// Matches features between two frames and fits the transform between them.
public enum PanoramaMatcher {
    /// A match is kept only if the best candidate is clearly better than the
    /// second best. Repeated texture — a row of windows, a brick wall — gives
    /// many equally good candidates, and this is what throws those away rather
    /// than picking one at random.
    public static let ratioThreshold = 0.78

    /// How far a point may land from where the homography says, in pixels of
    /// the 1024 px working image, and still count as agreeing with it.
    public static let inlierThreshold = 3.0

    /// The fewest inliers a pair may have and still be called overlapping.
    ///
    /// Brown and Lowe's rule of thumb, kept because it is the one the spike
    /// measured 0 false pairs with: a homography has 8 degrees of freedom, so
    /// agreement from a handful of points means nothing.
    public static let minimumInliers = 20

    // MARK: Matching

    /// Two-way nearest-neighbour matching with a ratio test.
    ///
    /// Two-way because one-way matching always returns something: every feature
    /// in A has a nearest neighbour in B, including the features that are of a
    /// part of the scene B never saw. Requiring the match to be mutual is what
    /// makes "these frames do not overlap" a possible answer.
    public static func matches(_ a: [PanoramaFeature], _ b: [PanoramaFeature]) -> [PanoramaMatch] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let forward = nearestNeighbours(from: a, to: b)
        let backward = nearestNeighbours(from: b, to: a)
        var result: [PanoramaMatch] = []
        result.reserveCapacity(min(a.count, b.count))
        for (indexA, candidate) in forward.enumerated() {
            guard let candidate, backward[candidate.index]?.index == indexA else { continue }
            result.append(PanoramaMatch(a: indexA, b: candidate.index, distance: candidate.distance))
        }
        return result
    }

    private struct Candidate {
        var index: Int
        var distance: Int
    }

    private static func nearestNeighbours(
        from source: [PanoramaFeature],
        to target: [PanoramaFeature]
    ) -> [Candidate?] {
        source.map { feature in
            var best = Candidate(index: -1, distance: Int.max)
            var second = Int.max
            for (index, other) in target.enumerated() {
                let distance = feature.descriptor.distance(to: other.descriptor)
                if distance < best.distance {
                    second = best.distance
                    best = Candidate(index: index, distance: distance)
                } else if distance < second {
                    second = distance
                }
            }
            guard best.index >= 0, second < Int.max else { return nil }
            guard Double(best.distance) < ratioThreshold * Double(second) else { return nil }
            return best
        }
    }

    // MARK: Fitting

    /// Fits the homography taking points of `a` onto points of `b`, ignoring
    /// the matches that disagree with it.
    ///
    /// RANSAC rather than a least-squares fit over every match: a few percent
    /// of matches are simply wrong, and one wrong pair drags a least-squares
    /// fit far enough to lose the rest. Returns nil when no transform is
    /// supported by `minimumInliers` matches, which is the app's answer to
    /// "these two frames do not overlap".
    public static func fit(
        matches: [PanoramaMatch],
        a: [PanoramaFeature],
        b: [PanoramaFeature],
        iterations: Int = 2_000
    ) -> PanoramaPairFit? {
        guard matches.count >= minimumInliers else { return nil }
        var generator = SplitMix64(seed: 0x484F_4D4F_4752_4150)
        var best: PanoramaPairFit?

        for _ in 0..<iterations {
            guard let sample = sampleFour(from: matches, using: &generator) else { continue }
            let points = sample.map { match -> (Double, Double, Double, Double) in
                (Double(a[match.a].x), Double(a[match.a].y), Double(b[match.b].x), Double(b[match.b].y))
            }
            guard let candidate = homography(fromFour: points) else { continue }
            let (inliers, error) = support(of: candidate, matches: matches, a: a, b: b)
            if inliers.count > (best?.inliers.count ?? 0) {
                best = PanoramaPairFit(homography: candidate, inliers: inliers, medianError: error)
            }
            // Enough agreement that another sample cannot plausibly beat it.
            if let best, best.inliers.count > matches.count * 9 / 10 { break }
        }

        guard let best, best.inliers.count >= minimumInliers else { return nil }
        // One more fit over everything that agreed: the four points that found
        // the transform were chosen for being lucky, not for being accurate.
        guard let refined = refine(best.inliers, a: a, b: b) else { return best }
        let (inliers, error) = support(of: refined, matches: matches, a: a, b: b)
        guard inliers.count >= best.inliers.count else { return best }
        return PanoramaPairFit(homography: refined, inliers: inliers, medianError: error)
    }

    private static func sampleFour(
        from matches: [PanoramaMatch],
        using generator: inout SplitMix64
    ) -> [PanoramaMatch]? {
        guard matches.count >= 4 else { return nil }
        var chosen: [Int] = []
        var attempts = 0
        while chosen.count < 4 && attempts < 32 {
            attempts += 1
            let index = Int(generator.next() % UInt64(matches.count))
            if !chosen.contains(index) { chosen.append(index) }
        }
        guard chosen.count == 4 else { return nil }
        return chosen.map { matches[$0] }
    }

    private static func support(
        of homography: PanoramaHomography,
        matches: [PanoramaMatch],
        a: [PanoramaFeature],
        b: [PanoramaFeature]
    ) -> ([PanoramaMatch], Double) {
        var inliers: [PanoramaMatch] = []
        var errors: [Double] = []
        for match in matches {
            guard let mapped = homography.map(x: Double(a[match.a].x), y: Double(a[match.a].y)) else { continue }
            let dx = mapped.x - Double(b[match.b].x)
            let dy = mapped.y - Double(b[match.b].y)
            let error = (dx * dx + dy * dy).squareRoot()
            if error <= inlierThreshold {
                inliers.append(match)
                errors.append(error)
            }
        }
        errors.sort()
        let median = errors.isEmpty ? Double.infinity : errors[errors.count / 2]
        return (inliers, median)
    }

    // MARK: The linear algebra

    /// The homography through four point pairs, by solving the 8×8 system the
    /// direct linear transform gives.
    ///
    /// Eight equations and eight unknowns, so this is Gaussian elimination and
    /// not a decomposition — the general least-squares case is handled by
    /// `refine`, which normalises first.
    static func homography(fromFour points: [(Double, Double, Double, Double)]) -> PanoramaHomography? {
        guard points.count == 4 else { return nil }
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for (index, point) in points.enumerated() {
            let (x, y, u, v) = point
            matrix[index * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            matrix[index * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        guard let solution = solve(matrix) else { return nil }
        return PanoramaHomography(solution + [1])
    }

    /// Least squares over every inlier, on coordinates normalised to zero mean
    /// and an average distance of √2 from the origin.
    ///
    /// The normalisation is not optional: in raw pixel coordinates the entries
    /// of the design matrix differ by six orders of magnitude, and the answer
    /// is then decided by rounding rather than by the points.
    static func refine(
        _ matches: [PanoramaMatch],
        a: [PanoramaFeature],
        b: [PanoramaFeature]
    ) -> PanoramaHomography? {
        guard matches.count >= 4 else { return nil }
        let sourcePoints = matches.map { (Double(a[$0.a].x), Double(a[$0.a].y)) }
        let targetPoints = matches.map { (Double(b[$0.b].x), Double(b[$0.b].y)) }
        guard let source = Normalisation(of: sourcePoints), let target = Normalisation(of: targetPoints) else {
            return nil
        }

        // Normal equations of the 2n×8 system, accumulated directly: n is a few
        // hundred at most, and forming AᵀA keeps the solve at 8×8.
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for index in matches.indices {
            let (x, y) = source.apply(sourcePoints[index])
            let (u, v) = target.apply(targetPoints[index])
            let rows = [
                [x, y, 1, 0, 0, 0, -u * x, -u * y, u],
                [0, 0, 0, x, y, 1, -v * x, -v * y, v],
            ]
            for row in rows {
                for i in 0..<8 {
                    for j in 0..<8 {
                        ata[i][j] += row[i] * row[j]
                    }
                    ata[i][8] += row[i] * row[8]
                }
            }
        }
        guard let solution = solve(ata) else { return nil }
        let normalised = solution + [1]
        return target.inverseApplied(to: source.applied(to: normalised))
    }

    /// Hartley normalisation for one point set.
    private struct Normalisation {
        var meanX: Double
        var meanY: Double
        var scale: Double

        init?(of points: [(Double, Double)]) {
            guard !points.isEmpty else { return nil }
            let count = Double(points.count)
            let centreX = points.reduce(0) { $0 + $1.0 } / count
            let centreY = points.reduce(0) { $0 + $1.1 } / count
            let mean = points.reduce(0.0) { partial, point in
                let dx = point.0 - centreX, dy = point.1 - centreY
                return partial + (dx * dx + dy * dy).squareRoot()
            } / count
            guard mean > 1e-9 else { return nil }
            meanX = centreX
            meanY = centreY
            scale = 2.0.squareRoot() / mean
        }

        func apply(_ point: (Double, Double)) -> (Double, Double) {
            ((point.0 - meanX) * scale, (point.1 - meanY) * scale)
        }

        /// H · T, where T is this normalisation as a matrix.
        func applied(to h: [Double]) -> [Double] {
            let t = [scale, 0, -scale * meanX, 0, scale, -scale * meanY, 0, 0, 1]
            return multiply(h, t)
        }

        /// T⁻¹ · H.
        func inverseApplied(to h: [Double]) -> PanoramaHomography? {
            let inverse = [1 / scale, 0, meanX, 0, 1 / scale, meanY, 0, 0, 1]
            return PanoramaHomography(multiply(inverse, h))
        }

        private func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
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
    }

    /// Gaussian elimination with partial pivoting on an augmented n×(n+1)
    /// matrix. Returns nil when the system is singular, which happens for real
    /// reasons — four sampled points that turn out to be collinear — and is not
    /// worth a thrown error.
    static func solve(_ input: [[Double]]) -> [Double]? {
        var matrix = input
        let n = matrix.count
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(matrix[row][column]) > abs(matrix[pivot][column]) {
                pivot = row
            }
            guard abs(matrix[pivot][column]) > 1e-12 else { return nil }
            matrix.swapAt(column, pivot)
            let divisor = matrix[column][column]
            for index in column...n { matrix[column][index] /= divisor }
            for row in 0..<n where row != column {
                let factor = matrix[row][column]
                guard factor != 0 else { continue }
                for index in column...n {
                    matrix[row][index] -= factor * matrix[column][index]
                }
            }
        }
        let solution = (0..<n).map { matrix[$0][n] }
        return solution.allSatisfy(\.isFinite) ? solution : nil
    }
}
