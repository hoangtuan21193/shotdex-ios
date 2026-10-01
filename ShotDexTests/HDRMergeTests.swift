import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.11 §5 — AC-1, AC-2: the radiance a series merges to.
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
}
