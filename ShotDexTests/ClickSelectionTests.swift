import Testing
@testable import ShotDex

@Suite struct ClickSelectionTests {
    let order = ["a", "b", "c", "d", "e"]

    @Test func plainClickPicksOneAndSetsTheAnchor() {
        var selection = ClickSelection()
        selection.click("b", in: order, extendsSelection: false, extendsRange: false)
        selection.click("d", in: order, extendsSelection: false, extendsRange: false)
        #expect(selection.ids == ["d"])
        #expect(selection.anchor == "d")
    }

    @Test func commandClickToggles() {
        var selection = ClickSelection()
        selection.click("a", in: order, extendsSelection: false, extendsRange: false)
        selection.click("c", in: order, extendsSelection: true, extendsRange: false)
        #expect(selection.ids == ["a", "c"])
        selection.click("a", in: order, extendsSelection: true, extendsRange: false)
        #expect(selection.ids == ["c"])
        #expect(selection.anchor == "a")
    }

    @Test func shiftClickPicksTheRunFromTheAnchorEitherWay() {
        var selection = ClickSelection()
        selection.click("c", in: order, extendsSelection: false, extendsRange: false)
        selection.click("e", in: order, extendsSelection: false, extendsRange: true)
        #expect(selection.ids == ["c", "d", "e"])
        // The anchor stays: a second ⇧-click re-draws the run from it.
        selection.click("a", in: order, extendsSelection: false, extendsRange: true)
        #expect(selection.ids == ["a", "b", "c"])
        #expect(selection.anchor == "c")
    }

    @Test func commandShiftAddsTheRun() {
        var selection = ClickSelection()
        selection.click("a", in: order, extendsSelection: false, extendsRange: false)
        selection.click("d", in: order, extendsSelection: true, extendsRange: false)
        selection.click("e", in: order, extendsSelection: true, extendsRange: true)
        #expect(selection.ids == ["a", "d", "e"])
    }

    @Test func shiftClickWithAnAnchorOutsideTheOrderIsAPlainClick() {
        var selection = ClickSelection()
        selection.click("x", in: ["x", "y"], extendsSelection: false, extendsRange: false)
        selection.click("b", in: order, extendsSelection: false, extendsRange: true)
        #expect(selection.ids == ["b"])
        #expect(selection.anchor == "b")
    }

    @Test func replaceKeepsTheAnchorWhileItIsStillPicked() {
        var selection = ClickSelection()
        selection.click("b", in: order, extendsSelection: false, extendsRange: false)
        selection.replace(with: ["b", "c", "d"], in: order)
        #expect(selection.anchor == "b")
        // The anchor left the selection: the first picked item takes over.
        selection.replace(with: ["d", "c"], in: order)
        #expect(selection.anchor == "c")
        selection.replace(with: [], in: order)
        #expect(selection.anchor == nil)
    }

    @Test func shiftClickOnAnItemOutsideTheOrderIsAPlainClick() {
        var selection = ClickSelection()
        selection.click("b", in: order, extendsSelection: false, extendsRange: false)
        selection.click("z", in: order, extendsSelection: false, extendsRange: true)
        #expect(selection.ids == ["z"])
        #expect(selection.anchor == "z")
    }

    @Test func pruneDropsWhatIsGone() {
        var selection = ClickSelection()
        selection.click("b", in: order, extendsSelection: false, extendsRange: false)
        selection.click("d", in: order, extendsSelection: true, extendsRange: false)
        selection.prune(to: ["a", "b", "c"])
        #expect(selection.ids == ["b"])
        #expect(selection.anchor == nil)
    }
}
