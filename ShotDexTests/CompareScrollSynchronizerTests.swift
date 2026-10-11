import Testing
import UIKit
@testable import ShotDex

/// Zoom and pan stay in step across every frame of a comparison, with no
/// switch to turn that off (FS-01.08c AC-16, 08 §5). Real `UIScrollView`s,
/// because the synchronizer only ever talks to UIKit.
@MainActor
struct CompareScrollSynchronizerTests {

    /// A scroll view whose content can zoom: `zoomScale` is ignored until a
    /// delegate names the view to scale.
    private final class Pane: NSObject, UIScrollViewDelegate {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))

        init(width: CGFloat = 300) {
            super.init()
            scrollView.frame.size.width = width
            content.frame.size.width = width
            scrollView.addSubview(content)
            scrollView.contentSize = content.frame.size
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 8
            scrollView.delegate = self
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    }

    @Test func everyPaneFollowsAPinch() {
        let sync = CompareScrollSynchronizer()
        let select = Pane()
        let candidate = Pane(width: 150)
        sync.register(select.scrollView, at: 0)
        sync.register(candidate.scrollView, at: 1)

        select.scrollView.zoomScale = 3
        select.scrollView.contentOffset = CGPoint(x: 300, y: 200)
        sync.mirror(from: select.scrollView)

        #expect(candidate.scrollView.zoomScale == 3)
        // The same relative spot on a frame half as wide: a third of the way in.
        let fraction = candidate.scrollView.contentOffset.x / candidate.scrollView.contentSize.width
        #expect(abs(fraction - 1.0 / 3.0) < 0.001)
    }

    /// A frame built after the pinch — the next candidate swiped in — arrives
    /// at the zoom the comparison is at, not at fit.
    @Test func aLatePaneCatchesUp() async {
        let sync = CompareScrollSynchronizer()
        let select = Pane()
        sync.register(select.scrollView, at: 0)
        select.scrollView.zoomScale = 2.5
        sync.mirror(from: select.scrollView)

        let late = Pane()
        sync.register(late.scrollView, at: 1)
        // The catch-up waits for the layout pass after registration.
        await Task.yield()
        await Task.yield()

        #expect(late.scrollView.zoomScale == 2.5)
    }
}
