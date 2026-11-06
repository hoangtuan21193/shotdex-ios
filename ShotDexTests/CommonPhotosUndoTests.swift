import CryptoKit
import Foundation
import os
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

    /// `IMG_1.ARW` and `IMG_1.MOV` share `IMG_1.xmp`: undoing one keeps it
    /// for the other; undoing the other then takes it. (A JPEG or HEIC
    /// beside the MOV would be a Live Photo, undone as a pair — §6f.)
    @Test func sharedSidecarGoesWithTheLastPhoto() async throws {
        let fixture = try Fixture(count: 2, layout: { index in
            index == 1 ? ("IMG_1.ARW", "IMG_1.ARW") : ("IMG_1.MOV", "IMG_1.MOV")
        })
        fixture.nas.put("A/IMG_1.xmp", Data("shared".utf8))
        let undoer = try await gathered(fixture, positions: [0])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("shared".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("shared".utf8))
        #expect(fixture.nas.files["C/IMG_1.ARW"] == nil)

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


    // MARK: Undo Move

    private func sources(_ fixture: Fixture, count: Int) -> [String: Data] {
        var files: [String: Data] = [:]
        for index in 1...count {
            files["A/IMG_\(index).JPG"] = fixture.photos["IMG_\(index).JPG"]
            files["B/IMG_\(index).JPG"] = fixture.photos["IMG_\(index).JPG"]
        }
        return files
    }

    /// AC-134: five Moved on one share — A's copies renamed back (no upload
    /// for them), B's uploaded and read back; the destination empty.
    @Test func undoMoveSameShare() async throws {
        let fixture = try Fixture(count: 5)
        let undoer = try await gathered(fixture, action: .move)
        #expect(sourceFiles(fixture).isEmpty)
        let before = fixture.nas.commands.count

        try await undoer.run("U1")

        #expect(sourceFiles(fixture) == sources(fixture, count: 5))
        #expect(fixture.destinationFiles.isEmpty)
        let commands = fixture.nas.commands.dropFirst(before)
        #expect(commands.filter { $0.hasPrefix("upload ") }.allSatisfy { $0.contains("B/") })
        #expect(commands.filter { $0.hasPrefix("upload ") }.count == 5)
        #expect(commands.contains("move C/IMG_1.JPG → A/IMG_1.JPG"))
        #expect(try undoItems(fixture).map(\.status) == Array(repeating: .undone, count: 5))
        #expect(try fixture.items().allSatisfy { $0.status == .undone && $0.sources.allSatisfy { !$0.isRemoved } })
    }

    /// AC-135: B's old path holds other bytes — never written over; A's copy
    /// goes back; the photo is never without a copy.
    @Test func undoMoveTakenPathIsSkipped() async throws {
        let fixture = try Fixture(count: 3)
        let undoer = try await gathered(fixture, action: .move)
        fixture.nas.put("B/IMG_2.JPG", Data("someone else".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files["B/IMG_2.JPG"] == Data("someone else".utf8))
        #expect(fixture.nas.files["A/IMG_2.JPG"] == fixture.photos["IMG_2.JPG"])
        #expect(fixture.nas.files["B/IMG_2 (2).JPG"] == nil)
        let rows = try undoItems(fixture)
        #expect(rows.map(\.status) == [.undone, .failed, .undone])
        #expect(rows[1].failure?.reason == .nameTaken)
        #expect(rows[1].failure?.detail == "B/IMG_2.JPG")
        // The run's row: A is back, B still removed — a later undo tries B again.
        let original = try fixture.items()[1]
        #expect(original.status == .moved)
        #expect(original.sources.map(\.isRemoved) == [false, true])
    }

    /// AC-136: a cross-share Move (copied, not renamed): every copy is
    /// uploaded; the destination copy goes only once all are back. Photo 2's
    /// A copy reads back wrong: its destination copy stays, its part goes.
    @Test func undoCrossShareMoveKeepsTheCopyUntilAllAreBack() async throws {
        let fixture = try Fixture(count: 3)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let undoer = try await gathered(fixture, action: .move)
        #expect(try fixture.items().allSatisfy { $0.movedFrom == nil || $0.status == .moved })
        fixture.nas.corruptReadBack = ["A/IMG_2.JPG.shotdex-part"]

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_2.JPG"] == fixture.photos["IMG_2.JPG"])
        #expect(fixture.nas.files["A/IMG_2.JPG"] == nil)
        #expect(fixture.nas.files["A/IMG_2.JPG.shotdex-part"] == nil)
        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil && fixture.nas.files["C/IMG_3.JPG"] == nil)
        for index in [1, 3] {
            #expect(fixture.nas.files["A/IMG_\(index).JPG"] == fixture.photos["IMG_\(index).JPG"])
            #expect(fixture.nas.files["B/IMG_\(index).JPG"] == fixture.photos["IMG_\(index).JPG"])
        }
        #expect(try undoItems(fixture).map(\.status) == [.undone, .failed, .undone])
    }

    /// AC-138, Move: each removed `.xmp` comes back beside its photo; the
    /// one the run wrote in the destination goes.
    @Test func undoMoveSidecarsGoBack() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("rated".utf8))
        fixture.nas.put("B/IMG_1.xmp", Data("rated".utf8))
        let undoer = try await gathered(fixture, action: .move)
        #expect(fixture.nas.files["A/IMG_1.xmp"] == nil && fixture.nas.files["B/IMG_1.xmp"] == nil)

        try await undoer.run("U1")

        #expect(fixture.nas.files["A/IMG_1.xmp"] == Data("rated".utf8))
        #expect(fixture.nas.files["B/IMG_1.xmp"] == Data("rated".utf8))
        #expect(fixture.destinationFiles.isEmpty)
    }

    /// The same bytes were in the destination before the Move: that file
    /// stays; both copies are written back.
    @Test func undoMoveLeavesWhatWasThere() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)
        let undoer = try await gathered(fixture, action: .move)

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(sourceFiles(fixture) == sources(fixture, count: 1))
        #expect(try undoItems(fixture).map(\.status) == [.undone])
    }

    /// A destination copy edited since the Move: nothing is written back.
    @Test func undoMoveOfAnEditedCopyDoesNothing() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let undoer = try await gathered(fixture, action: .move)
        var edited = fixture.photos["IMG_1.JPG"]!
        edited[10] ^= 1
        fixture.nas.put("C/IMG_1.JPG", edited)

        try await undoer.run("U1")

        #expect(sourceFiles(fixture).isEmpty)
        #expect(fixture.nas.files["C/IMG_1.JPG"] == edited)
        #expect(try undoItems(fixture).first?.failure?.reason == .changedInShared)
    }

    /// The same bytes were in the destination before the Move and a source
    /// `.xmp` was kept (so the row's reason is "sidecar not copied"): the
    /// file that was there still stays.
    @Test func whatWasThereStaysWhateverTheReason() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)
        fixture.nas.put("C/IMG_1.xmp", Data("theirs".utf8))
        fixture.nas.put("A/IMG_1.xmp", Data("mine".utf8))
        let undoer = try await gathered(fixture, action: .move)
        #expect(try fixture.items().first?.failure?.reason == .sidecarNotCopied)
        #expect(try fixture.items().first?.destinationWasThere == true)

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("theirs".utf8))
        #expect(sourceFiles(fixture)["A/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(sourceFiles(fixture)["B/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
    }

    /// A kill after the destination copy was set aside: resume finishes the
    /// removal, nothing stays hidden.
    @Test func undoMoveResumesASetAsideDestination() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let undoer = try await gathered(fixture, action: .move)
        let photo = fixture.photos["IMG_1.JPG"]!
        fixture.nas.put("A/IMG_1.JPG", photo)
        fixture.nas.put("B/IMG_1.JPG", photo)
        var row = try #require(try undoItems(fixture).first)
        row.sources = row.sources.map { var source = $0; source.isRemoved = false; return source }
        try fixture.store.update(row)
        try await fixture.nas.move("C/IMG_1.JPG", to: "C/IMG_1.JPG" + CommonPhotosRunner.removingSuffix)

        try await undoer.run("U1")

        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("C/") && !$0.hasSuffix(".csv") }.isEmpty)
        #expect(try undoItems(fixture).map(\.status) == [.undone])
    }

    /// The rename back refused: the copy is written back instead.
    @Test func refusedRenameBackIsWrittenInstead() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture, action: .move)
        fixture.nas.refusesMovesAcrossTopFolders = true

        try await undoer.run("U1")

        #expect(sourceFiles(fixture) == sources(fixture, count: 1))
        #expect(fixture.destinationFiles.isEmpty)
        #expect(try undoItems(fixture).map(\.status) == [.undone])
    }

    /// A copy put back earlier and edited since: the destination copy, the
    /// last of the original bytes, stays.
    @Test func editedPutBackCopyKeepsTheDestination() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let undoer = try await gathered(fixture, action: .move)
        var edited = fixture.photos["IMG_1.JPG"]!
        edited[3] ^= 1
        fixture.nas.put("A/IMG_1.JPG", edited)
        fixture.nas.put("B/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)
        var row = try #require(try undoItems(fixture).first)
        row.sources = row.sources.map { var source = $0; source.isRemoved = false; return source }
        try fixture.store.update(row)

        try await undoer.run("U1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(try undoItems(fixture).first?.failure?.reason == .changedOnServer)
    }

    /// A Move that removed copies and then failed can be undone.
    @Test func failedMoveWithRemovedCopiesIsUndoable() throws {
        var item = CommonPhotosItem(runId: "R1", position: 0, sha256: "a", size: 1,
                                    sources: [.init(path: "A/a", size: 1, modifiedAt: 1), .init(path: "B/a", size: 1, modifiedAt: 1)],
                                    status: .failed, destinationPath: "C/a")
        #expect(!item.isUndoable)
        item.sources[1].isRemoved = true
        #expect(item.isUndoable)
    }

    // MARK: Every failure point (AC-137) and resume (AC-140)

    /// Each photo has a copy with its bytes under a real name somewhere.
    private func everyPhotoHasACopy(_ fixture: Fixture, count: Int) -> Bool {
        let files = fixture.nas.files
        return (1...count).allSatisfy { index in
            guard let bytes = fixture.photos["IMG_\(index).JPG"] else { return false }
            return ["A", "B", "C"].contains { files["\($0)/IMG_\(index).JPG"] == bytes }
        }
    }

    /// What an undo leaves with no failure: the destination empty, every
    /// photo in A and B with its bytes (and its `.xmp` when it had one).
    private func expectCleanEnd(_ fixture: Fixture, count: Int, sidecars: Bool) {
        #expect(fixture.destinationFiles.isEmpty)
        var wanted = sources(fixture, count: count)
        if sidecars {
            for index in 1...count { wanted["A/IMG_\(index).xmp"] = Data("xmp \(index)".utf8) }
        }
        #expect(sourceFiles(fixture) == wanted)
    }

    private func sweepFixture(_ action: CommonPhotosRun.Action, crossShare: Bool, sidecars: Bool) async throws
        -> (Fixture, CommonPhotosUndoer) {
        let fixture = try Fixture(count: 3)
        fixture.nas.refusesMovesAcrossTopFolders = crossShare
        if sidecars {
            for index in 1...3 { fixture.nas.put("A/IMG_\(index).xmp", Data("xmp \(index)".utf8)) }
        }
        return (fixture, try await gathered(fixture, action: action))
    }

    /// AC-137: the connection lost at every write of an undo in turn —
    /// before the server does it and after — and at every read: every
    /// photo still has a copy under its own name, and Resume then ends
    /// where an undo with no failure ends. Writes are uploads, renames and
    /// deletes — the only ones an undo makes.
    @Test(arguments: [CommonPhotosRun.Action.move, .copy], [false, true])
    func everyFailurePointKeepsACopy(action: CommonPhotosRun.Action, crossShare: Bool) async throws {
        for sidecars in [false, true] {
            let (clean, cleanUndoer) = try await sweepFixture(action, crossShare: crossShare, sidecars: sidecars)
            clean.nas.failOnWrite = (Int.max, false)
            clean.nas.failOnRead = Int.max
            try await cleanUndoer.run("U1")
            let writes = clean.nas.writeCount
            let reads = clean.nas.readCount
            expectCleanEnd(clean, count: 3, sidecars: sidecars)
            #expect(writes > 0 && reads > 0)

            var points: [(write: Int?, read: Int?, afterDoing: Bool)] = []
            for number in 1...writes { points += [(number, nil, false), (number, nil, true)] }
            for number in 1...reads { points.append((nil, number, false)) }
            for point in points {
                let label = "sidecars \(sidecars), write \(point.write ?? 0) after \(point.afterDoing), read \(point.read ?? 0)"
                let (fixture, undoer) = try await sweepFixture(action, crossShare: crossShare, sidecars: sidecars)
                if let write = point.write { fixture.nas.failOnWrite = (write, point.afterDoing) }
                if let read = point.read { fixture.nas.failOnRead = read }

                await #expect(throws: RemoteFileError.connectionLost, "\(label)") { try await undoer.run("U1") }

                #expect(everyPhotoHasACopy(fixture, count: 3), "\(label)")
                // Paused, or — cut short in the CSV step — still finishing.
                #expect([.paused, .finishing].contains(try fixture.store.run(id: "U1")?.state), "\(label)")
                fixture.nas.failOnWrite = nil
                fixture.nas.failOnRead = nil
                try await undoer.run("U1")
                expectCleanEnd(fixture, count: 3, sidecars: sidecars)
                let rows = try undoItems(fixture)
                #expect(rows.count == 3 && rows.allSatisfy { $0.status == .undone }, "\(label)")
                #expect(try fixture.items().allSatisfy { $0.status == .undone }, "\(label)")
            }
        }
    }

    /// Undo Move, two shares over one volume: the destination copy is the
    /// same file as a restored copy — it goes back and the undo stops.
    @Test func undoMoveStopsWhenARestoredCopyIsTheDestination() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture, action: .move)
        let nas = fixture.nas
        nas.onMove = { from, _ in
            if from == "C/IMG_1.JPG" { nas.drop("B/IMG_1.JPG") }
        }
        // A's copy is renamed back last; set B up so the destination is
        // removed rather than renamed.
        var row = try #require(try undoItems(fixture).first)
        row.movedFrom = nil
        try fixture.store.update(row)

        await #expect(throws: CommonPhotosRunner.Stop.destinationIsASource) { try await undoer.run("U1") }

        #expect(nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(!nas.files.keys.contains { $0.hasSuffix(CommonPhotosRunner.removingSuffix) })
        #expect(try undoItems(fixture).map(\.status) == [.pending])
    }

    /// AC-140: an undo of 10 stopped after the 4th — Resume carries on from
    /// the 5th; the first four are not read again; 10 rows Undone.
    @Test func resumeUndoAfterQuit() async throws {
        let fixture = try Fixture(count: 10)
        let undoer = try await gathered(fixture)
        // Cancelled from inside the run, as Pause does — the progress call
        // runs on the run's own task.
        let run = Task {
            try await undoer.run("U1", progress: { progress in
                if progress.doneCount == 4 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(try fixture.store.run(id: "U1")?.state == .paused)
        #expect(try undoItems(fixture).filter { $0.status == .undone }.count == 4)
        let before = fixture.nas.commands.count

        try await undoer.run("U1")

        let resumed = fixture.nas.commands.dropFirst(before)
        #expect(resumed.contains { $0.contains("/IMG_5.JPG") })
        for index in 1...4 { #expect(!resumed.contains { $0.contains("/IMG_\(index).JPG") }) }
        #expect(try undoItems(fixture).map(\.status) == Array(repeating: .undone, count: 10))
        #expect(fixture.destinationFiles.isEmpty)
        #expect(try fixture.items().allSatisfy { $0.status == .undone })
    }

    // MARK: CSV and Undo Selected (AC-139)

    private func csvFiles(_ fixture: Fixture) -> [String: String] {
        fixture.nas.files.filter { $0.key.hasPrefix("C/ShotDex Common Photos ") && $0.key.hasSuffix(".csv") }
            .mapValues { String(decoding: $0, as: UTF8.self) }
    }

    /// AC-139: two rows of ten chosen — only they are undone; the run's CSV
    /// stays and `… Undo.csv` lists the two.
    @Test func undoSelectedTwoRows() async throws {
        let fixture = try Fixture(count: 10)
        let undoer = try await gathered(fixture, positions: [1, 4])
        let runCSV = try #require(try fixture.store.run(id: "R1")?.csvPath)

        try await undoer.run("U1")

        #expect(try fixture.items().map(\.status) == [.copied, .undone, .copied, .copied, .undone,
                                                       .copied, .copied, .copied, .copied, .copied])
        #expect(fixture.destinationFiles.count == 8)
        let csvs = csvFiles(fixture)
        #expect(csvs[runCSV] != nil)
        let undoCSV = try #require(try fixture.store.run(id: "U1")?.csvPath)
        #expect(undoCSV.hasSuffix(" Undo.csv"))
        let lines = try #require(csvs[undoCSV]).split(separator: "\r\n")
        #expect(lines.count == 3)
        #expect(lines.dropFirst().allSatisfy { $0.hasPrefix("Undone,") })
    }

    /// Everything taken back in two undos: the run's CSV and the first
    /// undo's CSV go with the second.
    @Test func lastUndoTakesTheCSVs() async throws {
        let fixture = try Fixture(count: 3)
        let undoer = try await gathered(fixture, positions: [0])
        try await undoer.run("U1")
        #expect(csvFiles(fixture).count == 2)

        try fixture.store.startUndo(of: "R1", id: "U2")
        try await undoer.run("U2")

        #expect(csvFiles(fixture).isEmpty)
        #expect(try fixture.store.run(id: "U2")?.csvPath == nil)
        #expect(try fixture.store.run(id: "R1")?.csvPath == nil)
        #expect(try fixture.store.run(id: "U1")?.csvPath == nil)
        #expect(try fixture.store.run(id: "U2")?.state == .finished)
    }

    /// A row not undone reads "Not undone" with its reason in the CSV.
    @Test func undoCSVSaysNotUndone() async throws {
        let fixture = try Fixture(count: 2)
        let undoer = try await gathered(fixture)
        fixture.nas.drop("A/IMG_2.JPG")
        fixture.nas.drop("B/IMG_2.JPG")

        try await undoer.run("U1")

        let undoCSV = try #require(try fixture.store.run(id: "U1")?.csvPath)
        let text = try #require(csvFiles(fixture)[undoCSV])
        #expect(text.split(separator: "\r\n").count == 3)
        #expect(text.contains("Undone,IMG_1.JPG"))
        #expect(text.contains("Not undone,IMG_2.JPG"))
        #expect(text.contains("no other copy"))
    }

    /// The copies written back reach the history step, which puts back
    /// what the Move moved.
    @Test func afterUndoHearsTheCopiesWrittenBack() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start(action: .move)
        try await fixture.runner.run("R1")
        try fixture.store.startUndo(of: "R1", id: "U1")
        let heard = OSAllocatedUnfairLock<Set<String>>(initialState: [])
        var undoer = CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work)
        undoer.afterUndo = { _, restored in heard.withLock { $0 = restored } }

        try await undoer.run("U1")

        #expect(heard.withLock { $0 } == ["A/IMG_1.JPG", "B/IMG_1.JPG", "A/IMG_2.JPG", "B/IMG_2.JPG"])
    }

    /// The history step failing leaves the undo finishing; Resume does it.
    @Test func failedHistoryStepResumes() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        try await fixture.runner.run("R1")
        try fixture.store.startUndo(of: "R1", id: "U1")
        var undoer = CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work)
        undoer.afterUndo = { _, _ in throw RemoteFileError.connectionLost }

        await #expect(throws: RemoteFileError.connectionLost) { try await undoer.run("U1") }
        #expect(try fixture.store.run(id: "U1")?.state == .finishing)

        undoer.afterUndo = { _, _ in }
        try await undoer.run("U1")
        #expect(try fixture.store.run(id: "U1")?.state == .finished)
    }

    /// A file the user saved under the run's CSV name is not deleted.
    @Test func foreignFileUnderTheLogNameStays() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        let runCSV = try #require(try fixture.store.run(id: "R1")?.csvPath)
        fixture.nas.put(runCSV, Data("my notes".utf8))

        try await undoer.run("U1")

        #expect(fixture.nas.files[runCSV] == Data("my notes".utf8))
    }

    /// An undo that ends a group keeps the group among the 20 kept, even
    /// when 20 newer runs finished meanwhile.
    @Test func undoneGroupCountsAsNew() async throws {
        let fixture = try Fixture(count: 1)
        let undoer = try await gathered(fixture)
        for index in 1...20 {
            try fixture.store.start(CommonPhotosRun(id: "N\(index)", connectionId: "S1", folders: ["X", "Y"], destination: "Z",
                                                    action: .copy, createdAt: Int(Date().timeIntervalSince1970) - 100 + index), items: [])
            try fixture.store.markState(.finished, runId: "N\(index)")
        }

        try await undoer.run("U1")

        #expect(try fixture.store.run(id: "R1") != nil)
        #expect(try fixture.store.run(id: "U1")?.state == .finished)
        #expect(try fixture.store.run(id: "N1") == nil)
    }
}
