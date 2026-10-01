import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.11 §5 — AC-6, AC-7, AC-8: deghosting against the per-pixel anchor.
@Suite struct HDRDeghostTests {
    static let stops: [Double] = [-4, -2, 0, 2, 4]

    static func radiance(_ fixture: HDRBracketFixture, _ series: HDRBracketFixture.Series,
                         _ deghost: HDRDeghost) throws -> [Float] {
        let input = HDRSeries(frames: series.frames.map(fixture.image), stops: series.stops,
                              reference: series.reference, noise: fixture.noise, pixelScale: 1)
        return fixture.pixels(try #require(HDRMerge.radiance(input, deghost: deghost)))
    }

    /// AC-6: a textured patch swaying 3 px a frame (at 1536), where the
    /// reference reads it. Off ghosts it; Low catches most; Medium and High
    /// catch it.
    @Test func aSwayingPatchIsCaughtFromMediumUp() throws {
        let fixture = HDRBracketFixture()
        let scale = Double(fixture.width) / 1536
        let size = Int((160 * scale).rounded())
        let patch = fixture.texture(size: size, cell: 3, levels: -5 ... -0.5, seed: 11)
        let base = fixture.scene()
        let origin = CGPoint(x: 200, y: 230)
        let series = fixture.series(stops: Self.stops, truth: 2) { k in
            fixture.pasting(patch, size: size, into: base,
                            at: CGPoint(x: origin.x + 3 * scale * Double(k - 2), y: origin.y))
        }
        let moving = CGRect(x: origin.x, y: origin.y, width: Double(size), height: Double(size)).insetBy(dx: 2, dy: 2)
        let inside: (Int) -> Bool = { i in moving.contains(CGPoint(x: i % fixture.width, y: i / fixture.width)) }
        var errors: [HDRDeghost: Double] = [:]
        for level in HDRDeghost.allCases {
            errors[level] = HDRBracketFixture.stopsError(try Self.radiance(fixture, series, level), series.scene, where: inside)
            print(String(format: "HDR AC-6 %@: %.3f stop in the moving patch", level.rawValue, errors[level]!))
        }
        #expect(errors[.off]! >= 0.5)
        #expect(errors[.low]! <= 0.25)
        #expect(errors[.medium]! <= 0.1)
        #expect(errors[.high]! <= 0.1)
    }

    /// AC-7: in a series where nothing moves, Medium leaves out at most half
    /// a percent of pixels and High at most three.
    @Test func aStillSeriesKeepsAlmostEveryPixel() throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: Self.stops)
        let input = HDRSeries(frames: series.frames.map(fixture.image), stops: series.stops,
                              reference: series.reference, noise: fixture.noise, pixelScale: 1)
        let extent = input.frames[0].extent
        let anchor = try #require(HDRMerge.anchor(input, extent: extent))
        for (level, limit) in [(HDRDeghost.medium, 0.005), (.high, 0.03)] {
            let keeps = try #require(HDRMerge.keepMasks(input, deghost: level, anchor: anchor, extent: extent))
            let masks = keeps.map(fixture.pixels)
            let count = fixture.width * fixture.height
            let dropped = (0..<count).filter { i in masks.contains { $0[i * 3] < 0.5 } }.count
            let fraction = Double(dropped) / Double(count)
            print(String(format: "HDR AC-7 %@: %.2f%% of still pixels left out", level.rawValue, fraction * 100))
            #expect(fraction <= limit)
        }
    }

    /// AC-8: something moving 70 px a frame (at 1536) through sky the
    /// reference clips comes out once — as the anchor saw it — not as a
    /// trail of copies.
    @Test func somethingMovingThroughClippedSkyComesOutOnce() throws {
        let fixture = HDRBracketFixture()
        let scale = Double(fixture.width) / 1536
        let sky = CGRect(x: 20, y: 10, width: 440, height: 110)
        let base = fixture.filling(fixture.scene(), rect: sky, level: 1.6)   // clipped at EV 0, read at −2
        let step = 70 * scale, radius = 30 * scale
        let centre = { (k: Int) in CGPoint(x: 240 + step * Double(k - 2), y: 65) }
        // The −2 frame reads the whole sky, so it is the anchor there.
        let series = fixture.series(stops: Self.stops, truth: 1) { k in
            fixture.disc(base, centre: centre(k), radius: radius, level: 0.6)
        }
        let trail: (Int) -> Bool = { i in
            let p = CGPoint(x: Double(i % fixture.width) + 0.5, y: Double(i / fixture.width) + 0.5)
            return (0..<5).contains { hypot(p.x - centre($0).x, p.y - centre($0).y) <= radius + 2 }
        }
        let off = HDRBracketFixture.stopsError(try Self.radiance(fixture, series, .off), series.scene, where: trail)
        let medium = HDRBracketFixture.stopsError(try Self.radiance(fixture, series, .medium), series.scene, where: trail)
        print(String(format: "HDR AC-8 along the trail: off %.3f, medium %.3f stop", off, medium))
        // Off blends the −4 frame's copy in at a fifth of the weight — a faint
        // ghost, but a ghost.
        #expect(off >= 0.08)
        #expect(medium <= 0.1)
    }
}
