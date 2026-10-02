import CoreGraphics
import Photos
import Testing
@testable import ShotDex

/// FS-01.12b AC-8 — the pass asks for screen-sized renditions only.
struct CullImagePolicyTests {

    @Test func neverRequestsOriginal() {
        for screen in [CGSize(width: 402, height: 874), CGSize(width: 1376, height: 1032), CGSize(width: 951, height: 669)] {
            let size = CullImagePolicy.targetSize(screen: screen, scale: 3)
            #expect(size != PHImageManagerMaximumSize)
            #expect(max(size.width, size.height) <= 2_800)
        }
        #expect(CullImagePolicy.targetSize(screen: CGSize(width: 402, height: 874), scale: 3) == CGSize(width: 1_206, height: 2_622))
        #expect(CullImagePolicy.allowsNetwork)
    }

    @Test func warmsTwoPagesEachSide() {
        #expect(CullImagePolicy.warmRange(index: 0, count: 50) == 0...2)
        #expect(CullImagePolicy.warmRange(index: 10, count: 50) == 8...12)
        #expect(CullImagePolicy.warmRange(index: 49, count: 50) == 47...49)
        #expect(CullImagePolicy.warmRange(index: 3, count: 0) == nil)
    }
}
