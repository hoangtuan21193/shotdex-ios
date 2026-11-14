import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// The Mac crop frame (FS-18.03 §1b): handles, locked ratios, the frame kept
/// on a straightened photo, turns and mirrors, the size line.
struct CropFrameEditingTests {
    private let level = CropFrameEditing(photoSize: CGSize(width: 6000, height: 4000), degrees: 0)

    @Test func aCornerKeepsTheOppositeCorner() {
        let start = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let rect = level.dragged(start, handle: .corner(right: true, bottom: true), dx: -0.2, dy: -0.1, ratio: nil)
        #expect(abs(rect.x - 0.1) < 1e-9 && abs(rect.y - 0.1) < 1e-9)
        #expect(abs(rect.width - 0.6) < 1e-9 && abs(rect.height - 0.7) < 1e-9)
    }

    @Test func aLockedCornerHoldsThePixelRatio() {
        let start = NormalizedRect.full
        let rect = level.dragged(start, handle: .corner(right: false, bottom: false), dx: 0.3, dy: 0.05, ratio: 1)
        let pixelRatio = rect.width * 6000 / (rect.height * 4000)
        #expect(abs(pixelRatio - 1) < 1e-6)
        // The bottom-right corner stays put.
        #expect(abs(rect.x + rect.width - 1) < 1e-9 && abs(rect.y + rect.height - 1) < 1e-9)
    }

    @Test func aLockedEdgeFollowsOnTheOtherAxis() {
        let start = NormalizedRect.full
        let rect = level.dragged(start, handle: .edge(.right), dx: -0.5, dy: 0, ratio: 1.5)
        #expect(abs(rect.width - 0.5) < 1e-9)
        #expect(abs(rect.width * 6000 / (rect.height * 4000) - 1.5) < 1e-6)
    }

    @Test func movingStopsAtTheEdge() {
        let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let rect = level.dragged(start, handle: .move, dx: 0.6, dy: -0.6, ratio: nil)
        #expect(abs(rect.x - 0.5) < 1e-9 && abs(rect.y) < 1e-9)
    }

    @Test func aStraightenedPhotoLeavesItsCornersOffTheFrame() {
        let tilted = CropFrameEditing(photoSize: CGSize(width: 6000, height: 4000), degrees: 5)
        #expect(!tilted.isOnPhoto(.full))
        let fitted = tilted.fitted(.full)
        #expect(tilted.isOnPhoto(fitted))
        // Centred, and not shrunk to nothing.
        #expect(abs(fitted.x + fitted.width / 2 - 0.5) < 1e-6)
        #expect(fitted.width > 0.7)
    }

    @Test func aDragOutwardStopsWhereThePhotoEnds() {
        let tilted = CropFrameEditing(photoSize: CGSize(width: 6000, height: 4000), degrees: 8)
        let start = tilted.fitted(NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        let rect = tilted.dragged(start, handle: .corner(right: true, bottom: true), dx: 0.6, dy: 0.6, ratio: nil)
        #expect(tilted.isOnPhoto(rect))
        #expect(rect.width > start.width)
    }

    @Test func quarterTurnsComeBackRound() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        var turned = rect
        for _ in 0..<4 { turned = CropFrameEditing.turned(turned, clockwise: true) }
        #expect(abs(turned.x - rect.x) < 1e-9 && abs(turned.y - rect.y) < 1e-9)
        let back = CropFrameEditing.turned(CropFrameEditing.turned(rect, clockwise: true), clockwise: false)
        #expect(abs(back.x - rect.x) < 1e-9 && abs(back.width - rect.width) < 1e-9)
    }

    @Test func theSizeLineCountsPixels() {
        let size = level.pixelSize(of: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(size.width == 3000 && size.height == 4000 && size.percent == 50)
    }

    @Test func swappedAspectsPairUp() {
        for aspect in CropAspect.allCases {
            guard let swapped = aspect.swapped else { continue }
            #expect(swapped.swapped == aspect)
            #expect(abs((aspect.ratio ?? 0) * (swapped.ratio ?? 0) - 1) < 1e-9)
        }
        #expect(CropFrameEditing.preset(matching: 6000.0 / 4000) == .threeTwo)
    }
}
