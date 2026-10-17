import Photos
import Testing
@testable import ShotDex

/// The frame picker's rules (FS-02.05 §4–§6) and the Bursts tab's rows
/// (FS-06.06 §7b). Pure, plus the two models against a fake library.
struct BurstSelectionTests {

    private func frames(_ count: Int, suggested: Set<Int> = []) -> [BurstFrame] {
        (1...count).map { BurstFrame(id: "f\($0)", isSuggested: suggested.contains($0), isPickedInPhotos: false) }
    }

    /// AC-2: nothing kept on open; Delete is off with the keep-one line.
    @Test func nothingIsKeptOnOpen() {
        let selection = BurstSelection(frames: frames(24, suggested: [7, 15]))
        #expect(selection.keptIds.isEmpty)
        #expect(!selection.canDelete)
        // FS-06.06 §8 / AC-F3: the red button dims and says what to do.
        #expect(selection.deleteTitle == "Keep picks, remove the rest")
        #expect(selection.deleteFootnote == "Choose at least one frame to keep")
        #expect(selection.hasSuggestions)
    }

    /// AC-3: Keep Only Suggested keeps 7 and 15; Delete 22.
    @Test func keepOnlySuggestedDeletesTheOtherTwentyTwo() {
        var selection = BurstSelection(frames: frames(24, suggested: [7, 15]))
        selection.keepOnlySuggested()
        #expect(selection.keptIds == ["f7", "f15"])
        #expect(selection.deleteIds.count == 22)
        #expect(selection.deleteTitle == "Keep 2, remove 22")
        #expect(!selection.deleteIds.contains("f7"))
    }

    /// AC-6: a tap on the big frame keeps it, a second takes it back.
    @Test func tappingTheBigFrameTogglesTheKeep() {
        var selection = BurstSelection(frames: frames(24))
        selection.show(2)
        selection.toggleKeepCurrent()
        #expect(selection.isKept("f3"))
        #expect(selection.deleteTitle == "Keep 1, remove 23")
        selection.toggleKeepCurrent()
        #expect(!selection.canDelete)
    }

    /// AC-7: no suggestion, no Keep Only Suggested.
    @Test func noSuggestionsMeansNoKeepOnlySuggested() {
        var selection = BurstSelection(frames: frames(5))
        #expect(!selection.hasSuggestions)
        selection.keepOnlySuggested()
        #expect(selection.keptIds.isEmpty)
    }

    @Test func keepingEveryFrameLeavesNothingToDelete() {
        var selection = BurstSelection(frames: frames(2))
        selection.show(0); selection.toggleKeepCurrent()
        selection.show(1); selection.toggleKeepCurrent()
        #expect(!selection.canDelete)
    }

    @Test func voiceOverReadsPositionSuggestionAndKeep() {
        var selection = BurstSelection(frames: frames(24, suggested: [3]))
        selection.show(2)
        selection.toggleKeepCurrent()
        #expect(selection.accessibilityLabel(at: 2) == "Frame 3 of 24, Suggested, kept")
        #expect(selection.accessibilityLabel(at: 3) == "Frame 4 of 24, not kept")
    }

    /// AC-B1: newest first, counts in words.
    @Test func burstRowsAreNewestFirstAndSayTheirCounts() {
        let old = BurstSummary(id: "a", coverId: "a1", date: Date(timeIntervalSince1970: 1), frameCount: 5, suggestedCount: 0)
        let new = BurstSummary(id: "b", coverId: "b1", date: Date(timeIntervalSince1970: 9), frameCount: 24, suggestedCount: 2)
        #expect(BurstSummary.sorted([old, new]).map(\.id) == ["b", "a"])
        #expect(new.framesTitle == "24 frames")
        #expect(new.suggestionTitle == "2 suggested by Photos")
        #expect(old.suggestionTitle == "No suggestion")
        #expect(BurstSummary.countTitle(3) == "3 bursts")
    }
}

/// A burst library held in memory.
@MainActor
private final class MemoryBurstLibrary: BurstLibrary {
    var bursts: [String: [BurstFrame]]
    var dates: [String: Date]

    init(bursts: [String: [BurstFrame]], dates: [String: Date] = [:]) {
        self.bursts = bursts
        self.dates = dates
    }

    func bursts() async -> [BurstSummary] {
        bursts.compactMap { id, frames in
            frames.first.map { BurstSummary(id: id, coverId: $0.id, date: dates[id]) }
        }
    }
    func frames(ofBurst id: String) async -> [BurstFrame] { bursts[id] ?? [] }
    func burstId(of assetId: String) -> String? { bursts.first { $0.value.contains { $0.id == assetId } }?.key }
    func asset(for frameId: String) -> PHAsset? { nil }
}

@MainActor
struct BurstModelTests {
    private func frames(_ prefix: String, _ count: Int, suggested: Set<Int> = []) -> [BurstFrame] {
        (1...count).map { BurstFrame(id: "\(prefix)\($0)", isSuggested: suggested.contains($0), isPickedInPhotos: false) }
    }

    /// AC-4 / AC-B3: the delete carries exactly the frames not kept, and a
    /// burst left with one frame drops out of the tab.
    @Test func deletingAllButOneDropsTheBurstFromTheTab() async {
        let library = MemoryBurstLibrary(
            bursts: ["big": frames("b", 24, suggested: [7, 15]), "small": frames("s", 5), "mid": frames("m", 10)],
            dates: ["big": Date(timeIntervalSince1970: 3), "mid": Date(timeIntervalSince1970: 2), "small": Date(timeIntervalSince1970: 1)]
        )
        let list = BurstListModel(library: library)
        await list.reload()
        for row in list.rows { await list.count(row.id) }
        #expect(list.listed.map(\.id) == ["big", "mid", "small"])
        #expect(list.listed.first?.suggestedCount == 2)

        var asked: [[String]] = []
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "small"),
            library: library,
            isLimited: false,
            banner: nil,
            deleteAssets: { ids in
                asked.append(ids)
                library.bursts["small"]?.removeAll { ids.contains($0.id) }
                return ids.count
            }
        )
        await picker.load()
        picker.show(0)
        picker.toggleKeepCurrent()
        let outcome = await picker.deleteUnkept()
        #expect(asked == [["s2", "s3", "s4", "s5"]])
        #expect(outcome == .deleted(kept: ["s1"]))

        await list.reload()
        #expect(list.listed.map(\.id) == ["big", "mid"])
        #expect(BurstSummary.countTitle(list.listed.count) == "2 bursts")
    }

    /// AC-5: Cancel in the system dialog deletes nothing and keeps the ticks.
    @Test func cancelKeepsTheTicks() async {
        let library = MemoryBurstLibrary(bursts: ["big": frames("b", 24, suggested: [7, 15])])
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "big"),
            library: library,
            isLimited: false,
            banner: nil,
            deleteAssets: { _ in throw PHPhotosError(.userCancelled) }
        )
        await picker.load()
        picker.keepOnlySuggested()
        let outcome = await picker.deleteUnkept()
        #expect(outcome == .cancelled)
        #expect(picker.selection.keptIds == ["b7", "b15"])
        #expect(picker.selection.count == 24)
    }

    /// AC-10: a failed delete loses nothing.
    @Test func aFailedDeleteKeepsEverything() async {
        struct Failure: Error {}
        let library = MemoryBurstLibrary(bursts: ["big": frames("b", 4, suggested: [2])])
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "big"), library: library, isLimited: false, banner: nil,
            deleteAssets: { _ in throw Failure() }
        )
        await picker.load()
        picker.keepOnlySuggested()
        #expect(await picker.deleteUnkept() == .failed)
        #expect(picker.selection.count == 4)
        #expect(picker.selection.keptIds == ["b2"])
    }

    /// AC-9: under limited access the picker says how many frames it sees.
    @Test func limitedAccessSaysHowManyFramesItSees() async {
        let library = MemoryBurstLibrary(bursts: ["big": frames("b", 3)])
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "big"), library: library, isLimited: true, banner: nil,
            deleteAssets: { _ in 0 }
        )
        await picker.load()
        #expect(picker.limitedNote?.hasPrefix("ShotDex can see 3 frames of this burst.") == true)
    }

    /// AC-B4: no bursts, nothing listed.
    @Test func noBurstsListsNothing() async {
        let list = BurstListModel(library: MemoryBurstLibrary(bursts: [:]))
        await list.reload()
        #expect(list.listed.isEmpty)
        #expect(list.phase == .ready)
    }
}

/// FS-06.06 §8 — the picker opened on a Duplicates group keeps its unmarked
/// frames, and Done hands the keeps back.
@MainActor
struct SharedFramePickerTests {
    @Test func groupMarksBecomeKeeps() {
        var selection = BurstSelection(frames: (1...5).map { BurstFrame(id: "f\($0)", isSuggested: false, isPickedInPhotos: false) })
        selection.keep(["f2", "f4", "not-a-frame"])
        #expect(selection.keptIds == ["f2", "f4"])
        #expect(selection.deleteTitle == "Keep 2, remove 3")
    }

    @Test func requestFromFramesIsNotABurst() {
        let request = BurstFramesRequest(frames: ["a", "b", "c"], startFrameId: "b")
        #expect(request.burstId == nil)
        #expect(request.source == .frames(["a", "b", "c"]))
        #expect(BurstFramesRequest(burstId: "x").burstId == "x")
    }
}

/// A group's picker deletes through the group (inheritance, banner); a
/// delete PhotoKit could not reach is not reported as done.
@MainActor
struct FramePickerDeleteTests {
    private func frames(_ count: Int) -> [BurstFrame] {
        (1...count).map { BurstFrame(id: "f\($0)", isSuggested: false, isPickedInPhotos: false) }
    }

    @Test func groupDeleteRunsInsteadOfPhotoKit() async {
        var handed: [String] = []
        var photoKitCalled = false
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "b"), library: MemoryBurstLibrary(bursts: ["b": frames(3)]),
            isLimited: false, banner: nil,
            groupDelete: { ids in handed = ids; return true },
            deleteAssets: { _ in photoKitCalled = true; return 0 }
        )
        await picker.load()
        picker.keepOnly("f1")
        #expect(await picker.deleteUnkept() == .deleted(kept: ["f1"]))
        #expect(handed == ["f2", "f3"])
        #expect(!photoKitCalled)
    }

    @Test func nothingReachableIsAFailureNotASuccess() async {
        let picker = BurstFramesModel(
            request: BurstFramesRequest(burstId: "b"), library: MemoryBurstLibrary(bursts: ["b": frames(3)]),
            isLimited: true, banner: nil, deleteAssets: { _ in 0 }
        )
        await picker.load()
        picker.keepOnly("f1")
        #expect(await picker.deleteUnkept() == .failed)
    }
}

