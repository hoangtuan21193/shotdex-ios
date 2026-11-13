import Photos
import Testing
@testable import ShotDex

/// FS-02 §8 — the viewer's loading rules that need no PhotoKit asset.
struct ViewerLoadingTests {

    /// AC-12: two pages each side, nearest first, clipped to the list.
    @Test func preheatsTwoEachSideNearestFirst() {
        #expect(ViewerPreheat.indices(around: 5, count: 20) == [5, 6, 4, 7, 3])
        #expect(ViewerPreheat.indices(around: 0, count: 20) == [0, 1, 2])
        #expect(ViewerPreheat.indices(around: 19, count: 20) == [19, 18, 17])
        #expect(ViewerPreheat.indices(around: 0, count: 1) == [0])
        #expect(ViewerPreheat.indices(around: 3, count: 0).isEmpty)
        #expect(ViewerPreheat.indices(around: 9, count: 4).isEmpty)
    }

    /// AC-11: a zoom's full-original request never joins the decoded cache.
    @Test func maximumSizeIsNotACacheableDisplaySize() {
        #expect(!PhotoLibraryService.isCacheableDetailSize(PHImageManagerMaximumSize))
        #expect(!PhotoLibraryService.isCacheableDetailSize(.zero))
        #expect(!PhotoLibraryService.isCacheableDetailSize(CGSize(width: CGFloat.infinity, height: 10)))
        #expect(PhotoLibraryService.isCacheableDetailSize(CGSize(width: 1320, height: 2868)))
    }
}
