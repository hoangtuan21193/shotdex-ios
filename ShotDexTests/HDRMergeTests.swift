import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-01.11 §4–5 — AC-1…AC-5: the radiance a series merges to, and how the
/// frames are lined up first.
@Suite struct HDRMergeTests {
    static func merged(_ fixture: HDRBracketFixture, _ series: HDRBracketFixture.Series) throws -> [Float] {
        let input = HDRSeries(frames: series.frames.map(fixture.image), stops: series.stops,
                              reference: series.reference, noise: fixture.noise, pixelScale: 1)
        let radiance = try #require(HDRMerge.radiance(input))
        return fixture.pixels(radiance)
    }

    /// AC-1: five RAW frames −4…+4 of a 14-stop scene come back within three
    /// hundredths of a stop of the truth.
    @Test func fiveFramesOfAFourteenStopSceneMergeWithinThreeHundredthsOfAStop() throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-4, -2, 0, 2, 4])
        let radiance = try Self.merged(fixture, series)
        let error = HDRBracketFixture.stopsError(radiance, series.scene)
        print(String(format: "HDR AC-1 radiance error %.4f stop", error))
        #expect(error <= 0.03)
    }

    /// AC-2: three frames ±2 of a 10-stop scene recover what the reference
    /// clipped, and nothing is left clipped.
    @Test func threeFramesRecoverTheReferencesClippedHighlights() throws {
        let fixture = HDRBracketFixture(dynamicRange: 10, highlightStops: 1.5)
        let series = fixture.series(stops: [-2, 0, 2])
        let radiance = try Self.merged(fixture, series)
        let reference = series.frames[1], darkest = series.frames[0]
        let clippedAtZero: (Int) -> Bool = { i in max(reference[i * 3], reference[i * 3 + 1], reference[i * 3 + 2]) >= 0.98 }
        let clippedCount = (0..<(fixture.width * fixture.height)).filter(clippedAtZero).count
        let recovered = HDRBracketFixture.stopsError(radiance, series.scene, where: clippedAtZero)
        let overall = HDRBracketFixture.stopsError(radiance, series.scene)
        print(String(format: "HDR AC-2 %d px clipped at EV 0, error there %.4f, overall %.4f stop",
                     clippedCount, recovered, overall))
        #expect(clippedCount > fixture.width * fixture.height / 50)
        #expect(recovered <= 0.05)
        #expect(overall <= 0.05)
        // The darkest frame holds the whole scene: no pixel falls back to a
        // clipped value.
        let stillClipped = (0..<(fixture.width * fixture.height)).filter { i in
            max(darkest[i * 3], darkest[i * 3 + 1], darkest[i * 3 + 2]) >= 0.98
        }
        #expect(stillClipped.isEmpty)
    }

    /// Where even the darkest frame clips, the merge answers with that
    /// frame's value rather than nothing.
    @Test func whereEveryFrameClipsTheDarkestFrameAnswers() throws {
        let fixture = HDRBracketFixture(dynamicRange: 10, highlightStops: 3)
        let series = fixture.series(stops: [-1, 0, 1])
        let radiance = try Self.merged(fixture, series)
        let darkest = series.frames[0]
        let allClipped = (0..<(fixture.width * fixture.height)).filter { i in
            max(darkest[i * 3], darkest[i * 3 + 1], darkest[i * 3 + 2]) >= 0.98
        }
        #expect(!allClipped.isEmpty)
        for i in allClipped.prefix(200) {
            #expect(abs(radiance[i * 3 + 1] - darkest[i * 3 + 1] * 2) < 0.01)
        }
    }

    // MARK: Alignment (§4)

    /// Mean distance between the found map and the true one over a grid of
    /// frame points, in pixels at 1536 on the long edge.
    static func alignmentError(found: CGAffineTransform, frameMap: CGAffineTransform, referenceMap: CGAffineTransform,
                               fixture: HDRBracketFixture) -> Double {
        let h = Double(fixture.height)
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        let truth = flip.concatenating(frameMap.concatenating(referenceMap.inverted())).concatenating(flip)
        var sum = 0.0, n = 0
        for gy in 1..<8 { for gx in 1..<8 {
            let p = CGPoint(x: Double(fixture.width) * Double(gx) / 8, y: h * Double(gy) / 8)
            let a = p.applying(found), b = p.applying(truth)
            sum += hypot(a.x - b.x, a.y - b.y); n += 1
        } }
        return sum / Double(n) * 1536 / Double(max(fixture.width, fixture.height))
    }

    /// AC-4: five frames three stops apart, each off by up to 30 px and 1.5°
    /// at 1536, line up within half a pixel and none is left out.
    @Test func alignsAcrossThreeStops() async throws {
        let fixture = HDRBracketFixture(width: 960, height: 720)
        let shift = 30.0 * 960 / 1536
        let maps = (0..<5).map { fixture.handheldMap(frame: $0, shift: shift, degrees: 1.5) }
        let series = fixture.series(stops: [-6, -3, 0, 3, 6], maps: maps)
        let prepared = try await PhotoStackRenderer().prepareHDR(
            images: series.frames.map(fixture.image), stops: series.stops, reference: 2, noise: .raw, pixelScale: 1)
        #expect(prepared.excludedFrames.isEmpty)
        #expect(prepared.series.reference == 2)
        for (position, input) in prepared.inputIndices.enumerated() where input != 2 {
            let error = Self.alignmentError(found: prepared.maps[position], frameMap: maps[input],
                                            referenceMap: maps[2], fixture: fixture)
            print(String(format: "HDR AC-4 frame %d (%+.0f EV): %.3f px at 1536", input, series.stops[input], error))
            #expect(error <= 0.5)
        }
    }

    /// AC-5: a frame of another scene in the series is left out, and the rest
    /// still merge on the reference.
    @Test func leavesOutAFrameFromAnotherScene() async throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-4, -2, 0, 2, 4])
        var other = fixture
        other.seed = 4242
        let stray = other.frame(of: other.scene(), stops: 3, seed: 9)
        let images = (series.frames[0...3] + [stray, series.frames[4]]).map(fixture.image)
        let prepared = try await PhotoStackRenderer().prepareHDR(
            images: images, stops: [-4, -2, 0, 2, 3, 4], reference: 2, noise: .raw, pixelScale: 1)
        #expect(prepared.excludedFrames == [4])
        #expect(prepared.inputIndices == [0, 1, 2, 3, 5])
        #expect(prepared.series.stops == [-4, -2, 0, 2, 4])
        let radiance = try #require(HDRMerge.radiance(prepared.series))
        #expect(HDRBracketFixture.stopsError(fixture.pixels(radiance), series.scene) <= 0.03)
    }

    /// AC-3: a shuffled selection, put in order by its EXIF, merges to the
    /// same picture as the series in order.
    @Test func aShuffledSelectionMergesToTheSamePicture() throws {
        let fixture = HDRBracketFixture()
        let stops: [Double] = [-4, -2, 0, 2, 4]
        let series = fixture.series(stops: stops)
        let shuffled = [3, 0, 4, 2, 1]
        let frames = shuffled.map { k in
            HDRBracketOrder.Frame(id: k, shutterSeconds: pow(2, stops[k]) / 125, iso: 100, aperture: 8,
                                  exposureBias: stops[k], isRAW: true)
        }
        let order = HDRBracketOrder.series(frames)
        #expect(order.order == [0, 1, 2, 3, 4])
        let inOrder = try Self.merged(fixture, series)
        let reordered = HDRSeries(frames: order.order.map { fixture.image(series.frames[$0]) }, stops: order.stops,
                                  reference: order.reference, noise: .raw, pixelScale: 1)
        let again = fixture.pixels(try #require(HDRMerge.radiance(reordered)))
        #expect(zip(inOrder, again).allSatisfy { abs($0 - $1) <= 1e-4 * max(1, abs($0)) })
    }
}
