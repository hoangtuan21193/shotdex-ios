import Testing
@testable import ShotDex

/// Who plays Select and Candidate, which frame is being worked on, and where
/// the viewer goes after a delete (FS-01.08c §3–§7). Pure.
struct CompareSessionTests {

    private func session(_ ids: [String] = ["a", "b", "c", "d"]) -> CompareSession {
        CompareSession(selection: ids)!
    }

    @Test func selectionOrderGivesSelectAndCandidateOneOfThree() {
        let compare = session()
        #expect(compare.selectId == "a")
        #expect(compare.candidateId == "b")
        #expect(compare.candidateLabel == "Candidate 1 of 3")
        #expect(compare.mode == .twoUp)
        #expect(compare.workingId == "a")
    }

    @Test func fewerThanTwoPhotosIsNoComparison() {
        #expect(CompareSession(selection: ["a"]) == nil)
        #expect(CompareSession(selection: ["a", "a"]) == nil)
    }

    /// AC-3: a swipe on the Candidate moves it; Select stays.
    @Test func swipeMovesOnlyTheCandidate() {
        var compare = session()
        let moved = compare.nextCandidate()
        #expect(moved)
        #expect(compare.selectId == "a")
        #expect(compare.candidateId == "c")
        #expect(compare.candidateLabel == "Candidate 2 of 3")
        compare.nextCandidate()
        let movedPastEnd = compare.nextCandidate()
        #expect(!movedPastEnd)
        #expect(compare.candidateId == "d")
    }

    @Test func workingOnTheCandidateFollowsTheSwipe() {
        var compare = session()
        compare.setWorking("b")
        compare.nextCandidate()
        #expect(compare.workingId == "c")
    }

    /// AC-5: Make Select swaps the roles.
    @Test func makeSelectSwapsRolesNotMarks() {
        var compare = session(["a", "b"])
        compare.makeSelect()
        #expect(compare.selectId == "b")
        #expect(compare.candidateId == "a")
    }

    /// AC-6: a tap picks the working frame and nothing else.
    @Test func tapSetsTheWorkingFrameOnly() {
        var compare = session()
        compare.mode = .survey
        compare.setWorking("c")
        #expect(compare.workingId == "c")
        #expect(compare.selectId == "a")
        #expect(compare.ids == ["a", "b", "c", "d"])
    }

    /// AC-7: removing takes the photo out of the comparison only.
    @Test func removeKeepsTheRestAndTheTitle() {
        var compare = session(["a", "b", "c", "d", "e", "f"])
        compare.mode = .survey
        compare.setWorking("c")
        let removed = compare.remove("c")
        #expect(removed)
        #expect(compare.ids == ["a", "b", "d", "e", "f"])
        #expect(compare.title == "5 Photos")
        #expect(compare.workingId == "a")
    }

    @Test func twoPhotosCannotLoseOne() {
        var compare = session(["a", "b"])
        #expect(!compare.canRemove)
        let removed = compare.remove("b")
        #expect(!removed)
    }

    /// AC-8: Keep Only This rejects the others, and un-rejects itself.
    @Test func keepOnlyRejectsTheOthersAndKeepsAPick() {
        let compare = session()
        let flags: [String: PhotoFlag] = ["b": .reject, "c": .reject, "a": .pick]
        let change = compare.keepOnly("b") { flags[$0] }
        #expect(change.reject == ["a", "d"])
        #expect(change.unreject == ["b"])

        let picked = compare.keepOnly("a") { flags[$0] }
        #expect(picked.unreject.isEmpty)
    }

    /// AC-9: two left — stay in the mode in use.
    @Test func twoLeftStayInTwoUp() {
        var compare = session()
        let next = compare.afterDeletion(gone: ["b", "c"])
        #expect(next == .stay)
        #expect(compare.ids == ["a", "d"])
        #expect(compare.candidateId == "d")
        #expect(compare.mode == .twoUp)
    }

    /// AC-10: one left — Single on it.
    @Test func oneLeftGoesSingleOnIt() {
        var compare = session(["a", "b", "c"])
        let next = compare.afterDeletion(gone: ["a", "b"])
        #expect(next == .single("c"))
    }

    @Test func noneLeftGoesToTheGrid() {
        var compare = session(["a", "b"])
        let next = compare.afterDeletion(gone: ["a", "b"])
        #expect(next == .grid)
    }

    @Test func deletingSelectHandsItToTheNextPhoto() {
        var compare = session()
        compare.setWorking("a")
        _ = compare.afterDeletion(gone: ["a"])
        #expect(compare.selectId == "b")
        #expect(compare.workingId == "b")
    }

    /// AC-14: folding Survey makes the working frame Select.
    @Test func foldingSurveyMakesTheWorkingFrameSelect() {
        var compare = session(["a", "b", "c", "d", "e", "f"])
        compare.mode = .survey
        compare.setWorking("d")
        compare.fold()
        #expect(compare.mode == .twoUp)
        #expect(compare.selectId == "d")
        #expect(compare.candidateId == "e")
    }

    /// AC-26 (a): from the viewer, Candidate is the next cell; the last cell
    /// compares with the one before.
    @Test func fromTheViewerTheCandidateIsTheNextCell() {
        let compare = CompareSession(viewing: "p5", next: "p6", previous: "p4")!
        #expect(compare.selectId == "p5")
        #expect(compare.candidateId == "p6")
        #expect(compare.candidateLabel == "Candidate 1 of 1")

        let last = CompareSession(viewing: "p9", next: nil, previous: "p8")!
        #expect(last.candidateId == "p8")
        #expect(CompareSession(viewing: "only", next: nil, previous: nil) == nil)
    }
}

struct ViewerModeTests {
    /// AC-26 (b): a compact viewer opened from one photo has no Compare.
    @Test func compactSingleOffersNoCompare() {
        #expect(ViewerMode.available(for: .phone, isComparing: false).isEmpty)
        #expect(ViewerMode.available(for: .duoCover, isComparing: false).isEmpty)
        #expect(ViewerMode.available(for: .phone, isComparing: true) == [.single, .twoUp])
    }

    @Test func wideWindowsOfferSurvey() {
        for windowClass in [VideoStudioWindowClass.iPadLandscape, .iPadPortrait, .duoInner] {
            #expect(ViewerMode.available(for: windowClass, isComparing: false) == [.single, .twoUp, .survey])
        }
    }

    @Test func twoUpIsCalledCompareWhereItStacks() {
        #expect(ViewerMode.twoUp.title(isCompact: true) == "Compare")
        #expect(ViewerMode.twoUp.title(isCompact: false) == "2-Up")
    }
}
