import Foundation
import Testing
@testable import ShotDex

struct CropFrameGeometryTests {
    /// The bug the equal-area rule exists for: chips used to inscribe the new ratio
    /// inside the old frame, so a few taps back and forth shrank the crop to a stamp.
    @Test func alternatingPresetsDoNotShrinkTheFrame() {
        let imageAspect = 3.0 / 2
        var rect = NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let startArea = rect.width * rect.height

        for _ in 0..<10 {
            rect = CropFrameGeometry.rect(
                matchingRatio: 1,
                keepingAreaOf: rect,
                imageAspect: imageAspect
            )
            rect = CropFrameGeometry.rect(
                matchingRatio: 4.0 / 3,
                keepingAreaOf: rect,
                imageAspect: imageAspect
            )
        }

        #expect(abs(rect.width * rect.height - startArea) < 0.0001)
    }

    @Test func aRatioTooTallForTheImageIsClampedOnceThenStable() {
        let imageAspect = 3.0 / 2
        let first = CropFrameGeometry.rect(
            matchingRatio: 9.0 / 16,
            keepingAreaOf: .full,
            imageAspect: imageAspect
        )
        // 9:16 on a 3:2 photo can only use the full height, so the area has to drop.
        #expect(first.height == 1)
        #expect(first.width < 1)
        #expect(first.width * first.height < 1)

        let second = CropFrameGeometry.rect(
            matchingRatio: 9.0 / 16,
            keepingAreaOf: first,
            imageAspect: imageAspect
        )
        #expect(abs(second.width - first.width) < 0.0001)
        #expect(abs(second.height - first.height) < 0.0001)
    }

    @Test func theRequestedRatioIsWhatComesOutInImageSpace() {
        let imageAspect = 3.0 / 2
        let rect = CropFrameGeometry.rect(
            matchingRatio: 16.0 / 9,
            keepingAreaOf: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
            imageAspect: imageAspect
        )
        let displayedRatio = (rect.width * imageAspect) / rect.height
        #expect(abs(displayedRatio - 16.0 / 9) < 0.0001)
    }

    @Test func theFrameKeepsItsCentreAndStaysInsideTheImage() {
        let rect = CropFrameGeometry.rect(
            matchingRatio: 1,
            keepingAreaOf: NormalizedRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4),
            imageAspect: 1
        )
        #expect(abs(rect.x + rect.width / 2 - 0.7) < 0.0001)
        #expect(abs(rect.y + rect.height / 2 - 0.7) < 0.0001)
        #expect(rect.x >= 0)
        #expect(rect.y >= 0)
        #expect(rect.x + rect.width <= 1.0001)
        #expect(rect.y + rect.height <= 1.0001)
    }

    @Test func aFrameAtTheEdgeIsPushedBackInsteadOfOverflowing() {
        let rect = CropFrameGeometry.rect(
            matchingRatio: 16.0 / 9,
            keepingAreaOf: NormalizedRect(x: 0.85, y: 0.85, width: 0.15, height: 0.15),
            imageAspect: 1
        )
        #expect(rect.x + rect.width <= 1.0001)
        #expect(rect.y + rect.height <= 1.0001)
        #expect(rect.width >= CropFrameGeometry.minimumEdge)
        #expect(rect.height >= CropFrameGeometry.minimumEdge)
    }
}
