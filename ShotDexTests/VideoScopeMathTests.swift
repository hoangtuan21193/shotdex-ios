import Testing
@testable import ShotDex

/// The counting behind the scopes.
///
/// A scope is only useful if it is honest about the frame, so these assert
/// the invariants a colourist reads it by: a flat patch lands on one level,
/// black is at the bottom, neutral sits at the centre of the vectorscope,
/// and nothing is lost or invented between the pixels and the grid.
struct VideoScopeMathTests {
    /// A solid patch, in tightly packed RGBA8 — the shape
    /// `CIContext.render(toBitmap:)` returns.
    private func solid(
        r: UInt8, g: UInt8, b: UInt8, width: Int, height: Int
    ) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) { bytes.append(contentsOf: [r, g, b, 255]) }
        return bytes
    }

    // MARK: Luma

    @Test func lumaWeightsSumToOne() {
        #expect(VideoScopeMath.luma(r: 255, g: 255, b: 255) == 255)
        #expect(VideoScopeMath.luma(r: 0, g: 0, b: 0) == 0)
    }

    /// Rec.709 weights green far heavier than blue, which is why a green
    /// frame reads high on a waveform and a blue one reads low.
    @Test func greenCountsForMoreThanBlue() {
        let green = VideoScopeMath.luma(r: 0, g: 255, b: 0)
        let blue = VideoScopeMath.luma(r: 0, g: 0, b: 255)
        let red = VideoScopeMath.luma(r: 255, g: 0, b: 0)
        #expect(green > red)
        #expect(red > blue)
    }

    // MARK: Waveform

    @Test func aFlatPatchLandsOnOneLevel() {
        let width = 32, height = 16, columns = 8, levels = 64
        let grid = VideoScopeMath.waveform(
            rgba: solid(r: 128, g: 128, b: 128, width: width, height: height),
            width: width, height: height,
            columns: columns, levels: levels, channel: .luma
        )
        #expect(grid.count == columns * levels)
        let occupied = (0..<levels).filter { level in
            (0..<columns).contains { grid[level * columns + $0] > 0 }
        }
        #expect(occupied.count == 1)
        // 128 of 256, over 64 levels, is level 32 — the middle of the trace.
        #expect(occupied.first == 32)
    }

    @Test func blackSitsAtTheBottomOfTheGrid() {
        let width = 16, height = 8, columns = 4, levels = 32
        let grid = VideoScopeMath.waveform(
            rgba: solid(r: 0, g: 0, b: 0, width: width, height: height),
            width: width, height: height,
            columns: columns, levels: levels, channel: .luma
        )
        #expect(grid[0..<columns].allSatisfy { $0 > 0 })
        #expect(grid[columns...].allSatisfy { $0 == 0 })
    }

    @Test func everyPixelIsCountedExactlyOnce() {
        let width = 30, height = 12, columns = 10, levels = 16
        let grid = VideoScopeMath.waveform(
            rgba: solid(r: 90, g: 180, b: 30, width: width, height: height),
            width: width, height: height,
            columns: columns, levels: levels, channel: .green
        )
        #expect(grid.reduce(0, +) == width * height)
    }

    /// The parade reads each channel separately — the whole point of it.
    @Test func channelsAreMeasuredIndependently() {
        let width = 8, height = 8
        let bytes = solid(r: 240, g: 20, b: 20, width: width, height: height)
        func level(_ channel: VideoScopeMath.Channel) -> Int? {
            let grid = VideoScopeMath.waveform(
                rgba: bytes, width: width, height: height,
                columns: 1, levels: 16, channel: channel
            )
            return grid.firstIndex { $0 > 0 }
        }
        #expect(level(.red) == 15)
        #expect(level(.green) == 1)
        #expect(level(.blue) == 1)
    }

    @Test func aMalformedBufferCountsNothing() {
        #expect(VideoScopeMath.waveform(
            rgba: [0, 0, 0, 255], width: 64, height: 64,
            columns: 4, levels: 4, channel: .luma
        ).isEmpty)
    }

    // MARK: Vectorscope

    /// Grey has no chroma, so every sample of a neutral frame must land in
    /// the middle. If this drifts the whole scope is lying about casts.
    @Test func neutralSitsAtTheCentre() {
        let size = 32
        let width = 10, height = 10
        for value: UInt8 in [0, 64, 128, 200, 255] {
            let grid = VideoScopeMath.vectorscope(
                rgba: solid(r: value, g: value, b: value, width: width, height: height),
                width: width, height: height, size: size
            )
            #expect(grid[(size / 2) * size + (size / 2)] == width * height)
        }
    }

    /// Red is to the right of neutral, blue below it — the orientation the
    /// graticule is drawn for.
    @Test func redAndBlueLandOnOppositeSidesOfNeutral() {
        let size = 64
        func centroid(r: UInt8, g: UInt8, b: UInt8) -> (x: Int, y: Int)? {
            let grid = VideoScopeMath.vectorscope(
                rgba: solid(r: r, g: g, b: b, width: 8, height: 8),
                width: 8, height: 8, size: size
            )
            guard let index = grid.firstIndex(where: { $0 > 0 }) else { return nil }
            return (index % size, index / size)
        }
        let red = centroid(r: 255, g: 0, b: 0)
        let blue = centroid(r: 0, g: 0, b: 255)
        #expect(red != nil)
        #expect(blue != nil)
        #expect((red?.x ?? 0) > size / 2)
        #expect((blue?.y ?? 0) > size / 2)
    }

    // MARK: Histogram

    @Test func everyChannelCountsTheWholeFrame() {
        let width = 12, height = 5, buckets = 32
        let counts = VideoScopeMath.histogram(
            rgba: solid(r: 10, g: 128, b: 250, width: width, height: height),
            width: width, height: height, buckets: buckets
        )
        for channel in [counts.red, counts.green, counts.blue, counts.luma] {
            #expect(channel.count == buckets)
            #expect(channel.reduce(0, +) == width * height)
        }
        #expect(counts.red.firstIndex { $0 > 0 } == 1)
        #expect(counts.blue.firstIndex { $0 > 0 } == 31)
    }

    // MARK: Trace brightness

    /// Full brightness has to be reachable by ordinary detail, not only by a
    /// column that is entirely one value — otherwise every scope is black.
    @Test func theTraceCeilingIsBelowAFullColumn() {
        #expect(VideoScopeMath.traceCeiling(sampleHeight: 135) < 135)
        #expect(VideoScopeMath.traceCeiling(sampleHeight: 135) > 0)
        #expect(VideoScopeMath.traceCeiling(sampleHeight: 0) == 1)
    }
}
