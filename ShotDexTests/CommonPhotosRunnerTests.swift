import CryptoKit
import Foundation
import os
import Testing
@testable import ShotDex

/// FS-19.08 §6: copying and moving the Same photos into the shared folder.
@Suite struct CommonPhotosRunnerTests {
    /// A NAS with `count` photos present in both `A` and `B`, scanned, and a
    /// run started on them.
    struct Fixture {
        let nas = InMemoryRemoteFileClient()
        let store: CommonPhotosStore
        let work: URL
        var runId = "R1"
        var photos: [String: Data] = [:]

        init(count: Int, layout: (Int) -> (a: String, b: String) = { ("IMG_\($0).JPG", "IMG_\($0).JPG") }) throws {
            store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosRunnerTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            for index in 1...count {
                let bytes = Data((0..<(1_000 + index)).map { UInt8(truncatingIfNeeded: $0 &+ index) })
                let (a, b) = layout(index)
                nas.put("A/\(a)", bytes)
                nas.put("B/\(b)", bytes)
                photos[a] = bytes
            }
            nas.addDirectory("C")
        }

        func start(action: CommonPhotosRun.Action = .copy) async throws {
            let scanner = CommonPhotosScanner(client: nas)
            let listing = try await scanner.list(["A", "B"])
            let found = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])
            let items = CommonPhotosRunner.items(for: found.sorted { $0.size < $1.size }, runId: runId, folders: ["A", "B"],
                                                 files: listing.files, sidecars: listing.sidecars)
            try store.start(CommonPhotosRun(id: runId, connectionId: "S1", folders: ["A", "B"], destination: "C", action: action),
                            items: items)
        }

        var runner: CommonPhotosRunner { CommonPhotosRunner(client: nas, store: store, workDirectory: work) }

        func items() throws -> [CommonPhotosItem] { try store.items(runId: runId) }
    }

    /// AC-121: five Same photos copied; each one read back and matched; the
    /// sources untouched; five Copied rows.
    @Test func copyVerifiesReadBack() async throws {
        let fixture = try Fixture(count: 5)
        try await fixture.start()
        let before = fixture.nas.files.filter { !$0.key.hasPrefix("C/") }

        try await fixture.runner.run("R1")

        let copied = fixture.nas.files.filter { $0.key.hasPrefix("C/") }
        #expect(copied.count == 5)
        for (name, bytes) in fixture.photos { #expect(copied["C/\(name)"] == bytes) }
        #expect(fixture.nas.files.filter { !$0.key.hasPrefix("C/") } == before)
        #expect(Set(fixture.nas.sha256Paths.filter { $0.hasPrefix("C/") }) == Set((1...5).map { "C/IMG_\($0).JPG.shotdex-part" }))
        let items = try fixture.items()
        #expect(items.map(\.status) == Array(repeating: .copied, count: 5))
        #expect(items.allSatisfy { $0.partPath == nil && $0.destinationPath?.hasPrefix("C/") == true })
        #expect(try fixture.store.run(id: "R1")?.state == .finishing)
    }

    /// AC-122: the third read-back is wrong — its part is removed, nothing
    /// under its real name, Failed "Checksum mismatch"; the other four Copied.
    @Test func copyMismatchLeavesNothing() async throws {
        let fixture = try Fixture(count: 5)
        try await fixture.start()
        fixture.nas.corruptReadBack = ["C/IMG_3.JPG.shotdex-part"]

        try await fixture.runner.run("R1")

        let files = fixture.nas.files
        #expect(files["C/IMG_3.JPG"] == nil)
        #expect(files["C/IMG_3.JPG.shotdex-part"] == nil)
        let items = try fixture.items()
        #expect(items.map(\.status) == [.copied, .copied, .failed, .copied, .copied])
        #expect(items[2].failure?.reason == .checksumMismatch)
        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.count == 10)
    }

    /// A source rewritten since the scan is not copied.
    @Test func changedSourceIsNotCopied() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        fixture.nas.put("A/IMG_1.JPG", Data(repeating: 7, count: 1_001))

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil)
        #expect(try fixture.items().map(\.status) == [.failed, .copied])
        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
    }

    /// A lost connection stops the run, paused, with what is done kept.
    @Test func lostConnectionPauses() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        fixture.nas.dropConnectionOnDownload = 2

        await #expect(throws: RemoteFileError.connectionLost) { try await fixture.runner.run("R1") }

        #expect(try fixture.store.run(id: "R1")?.state == .paused)
        #expect(try fixture.items().map(\.status) == [.copied, .pending, .pending])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// No room on this Mac: stopped before the download, paused.
    @Test func noRoomStops() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        var runner = fixture.runner
        runner.freeBytes = { 100 }

        await #expect(throws: CommonPhotosRunner.Stop.noRoom) { try await runner.run("R1") }

        #expect(fixture.nas.downloadCount == 0)
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
        #expect(try fixture.items().map(\.status) == [.pending])
    }

    /// AC-126: the destination holds `IMG_1.JPG` with the same bytes and
    /// `IMG_2.JPG` with others — IMG_1 Skipped (already there), IMG_2 lands as
    /// `IMG_2 (2).JPG`; nothing written over.
    @Test func nameClashRules() async throws {
        var fixture = try Fixture(count: 2)
        try await fixture.start()
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)
        let other = Data(repeating: 5, count: 1_002)
        fixture.nas.put("C/img_2.jpg", other)
        fixture.photos = [:]

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.skipped, .copied])
        #expect(items[0].failure?.reason == .alreadyThere)
        #expect(items[1].destinationPath == "C/IMG_2 (2).JPG")
        #expect(fixture.nas.files["C/img_2.jpg"] == other)
        #expect(fixture.nas.files["C/IMG_2 (2).JPG"]?.count == 1_002)
        #expect(fixture.nas.downloadCount == 1)
    }

    /// Two different photos of one name in one run: the second takes the
    /// next free name, part file included.
    @Test func sameNameTwiceInOneRun() async throws {
        let fixture = try Fixture(count: 2, layout: { ("\($0)/IMG.JPG", "\($0)/IMG.JPG") })
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.destinationPath) == ["C/IMG.JPG", "C/IMG (2).JPG"])
        #expect(fixture.nas.files["C/IMG.JPG"] == fixture.photos["1/IMG.JPG"])
        #expect(fixture.nas.files["C/IMG (2).JPG"] == fixture.photos["2/IMG.JPG"])
    }

    /// A source that cannot be read fails that photo; the run goes on.
    @Test func unreadableSourceFailsOnePhoto() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        fixture.nas.refuseDownload = (2, .permissionDenied("A/IMG_2.JPG"))

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.copied, .failed, .copied])
        #expect(items[1].failure?.reason == .serverError)
    }

    /// Cancel mid-copy: the run pauses, the photo goes back to pending, no
    /// part is left, nothing is called failed.
    @Test func cancelLeavesNoPart() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        let runner = fixture.runner
        let task = Task { try await runner.run("R1") }
        fixture.nas.onUpload = { number in if number == 2 { task.cancel() } }

        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(try fixture.items().map(\.status) == [.copied, .pending])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
    }

    /// A photo a stopped run left mid-copy that is already in place with the
    /// scanned bytes is Copied without another transfer.
    @Test func copyingFoundInPlace() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        var item = try #require(try fixture.items().first)
        item.status = .copying
        item.destinationPath = "C/IMG_1.JPG"
        item.partPath = "C/IMG_1.JPG.shotdex-part"
        try fixture.store.update(item)
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.copied])
        #expect(fixture.nas.downloadCount == 0)
    }

    /// Progress moves through the steps of each photo and ends full.
    @Test func progressEndsFull() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        let reports = OSAllocatedUnfairLock(initialState: [CommonPhotosRunner.Progress]())

        try await fixture.runner.run("R1", progress: { report in reports.withLock { $0.append(report) } })

        let all = reports.withLock { $0 }
        let last = try #require(all.last)
        #expect(last.doneCount == 2)
        #expect(last.doneBytes == last.totalBytes)
        #expect(all.map(\.doneBytes) == all.map(\.doneBytes).sorted())
        let steps = all.compactMap(\.currentStep).reduce(into: [CommonPhotosRunner.Progress.Step]()) { if $0.last != $1 { $0.append($1) } }
        #expect(steps == [.downloading, .uploading, .readingBack, .downloading, .uploading, .readingBack])
    }

    /// AC-127: a photo in `A/2025/06/` and `B/x/` lands flat in the
    /// destination, its `.xmp` beside it under the photo's final name.
    @Test func flatDestinationWithSidecar() async throws {
        let fixture = try Fixture(count: 2, layout: { index in
            index == 1 ? ("2025/06/IMG_1.JPG", "x/IMG_1.JPG") : ("2025/07/IMG_1.JPG", "y/IMG_1.JPG")
        })
        let xmp = Data("<x:xmpmeta rating=5/>".utf8)
        fixture.nas.put("A/2025/06/IMG_1.xmp", xmp)
        fixture.nas.put("B/y/IMG_1.XMP", Data("<x:xmpmeta rating=2/>".utf8))
        try await fixture.start()

        try await fixture.runner.run("R1")

        let destination = fixture.nas.files.filter { $0.key.hasPrefix("C/") }
        #expect(Set(destination.keys) == ["C/IMG_1.JPG", "C/IMG_1.xmp", "C/IMG_1 (2).JPG", "C/IMG_1 (2).XMP"])
        #expect(destination["C/IMG_1.xmp"] == xmp)
        // Photo 2 is copied from A, which has no sidecar: B's goes with it.
        #expect(destination["C/IMG_1 (2).XMP"] == Data("<x:xmpmeta rating=2/>".utf8))
        #expect(destination["C/IMG_1.JPG"] == fixture.photos["2025/06/IMG_1.JPG"])
    }

    /// FS-19.01 §3: beside a RAW, `IMG_1.xmp` is the RAW's — the JPEG takes
    /// only `IMG_1.JPG.xmp`, and keeps that full-name form in the destination.
    @Test func rawSidecarStaysWithTheRaw() async throws {
        let fixture = try Fixture(count: 2)
        fixture.nas.put("A/IMG_1.CR3", Data(repeating: 9, count: 5_000))
        fixture.nas.put("A/IMG_1.xmp", Data("raw".utf8))
        fixture.nas.put("A/IMG_2.CR3", Data(repeating: 8, count: 6_000))
        fixture.nas.put("A/IMG_2.JPG.xmp", Data("jpeg".utf8))
        try await fixture.start()

        try await fixture.runner.run("R1")

        let destination = fixture.nas.files.filter { $0.key.hasPrefix("C/") }
        #expect(Set(destination.keys) == ["C/IMG_1.JPG", "C/IMG_2.JPG", "C/IMG_2.JPG.xmp"])
        #expect(destination["C/IMG_2.JPG.xmp"] == Data("jpeg".utf8))
    }

    /// A stop while the sidecar copies leaves the photo in place; Resume
    /// finds it there, copies the sidecar and calls it Copied.
    @Test func sidecarRetriedOnResume() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("rating".utf8))
        try await fixture.start()
        fixture.nas.dropConnectionOnDownload = 2

        await #expect(throws: RemoteFileError.connectionLost) { try await fixture.runner.run("R1") }
        #expect(try fixture.items().map(\.status) == [.copying])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        fixture.nas.dropConnectionOnDownload = nil
        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.copied])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("rating".utf8))
        #expect(fixture.nas.uploadCount == 2)
    }

    /// A photo already in the destination is Skipped; its missing sidecar is
    /// put beside it.
    @Test func skippedPhotoGetsItsSidecar() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("rating".utf8))
        try await fixture.start()
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.skipped])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("rating".utf8))
    }

    /// A sidecar name already taken in the destination is left alone; the
    /// photo is still Copied.
    @Test func sidecarNeverOverwrites() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("new".utf8))
        fixture.nas.put("C/IMG_1.xmp", Data("theirs".utf8))
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("theirs".utf8))
        #expect(try fixture.items().map(\.status) == [.copied])
        #expect(try fixture.items().first?.failure?.reason == .sidecarNotCopied)
        #expect(fixture.nas.uploadCount == 1)
    }

    /// AC-123: five Same photos, Move, one share — renamed into place, never
    /// downloaded; both sources gone; five Moved.
    @Test func moveRenamesThenDeletes() async throws {
        let fixture = try Fixture(count: 5)
        try await fixture.start(action: .move)

        try await fixture.runner.run("R1")

        let files = fixture.nas.files
        #expect(files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.isEmpty)
        for (name, bytes) in fixture.photos { #expect(files["C/\(name)"] == bytes) }
        #expect(fixture.nas.commands.filter { $0.hasPrefix("move A/") }.count == 5)
        #expect(fixture.nas.downloadCount == 0)
        let commands = fixture.nas.commands
        for index in 1...5 {
            let name = "IMG_\(index).JPG"
            let order = ["move A/\(name) → C/\(name)", "move B/\(name) → B/\(name).shotdex-removing", "remove B/\(name).shotdex-removing"]
            let positions = order.compactMap { commands.firstIndex(of: $0) }
            #expect(positions.count == 3)
            #expect(positions == positions.sorted())
        }
        #expect(try fixture.items().map(\.status) == Array(repeating: .moved, count: 5))
        #expect(try fixture.items().allSatisfy { $0.sources.allSatisfy(\.isRemoved) })
    }

    /// AC-124: the server will not rename across shares — copied, read back,
    /// only then the sources removed.
    @Test func crossShareMoveCopiesFirst() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start(action: .move)
        fixture.nas.refusesMovesAcrossTopFolders = true

        try await fixture.runner.run("R1")

        let commands = fixture.nas.commands
        for index in 1...2 {
            let name = "IMG_\(index).JPG"
            let order = ["move A/\(name) → C/\(name)", "download A/\(name)", "upload C/\(name).shotdex-part",
                         "sha256 C/\(name).shotdex-part", "move C/\(name).shotdex-part → C/\(name)",
                         "remove A/\(name).shotdex-removing", "remove B/\(name).shotdex-removing"]
            let positions = order.map { commands.firstIndex(of: $0) }
            #expect(positions.allSatisfy { $0 != nil })
            #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
        }
        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.isEmpty)
        #expect(try fixture.items().map(\.status) == [.moved, .moved])
    }

    /// AC-125: B's copy changed size after the scan — it is kept, the photo
    /// fails "changed on server", the destination copy stays.
    @Test func changedSourceNotDeleted() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        fixture.nas.put("B/IMG_1.JPG", Data(repeating: 1, count: 2_000))

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files["B/IMG_1.JPG"]?.count == 2_000)
        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(try fixture.items().first?.status == .failed)
        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
    }

    /// A write time that moved since the scan also keeps the copy.
    @Test func changedWriteTimeNotDeleted() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.modified = ["A/IMG_1.JPG": Date(timeIntervalSince1970: 100), "B/IMG_1.JPG": Date(timeIntervalSince1970: 200)]
        try await fixture.start(action: .move)
        fixture.nas.modified["B/IMG_1.JPG"] = Date(timeIntervalSince1970: 300)

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files["B/IMG_1.JPG"] != nil)
        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
    }

    /// A rename the server did before the reply was lost: Resume finds the
    /// photo in place and removes the rest.
    @Test func moveResumesAfterLostReply() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        var item = try #require(try fixture.items().first)
        item.status = .moving
        item.destinationPath = "C/IMG_1.JPG"
        item.movedFrom = "A/IMG_1.JPG"
        try fixture.store.update(item)
        try await fixture.nas.move("A/IMG_1.JPG", to: "C/IMG_1.JPG")

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.moved])
        #expect(fixture.nas.files["B/IMG_1.JPG"] == nil)
        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(fixture.nas.downloadCount == 0)
    }

    /// The rename is done but its reply is an error: the photo is found in
    /// place, not copied again.
    @Test func renameReplyLostButDone() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        fixture.nas.failMoveAfterDoing = true

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.moved])
        #expect(fixture.nas.downloadCount == 0)
        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
    }

    /// A source removed by a stop before it was recorded is not "changed":
    /// Resume finishes the photo Moved.
    @Test func removedBeforeRecordedIsNotChanged() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        var item = try #require(try fixture.items().first)
        try await fixture.nas.move("A/IMG_1.JPG", to: "C/IMG_1.JPG")
        item.status = .placed
        item.destinationPath = "C/IMG_1.JPG"
        item.movedFrom = "A/IMG_1.JPG"
        item.sources[0].isRemoved = true
        try fixture.store.update(item)
        fixture.nas.drop("B/IMG_1.JPG")

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.moved])
    }

    /// A copy set aside and not yet deleted is deleted on Resume.
    @Test func setAsideCopyIsDeletedOnResume() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        var item = try #require(try fixture.items().first)
        try await fixture.nas.move("A/IMG_1.JPG", to: "C/IMG_1.JPG")
        item.status = .placed
        item.destinationPath = "C/IMG_1.JPG"
        item.sources[0].isRemoved = true
        try fixture.store.update(item)
        try await fixture.nas.move("B/IMG_1.JPG", to: "B/IMG_1.JPG.shotdex-removing")

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.moved])
        #expect(!fixture.nas.files.keys.contains { $0.hasPrefix("B/") })
    }

    /// The first source rewritten at the same size since the scan: not
    /// moved, no copy touched.
    @Test func sameSizeEditOfTheFirstSourceIsNotMoved() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        fixture.nas.put("A/IMG_1.JPG", Data(repeating: 3, count: 1_001))

        try await fixture.runner.run("R1")

        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
        #expect(fixture.nas.files["A/IMG_1.JPG"] != nil)
        #expect(fixture.nas.files["B/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil)
    }

    /// The destination replaced while the run was paused: Resume proves it
    /// again and removes nothing.
    @Test func destinationChangedWhilePaused() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        var item = try #require(try fixture.items().first)
        try await fixture.nas.move("A/IMG_1.JPG", to: "C/IMG_1.JPG")
        item.status = .placed
        item.destinationPath = "C/IMG_1.JPG"
        item.sources[0].isRemoved = true
        try fixture.store.update(item)
        fixture.nas.put("C/IMG_1.JPG", Data(repeating: 4, count: 1_001))

        try await fixture.runner.run("R1")

        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
        #expect(fixture.nas.files["B/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
    }

    /// Two paths to one file: setting the source aside makes the destination
    /// vanish — the source is put back and the run stops.
    @Test func destinationThatIsASourceStopsTheRun() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        let nas = fixture.nas
        nas.onMove = { from, to in
            if from == "B/IMG_1.JPG", to.hasSuffix(".shotdex-removing") { nas.drop("C/IMG_1.JPG") }
        }

        await #expect(throws: CommonPhotosRunner.Stop.destinationIsASource) { try await fixture.runner.run("R1") }

        #expect(nas.files["B/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
    }

    /// A destination inside a source is refused before anything runs.
    @Test func destinationInsideASourceIsRefused() async throws {
        let fixture = try Fixture(count: 1)
        let listing = try await CommonPhotosScanner(client: fixture.nas).list(["A", "B"])
        let found = try await CommonPhotosVerifier(client: fixture.nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])
        try fixture.store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "B/Shared", action: .move),
                                items: CommonPhotosRunner.items(for: found, runId: "R1", folders: ["A", "B"]))

        await #expect(throws: CommonPhotosRunner.Stop.destinationIsASource) { try await fixture.runner.run("R1") }

        #expect(fixture.nas.commands.isEmpty)
    }

    /// `IMG_1.JPG` and `IMG_1.MOV` share `IMG_1.xmp`: it stays in the source
    /// until both are moved, then goes.
    @Test func sharedSidecarWaitsForTheLastPhoto() async throws {
        let fixture = try Fixture(count: 1)
        let movie = Data(repeating: 6, count: 5_000)
        fixture.nas.put("A/IMG_1.MOV", movie)
        fixture.nas.put("B/IMG_1.MOV", movie)
        fixture.nas.put("A/IMG_1.xmp", Data("edits".utf8))
        fixture.nas.put("B/IMG_1.xmp", Data("edits".utf8))
        try await fixture.start(action: .move)

        try await fixture.runner.run("R1")

        let commands = fixture.nas.commands
        // The JPEG runs first (smaller) and leaves the shared sidecar; the
        // movie's turn removes it.
        let firstPhotoDone = try #require(commands.lastIndex { $0.hasPrefix("remove B/IMG_1.JPG") })
        let movieStarts = try #require(commands.firstIndex { $0.hasPrefix("move A/IMG_1.MOV") })
        let sidecarRemove = try #require(commands.firstIndex { $0.hasPrefix("remove A/IMG_1.xmp") })
        #expect(sidecarRemove > firstPhotoDone && sidecarRemove > movieStarts)
        #expect(try fixture.items().map(\.status) == [.moved, .moved])
        #expect(fixture.nas.files["C/IMG_1.xmp"] == Data("edits".utf8))
        #expect(fixture.nas.files["A/IMG_1.xmp"] == nil && fixture.nas.files["B/IMG_1.xmp"] == nil)
    }

    /// A moving row missing what it was moving is reset, never removed from.
    @Test func damagedMovingRowStartsOver() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        var item = try #require(try fixture.items().first)
        item.status = .moving
        item.destinationPath = "C/IMG_1.JPG"
        try fixture.store.update(item)

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.moved])
        #expect(fixture.nas.files["C/IMG_1.JPG"] == fixture.photos["IMG_1.JPG"])
    }

    /// Move takes the sidecars along: identical ones go, one with other
    /// edits is kept and noted.
    @Test func moveSidecars() async throws {
        let fixture = try Fixture(count: 2)
        fixture.nas.put("A/IMG_1.xmp", Data("same".utf8))
        fixture.nas.put("B/IMG_1.xmp", Data("same".utf8))
        fixture.nas.put("A/IMG_2.xmp", Data("rating=5".utf8))
        fixture.nas.put("B/IMG_2.xmp", Data("rating=1".utf8))
        try await fixture.start(action: .move)

        try await fixture.runner.run("R1")

        let files = fixture.nas.files
        #expect(files["C/IMG_1.xmp"] == Data("same".utf8))
        #expect(files["A/IMG_1.xmp"] == nil && files["B/IMG_1.xmp"] == nil)
        #expect(files["C/IMG_2.xmp"] == Data("rating=5".utf8))
        #expect(files["A/IMG_2.xmp"] == nil)
        #expect(files["B/IMG_2.xmp"] == Data("rating=1".utf8))
        let items = try fixture.items()
        #expect(items.map(\.status) == [.moved, .moved])
        #expect(items[1].failure?.reason == .sidecarNotCopied)
    }

    /// A Move whose photo already sits in the destination removes the
    /// sources and says so.
    @Test func moveAlreadyThere() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start(action: .move)
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.isEmpty)
        #expect(try fixture.items().first?.status == .moved)
        #expect(try fixture.items().first?.failure?.reason == .alreadyThere)
        #expect(fixture.nas.downloadCount == 0 && fixture.nas.uploadCount == 0)
    }

    /// AC-128: ten photos, the connection lost on the fifth; Resume carries
    /// on from the fifth, the first four not read again; ten log rows.
    @Test(arguments: [CommonPhotosRun.Action.copy, .move]) func resumeAfterDisconnect(action: CommonPhotosRun.Action) async throws {
        let fixture = try Fixture(count: 10)
        try await fixture.start(action: action)
        if action == .copy {
            fixture.nas.dropConnectionOnDownload = 5
        } else {
            // Renamed on the server, then the line drops before it is checked.
            let nas = fixture.nas
            nas.onMove = { from, _ in if from == "A/IMG_5.JPG" { nas.entriesError = .connectionLost } }
        }

        await #expect(throws: RemoteFileError.connectionLost) { try await fixture.runner.run("R1") }
        let done = try fixture.items().filter(\.isDone).map(\.position)
        #expect(done == [0, 1, 2, 3])
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
        let fifth = try #require(try fixture.items().dropFirst(4).first)
        #expect(fifth.status == (action == .copy ? .pending : .moving))
        let before = fixture.nas.commands.count
        let reports = OSAllocatedUnfairLock(initialState: [CommonPhotosRunner.Progress]())
        fixture.nas.dropConnectionOnDownload = nil
        fixture.nas.onMove = nil
        fixture.nas.entriesError = nil

        try await fixture.runner.run("R1", progress: { report in reports.withLock { $0.append(report) } })

        let later = fixture.nas.commands.dropFirst(before)
        for index in 1...4 { #expect(!later.contains { $0.contains("/IMG_\(index).JPG") }) }
        let first = try #require(reports.withLock { $0.first })
        #expect(first.doneCount == 4 && first.totalCount == 10)
        let items = try fixture.items()
        #expect(items.count == 10)
        #expect(items.map(\.status) == Array(repeating: action == .copy ? .copied : .moved, count: 10))
        #expect(items.allSatisfy { $0.partPath == nil && $0.destinationPath != nil })
        let destination = fixture.nas.files.filter { $0.key.hasPrefix("C/") }
        #expect(destination.count == 10)
        for (name, bytes) in fixture.photos { #expect(destination["C/\(name)"] == bytes) }
        let sources = fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }
        #expect(sources.count == (action == .copy ? 20 : 0))
    }

    /// Resume pressed twice: the second runner is turned away while the
    /// first goes on, and the banner sees the run as going.
    @Test func secondRunnerIsTurnedAway() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        let runner = fixture.runner
        let database = fixture.store.database
        let second = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
        let wasActive = OSAllocatedUnfairLock(initialState: false)
        fixture.nas.whileUploading = { number in
            guard number == 1 else { return }
            wasActive.withLock { $0 = CommonPhotosRunner.isActive(runId: "R1", in: database) }
            do { try await runner.run("R1") } catch { second.withLock { $0 = error } }
        }

        try await runner.run("R1")

        #expect(wasActive.withLock { $0 })
        #expect(second.withLock { $0 as? CommonPhotosRunner.Stop } == .alreadyRunning)
        #expect(!CommonPhotosRunner.isActive(runId: "R1", in: database))
        #expect(try fixture.items().map(\.status) == [.copied, .copied])
    }

    /// A process killed mid-copy: the run is left `running`, one photo
    /// `copying` with its part on the server. Resume removes the part, copies
    /// it under its own name, and reads nothing it had done.
    @Test func killedMidCopyResumes() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        var items = try fixture.items()
        for index in 0..<2 {
            fixture.nas.put("C/IMG_\(index + 1).JPG", fixture.photos["IMG_\(index + 1).JPG"]!)
            items[index].status = .copied
            items[index].destinationPath = "C/IMG_\(index + 1).JPG"
            try fixture.store.update(items[index])
        }
        items[2].status = .copying
        items[2].destinationPath = "C/IMG_3.JPG"
        items[2].partPath = "C/IMG_3.JPG.shotdex-part"
        try fixture.store.update(items[2])
        fixture.nas.put("C/IMG_3.JPG.shotdex-part", Data(repeating: 0, count: 500))
        #expect(try fixture.store.run(id: "R1")?.state == .running)

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.copied, .copied, .copied])
        #expect(Set(fixture.nas.files.keys.filter { $0.hasPrefix("C/") }) == ["C/IMG_1.JPG", "C/IMG_2.JPG", "C/IMG_3.JPG"])
        #expect(fixture.nas.files["C/IMG_3.JPG"] == fixture.photos["IMG_3.JPG"])
        #expect(fixture.nas.commands.filter { $0.hasPrefix("download") } == ["download A/IMG_3.JPG"])
    }

    /// A run killed after its last photo (`finishing`) is accepted by Resume.
    @Test func finishingRunResumes() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        try await fixture.runner.run("R1")
        let commands = fixture.nas.commands.count

        try await fixture.runner.run("R1")

        #expect(try fixture.store.run(id: "R1")?.state == .finishing)
        #expect(fixture.nas.commands.count == commands)
    }

    /// A stopped run is not resumed.
    @Test func stoppedRunIsNotResumed() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        try fixture.store.markState(.stopped, runId: "R1")

        await #expect(throws: CommonPhotosRunner.Stop.notResumable) { try await fixture.runner.run("R1") }
    }
}
