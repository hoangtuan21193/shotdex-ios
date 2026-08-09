import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct VideoGeometryTests {
    private func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(a - b) <= tolerance
    }

    /// The four transforms iPhone footage actually ships with. `naturalSize`
    /// stays landscape for portrait video — only the transform tells the truth.
    private let landscape = CGSize(width: 1920, height: 1080)

    private var portrait90: CGAffineTransform {
        // Typical portrait video: rotate 90° and shift back on-screen.
        CGAffineTransform(rotationAngle: .pi / 2)
            .translatedBy(x: 0, y: -1080)
    }

    @Test func displaySizeIsUnchangedByIdentity() {
        let size = VideoGeometry.displaySize(naturalSize: landscape, preferredTransform: .identity)
        #expect(size == landscape)
    }

    @Test func displaySizeSwapsAxesUnderAQuarterTurn() {
        let size = VideoGeometry.displaySize(naturalSize: landscape, preferredTransform: portrait90)
        #expect(isClose(size.width, 1080))
        #expect(isClose(size.height, 1920))
    }

    @Test func displaySizeSurvivesA180Turn() {
        let flipped = CGAffineTransform(rotationAngle: .pi).translatedBy(x: -1920, y: -1080)
        let size = VideoGeometry.displaySize(naturalSize: landscape, preferredTransform: flipped)
        #expect(isClose(size.width, 1920))
        #expect(isClose(size.height, 1080))
    }

    /// A landscape source into a landscape canvas of the same aspect fills it.
    @Test func fitTransformFillsAMatchingCanvas() {
        let transform = VideoGeometry.fitTransform(
            naturalSize: landscape,
            preferredTransform: .identity,
            quarterTurns: 0,
            renderSize: CGSize(width: 1920, height: 1080)
        )
        let mapped = CGRect(origin: .zero, size: landscape).applying(transform)
        #expect(isClose(mapped.minX, 0))
        #expect(isClose(mapped.minY, 0))
        #expect(isClose(mapped.width, 1920))
        #expect(isClose(mapped.height, 1080))
    }

    /// Portrait footage on a landscape canvas pillarboxes: full height,
    /// centred horizontally — never stretched.
    @Test func portraitSourcePillarboxesOnALandscapeCanvas() {
        let render = CGSize(width: 1920, height: 1080)
        let transform = VideoGeometry.fitTransform(
            naturalSize: landscape,
            preferredTransform: portrait90,
            quarterTurns: 0,
            renderSize: render
        )
        let mapped = CGRect(origin: .zero, size: landscape).applying(transform)
        let expectedWidth = 1080 * (1080.0 / 1920.0)
        #expect(isClose(mapped.height, 1080))
        #expect(isClose(mapped.width, expectedWidth, tolerance: 0.01))
        #expect(isClose(mapped.midX, render.width / 2, tolerance: 0.01))
        #expect(mapped.minY >= -0.001)
    }

    @Test func quarterTurnsComposeOnTopOfOrientation() {
        let render = CGSize(width: 1920, height: 1080)
        // One user turn on an identity-transform landscape source → portrait
        // display, pillarboxed.
        let transform = VideoGeometry.fitTransform(
            naturalSize: landscape,
            preferredTransform: .identity,
            quarterTurns: 1,
            renderSize: render
        )
        let mapped = CGRect(origin: .zero, size: landscape).applying(transform)
        #expect(isClose(mapped.height, 1080))
        #expect(mapped.width < 1080)
        // Four turns are a no-op.
        let fullCircle = VideoGeometry.fitTransform(
            naturalSize: landscape,
            preferredTransform: .identity,
            quarterTurns: 4,
            renderSize: render
        )
        let identityMapped = CGRect(origin: .zero, size: landscape).applying(fullCircle)
        #expect(isClose(identityMapped.width, 1920))
    }

    @Test func degenerateSizesFallBackToIdentity() {
        let transform = VideoGeometry.fitTransform(
            naturalSize: .zero,
            preferredTransform: .identity,
            quarterTurns: 0,
            renderSize: CGSize(width: 1920, height: 1080)
        )
        #expect(transform == .identity)
    }

    @Test func stillFitRectCentersAndFits() {
        let render = CGSize(width: 1920, height: 1080)
        let tall = VideoGeometry.stillFitRect(
            imageSize: CGSize(width: 3000, height: 4000),
            renderSize: render
        )
        #expect(isClose(tall.height, 1080))
        #expect(isClose(tall.midX, 960))
        let wide = VideoGeometry.stillFitRect(
            imageSize: CGSize(width: 8000, height: 1000),
            renderSize: render
        )
        #expect(isClose(wide.width, 1920))
        #expect(isClose(wide.midY, 540))
    }
}
