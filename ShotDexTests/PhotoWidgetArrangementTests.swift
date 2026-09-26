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
        var settings = PhotoWidgetSettings()
        settings.showsWeather = true
        settings.anchor = .bottomLeading
        let components = PhotoWidgetComponent.components(settings: settings)
        #expect(components.contains(.time))
        #expect(components.contains(.weather))

        settings.setAnchor(PhotoWidgetSettings.Anchor(x: 1, y: 0), for: .time, in: components)

        #expect(settings.anchor(for: .time) == PhotoWidgetSettings.Anchor(x: 1, y: 0))
        for other in components where other != .time {
            #expect(settings.anchor(for: other) == .bottomLeading)
        }
    }

    @Test func stackingEverythingTogetherUndoesTheArrangement() {
        var settings = PhotoWidgetSettings()
        let components = PhotoWidgetComponent.components(settings: settings)
        settings.setAnchor(.center, for: .time, in: components)
        #expect(!settings.componentAnchors.isEmpty)

        settings.resetComponentAnchors()
        #expect(settings.componentAnchors.isEmpty)
        #expect(settings.anchor(for: .time) == settings.anchor)
    }

    /// Pieces at the same spot are one stack — that is what keeps a widget
    /// nobody has rearranged looking exactly as it did.
    @Test func piecesAtTheSameSpotAreDrawnAsOneStack() {
        var settings = PhotoWidgetSettings()
        settings.showsWeather = true
        settings.showsCalendar = true
        let components = PhotoWidgetComponent.components(settings: settings)

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

    // MARK: Picking a line

    /// The complaint that started this: tapping the date selected the clock,
    /// because the hit test ran against the stack and took its first line.
    @Test func aTapPicksTheLineUnderIt() {
        let frames: [PhotoWidgetComponent: CGRect] = [
            .time: CGRect(x: 10, y: 10, width: 80, height: 30),
            .date: CGRect(x: 10, y: 44, width: 90, height: 14),
            .weather: CGRect(x: 10, y: 62, width: 120, height: 40),
        ]
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 20), frames: frames) == .time)
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 50), frames: frames) == .date)
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 80), frames: frames) == .weather)
    }

    /// A line of text is thin. A touch just off one still picks it, or
    /// selecting the date on a 158pt preview is a game of darts.
    @Test func aTapJustOffALinePicksTheNearestOne() {
        let frames: [PhotoWidgetComponent: CGRect] = [
            .date: CGRect(x: 10, y: 44, width: 90, height: 14),
        ]
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 62), frames: frames) == .date)
        // Far away is still nothing: tapping the empty half of a widget
        // deselects rather than grabbing whatever is closest.
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 200), frames: frames) == nil)
    }

    /// Where a small line sits on top of a big block, the small one wins: it
    /// is the harder target, and the block can be grabbed anywhere else.
    @Test func theSmallerLineWinsWhereTwoOverlap() {
        let frames: [PhotoWidgetComponent: CGRect] = [
            .calendar: CGRect(x: 0, y: 0, width: 150, height: 120),
            .time: CGRect(x: 20, y: 20, width: 60, height: 24),
        ]
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 40, y: 30), frames: frames) == .time)
        #expect(PhotoWidgetHitTest.component(at: CGPoint(x: 120, y: 100), frames: frames) == .calendar)
    }

    // MARK: Sizing one line

    /// The two sliders only ever reached the clock and the supporting lines,
    /// so the weather block and the calendar could not be resized at all.
    @Test func everyLineHasASizeOfItsOwn() {
        var settings = PhotoWidgetSettings()
        #expect(settings.scale(for: .weather) == 1)

        settings.setScale(1.4, for: .weather)
        #expect(settings.scale(for: .weather) == 1.4)
        #expect(settings.scale(for: .calendar) == 1)

        // Out of range is clamped rather than refused.
        settings.setScale(9, for: .calendar)
        #expect(settings.scale(for: .calendar) == PhotoWidgetSettings.componentScaleRange.upperBound)
        settings.setScale(0.01, for: .calendar)
        #expect(settings.scale(for: .calendar) == PhotoWidgetSettings.componentScaleRange.lowerBound)
    }

    /// Back at its natural size, a line stores nothing — otherwise the file
    /// fills with 1.0s and "has this been changed" stops being answerable.
    @Test func aLineBackAtItsNaturalSizeStoresNothing() {
        var settings = PhotoWidgetSettings()
        settings.setScale(1.5, for: .time)
        #expect(!settings.componentScales.isEmpty)
        settings.setScale(1, for: .time)
        #expect(settings.componentScales.isEmpty)
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
