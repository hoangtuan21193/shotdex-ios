import Foundation

/// Where the join between two frames should run (FS-14.02 §5).
///
/// A weighted blend down the middle of the overlap is right for a still
/// scene and wrong for every other one: someone who walked through the
/// overlap between two shutter presses is in one frame and not the other, and
/// a join that crosses them cuts them in half or prints them twice. The fix
/// is old and cheap — put the join where the two frames already agree, and
/// let it bend around whatever moved.
///
/// This finds the join on a small copy. Nothing about it is per-pixel exact:
/// it decides *which frame owns which side*, and the multi-band blend still
/// does the fading, so a join a pixel out at working size is a join nobody
/// can find in the picture.
public enum PanoramaSeamFinder {

    /// Which way the join runs.
    public enum Axis: Sendable {
        /// Frames side by side: the join is a line from top to bottom.
        case vertical
        /// Frames stacked: the join runs from left to right.
        case horizontal

        /// The axis a join should take across a region of this shape — the
        /// join crosses the overlap's *short* way, because the long way is
        /// the direction the frames are offset in.
        public static func across(width: Int, height: Int) -> Axis {
            width <= height ? .vertical : .horizontal
        }
    }

    /// How much a pixel outside the overlap costs to cut through.
    ///
    /// Not infinity, which the arithmetic would rather not carry, and not
    /// zero, which would let the join escape the overlap and run down the
    /// cheap empty space beside it — handing one frame the whole overlap for
    /// no reason. Far above any real difference between two frames of the
    /// same wall, so the join leaves the overlap only when a row gives it no
    /// choice.
    public static let outsideCost: Float = 4

    /// How much the join pays for leaving the middle of the overlap.
    ///
    /// Without this the join is free to wander: across a plain sky two frames
    /// of the same thing differ by nothing anywhere in the overlap, every path
    /// costs zero, and the one that comes back is whichever way the arithmetic
    /// happened to lean. That join can end up against a frame's own edge,
    /// where vignetting and a stop of exposure drift are at their worst, and
    /// it shows as a step. Paying to move keeps the join where the two frames
    /// have the most equal say — the place the plain blend would have put it —
    /// unless something real is in the way.
    ///
    /// Half: a pixel where the frames disagree by a tenth is worth moving
    /// about a fifth of the overlap to avoid, which is the size of a person
    /// and not the size of a sky.
    public static let balance: Float = 0.5

    /// What a pixel costs to cut through: how differently the two frames saw
    /// it, plus what it costs to be there rather than in the middle of the
    /// overlap, and `outsideCost` where there is no overlap at all.
    ///
    /// Difference is measured on luminance rather than per channel: a person
    /// against a wall differs in brightness at every edge of them, and
    /// summing channels only triples the same signal.
    ///
    /// `rampA`/`rampB` are how much say each frame has at that pixel — the
    /// blend's own weighting. Leaving them out drops the second term, which
    /// is what the pure-difference tests want.
    public static func cost(
        a: [Float],
        b: [Float],
        coverageA: [Float],
        coverageB: [Float],
        width: Int,
        height: Int,
        rampA: [Float]? = nil,
        rampB: [Float]? = nil
    ) -> [Float]? {
        let count = width * height
        guard count > 0, a.count >= count, b.count >= count,
              coverageA.count >= count, coverageB.count >= count
        else { return nil }
        if let rampA, let rampB, rampA.count < count || rampB.count < count { return nil }
        var cost = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let shared = min(coverageA[index], coverageB[index])
            guard shared > 0.01 else {
                cost[index] = outsideCost
                continue
            }
            var value = abs(a[index] - b[index])
            if let rampA, let rampB {
                value += balance * abs(rampA[index] - rampB[index])
            }
            cost[index] = value
        }
        return cost
    }

    /// The cheapest path across `cost`, as one column (or row) index per line.
    ///
    /// Dynamic programming, the seam-carving recurrence: the cheapest way to
    /// reach a pixel is its own cost plus the cheapest of the three pixels
    /// behind it. One pass forward to accumulate, one back to read the path
    /// out. Linear in pixels, which is why it can run on a picture this size
    /// at all.
    public static func path(cost: [Float], width: Int, height: Int, axis: Axis) -> [Int]? {
        switch axis {
        case .vertical:
            return path(cost: cost, across: width, along: height) { line, position in
                line * width + position
            }
        case .horizontal:
            return path(cost: cost, across: height, along: width) { line, position in
                position * width + line
            }
        }
    }

    /// `across` is how many choices each step has; `along` is how many steps.
    private static func path(
        cost: [Float],
        across: Int,
        along: Int,
        index: (Int, Int) -> Int
    ) -> [Int]? {
        guard across > 0, along > 0, cost.count >= across * along else { return nil }
        var total = [Float](repeating: 0, count: across * along)
        var came = [Int](repeating: 0, count: across * along)
        for position in 0..<across { total[position] = cost[index(0, position)] }

        for line in 1..<along {
            for position in 0..<across {
                var best = total[(line - 1) * across + position]
                var from = position
                if position > 0, total[(line - 1) * across + position - 1] < best {
                    best = total[(line - 1) * across + position - 1]
                    from = position - 1
                }
                if position + 1 < across, total[(line - 1) * across + position + 1] < best {
                    best = total[(line - 1) * across + position + 1]
                    from = position + 1
                }
                total[line * across + position] = cost[index(line, position)] + best
                came[line * across + position] = from
            }
        }

        var end = 0
        for position in 1..<across where total[(along - 1) * across + position]
            < total[(along - 1) * across + end] {
            end = position
        }
        var seam = [Int](repeating: 0, count: along)
        var position = end
        for line in stride(from: along - 1, through: 0, by: -1) {
            seam[line] = position
            position = came[line * across + position]
        }
        return seam
    }

    /// Who owns each pixel, given the join: true where the first frame does.
    ///
    /// Everything on one side of the join is the first frame's and everything
    /// on the other is the second's, *except* where only one of them has any
    /// picture — a frame cannot own what it never saw.
    public static func ownership(
        seam: [Int],
        coverageA: [Float],
        coverageB: [Float],
        width: Int,
        height: Int,
        axis: Axis
    ) -> [Bool]? {
        let count = width * height
        guard count > 0, coverageA.count >= count, coverageB.count >= count else { return nil }
        switch axis {
        case .vertical: guard seam.count >= height else { return nil }
        case .horizontal: guard seam.count >= width else { return nil }
        }
        var owned = [Bool](repeating: true, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let onFirstSide: Bool = switch axis {
                case .vertical: x <= seam[y]
                case .horizontal: y <= seam[x]
                }
                if coverageA[index] <= 0.01 {
                    owned[index] = false
                } else if coverageB[index] <= 0.01 {
                    owned[index] = true
                } else {
                    owned[index] = onFirstSide
                }
            }
        }
        return owned
    }

    /// The whole answer for one pair, in one call.
    public static func ownership(
        a: [Float],
        b: [Float],
        coverageA: [Float],
        coverageB: [Float],
        width: Int,
        height: Int,
        axis: Axis? = nil,
        rampA: [Float]? = nil,
        rampB: [Float]? = nil
    ) -> [Bool]? {
        let axis = axis ?? Axis.across(width: width, height: height)
        guard let cost = cost(
            a: a, b: b, coverageA: coverageA, coverageB: coverageB,
            width: width, height: height, rampA: rampA, rampB: rampB
        ), let seam = path(cost: cost, width: width, height: height, axis: axis) else { return nil }
        return ownership(
            seam: seam,
            coverageA: coverageA,
            coverageB: coverageB,
            width: width,
            height: height,
            axis: axis
        )
    }
}
