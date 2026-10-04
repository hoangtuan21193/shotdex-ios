import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit

/// The geometry of FS-05.04 §3, without drawing: a block that scales with its
/// frame, placed by `WatermarkLayout`.
struct WatermarkLayoutTests {
    /// A block 30% of the frame's width by 5% of its height, in the frame's
    /// bottom-right — whatever the frame size, as Core Text would give it.
    private func block(_ frame: CGSize) -> CGRect? {
        CGRect(x: frame.width * 0.65, y: frame.height * 0.9, width: frame.width * 0.3, height: frame.height * 0.05)
    }

    /// AC-1's geometry: photo A resized to 2048×1365, configuration W.
    @Test func bottomRightAt2048() throws {
        let frame = try #require(WatermarkLayout.place(
            sourceAspect: 1.5,
            placement: WatermarkPlacement(anchor: .bottomRight, margin: 0.03, size: 0.04, opacity: 1),
            imageSize: CGSize(width: 2048, height: 1365),
            measure: block
        ))
        #expect(abs(frame.box.maxX - 2007) <= 1)
        #expect(abs(frame.box.maxY - 1324) <= 1)
        #expect(abs(frame.box.height - 55) <= 1)
        // The block keeps its own proportions: 30% × 1.5 wide for 5% tall.
        #expect(abs(frame.box.width / frame.box.height - 9) < 0.01)
    }

    @Test func naturalSizeIsThePresetsOwn() throws {
        let frame = try #require(WatermarkLayout.place(
            sourceAspect: 1.5,
            placement: WatermarkPlacement(anchor: .bottomRight, margin: 0.03, size: nil, opacity: 1),
            imageSize: CGSize(width: 3000, height: 2000),
            measure: block
        ))
        // 5% of a 3:2 frame's height = 5% of its short edge.
        #expect(abs(frame.box.height - 100) <= 1)
    }

    @Test func sizeFollowsTheShortEdgeNotTheWidth() throws {
        let landscape = try #require(WatermarkLayout.place(
            sourceAspect: 1.5, placement: WatermarkFixture.placementW,
            imageSize: CGSize(width: 6000, height: 4000), measure: block
        ))
        let portrait = try #require(WatermarkLayout.place(
            sourceAspect: 1.5, placement: WatermarkFixture.placementW,
            imageSize: CGSize(width: 4000, height: 6000), measure: block
        ))
        #expect(abs(landscape.box.height - 160) <= 1)
        #expect(abs(portrait.box.height - 160) <= 1)
    }

    @Test func stepperPixelsRoundTrip() {
        #expect(WatermarkLayout.pixels(forSize: 0.04, shortEdge: 1365) == 55)
        #expect(abs(WatermarkLayout.size(forPixels: 55, shortEdge: 1365) - 0.0403) < 0.0001)
        #expect(WatermarkLayout.size(forPixels: 10_000, shortEdge: 1365) == 0.25)
        #expect(WatermarkLayout.size(forPixels: 1, shortEdge: 1365) == 0.01)
    }
}
