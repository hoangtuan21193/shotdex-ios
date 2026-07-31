import Foundation

/// Exemplar-based inpainting over a small tile, in pure Swift so the maths can
/// be tested without a GPU — the same reason `ColorRenderMath` exists.
///
/// The usual coarse-to-fine PatchMatch/EM loop (Barnes et al.): improve the
/// nearest-neighbour field, vote the hole colours back from it, repeat, then
/// carry the field to the next finer level. What comes out is the voted tile —
/// each hole pixel the weighted mean of every patch covering it.
///
/// An earlier version returned the offset field instead and had the renderer
/// gather through it on the GPU, so a removal would follow later tone changes for
/// free. That kernel sampled outside its region of interest on device and filled
/// the stroke with transparent black, and the machinery it needed — a float
/// offset image, a general `CIKernel`, an ROI callback — was the least
/// verifiable part of the whole feature. Pixels plus the low-frequency tone match
/// at composite time get the same result out of primitives the codebase already
/// leans on everywhere else.
enum PatchMatchInpainter {
    struct Tile: Sendable {
        var width: Int
        var height: Int
        /// RGB interleaved, three floats per pixel, nominally 0…1.
        var pixels: [Float]

        init(width: Int, height: Int, pixels: [Float]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }
    }

    struct Parameters: Sendable {
        /// Odd, so a patch has a centre pixel.
        var patchSize = 7
        var levels = 5
        /// EM sweeps per pyramid level.
        var iterations = 4

        init(patchSize: Int = 7, levels: Int = 5, iterations: Int = 4) {
            self.patchSize = patchSize
            self.levels = levels
            self.iterations = iterations
        }
    }

    /// The tile with its hole filled, RGB interleaved like the input. Returns nil
    /// when there is nothing to fill or nowhere valid to read from — the caller
    /// then leaves the pixels alone, which beats smearing them.
    static func filled(
        tile: Tile,
        hole: [Bool],
        parameters: Parameters = Parameters(),
        seed: UInt64
    ) -> [Float]? {
        let count = tile.width * tile.height
        guard tile.width > 0, tile.height > 0,
              tile.pixels.count >= count * 3,
              hole.count == count,
              hole.contains(true)
        else { return nil }

        let patch = max(3, parameters.patchSize | 1)
        var pyramid = makePyramid(
            tile: tile,
            hole: hole,
            patch: patch,
            levels: max(1, parameters.levels)
        )
        // A hole that leaves no complete clean patch anywhere has no exemplar to
        // copy.
        guard pyramid.allSatisfy({ $0.validCenters.contains(true) }) else { return nil }

        var random = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15)
        var field: [Int32] = []

        for index in stride(from: pyramid.count - 1, through: 0, by: -1) {
            var level = pyramid[index]
            if field.isEmpty {
                onionPeelFill(&level)
                field = randomField(level: level, random: &random)
            } else {
                field = upsampleField(field, from: pyramid[index + 1], to: level)
            }
            vote(level: &level, field: field, patch: patch)
            for iteration in 0..<max(1, parameters.iterations) {
                propagate(
                    level: level,
                    field: &field,
                    patch: patch,
                    reversed: iteration % 2 == 1,
                    random: &random
                )
                vote(level: &level, field: field, patch: patch)
            }
            pyramid[index] = level
        }

        // The finest level's voted colours *are* the answer: every hole pixel is
        // the weighted mean of the patches covering it, which is smoother than
        // the single best patch each pixel points at.
        return pyramid[0].pixels
    }

    // MARK: - Level

    /// One pyramid step. `pixels` is mutable: the EM loop writes voted colours
    /// into the hole so the next nearest-neighbour search has something to match
    /// against.
    private struct Level {
        var width: Int
        var height: Int
        var pixels: [Float]
        var hole: [Bool]
        /// A patch centred here is fully inside the tile and free of hole
        /// pixels, i.e. it is a legal exemplar.
        var validCenters: [Bool]
        var holeIndices: [Int]
    }

    private static func makePyramid(
        tile: Tile,
        hole: [Bool],
        patch: Int,
        levels: Int
    ) -> [Level] {
        var result = [makeLevel(width: tile.width, height: tile.height, pixels: tile.pixels, hole: hole, patch: patch)]
        let minimumEdge = patch * 2 + 1
        while result.count < levels {
            guard let finer = result.last,
                  finer.width / 2 >= minimumEdge,
                  finer.height / 2 >= minimumEdge
            else { break }
            result.append(downsample(finer, patch: patch))
        }
        return result
    }

    private static func makeLevel(
        width: Int,
        height: Int,
        pixels: [Float],
        hole: [Bool],
        patch: Int
    ) -> Level {
        let radius = patch / 2
        let count = width * height
        var validCenters = [Bool](repeating: false, count: count)
        var holeIndices: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if hole[index] { holeIndices.append(index) }
                guard x >= radius, y >= radius,
                      x + radius < width, y + radius < height
                else { continue }
                var clean = true
                var row = y - radius
                while row <= y + radius, clean {
                    var column = x - radius
                    while column <= x + radius {
                        if hole[row * width + column] {
                            clean = false
                            break
                        }
                        column += 1
                    }
                    row += 1
                }
                validCenters[index] = clean
            }
        }
        return Level(
            width: width,
            height: height,
            pixels: pixels,
            hole: hole,
            validCenters: validCenters,
            holeIndices: holeIndices
        )
    }

    /// Box-filtered half-size copy. A coarse pixel counts as hole when *any* of
    /// its children does, so a coarse exemplar never smuggles in unknown pixels.
    private static func downsample(_ level: Level, patch: Int) -> Level {
        let width = level.width / 2
        let height = level.height / 2
        var pixels = [Float](repeating: 0, count: width * height * 3)
        var hole = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let target = y * width + x
                var sum = SIMD3<Float>.zero
                var isHole = false
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let source = (y * 2 + dy) * level.width + (x * 2 + dx)
                        sum += SIMD3(
                            level.pixels[source * 3],
                            level.pixels[source * 3 + 1],
                            level.pixels[source * 3 + 2]
                        )
                        if level.hole[source] { isHole = true }
                    }
                }
                sum /= 4
                pixels[target * 3] = sum.x
                pixels[target * 3 + 1] = sum.y
                pixels[target * 3 + 2] = sum.z
                hole[target] = isHole
            }
        }
        return makeLevel(width: width, height: height, pixels: pixels, hole: hole, patch: patch)
    }

    // MARK: - Initialization

    /// Seeds the hole from its rim inwards, one ring per pass, so the coarsest
    /// level starts from something locally plausible instead of one flat mean.
    private static func onionPeelFill(_ level: inout Level) {
        var remaining = Set(level.holeIndices)
        guard !remaining.isEmpty else { return }
        var known = level.hole.map { !$0 }
        while !remaining.isEmpty {
            var filled: [Int] = []
            for index in remaining.sorted() {
                let x = index % level.width
                let y = index / level.width
                var sum = SIMD3<Float>.zero
                var weight: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, ny >= 0, nx < level.width, ny < level.height else { continue }
                        let neighbor = ny * level.width + nx
                        guard known[neighbor] else { continue }
                        sum += SIMD3(
                            level.pixels[neighbor * 3],
                            level.pixels[neighbor * 3 + 1],
                            level.pixels[neighbor * 3 + 2]
                        )
                        weight += 1
                    }
                }
                guard weight > 0 else { continue }
                sum /= weight
                level.pixels[index * 3] = sum.x
                level.pixels[index * 3 + 1] = sum.y
                level.pixels[index * 3 + 2] = sum.z
                filled.append(index)
            }
            // An isolated hole with no known neighbour at all: stop rather than
            // spin forever.
            guard !filled.isEmpty else { break }
            for index in filled {
                known[index] = true
                remaining.remove(index)
            }
        }
    }

    private static func randomField(level: Level, random: inout SplitMix64) -> [Int32] {
        var field = [Int32](repeating: 0, count: level.width * level.height)
        let candidates = (0..<level.validCenters.count).filter { level.validCenters[$0] }
        guard !candidates.isEmpty else { return field }
        for index in 0..<field.count {
            field[index] = Int32(index)
            guard level.hole[index] else { continue }
            field[index] = Int32(candidates[random.index(below: candidates.count)])
        }
        return field
    }

    /// Carries a solved field to the next finer level: the same source region,
    /// at twice the coordinates.
    private static func upsampleField(
        _ field: [Int32],
        from coarse: Level,
        to fine: Level
    ) -> [Int32] {
        var result = [Int32](repeating: 0, count: fine.width * fine.height)
        for y in 0..<fine.height {
            for x in 0..<fine.width {
                let index = y * fine.width + x
                result[index] = Int32(index)
                guard fine.hole[index] else { continue }
                let coarseX = min(coarse.width - 1, x / 2)
                let coarseY = min(coarse.height - 1, y / 2)
                let source = Int(field[coarseY * coarse.width + coarseX])
                let dx = (source % coarse.width - coarseX) * 2
                let dy = (source / coarse.width - coarseY) * 2
                var candidate = (y + dy) * fine.width + (x + dx)
                if !isValid(candidate, in: fine) {
                    candidate = nearestValid(to: index, in: fine) ?? index
                }
                result[index] = Int32(candidate)
            }
        }
        return result
    }

    private static func isValid(_ index: Int, in level: Level) -> Bool {
        index >= 0 && index < level.validCenters.count && level.validCenters[index]
    }

    /// Spiral outwards for a legal exemplar. Only used to repair an upsampled
    /// offset that landed on contaminated pixels, so the search stays short.
    private static func nearestValid(to index: Int, in level: Level) -> Int? {
        let x = index % level.width
        let y = index / level.width
        var radius = 1
        let limit = max(level.width, level.height)
        while radius < limit {
            for dy in -radius...radius {
                for dx in -radius...radius where abs(dx) == radius || abs(dy) == radius {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, ny >= 0, nx < level.width, ny < level.height else { continue }
                    let candidate = ny * level.width + nx
                    if level.validCenters[candidate] { return candidate }
                }
            }
            radius += 1
        }
        return nil
    }

    // MARK: - PatchMatch

    private static func propagate(
        level: Level,
        field: inout [Int32],
        patch: Int,
        reversed: Bool,
        random: inout SplitMix64
    ) {
        let order = reversed ? level.holeIndices.reversed().map { $0 } : level.holeIndices
        let step = reversed ? 1 : -1
        let searchLimit = max(level.width, level.height)
        for index in order {
            let x = index % level.width
            let y = index / level.width
            var best = Int(field[index])
            var bestCost = patchCost(
                level: level,
                targetX: x,
                targetY: y,
                sourceIndex: best,
                patch: patch,
                ceiling: .greatestFiniteMagnitude
            )

            // Propagation: a good source for the neighbour, shifted by the same
            // step, is usually a good source here.
            for (dx, dy) in [(step, 0), (0, step)] {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, ny >= 0, nx < level.width, ny < level.height else { continue }
                let neighbor = Int(field[ny * level.width + nx])
                let candidate = (neighbor / level.width - dy) * level.width
                    + (neighbor % level.width - dx)
                guard isValid(candidate, in: level) else { continue }
                let cost = patchCost(
                    level: level,
                    targetX: x,
                    targetY: y,
                    sourceIndex: candidate,
                    patch: patch,
                    ceiling: bestCost
                )
                if cost < bestCost {
                    bestCost = cost
                    best = candidate
                }
            }

            // Random search, halving the radius each try.
            var radius = searchLimit
            while radius >= 1 {
                let cx = best % level.width
                let cy = best / level.width
                let nx = cx + random.index(below: radius * 2 + 1) - radius
                let ny = cy + random.index(below: radius * 2 + 1) - radius
                radius /= 2
                guard nx >= 0, ny >= 0, nx < level.width, ny < level.height else { continue }
                let candidate = ny * level.width + nx
                guard isValid(candidate, in: level) else { continue }
                let cost = patchCost(
                    level: level,
                    targetX: x,
                    targetY: y,
                    sourceIndex: candidate,
                    patch: patch,
                    ceiling: bestCost
                )
                if cost < bestCost {
                    bestCost = cost
                    best = candidate
                }
            }
            field[index] = Int32(best)
        }
    }

    /// Sum of squared RGB differences over the patch, abandoned as soon as it
    /// passes `ceiling` — most candidates are rejected in the first few pixels.
    private static func patchCost(
        level: Level,
        targetX: Int,
        targetY: Int,
        sourceIndex: Int,
        patch: Int,
        ceiling: Float
    ) -> Float {
        guard isValid(sourceIndex, in: level) else { return .greatestFiniteMagnitude }
        let radius = patch / 2
        let sourceX = sourceIndex % level.width
        let sourceY = sourceIndex / level.width
        var total: Float = 0
        for dy in -radius...radius {
            let ty = targetY + dy
            let sy = sourceY + dy
            guard ty >= 0, ty < level.height else { continue }
            for dx in -radius...radius {
                let tx = targetX + dx
                let sx = sourceX + dx
                guard tx >= 0, tx < level.width else { continue }
                let target = (ty * level.width + tx) * 3
                let source = (sy * level.width + sx) * 3
                let dr = level.pixels[target] - level.pixels[source]
                let dg = level.pixels[target + 1] - level.pixels[source + 1]
                let db = level.pixels[target + 2] - level.pixels[source + 2]
                total += dr * dr + dg * dg + db * db
                if total >= ceiling { return total }
            }
        }
        return total
    }

    /// Writes hole colours back as the mean of every patch that covers them.
    /// Only the search uses these colours; the returned field is single-source.
    private static func vote(level: inout Level, field: [Int32], patch: Int) {
        guard !level.holeIndices.isEmpty else { return }
        let radius = patch / 2
        let count = level.width * level.height
        var sums = [Float](repeating: 0, count: count * 3)
        var weights = [Float](repeating: 0, count: count)
        for center in level.holeIndices {
            let cx = center % level.width
            let cy = center / level.width
            let source = Int(field[center])
            let sx = source % level.width
            let sy = source / level.width
            for dy in -radius...radius {
                let ty = cy + dy
                let syy = sy + dy
                guard ty >= 0, ty < level.height, syy >= 0, syy < level.height else { continue }
                for dx in -radius...radius {
                    let tx = cx + dx
                    let sxx = sx + dx
                    guard tx >= 0, tx < level.width, sxx >= 0, sxx < level.width else { continue }
                    let target = ty * level.width + tx
                    guard level.hole[target] else { continue }
                    let read = (syy * level.width + sxx) * 3
                    sums[target * 3] += level.pixels[read]
                    sums[target * 3 + 1] += level.pixels[read + 1]
                    sums[target * 3 + 2] += level.pixels[read + 2]
                    weights[target] += 1
                }
            }
        }
        for index in level.holeIndices where weights[index] > 0 {
            let weight = weights[index]
            level.pixels[index * 3] = sums[index * 3] / weight
            level.pixels[index * 3 + 1] = sums[index * 3 + 1] / weight
            level.pixels[index * 3 + 2] = sums[index * 3 + 2] / weight
        }
    }

    // MARK: - Deterministic randomness

    /// Seeded on purpose: the same recipe has to fill identically in the 1024pt
    /// preview and in the full-resolution export.
    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func index(below limit: Int) -> Int {
            guard limit > 0 else { return 0 }
            return Int(next() % UInt64(limit))
        }
    }
}
