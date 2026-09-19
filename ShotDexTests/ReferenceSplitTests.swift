import CoreGraphics
import SwiftUI
import Testing
@testable import ShotDex

/// Which way the canvas is cut when a reference frame is pinned. The rule is
/// "whichever way leaves each photo bigger", so the tests are about area, not
/// about taste.
struct ReferenceSplitTests {

    /// An iPad in portrait with the sidebar taken off: tall and narrow. A 3:2
    /// landscape frame already fills the width, so halving the width halves the
    /// photo; halving the height costs it nothing it was using.
    @Test func landscapePhotoInATallCanvasStacks() {
        let axis = EditorLayoutMetrics.referenceSplit(
            canvas: CGSize(width: 700, height: 1300),
            aspectRatio: 3.0 / 2.0
        )
        #expect(axis == .vertical)
    }

    /// A landscape frame keeps preferring the stack for longer than intuition
    /// says: on a 1300×900 canvas, stacking still wins (304k px² against 282k),
    /// because halving 900 leaves a pane that is *still* taller than a 3:2 frame
    /// needs. The canvas has to get properly letterbox-shaped before side by
    /// side pays.
    @Test func landscapePhotoNeedsAVeryWideCanvasBeforeSideBySideWins() {
        #expect(
            EditorLayoutMetrics.referenceSplit(
                canvas: CGSize(width: 1300, height: 900),
                aspectRatio: 3.0 / 2.0
            ) == .vertical
        )
        #expect(
            EditorLayoutMetrics.referenceSplit(
                canvas: CGSize(width: 1800, height: 700),
                aspectRatio: 3.0 / 2.0
            ) == .horizontal
        )
    }

    /// A portrait frame is the mirror image: side by side in a wide canvas is
    /// wrong for landscape photos and right for portrait ones.
    @Test func portraitPhotoInAWideCanvasSitsSideBySide() {
        let axis = EditorLayoutMetrics.referenceSplit(
            canvas: CGSize(width: 1300, height: 900),
            aspectRatio: 2.0 / 3.0
        )
        #expect(axis == .horizontal)
    }

    @Test func portraitPhotoInATallCanvasStacks() {
        let axis = EditorLayoutMetrics.referenceSplit(
            canvas: CGSize(width: 700, height: 1300),
            aspectRatio: 2.0 / 3.0
        )
        #expect(axis == .vertical)
    }

    /// Whichever way is chosen has to actually be the bigger one — the property
    /// the rule exists for, checked against the area function directly.
    @Test func theChosenSplitIsNeverTheSmallerOne() {
        let canvases = [
            CGSize(width: 700, height: 1300),
            CGSize(width: 1300, height: 900),
            CGSize(width: 1000, height: 1000),
            CGSize(width: 760, height: 620),
        ]
        let aspects: [CGFloat] = [3.0 / 2.0, 2.0 / 3.0, 1, 16.0 / 9.0, 9.0 / 16.0]

        for canvas in canvases {
            for aspect in aspects {
                let axis = EditorLayoutMetrics.referenceSplit(canvas: canvas, aspectRatio: aspect)
                let sideBySide = EditorLayoutMetrics.fittedArea(
                    aspectRatio: aspect,
                    in: CGSize(width: canvas.width / 2, height: canvas.height)
                )
                let stacked = EditorLayoutMetrics.fittedArea(
                    aspectRatio: aspect,
                    in: CGSize(width: canvas.width, height: canvas.height / 2)
                )
                let chosen = axis == .horizontal ? sideBySide : stacked
                #expect(chosen >= max(sideBySide, stacked) - 0.001)
            }
        }
    }

    /// A square photo in a square canvas has no better answer, so it takes the
    /// documented tie-break rather than flapping between the two.
    @Test func tiesGoSideBySide() {
        let axis = EditorLayoutMetrics.referenceSplit(
            canvas: CGSize(width: 1000, height: 1000),
            aspectRatio: 1
        )
        #expect(axis == .horizontal)
    }

    @Test func degenerateInputsFallBackRatherThanDivideByZero() {
        #expect(
            EditorLayoutMetrics.referenceSplit(canvas: .zero, aspectRatio: 1.5) == .horizontal
        )
        #expect(
            EditorLayoutMetrics.referenceSplit(
                canvas: CGSize(width: 800, height: 600),
                aspectRatio: 0
            ) == .horizontal
        )
        #expect(EditorLayoutMetrics.fittedArea(aspectRatio: 1.5, in: .zero) == 0)
    }
}
