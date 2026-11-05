import Foundation
import os
import Testing
@testable import ShotDex

/// FS-19.08 §6e: a copy on the server carries its source's dates and flags.
@Suite struct RemoteFileInfoTests {
    /// 2020-01-02 03:04:05 UTC, the date the SMB fixtures carry.
    static let old = Date(timeIntervalSince1970: 1_577_934_245)
    static let older = Date(timeIntervalSince1970: 1_546_398_245)

    private func part(_ nas: InMemoryRemoteFileClient, _ destination: String, _ bytes: Data = Data([1, 2, 3])) {
        nas.put(ServerUploadPath.partPath(for: destination), bytes)
    }

    // MARK: VerifiedRemoteWrite

    /// AC-211 (order): dates on the part, the rename, read-only only after
    /// it, then the read-back says kept.
    @Test func infoSetBeforeRenameReadOnlyAfter() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.readOnlyRefusesChanges = true
        part(nas, "C/a.JPG")
        let info = RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true, isHidden: true)

        let outcome = try await VerifiedRemoteWrite(client: nas).moveIntoPlace("C/a.JPG", replacing: false, info: info)

        #expect(outcome == .kept)
        #expect(nas.commands == ["info C/a.JPG.shotdex-part", "move C/a.JPG.shotdex-part → C/a.JPG", "info C/a.JPG read-only"])
        #expect(try await nas.fileInfo(at: "C/a.JPG") == info)
    }

    /// AC-215: the server takes the request and keeps another date — the
    /// copy is in place, reported `dates not kept`, never failed.
    @Test func driftIsReported() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.dateDrift = 3_600
        part(nas, "C/a.JPG")

        let outcome = try await VerifiedRemoteWrite(client: nas).moveIntoPlace("C/a.JPG", replacing: false, info: RemoteFileInfo(modified: Self.old))

        #expect(outcome == .datesNotKept)
        #expect(nas.files["C/a.JPG"] == Data([1, 2, 3]))
    }

    /// A server that sets no dates (SFTP): reported, the rename still done.
    @Test func unsupportedServerIsReported() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.keepsDates = false
        part(nas, "C/a.JPG")

        let outcome = try await VerifiedRemoteWrite(client: nas).moveIntoPlace("C/a.JPG", replacing: false, info: RemoteFileInfo(modified: Self.old))

        #expect(outcome == .datesNotKept)
        #expect(nas.files["C/a.JPG"] != nil)
    }

    /// Two seconds either way is the same time (FAT keeps 2-second steps);
    /// three is not.
    @Test func sameModifiedWithinTwoSeconds() {
        let base = RemoteFileInfo(modified: Self.old)
        #expect(base.hasSameModified(as: RemoteFileInfo(modified: Self.old.addingTimeInterval(2))))
        #expect(base.hasSameModified(as: RemoteFileInfo(modified: Self.old.addingTimeInterval(-1.5))))
        #expect(!base.hasSameModified(as: RemoteFileInfo(modified: Self.old.addingTimeInterval(3))))
    }

    // MARK: SMB request

    /// MS-FSCC 2.4.7 as sent: creation, access 0 (leave), write, change =
    /// write, attributes; a file with no flags says NORMAL, not 0.
    @Test func smbBasicInformationBytes() {
        let flagged = SMBFileClient.basicInformation(RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true, isArchive: true)).encoded()
        let words = stride(from: 0, to: 32, by: 8).map { flagged.subdata(in: $0..<$0 + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian } }
        #expect(words == [131_908_718_450_000_000, 0, 132_224_078_450_000_000, 132_224_078_450_000_000])
        #expect(flagged.subdata(in: 32..<36).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } == 0x21)

        let plain = SMBFileClient.basicInformation(RemoteFileInfo(modified: Self.old)).encoded()
        #expect(plain.subdata(in: 0..<8).allSatisfy { $0 == 0 })
        #expect(plain.subdata(in: 32..<36).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } == 0x80)

        let clearing = SMBFileClient.basicInformation(attributesOnly: []).encoded()
        #expect(clearing.subdata(in: 0..<32).allSatisfy { $0 == 0 })
        #expect(clearing.subdata(in: 32..<36).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } == 0x80)
    }

    // MARK: Runner

    /// AC-211 (runner): the copy in `C` gets the first folder's dates and
    /// flags; the row says kept.
    @Test func copyCarriesTheFirstFolderInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 2)
        let info = RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true)
        fixture.nas.infos["A/IMG_1.JPG"] = info
        fixture.nas.infos["B/IMG_1.JPG"] = RemoteFileInfo(modified: Self.older)
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == info)
        let items = try fixture.items()
        #expect(items.allSatisfy { $0.status == .copied && $0.fileInfo == .kept })
    }

    /// AC-218: a photo already in `C` is not touched — not even its dates.
    @Test func alreadyThereKeepsItsInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.put("C/IMG_1.JPG", try #require(fixture.photos["IMG_1.JPG"]))
        let there = RemoteFileInfo(modified: Self.older)
        fixture.nas.infos["C/IMG_1.JPG"] = there
        fixture.nas.infos["A/IMG_1.JPG"] = RemoteFileInfo(modified: Self.old)
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.skipped])
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == there)
        #expect(!fixture.nas.commands.contains { $0.hasPrefix("info C/IMG_1.JPG") })
    }

    /// AC-215 / SFTP at the runner: the photo is Copied, the row says dates
    /// not kept.
    @Test func copyOnAServerThatKeepsNoDates() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.keepsDates = false
        try await fixture.start()

        try await fixture.runner.run("R1")

        let item = try #require(try fixture.items().first)
        #expect(item.status == .copied)
        #expect(item.fileInfo == .datesNotKept)
    }

    /// AC-223 (commands): keeping the info costs at most two writes a photo
    /// (dates on the part; read-only after the rename) on top of the copy.
    @Test func infoCostsAtMostTwoWritesAPhoto() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 4)
        for index in 1...4 { fixture.nas.infos["A/IMG_\(index).JPG"] = RemoteFileInfo(modified: Self.old, isReadOnly: index.isMultiple(of: 2)) }
        try await fixture.start()

        try await fixture.runner.run("R1")

        let infoWrites = fixture.nas.commands.filter { $0.hasPrefix("info ") }
        #expect(infoWrites.count == 4 + 2)
    }

    // MARK: Move, sidecars, the server's verdict (T3)

    /// AC-213 (rename): a Move renamed on the server keeps the dates; the
    /// row says kept after checking.
    @Test func moveByRenameKeepsInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        let info = RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true)
        fixture.nas.infos["A/IMG_1.JPG"] = info
        try await fixture.start(action: .move)

        try await fixture.runner.run("R1")

        let item = try #require(try fixture.items().first)
        #expect(item.status == .moved)
        #expect(item.fileInfo == .kept)
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == info)
    }

    /// AC-213 (refused rename) + AC-224: the server will not rename across
    /// folders, so the photo is copied — with the first folder's dates —
    /// and both copies' info is on the row before either is removed.
    @Test func moveByCopyKeepsInfoAndRecordsTheRemovedCopies() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let first = RemoteFileInfo(modified: Self.old, isReadOnly: true)
        let second = RemoteFileInfo(modified: Self.older, isHidden: true)
        fixture.nas.infos["A/IMG_1.JPG"] = first
        fixture.nas.infos["B/IMG_1.JPG"] = second
        try await fixture.start(action: .move)

        try await fixture.runner.run("R1")

        let item = try #require(try fixture.items().first)
        #expect(item.status == .moved)
        #expect(item.fileInfo == .kept)
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == first)
        #expect(item.sources.map(\.info) == [first, second])
        #expect(item.sources.allSatisfy { $0.isRemoved })
    }

    /// AC-224: the same on a server that keeps no dates — still Moved (the
    /// user's choice, 2026-11-05), dates not kept, and the removed copies'
    /// info recorded for Undo.
    @Test func moveOnAServerThatKeepsNoDates() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        fixture.nas.keepsDates = false
        let first = RemoteFileInfo(modified: Self.old)
        fixture.nas.infos["A/IMG_1.JPG"] = first
        fixture.nas.put("A/IMG_1.xmp", Data("<x/>".utf8))
        let sidecar = RemoteFileInfo(modified: Self.older)
        fixture.nas.infos["A/IMG_1.xmp"] = sidecar
        try await fixture.start(action: .move)
        // What the store holds at the moment A's photo is first set aside
        // or removed: the info must already be there.
        let store = fixture.store
        let atRemoval = OSAllocatedUnfairLock<CommonPhotosItem.Source?>(initialState: nil)
        fixture.nas.onMove = { source, _ in
            guard source == "A/IMG_1.JPG" else { return }
            let row = try? store.items(runId: "R1").first?.sources.first
            atRemoval.withLock { if $0 == nil { $0 = row } }
        }

        try await fixture.runner.run("R1")

        let item = try #require(try fixture.items().first)
        #expect(item.status == .moved)
        #expect(item.fileInfo == .datesNotKept)
        #expect(item.sources.first?.info == first)
        #expect(item.sources.first?.sidecarInfo == sidecar)
        let recorded = try #require(atRemoval.withLock { $0 })
        #expect(recorded.info == first)
        #expect(recorded.sidecarInfo == sidecar)
    }

    /// AC-216 + AC-224: Undo Move writes each removed copy back with the
    /// dates and flags recorded before the Move removed it — its own, not
    /// the shared copy's — and its `.xmp` with the sidecar's. The run fell
    /// back to copying (the server would not rename across folders) on a
    /// server that keeps no dates on new copies… until the undo, which
    /// writes on one that does.
    @Test func undoMovePutsEachCopyBackAsItWas() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.refusesMovesAcrossTopFolders = true
        let first = RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true)
        let second = RemoteFileInfo(modified: Self.older, isHidden: true)
        let sidecar = RemoteFileInfo(modified: Date(timeIntervalSince1970: 1_500_000_000))
        fixture.nas.infos["A/IMG_1.JPG"] = first
        fixture.nas.infos["B/IMG_1.JPG"] = second
        fixture.nas.put("A/IMG_1.xmp", Data("<x/>".utf8))
        fixture.nas.infos["A/IMG_1.xmp"] = sidecar
        try await fixture.start(action: .move)
        fixture.nas.keepsDates = false
        try await fixture.runner.run("R1")
        #expect(try fixture.items().first?.status == .moved)
        #expect(fixture.nas.files["A/IMG_1.JPG"] == nil && fixture.nas.files["B/IMG_1.JPG"] == nil)

        fixture.nas.keepsDates = true
        try fixture.store.startUndo(of: "R1", id: "U1")
        try await CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work).run("U1")

        let undone = try #require(try fixture.store.items(runId: "U1").first)
        #expect(undone.status == .undone)
        #expect(undone.fileInfo == .kept)
        #expect(try await fixture.nas.fileInfo(at: "A/IMG_1.JPG") == first)
        #expect(try await fixture.nas.fileInfo(at: "B/IMG_1.JPG") == second)
        #expect(try await fixture.nas.fileInfo(at: "A/IMG_1.xmp") == sidecar)
    }

    /// AC-216: a Move renamed on the server whose copy in `C` has lost its
    /// date since (or never kept it): the undo renames it back and sets the
    /// recorded date and flags again.
    @Test func undoRenameBackSetsTheRecordedInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        let first = RemoteFileInfo(modified: Self.old, isReadOnly: true)
        fixture.nas.infos["A/IMG_1.JPG"] = first
        try await fixture.start(action: .move)
        try await fixture.runner.run("R1")
        fixture.nas.infos["C/IMG_1.JPG"] = RemoteFileInfo(modified: Date(timeIntervalSince1970: 1_793_836_800))

        try fixture.store.startUndo(of: "R1", id: "U1")
        try await CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work).run("U1")

        #expect(try fixture.store.items(runId: "U1").first?.fileInfo == .kept)
        #expect(try await fixture.nas.fileInfo(at: "A/IMG_1.JPG") == first)
    }

    /// AC-224: an undo on a server that sets no dates puts every photo back
    /// (Undone, not a failure) and says so on the row and in the CSV; the
    /// run's own verdict is not carried over.
    @Test func undoOnAServerThatKeepsNoDatesSaysSo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 2)
        fixture.nas.refusesMovesAcrossTopFolders = true
        fixture.nas.infos["A/IMG_1.JPG"] = RemoteFileInfo(modified: Self.old)
        try await fixture.start(action: .move)
        try await fixture.runner.run("R1")
        #expect(try fixture.items().allSatisfy { $0.fileInfo == .kept })

        fixture.nas.keepsDates = false
        try fixture.store.startUndo(of: "R1", id: "U1")
        try await CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work).run("U1")

        let rows = try fixture.store.items(runId: "U1")
        #expect(rows.map(\.status) == [.undone, .undone])
        #expect(rows.allSatisfy { $0.fileInfo == .datesNotKept })
        // A whole undo takes its CSVs away (§6b); a partial one leaves this.
        #expect(CommonPhotosLog.csv(rows, isUndo: true).contains(",dates not kept,\r\n"))
    }

    /// An undo of a Copy dates nothing: its rows carry no verdict, not the
    /// run's "kept".
    @Test func undoCopyCarriesNoVerdict() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.infos["A/IMG_1.JPG"] = RemoteFileInfo(modified: Self.old)
        try await fixture.start()
        try await fixture.runner.run("R1")

        try fixture.store.startUndo(of: "R1", id: "U1")
        try await CommonPhotosUndoer(client: fixture.nas, store: fixture.store, workDirectory: fixture.work).run("U1")

        #expect(try fixture.store.items(runId: "U1").first?.fileInfo == nil)
    }

    /// The undo row's verdict: the worst of its copies.
    @Test func worstOutcomeWins() {
        #expect(CommonPhotosUndoer.worst([]) == nil)
        #expect(CommonPhotosUndoer.worst([.kept, .kept]) == .kept)
        #expect(CommonPhotosUndoer.worst([.kept, .datesNotKept]) == .datesNotKept)
    }

    /// AC-213 (sidecar): the `.xmp` gets its own source's dates, not the
    /// photo's.
    @Test func sidecarKeepsItsOwnInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("<x/>".utf8))
        let photo = RemoteFileInfo(modified: Self.old)
        let sidecar = RemoteFileInfo(modified: Self.older)
        fixture.nas.infos["A/IMG_1.JPG"] = photo
        fixture.nas.infos["A/IMG_1.xmp"] = sidecar
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == photo)
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.xmp") == sidecar)
    }

    /// AC-214: a run that lost every date records it for the connection;
    /// the next sheet on that connection warns; the CSV says why per photo.
    /// A run that kept them clears the warning again.
    @Test @MainActor func refusedDatesAreRemembered() async throws {
        var fixture = try CommonPhotosRunnerTests.Fixture(count: 2)
        fixture.nas.keepsDates = false
        try await fixture.start()

        try await fixture.runner.run("R1")

        let database = fixture.store.database
        #expect(try ServerFileInfoSupport.keepsDates(connectionId: "S1", in: database) == false)
        let sheet = CommonPhotosScanModel(connectionId: "S1", sourceId: "src", folders: ["A", "B"], client: fixture.nas, database: database)
        #expect(sheet.serverKeepsNoDates)
        let csv = try #require(fixture.csv)
        #expect(csv.text.contains(",dates not kept,full\r\n"))

        fixture.nas.keepsDates = true
        for path in fixture.nas.files.keys where path.hasPrefix("C/") { fixture.nas.drop(path) }
        fixture.runId = "R2"
        try await fixture.start()
        try await fixture.runner.run("R2")
        #expect(try ServerFileInfoSupport.keepsDates(connectionId: "S1", in: database) == true)
        #expect(!CommonPhotosScanModel(connectionId: "S1", sourceId: "src", folders: ["A", "B"], client: fixture.nas, database: database).serverKeepsNoDates)
    }

    /// The verdict from a run's outcomes: lost only when every copy lost
    /// them; nothing written, no verdict.
    @Test func verdictFromOutcomes() {
        #expect(ServerFileInfoSupport.keepsDates(from: []) == nil)
        #expect(ServerFileInfoSupport.keepsDates(from: [.datesNotKept, .datesNotKept]) == false)
        #expect(ServerFileInfoSupport.keepsDates(from: [.datesNotKept, .kept]) == true)
    }

    // MARK: Restore File Info… (T5)

    /// A Copy run whose copies lost their dates (a server that set none,
    /// or a run before §6e), on a server that sets them now.
    private func runThatLostTheDates(count: Int) async throws -> CommonPhotosRunnerTests.Fixture {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: count)
        for index in 1...count { fixture.nas.infos["A/IMG_\(index).JPG"] = RemoteFileInfo(modified: Self.old.addingTimeInterval(Double(index)), isReadOnly: index == 1) }
        fixture.nas.keepsDates = false
        try await fixture.start()
        try await fixture.runner.run("R1")
        fixture.nas.keepsDates = true
        return fixture
    }

    /// AC-217: two copies take the first folder's dates and flags; the one
    /// changed in Shared since is said and left; not a byte uploaded or
    /// hashed.
    @Test func restoreSetsTheDatesWithoutCopying() async throws {
        let fixture = try await runThatLostTheDates(count: 3)
        #expect(try fixture.items().allSatisfy { $0.fileInfo == .datesNotKept })
        fixture.nas.put("C/IMG_3.JPG", Data(repeating: 7, count: 10))
        let before = fixture.nas.commands.count

        let result = try await CommonPhotosInfoRestorer(client: fixture.nas, store: fixture.store).run("R1")

        #expect(result == .init(done: 3, total: 3, restored: 2, leftAlone: 1))
        let after = fixture.nas.commands.dropFirst(before)
        #expect(!after.contains { $0.hasPrefix("upload ") || $0.hasPrefix("sha256 ") || $0.hasPrefix("download ") })
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_1.JPG") == fixture.nas.infos["A/IMG_1.JPG"])
        #expect(try await fixture.nas.fileInfo(at: "C/IMG_2.JPG") == fixture.nas.infos["A/IMG_2.JPG"])
        let rows = try fixture.items()
        #expect(rows.map(\.status) == [.copied, .copied, .copied])
        #expect(rows.map(\.fileInfo) == [.kept, .kept, .datesNotKept])
        #expect(rows[2].failure?.reason == .changedInShared)
        // Left alone with its reason: not offered again.
        #expect(CommonPhotosInfoRestorer.candidates(rows, run: try #require(try fixture.store.run(id: "R1"))).isEmpty)
    }

    /// AC-225: Stop at row 12 of 30 keeps the 12 set and leaves the rest
    /// untouched; running it again does the rest.
    @Test func restoreStopsAndContinues() async throws {
        let fixture = try await runThatLostTheDates(count: 30)
        let restorer = CommonPhotosInfoRestorer(client: fixture.nas, store: fixture.store)
        let handle = OSAllocatedUnfairLock<Task<Void, Error>?>(initialState: nil)
        let started = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            while !started.withLock({ $0 }) { await Task.yield() }
            try await restorer.run("R1") { progress in
                if progress.done == 12 { handle.withLock { $0?.cancel() } }
            }
        }
        handle.withLock { $0 = task }
        started.withLock { $0 = true }
        await #expect(throws: CancellationError.self) { try await task.value }

        var rows = try fixture.items()
        #expect(rows.filter { $0.fileInfo == .kept }.count == 12)
        #expect(rows.filter { $0.fileInfo == .datesNotKept }.count == 18)
        // What the 12 showed about the server is recorded, Stop or not.
        #expect(try ServerFileInfoSupport.keepsDates(connectionId: "S1", in: fixture.store.database) == true)
        // The claim went with the restore: the run can go again.
        #expect(!CommonPhotosRunner.isActive(runId: "R1", in: fixture.store.database))

        let rest = try await restorer.run("R1")
        #expect(rest.total == 18 && rest.restored == 18)
        rows = try fixture.items()
        #expect(rows.allSatisfy { $0.fileInfo == .kept })
    }

    /// A Copied row's own warning (sidecar not copied) survives a restore,
    /// whether the copy is set or left alone.
    @Test func restoreKeepsTheRowsOwnReason() async throws {
        let fixture = try await runThatLostTheDates(count: 2)
        for var item in try fixture.items() {
            item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
            try fixture.store.update(item)
        }
        fixture.nas.put("C/IMG_2.JPG", Data(repeating: 1, count: 3))

        try await CommonPhotosInfoRestorer(client: fixture.nas, store: fixture.store).run("R1")

        let rows = try fixture.items()
        #expect(rows.map(\.fileInfo) == [.kept, .datesNotKept])
        #expect(rows.allSatisfy { $0.failure?.reason == .sidecarNotCopied })
    }

    /// A row an undo took back while the restore went is not written back
    /// as Copied: only a Copied row's File info and Reason change.
    @Test func restoreNeverRewritesAnUndoneRow() async throws {
        let fixture = try await runThatLostTheDates(count: 1)
        var item = try #require(try fixture.items().first)
        item.status = .undone
        try fixture.store.update(item)

        #expect(try !fixture.store.setRestoredInfo(runId: "R1", position: item.position, fileInfo: .kept, reason: nil))
        #expect(try fixture.items().first?.status == .undone)
        #expect(try fixture.items().first?.fileInfo == .datesNotKept)
    }

    /// Not beside the run itself (or the helper's runner, which holds the
    /// same claim).
    @Test func restoreRefusesAClaimedRun() async throws {
        let fixture = try await runThatLostTheDates(count: 1)
        #expect(CommonPhotosRunner.claim(runId: "R1", in: fixture.store.database))
        defer { CommonPhotosRunner.release(runId: "R1", in: fixture.store.database) }
        await #expect(throws: CommonPhotosInfoRestorer.Refusal.busy) {
            try await CommonPhotosInfoRestorer(client: fixture.nas, store: fixture.store).run("R1")
        }
    }

    /// Nothing to restore on a Move run, an undo, or rows that kept theirs.
    @Test func restoreCandidatesAreCopiedRowsWithoutInfo() async throws {
        let fixture = try CommonPhotosRunnerTests.Fixture(count: 1)
        fixture.nas.infos["A/IMG_1.JPG"] = RemoteFileInfo(modified: Self.old)
        try await fixture.start()
        try await fixture.runner.run("R1")
        let run = try #require(try fixture.store.run(id: "R1"))
        #expect(CommonPhotosInfoRestorer.candidates(try fixture.items(), run: run).isEmpty)
        var moveRun = run
        moveRun.action = .move
        var lost = try #require(try fixture.items().first)
        lost.fileInfo = .datesNotKept
        #expect(CommonPhotosInfoRestorer.candidates([lost], run: moveRun).isEmpty)
        #expect(CommonPhotosInfoRestorer.candidates([lost], run: run).count == 1)
    }

    // MARK: Server Upload and Backup (T6)

    /// AC-219 (Upload) + AC-220: a Photos photo taken 2025-10-12 14:03:27
    /// lands created and modified then; the folder's listing shows that
    /// date, so On Server's check of a listing taken after the upload finds
    /// the copy the same, never re-dated under it.
    @Test func uploadCarriesTheCaptureDate() async throws {
        let taken = Date(timeIntervalSince1970: 1_760_277_807)
        let fixture = UploadFixture(count: 1, bytes: 2_000)
        var item = fixture.items[0]
        item.takenAt = taken
        let client = InMemoryRemoteFileClient()
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder).run([item])

        #expect(result.outcomes == [.uploaded(remotePath: item.remotePath)])
        #expect(result.fileInfo == [.kept])
        #expect(try await client.fileInfo(at: item.remotePath) == RemoteFileInfo(modified: taken, created: taken))
        let entry = try await client.entries(in: ServerUploadPath.parent(of: item.remotePath)).first { $0.name == item.file.filename }
        #expect(entry?.modified == taken)
        // What a listing after the upload records, checked against the server as it is now.
        #expect(ServerCopyVerification.compare(size: 2_000, modifiedAt: Int(taken.timeIntervalSince1970), entry: entry) == .same)
        // Dated before the rename: the info lands on the part, never on the real name after it.
        #expect(!client.commands.contains("info \(item.remotePath)"))
    }

    /// An upload with no capture date sets nothing — the server's clock.
    @Test func uploadWithoutACaptureDateSetsNothing() async throws {
        let fixture = UploadFixture(count: 1, bytes: 2_000)
        let client = InMemoryRemoteFileClient()
        let result = await makeSession(fixture, client: client, recorder: UploadRecorder()).run(fixture.items)
        #expect(!client.commands.contains { $0.hasPrefix("info ") })
        #expect(result.fileInfo.isEmpty)
    }

    /// An upload to a server that sets no dates says so in its result:
    /// what the model records for the connection's next sheet (§6e).
    @Test func uploadToAServerThatKeepsNoDatesSaysSo() async throws {
        let fixture = UploadFixture(count: 2, bytes: 2_000)
        let items = fixture.items.map { var item = $0; item.takenAt = Self.old; return item }
        let client = InMemoryRemoteFileClient()
        client.keepsDates = false
        let result = await makeSession(fixture, client: client, recorder: UploadRecorder()).run(items)
        #expect(result.datesNotKept == 2)
        #expect(ServerFileInfoSupport.keepsDates(from: result.fileInfo) == false)
    }

    /// AC-219 (Backup): a Photos asset's files are dated by when it was
    /// taken; a folder source's file by its own write time; a RAW's JPEG
    /// twin, whose own time the listing does not have, gets none.
    @Test @MainActor func backupCarriesTheSourceDates() async throws {
        let f = try BackupFixture(photos: 1, videos: 0)
        let taken = Date(timeIntervalSince1970: 1_643_760_000)
        let info = RemoteFileInfo(modified: taken, created: taken)
        f.source.replace(f.source.items.map { item in
            BackupSourceItem(itemKey: item.itemKey, date: item.date, isVideo: item.isVideo, album: item.album,
                             files: item.files.map { var file = $0; file.info = info; return file })
        })

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        let landed = try #require(f.remoteFiles.keys.first)
        #expect(try await f.client.fileInfo(at: landed) == info)
        #expect(try ServerFileInfoSupport.keepsDates(connectionId: f.job.connectionId, in: f.database) == true)

        let own = SourceCopyBackupSource.file(path: "2022/IMG_9.CR3", size: 25_000_000, modified: 1_643_760_000)
        #expect(own.info == RemoteFileInfo(modified: taken))
        #expect(SourceCopyBackupSource.file(path: "2022/IMG_9.JPG", size: 0, modified: 1_643_760_000).info == nil)
    }

    // MARK: Files folder (AC-222)

    /// AC-222: a copy given the read-only (locked) flag can still be renamed
    /// (Undo, a later Move) and removed (Undo, a failed part's cleanup); it
    /// stays locked after the rename.
    @Test @MainActor func lockedCopyCanBeRemoved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2, 3]).write(to: url.appendingPathComponent("a.JPG.shotdex-part"))
        let described = FilesFolderClient.describe(url)
        let client = FilesFolderClient(server: FileServer(name: "Locked", transferProtocol: .files, host: described.service, username: "",
                                                          share: described.folder, bookmark: try url.bookmarkData()))
        try await client.connect()
        defer { Task { await client.disconnect() } }
        let info = RemoteFileInfo(modified: Self.old, created: Self.older, isReadOnly: true)

        let outcome = try await VerifiedRemoteWrite(client: client).moveIntoPlace("a.JPG", replacing: false, info: info)

        #expect(outcome == .kept)
        let landed = try #require(try await client.fileInfo(at: "a.JPG"))
        #expect(landed.isReadOnly)
        #expect(landed.hasSameModified(as: info))
        try await client.move("a.JPG", to: "b.JPG")
        #expect(try await client.fileInfo(at: "b.JPG")?.isReadOnly == true)
        try await client.remove("b.JPG")
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("b.JPG").path))
    }
}
