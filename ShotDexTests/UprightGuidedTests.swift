import CoreGraphics
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15b AC-24 — Upright Guided.
struct UprightGuidedTests {

    private static let aspect = 1.5
    private static var extent: CGRect { CGRect(x: 0, y: 0, width: aspect * 1000, height: 1000) }

    private static func degreesOffVertical(_ guide: PhotoUprightGuide, _ transform: PhotoUprightTransform) -> Double {
        let map = GeoForwardMap(adjustments: .zero, upright: transform, extent: extent)
        func point(_ p: NormalizedPoint) -> CGPoint {
            map.apply(CGPoint(x: p.x * extent.width, y: (1 - p.y) * extent.height))
        }
        let a = point(guide.start), b = point(guide.end)
        let angle = atan2(Double(b.x - a.x), Double(b.y - a.y))
        var degrees = angle * 180 / .pi
        if degrees > 90 { degrees -= 180 }
        if degrees < -90 { degrees += 180 }
        return degrees
    }

    /// Two edges of a building shot from below, tops leaning in.
    private static let leftEdge = PhotoUprightGuide(
        start: NormalizedPoint(x: 0.22, y: 0.9), end: NormalizedPoint(x: 0.3, y: 0.1)
    )
    private static let rightEdge = PhotoUprightGuide(
        start: NormalizedPoint(x: 0.8, y: 0.9), end: NormalizedPoint(x: 0.71, y: 0.1)
    )

    /// AC-24. Two guides along the two leaning edges: both end up vertical to
    /// within 0.5°.
    @Test func twoGuidesMakeBothVertical() {
        let transform = UprightGuidedSolver.solve([Self.leftEdge, Self.rightEdge], aspect: Self.aspect)
        #expect(transform.vertical != 0, "the convergence needs the keystone")
        for guide in [Self.leftEdge, Self.rightEdge] {
            let off = Self.degreesOffVertical(guide, transform)
            #expect(abs(off) <= 0.5, "guide left \(off)° off vertical")
        }
    }

    /// One guide can only say which way is up: it rotates and nothing else.
    @Test func oneGuideOnlyRotates() {
        let transform = UprightGuidedSolver.solve([Self.leftEdge], aspect: Self.aspect)
        #expect(transform.vertical == 0 && transform.horizontal == 0)
        #expect(abs(Self.degreesOffVertical(Self.leftEdge, transform)) <= 0.5)
    }

    /// The editor side of AC-24: four guides is the limit and the fifth is
    /// refused with the rule said; each guide is one undo step.
    @MainActor @Test func aFifthGuideIsRefusedAndEachGuideIsOneUndo() {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.enterUprightGuided()
        #expect(controller.recipe.upright.mode == .guided)
        for index in 0..<4 {
            let x = 0.2 + Double(index) * 0.15
            #expect(controller.addUprightGuide(
                from: NormalizedPoint(x: x, y: 0.9),
                to: NormalizedPoint(x: x + 0.02, y: 0.1)
            ))
        }
        #expect(!controller.addUprightGuide(
            from: NormalizedPoint(x: 0.5, y: 0.8),
            to: NormalizedPoint(x: 0.52, y: 0.2)
        ))
        #expect(controller.recipe.upright.guides.count == 4)
        #expect(controller.uprightGuideNotice == "Up to 4 guides")

        controller.undo()
        #expect(controller.recipe.upright.guides.count == 3, "one undo takes off one guide")
        #expect(controller.uprightGuideNotice == nil, "the refusal note goes with the next step")
        #expect(!controller.recipe.upright.solved.isIdentity)
    }
}
