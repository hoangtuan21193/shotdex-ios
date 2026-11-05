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
        #expect(CommonPhotosLog.csv(rows, isUndo: true).contains(",dates not kept\r\n"))
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
        #expect(csv.text.contains(",dates not kept\r\n"))

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
