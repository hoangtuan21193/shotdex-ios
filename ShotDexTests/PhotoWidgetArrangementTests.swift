import Foundation
import Testing
@testable import ShotDex

/// Arranging a widget: which piece sits where, what the guides catch, and how
/// far the photo behind can move. All of it arithmetic, so none of it needs a
/// finger on a preview to check.
struct PhotoWidgetArrangementTests {

    // MARK: Per-piece placement

    /// Moving one piece pins the others where they already were, instead of
    /// dragging them along behind it.
    @Test func movingOnePieceLeavesTheOthersWhereTheyWere() {
        var settings = PhotoWidgetSettings.default(for: .combined)
        settings.anchor = .bottomLeading
        let components = PhotoWidgetComponent.components(for: .combined, settings: settings)
        #expect(components.contains(.time))
        #expect(components.contains(.weather))

        settings.setAnchor(PhotoWidgetSettings.Anchor(x: 1, y: 0), for: .time, in: components)

        #expect(settings.anchor(for: .time) == PhotoWidgetSettings.Anchor(x: 1, y: 0))
        for other in components where other != .time {
            #expect(settings.anchor(for: other) == .bottomLeading)
        }
    }

    @Test func stackingEverythingTogetherUndoesTheArrangement() {
        var settings = PhotoWidgetSettings.default(for: .clock)
        let components = PhotoWidgetComponent.components(for: .clock, settings: settings)
        settings.setAnchor(.center, for: .time, in: components)
        #expect(!settings.componentAnchors.isEmpty)

        settings.resetComponentAnchors()
        #expect(settings.componentAnchors.isEmpty)
        #expect(settings.anchor(for: .time) == settings.anchor)
    }

    /// Pieces at the same spot are one stack — that is what keeps a widget
    /// nobody has rearranged looking exactly as it did.
    @Test func piecesAtTheSameSpotAreDrawnAsOneStack() {
        var settings = PhotoWidgetSettings.default(for: .combined)
        let components = PhotoWidgetComponent.components(for: .combined, settings: settings)

        let together = PhotoWidgetLayout.groups(
            components, anchors: settings.componentAnchorsByComponent, blockAnchor: settings.anchor
        )
        #expect(together.count == 1)
        #expect(together[0].components == components)

        settings.setAnchor(PhotoWidgetSettings.Anchor(x: 1, y: 0), for: .time, in: components)
        let apart = PhotoWidgetLayout.groups(
            components, anchors: settings.componentAnchorsByComponent, blockAnchor: settings.anchor
        )
        #expect(apart.count == 2)
        #expect(apart.contains { $0.components == [.time] })
    }

    // MARK: Guides

    @Test func theMiddlePullsAPieceThatIsNearlyThere() {
        let result = PhotoWidgetSnapping.snap(
            PhotoWidgetSettings.Anchor(x: 0.52, y: 0.48), others: []
        )
        #expect(result.anchor == PhotoWidgetSettings.Anchor(x: 0.5, y: 0.5))
        #expect(result.verticalGuides == [0.5])
        #expect(result.horizontalGuides == [0.5])
        #expect(result.isSnapped)
    }

    @Test func aPieceFarFromAnythingIsLeftAlone() {
        let anchor = PhotoWidgetSettings.Anchor(x: 0.3, y: 0.25)
        let result = PhotoWidgetSnapping.snap(anchor, others: [])
        #expect(result.anchor == anchor)
        #expect(!result.isSnapped)
    }

    /// Lining up with a piece already placed is the other thing a person is
    /// trying to do by eye.
    @Test func aPieceLinesUpWithAnotherPiece() {
        let other = PhotoWidgetSettings.Anchor(x: 0.2, y: 0.8)
        let result = PhotoWidgetSnapping.snap(
            PhotoWidgetSettings.Anchor(x: 0.23, y: 0.3), others: [other]
        )
        #expect(result.anchor.x == 0.2)
        #expect(result.verticalGuides == [0.2])
        // Nothing to line up with vertically, so that axis is untouched.
        #expect(result.anchor.y == 0.3)
        #expect(result.horizontalGuides.isEmpty)
    }

    /// An edge catches too, but draws no line: the widget's own boundary is
    /// already there to see.
    @Test func edgesCatchWithoutDrawingALine() {
        let result = PhotoWidgetSnapping.snap(
            PhotoWidgetSettings.Anchor(x: 0.03, y: 0.97), others: []
        )
        #expect(result.anchor == PhotoWidgetSettings.Anchor(x: 0, y: 1))
        #expect(result.verticalGuides.isEmpty)
        #expect(result.horizontalGuides.isEmpty)
    }

    // MARK: The photo behind

    /// A filled photo is cropped before any zoom, and that cropped part is
    /// what a two-finger drag brings into view — so panning has to work at 1×.
    @Test func aWidePhotoCanBePannedEvenUnzoomed() {
        let size = CGSize(width: 158, height: 158)
        let slack = PhotoWidgetImageLayer.slack(in: size, aspectRatio: 3.0 / 2.0, scale: 1)
        // A 3:2 photo filling a square hides (237 - 158) / 2 ≈ 39pt each side.
        #expect(slack.width > 38)
        #expect(slack.width < 40)
        #expect(slack.height == 0)
    }

    @Test func aPhotoTheShapeOfTheWidgetOnlyMovesOnceZoomed() {
        let size = CGSize(width: 329, height: 158)
        let matching = 329.0 / 158.0
        #expect(PhotoWidgetImageLayer.slack(in: size, aspectRatio: matching, scale: 1) == .zero)

        let zoomed = PhotoWidgetImageLayer.slack(in: size, aspectRatio: matching, scale: 2)
        #expect(zoomed.width > 160)
        #expect(zoomed.height > 78)
    }

    @Test func slackIsZeroForNonsenseInput() {
        #expect(PhotoWidgetImageLayer.slack(in: .zero, aspectRatio: 1.5, scale: 2) == .zero)
        #expect(
            PhotoWidgetImageLayer.slack(
                in: CGSize(width: 100, height: 100), aspectRatio: 0, scale: 2
            ) == .zero
        )
    }
}
