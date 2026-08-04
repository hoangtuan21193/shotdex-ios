import Foundation
import Testing
@testable import ShotDex

struct EditorHistoryAndSummaryTests {
    @Test func timelineOrdersOldestFirstAroundTheCurrentStep() {
        var history = PhotoEditHistory()
        let first = PhotoEditRecipe.identity
        var second = first
        second.adjustments.exposure = 0.4
        var third = second
        third.adjustments.shadows = 0.2

        history.record(first)
        history.record(second)
        #expect(history.timeline(current: third) == [first, second, third])
        #expect(history.currentIndex == 2)

        _ = history.undo(current: third)
        #expect(history.timeline(current: second) == [first, second, third])
        #expect(history.currentIndex == 1)
    }

    @Test func jumpMovesBothStacksAndIsIdempotentOnTheCurrentStep() {
        var history = PhotoEditHistory()
        let first = PhotoEditRecipe.identity
        var second = first
        second.adjustments.exposure = 0.4
        var third = second
        third.adjustments.shadows = 0.2
        history.record(first)
        history.record(second)

        #expect(history.jump(to: 2, current: third) == nil)
        #expect(history.jump(to: 9, current: third) == nil)
        #expect(history.jump(to: 0, current: third) == first)
        #expect(history.currentIndex == 0)
        #expect(history.canUndo == false)
        #expect(history.canRedo)
        #expect(history.timeline(current: first) == [first, second, third])
        #expect(history.redo(current: first) == second)
    }

    /// A cancelled Crop session drops its own entries: undo must not step back into
    /// framing that was just thrown away.
    @Test func rewindDropsTheEntriesRecordedAfterTheGivenDepth() {
        var history = PhotoEditHistory()
        let first = PhotoEditRecipe.identity
        var second = first
        second.adjustments.exposure = 0.4
        var beforeCrop = second
        beforeCrop.adjustments.shadows = 0.2
        history.record(first)
        history.record(second)
        let depth = history.undoDepth

        // The first drag of the Crop session records the state it started from.
        history.record(beforeCrop)
        #expect(history.undoDepth == depth + 1)

        // Cancelling puts `beforeCrop` back and takes that entry with it.
        history.rewind(toUndoDepth: depth)
        #expect(history.undoDepth == depth)
        #expect(history.timeline(current: beforeCrop) == [first, second, beforeCrop])
        #expect(history.canRedo == false)

        // Out-of-range depths leave the stack alone rather than clearing it.
        history.rewind(toUndoDepth: depth)
        history.rewind(toUndoDepth: 99)
        #expect(history.undoDepth == depth)
    }

    @Test func maskSummaryListsSetSlidersAndCountsTheRest() {
        var adjustments = PhotoAdjustments.zero
        #expect(EditorAdjustmentSummary.text(for: adjustments) == nil)

        adjustments.exposure = 0.8
        adjustments.shadows = 0.12
        #expect(
            EditorAdjustmentSummary.text(for: adjustments) == "Exposure +0.80 · Shadows +12"
        )

        adjustments.highlights = -0.24
        adjustments.vignette = 0.5
        #expect(
            EditorAdjustmentSummary.text(for: adjustments, limit: 2)
                == "Exposure +0.80 · Highlights \u{2212}24 +2"
        )
    }

    @Test func historyLabelsDescribeWhatTheStepChanged() {
        let base = PhotoEditRecipe.identity

        var slider = base
        slider.adjustments.exposure = 0.8
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: slider)
                == "Exposure +0.80"
        )

        var filtered = base
        filtered.filter = .vivid
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: filtered)
                == "Filter Vivid"
        )

        var cropped = base
        cropped.crop.aspect = .fourThree
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: cropped) == "Crop 4:3"
        )

        var straightened = base
        straightened.crop.straightenDegrees = 2.5
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: straightened)
                == "Straighten +2.5°"
        )

        var withMask = base
        withMask.masks = [
            PhotoMask(name: "Subject 1", component: PhotoMaskComponent(kind: .subject))
        ]
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: withMask)
                == "Added Subject 1"
        )

        var maskAdjusted = withMask
        maskAdjusted.masks[0].adjustments.exposure = 0.8
        #expect(
            EditorAdjustmentSummary.describeChange(from: withMask, to: maskAdjusted)
                == "Subject 1 · Exposure +0.80"
        )

        #expect(
            EditorAdjustmentSummary.describeChange(from: maskAdjusted, to: base) == "Reset"
        )
    }

    @Test func autoToneBrightensAndOpensUpAFlatDarkHistogram() {
        // Everything bunched into the low quarter: needs exposure, whites and
        // contrast.
        let dark = PhotoHistogram(
            red: bins(populated: 0..<8, count: 64),
            green: bins(populated: 0..<8, count: 64),
            blue: bins(populated: 0..<8, count: 64)
        )
        let suggestion = EditorAutoTone.suggestion(for: .zero, histogram: dark)
        #expect(suggestion.exposure > 0.3)
        #expect(suggestion.whites > 0.3)
        #expect(suggestion.contrast > 0)

        // A full-range, centred histogram is left alone.
        let even = PhotoHistogram(
            red: bins(populated: 0..<64, count: 64),
            green: bins(populated: 0..<64, count: 64),
            blue: bins(populated: 0..<64, count: 64)
        )
        let neutral = EditorAutoTone.suggestion(for: .zero, histogram: even)
        #expect(abs(neutral.exposure) < 0.2)
        #expect(neutral.whites == 0)
        #expect(neutral.contrast == 0)
    }

    @Test func autoToneKeepsOtherSlidersUntouched() {
        var current = PhotoAdjustments.zero
        current.saturation = 0.4
        current.grain = 0.25
        let suggestion = EditorAutoTone.suggestion(
            for: current,
            histogram: PhotoHistogram(
                red: bins(populated: 10..<40, count: 64),
                green: bins(populated: 10..<40, count: 64),
                blue: bins(populated: 10..<40, count: 64)
            )
        )
        #expect(suggestion.saturation == 0.4)
        #expect(suggestion.grain == 0.25)
    }

    @Test func histogramReportsClippingSeparatelyFromBins() {
        var histogram = PhotoHistogram(red: [], green: [], blue: [])
        #expect(!histogram.hasClippedHighlights)
        histogram.clippedHighlightFraction = 0.02
        #expect(histogram.hasClippedHighlights)
        #expect(!histogram.hasClippedShadows)
    }

    @Test func historyLabelsDescribeColorChanges() {
        let base = PhotoEditRecipe.identity

        var mixed = base
        mixed.color.mixer.red.hue = 0.2
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: mixed)
                == "Mixer · Red Hue +20"
        )

        var pointed = base
        pointed.color.points = [
            PointColorAdjustment(referenceHue: 210, referenceSaturation: 0.7, referenceValue: 0.5)
        ]
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: pointed)
                == "Added Point Color"
        )
        // Back to a recipe that still has *something* in it — dropping the last
        // adjustment of all is a "Reset", which is a different label on purpose.
        var keptSomething = base
        keptSomething.adjustments.exposure = 0.3
        var pointedOnTop = keptSomething
        pointedOnTop.color.points = pointed.color.points
        #expect(
            EditorAdjustmentSummary.describeChange(from: pointedOnTop, to: keptSomething)
                == "Removed Point Color"
        )

        var graded = base
        graded.color.grading.shadows.hue = 220
        graded.color.grading.shadows.saturation = 0.4
        #expect(
            EditorAdjustmentSummary.describeChange(from: base, to: graded)
                == "Grading · Shadows"
        )

        var blended = graded
        blended.color.grading.blending = 0.65
        #expect(
            EditorAdjustmentSummary.describeChange(from: graded, to: blended)
                == "Grading · Blending 65"
        )

        #expect(EditorAdjustmentSummary.describeChange(from: mixed, to: base) == "Reset")
    }

    @Test func undoRestoresTheColorRecipe() {
        var history = PhotoEditHistory()
        let before = PhotoEditRecipe.identity
        var after = before
        after.color.grading.midtones.hue = 120
        after.color.grading.midtones.saturation = 0.5

        history.record(before)
        #expect(history.undo(current: after) == before)
        #expect(history.redo(current: before) == after)
    }

    @Test func discardingTheLastStepUndoesAGestureThatChangedNothing() {
        var history = PhotoEditHistory()
        let before = PhotoEditRecipe.identity
        var painted = before
        painted.adjustments.exposure = 0.5

        // A gesture that a second finger cancelled: recorded on touch-down, rolled
        // back on cancel. The entry goes with it, so the zoom costs no undo.
        history.record(before)
        history.discardLast(matching: before)
        #expect(!history.canUndo)

        // A step that really did change something is never swallowed, even when a
        // cancel is reported after it.
        history.record(before)
        history.discardLast(matching: painted)
        #expect(history.undo(current: painted) == before)
    }

    private func bins(populated: Range<Int>, count: Int) -> [Double] {
        (0..<count).map { populated.contains($0) ? 0.8 : 0 }
    }
}
