import Testing
@testable import ShotDex

struct PatchMatchInpainterTests {
    @Test func aFlatRegionFillsWithItsOwnColour() {
        let tile = makeTile(width: 64, height: 64) { _, _ in (0.3, 0.6, 0.2) }
        let hole = makeHole(width: 64, height: 64, x: 24, y: 24, holeWidth: 12, holeHeight: 12)
        let filled = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 42)
        #expect(filled != nil)
        guard let filled else { return }

        var largestError: Float = 0
        for index in 0..<(64 * 64) where hole[index] {
            largestError = max(
                largestError,
                abs(filled[index * 3] - 0.3),
                abs(filled[index * 3 + 1] - 0.6),
                abs(filled[index * 3 + 2] - 0.2)
            )
        }
        #expect(largestError < 1.0 / 255.0)
    }

    @Test func pixelsOutsideTheHoleAreLeftAlone() {
        let tile = makeTile(width: 64, height: 64) { x, y in
            (Float(x) / 64, Float(y) / 64, 0.5)
        }
        let hole = makeHole(width: 64, height: 64, x: 20, y: 30, holeWidth: 16, holeHeight: 10)
        guard let filled = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 3) else {
            #expect(Bool(false))
            return
        }
        #expect(filled.count == tile.pixels.count)
        for index in 0..<(64 * 64) where !hole[index] {
            #expect(filled[index * 3] == tile.pixels[index * 3])
            #expect(filled[index * 3 + 1] == tile.pixels[index * 3 + 1])
            #expect(filled[index * 3 + 2] == tile.pixels[index * 3 + 2])
        }
        // And the hole itself did change — a fill that returned the input would
        // pass every other check here.
        var changed = 0
        for index in 0..<(64 * 64) where hole[index] {
            if abs(filled[index * 3] - tile.pixels[index * 3]) > 0.001 { changed += 1 }
        }
        #expect(changed > 0)
    }

    @Test func theSameSeedFillsIdenticallyAndADifferentOneDoesNot() {
        let tile = makeTile(width: 48, height: 48) { x, y in
            (Float((x * y) % 17) / 17, 0.4, 0.7)
        }
        let hole = makeHole(width: 48, height: 48, x: 18, y: 18, holeWidth: 10, holeHeight: 10)
        // Stability matters beyond tidiness: the preview and the exported file are
        // separate renders of the same recipe and must agree pixel for pixel.
        let first = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 42)
        let again = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 42)
        let other = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 43)
        #expect(first == again)
        #expect(first != other)
    }

    @Test func aPeriodicPatternContinuesThroughTheHole() {
        // Vertical stripes of period 8: a fill that just averaged the rim would
        // come out flat grey, so this is the test that the exemplar search works.
        let tile = makeTile(width: 64, height: 64) { x, _ in
            x % 8 < 4 ? (0.9, 0.9, 0.9) : (0.1, 0.1, 0.1)
        }
        let hole = makeHole(width: 64, height: 64, x: 24, y: 24, holeWidth: 12, holeHeight: 12)
        guard let filled = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 7) else {
            #expect(Bool(false))
            return
        }

        var matching = 0
        var total = 0
        for index in 0..<(64 * 64) where hole[index] {
            let expected: Float = (index % 64) % 8 < 4 ? 0.9 : 0.1
            total += 1
            if abs(filled[index * 3] - expected) < 0.15 { matching += 1 }
        }
        #expect(total > 0)
        #expect(Double(matching) / Double(total) > 0.8)
    }

    @Test func degenerateInputFillsNothing() {
        let tile = makeTile(width: 40, height: 40) { _, _ in (0.5, 0.5, 0.5) }

        // Nothing painted.
        #expect(
            PatchMatchInpainter.filled(
                tile: tile,
                hole: [Bool](repeating: false, count: 1_600),
                seed: 1
            ) == nil
        )
        // Painted edge to edge: no clean patch survives anywhere, so leaving the
        // pixels alone beats smearing the tile.
        #expect(
            PatchMatchInpainter.filled(
                tile: tile,
                hole: [Bool](repeating: true, count: 1_600),
                seed: 1
            ) == nil
        )
        // A hole array that does not match the tile.
        #expect(PatchMatchInpainter.filled(tile: tile, hole: [true, false], seed: 1) == nil)
        #expect(
            PatchMatchInpainter.filled(
                tile: PatchMatchInpainter.Tile(width: 0, height: 0, pixels: []),
                hole: [],
                seed: 1
            ) == nil
        )
    }

    @Test func aHoleTouchingTheEdgeStillFills() {
        let tile = makeTile(width: 64, height: 64) { _, y in (Float(y) / 64, 0.3, 0.3) }
        let hole = makeHole(width: 64, height: 64, x: 0, y: 0, holeWidth: 10, holeHeight: 10)
        #expect(PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 11) != nil)
    }

    @Test func everyFilledValueStaysInRange() {
        let tile = makeTile(width: 56, height: 56) { x, y in
            (Float(x % 9) / 9, Float(y % 5) / 5, 0.8)
        }
        let hole = makeHole(width: 56, height: 56, x: 20, y: 20, holeWidth: 14, holeHeight: 14)
        guard let filled = PatchMatchInpainter.filled(tile: tile, hole: hole, seed: 5) else {
            #expect(Bool(false))
            return
        }
        // The renderer packs these straight into 8-bit pixels, so anything outside
        // 0…1 would clip visibly rather than fail loudly.
        #expect(filled.allSatisfy { $0 >= -0.0001 && $0 <= 1.0001 })
    }

    // MARK: Helpers

    private func makeTile(
        width: Int,
        height: Int,
        _ color: (Int, Int) -> (Float, Float, Float)
    ) -> PatchMatchInpainter.Tile {
        var pixels = [Float](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue) = color(x, y)
                let index = (y * width + x) * 3
                pixels[index] = red
                pixels[index + 1] = green
                pixels[index + 2] = blue
            }
        }
        return PatchMatchInpainter.Tile(width: width, height: height, pixels: pixels)
    }

    private func makeHole(
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        holeWidth: Int,
        holeHeight: Int
    ) -> [Bool] {
        var hole = [Bool](repeating: false, count: width * height)
        for row in y..<(y + holeHeight) {
            for column in x..<(x + holeWidth) {
                hole[row * width + column] = true
            }
        }
        return hole
    }
}
