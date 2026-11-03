import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6b: taking a common-photos run back from its log.
@Suite struct CommonPhotosUndoTests {
    typealias Fixture = CommonPhotosRunnerTests.Fixture

    /// A run gathered, then an undo of it started (every row, or `positions`).
    private func gathered(_ fixture: Fixture, action: CommonPhotosRun.Action = .copy,
                          positions: Set<Int>? = nil) async throws -> CommonPhotosUndoer {
        try await fixture.start(action: action)
        try await fixture.runner.run("R1")
        try fixture.store.startUndo(of: "R1", positions: positions, id: "U1")
        return CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work)
    }

    private func undoItems(_ fixture: Fixture) throws -> [CommonPhotosItem] {
        try fixture.store.items(runId: "U1")
    }

    private func sourceFiles(_ fixture: Fixture) -> [String: Data] {
        fixture.nas.files.filter { $0.key.hasPrefix("A/") || $0.key.hasPrefix("B/") }
    }

    // MARK: Undo Copy

    /// AC-131: five Copied and one Skipped (already in the destination) —
    /// the five go, the Skipped one stays, A and B are untouched.
    @Test func undoCopyRemovesOnlyCopied() async throws {
        let fixture = try Fixture(count: 6)
        fixture.nas.put("C/IMG_6.JPG", fixture.photos["IMG_6.JPG"]!)
        let undoer = try await gathered(fixture)
        let sources = sourceFiles(fixture)
        #expect(try fixture.items().map(\.status) == [.copied, .copied, .copied, .copied, .copied, .skipped])

        try await undoer.run("U1")

        #expect(Set(fixture.destinationFiles.keys) == ["C/IMG_6.JPG"])
        #expect(sourceFiles(fixture) == sources)
        #expect(try undoItems(fixture).map(\.status) == Array(repeating: .undone, count: 5))
        #expect(try fixture.items().map(\.status) == [.undone, .undone, .undone, .undone, .undone, .skipped])
        #expect(try fixture.store.run(id: "U1")?.state == .finished)
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(CommonPhotosRunner.removingSuffix) })
    }

    /// AC-132: both sources of photo 2 deleted after the copy — its copy in
    /// the destination is the last one and stays; nothing is removed there.
    @Test func undoCopyKeepsTheLastCopy() async throws {
        let fixture = try Fixture(count: 5)
        let undoer = try await gathered(fixture)
        fixture.nas.drop("A/IMG_2.JPG")
        fixture.nas.drop("B/IMG_2.JPG")
        let before = fixture.nas.commands.count

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_2.JPG"] == fixture.photos["IMG_2.JPG"])
        #expect(!fixture.nas.commands.dropFirst(before).contains { $0.contains("C/IMG_2.JPG") && ($0.hasPrefix("remove") || $0.hasPrefix("move")) })
        let items = try undoItems(fixture)
        #expect(items.map(\.status) == [.undone, .failed, .undone, .undone, .undone])
        #expect(items[1].failure?.reason == .noOtherCopy)
        // Still Copied on the run: a later undo may try it again.
        #expect(try fixture.items()[1].status == .copied)
    }

    /// AC-133: the copy of photo 3 edited in the destination — kept as is.
    @Test func undoCopyKeepsAnEditedCopy() async throws {
        let fixture = try Fixture(count: 5)
        let undoer = try await gathered(fixture)
        var edited = fixture.photos["IMG_3.JPG"]!
        edited[500] ^= 0xFF
        fixture.nas.put("C/IMG_3.JPG", edited)

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_3.JPG"] == edited)
        let items = try undoItems(fixture)
        #expect(items[2].status == .failed)
        #expect(items[2].failure?.reason == .changedInShared)
        #expect(items.filter { $0.status == .undone }.count == 4)
    }

    /// AC-138, Copy: the `.xmp` the run wrote goes; one that was there
    /// before the run stays.
    @Test func undoCopySidecarRules() async throws {
        let fixture = try Fixture(count: 4)
        fixture.nas.put("A/IMG_1.xmp", Data("one".utf8))
        fixture.nas.put("A/IMG_4.xmp", Data("four".utf8))
        fixture.nas.put("C/IMG_4.xmp", Data("four".utf8))
        let undoer = try await gathered(fixture)
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("one".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.xmp"] == nil)
        #expect(fixture.nas.files["C/IMG_4.xmp"] == Data("four".utf8))
        #expect(Set(fixture.destinationFiles.keys) == ["C/IMG_4.xmp"])
    }

    /// `IMG_1.JPG` and `IMG_1.MOV` share `IMG_1.xmp`: undoing one keeps it
    /// for the other; undoing the other then takes it.
    @Test func sharedSidecarGoesWithTheLastPhoto() async throws {
        let fixture = try Fixture(count: 2, layout: { index in
            index == 1 ? ("IMG_1.JPG", "IMG_1.JPG") : ("IMG_1.MOV", "IMG_1.MOV")
        })
        fixture.nas.put("A/IMG_1.xmp", Data("shared".utf8))
        let undoer = try await gathered(fixture, positions: [0])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("shared".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("shared".utf8))
        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil)

        try fixture.store.startUndo(of: "R1", id: "U2")
        try await undoer.run("U2")

        #expect(fixture.destinationFiles.isEmpty)
    }

    /// A stop after the copy was set aside: resume deletes it, never leaving
    /// the aside file behind or counting the photo twice.
    @Test func undoCopyResumesASetAsideCopy() async throws {
        let fixture = try Fixture(count: 2)
        let undoer = try await gathered(fixture)
        try await fixture.nas.move("C/IMG_1.JPG", to: "C/IMG_1.JPG" + CommonPhotosRunner.removingSuffix)

        try await undoer.run("U1")

        #expect(fixture.destinationFiles.isEmpty)
        #expect(try undoItems(fixture).map(\.status) == [.undone, .undone])
    }

    /// Two shares over one volume: a source — the first or any other —
    /// vanishes with the set-aside. The copy goes back, nothing is deleted,
    /// and the undo stops with the row still to do.
    @Test(arguments: ["A/IMG_1.JPG", "B/IMG_1.JPG"])
    func undoCopyStopsWhenASourceIsTheSameFile(alias: String) async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        let nas = fixture.nas
        nas.onMove = { from, _ in
            if from == "C/IMG_1.JPG" { nas.drop(alias) }
        }
        let before = nas.commands.count

        await #expect(throws: CommonPhotosRunner.Stop.destinationIsASource) { try await undoer.run("U1") }

        #expect(nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(!nas.files.keys.contains { $0.hasSuffix(CommonPhotosRunner.removingSuffix) })
        #expect(!nas.commands.dropFirst(before).contains { $0.hasPrefix("remove") })
        #expect(try fixture.store.run(id: "U1")?.state == .paused)
        #expect(try undoItems(fixture).map(\.status) == [.pending])
        #expect(try fixture.items().map(\.status) == [.copied])
    }

    /// A server error after the set-aside puts the copy back under its name.
    @Test func undoCopyErrorPutsTheCopyBack() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        fixture.nas.refuseRemoving = ["C/IMG_1.JPG" + CommonPhotosRunner.removingSuffix]

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(CommonPhotosRunner.removingSuffix) })
        #expect(try undoItems(fixture).map(\.status) == [.failed])
        #expect(try fixture.items().map(\.status) == [.copied])
    }

    /// The `.xmp` stays when no source holds its bytes any more (the user
    /// edited or deleted theirs), or when it was edited in the destination.
    @Test func lastSidecarStays() async throws {
        let fixture = try Fixture(count: 2)
        fixture.nas.put("A/IMG_1.xmp", Data("one".utf8))
        fixture.nas.put("A/IMG_2.xmp", Data("two".utf8))
        let undoer = try await gathered(fixture)
        fixture.nas.put("A/IMG_1.xmp", Data("one, edited".utf8))
        fixture.nas.put("C/IMG_2.xmp", Data("two, edited".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("one".utf8))
        #expect(fixture.nas.files["C/IMG_2.xmp"] == Data("two, edited".utf8))
        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil && fixture.nas.files["C/IMG_2.JPG"] == nil)
        #expect(try undoItems(fixture).map(\.status) == [.undone, .undone])
    }

    /// A quit between the undo row and the run's row: resume carries the
    /// undone mark over, so Undo is not offered for it again.
    @Test func undoneRowsReachTheRunOnResume() async throws {
        let fixture = try Fixture(count: 2)
        let undoer = try await gathered(fixture)
        var row = try #require(try undoItems(fixture).first)
        row.status = .undone
        try fixture.store.update(row)
        fixture.nas.drop("C/IMG_1.JPG")

        try await undoer.run("U1")

        #expect(try fixture.items().map(\.status) == [.undone, .undone])
    }

    /// The runner and the undoer take one claim per run.
    @Test func undoRunIsNotRunTwice() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        #expect(CommonPhotosRunner.claim(runId: "U1", in: fixture.store.database))
        defer { CommonPhotosRunner.release(runId: "U1", in: fixture.store.database) }

        await #expect(throws: CommonPhotosRunner.Stop.alreadyRunning) { try await undoer.run("U1") }
    }

    /// The set-aside's reply lost after the server did it: the copy is put
    /// back, the row fails and can be tried again.
    @Test func lostRenameReplyPutsTheCopyBack() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        fixture.nas.failMoveAfterDoing = true

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(CommonPhotosRunner.removingSuffix) })
        #expect(try undoItems(fixture).map(\.status) == [.failed])
    }

    /// The photo goes but its `.xmp` will not: the row is Undone with a
    /// note, and the sidecar is back under its name.
    @Test func sidecarThatWillNotGoLeavesTheRowUndone() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("one".utf8))
        let undoer = try await gathered(fixture)
        fixture.nas.refuseRemoving = ["C/IMG_1.xmp" + CommonPhotosRunner.removingSuffix]

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil)
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("one".utf8))
        let row = try #require(try undoItems(fixture).first)
        #expect(row.status == .undone)
        #expect(row.failure?.reason == .serverError)
        #expect(try fixture.items().map(\.status) == [.undone])
    }

    /// A copy set aside that is not the run's bytes on resume goes back.
    @Test func foreignAsideIsPutBack() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        fixture.nas.drop("C/IMG_1.JPG")
        fixture.nas.put("C/IMG_1.JPG" + CommonPhotosRunner.removingSuffix, Data("other".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == Data("other".utf8))
        #expect(try undoItems(fixture).first?.failure?.reason == .changedInShared)
    }

    /// Sources: a write time that moved is checked by SHA-256; a folder that
    /// is gone is no copy.
    @Test func sourcesCheckedBySHAWhenTheWriteTimeMoved() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        fixture.nas.modified["A/IMG_1.JPG"] = Date(timeIntervalSince1970: 42)
        fixture.nas.drop("B/IMG_1.JPG")

        try await undoer.run("U1")

        #expect(try undoItems(fixture).map(\.status) == [.undone])
    }

    /// An undo of a Move is refused before the run is touched (U3 adds it).
    @Test func undoMoveRefusedUntouched() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture, action: .move)

        await #expect(throws: CommonPhotosRunner.Stop.notResumable) { try await undoer.run("U1") }
        #expect(try fixture.store.run(id: "U1")?.state == .running)
    }
}
