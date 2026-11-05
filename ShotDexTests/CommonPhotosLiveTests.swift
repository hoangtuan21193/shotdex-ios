import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6f: a Live Photo's still and motion are held together — Same
/// only as a pair, one name and one folder in the destination, never parted
/// by a Move.
@Suite struct CommonPhotosLiveTests {
    private static func file(_ folder: Int, _ path: String, _ size: Int64) -> CommonPhotosFile {
        CommonPhotosFile(folder: folder, relativePath: path, size: size, modified: nil)
    }

    private static func photo(_ sha: String, _ files: [[CommonPhotosFile]]) -> CommonPhoto {
        CommonPhoto(sha256: sha, size: files[0][0].size, files: files)
    }

    @Test func partnersAreOneStillAndOneMotionOfOneName() {
        let files = [[Self.file(0, "a/IMG_1.HEIC", 10), Self.file(0, "a/IMG_1.MOV", 20),
                      Self.file(0, "a/IMG_2.JPG", 30), Self.file(0, "a/IMG_2.HEIC", 31), Self.file(0, "a/IMG_2.MOV", 32),
                      Self.file(0, "b/IMG_1.MOV", 40)]]
        let partners = CommonPhotosLive.partners(in: files)
        #expect(partners[files[0][0]] == files[0][1])
        #expect(partners[files[0][1]] == files[0][0])
        // Two stills for one motion: whose it is cannot be told.
        #expect(partners[files[0][4]] == nil)
        // Another folder, another photo.
        #expect(partners[files[0][5]] == nil)
    }

    @Test func pairKeptStillThenMotion() {
        let still = [[Self.file(0, "IMG_1.HEIC", 10)], [Self.file(1, "IMG_1.HEIC", 10)]]
        let motion = [[Self.file(0, "IMG_1.MOV", 20)], [Self.file(1, "IMG_1.MOV", 20)]]
        let other = [[Self.file(0, "DSC_9.JPG", 30)], [Self.file(1, "DSC_9.JPG", 30)]]
        let files = [still[0] + motion[0] + other[0], still[1] + motion[1] + other[1]]
        // Found motion first: the still is put before it.
        let result = CommonPhotosLive.pair([Self.photo("m", motion), Self.photo("o", other), Self.photo("s", still)], files: files)
        #expect(result.photos.map(\.sha256) == ["s", "m", "o"])
        #expect(result.motionOf == ["s": "m"])
        #expect(result.split.isEmpty)
    }

    /// The motion differs in one folder: neither half is Same alone.
    @Test func motionNotSameSplitsTheStill() {
        let still = [[Self.file(0, "IMG_1.HEIC", 10)], [Self.file(1, "IMG_1.HEIC", 10)]]
        let files = [still[0] + [Self.file(0, "IMG_1.MOV", 20)], still[1] + [Self.file(1, "IMG_1.MOV", 21)]]
        let result = CommonPhotosLive.pair([Self.photo("s", still)], files: files)
        #expect(result.photos.isEmpty)
        #expect(result.split.map(\.sha256) == ["s"])
    }

    /// One folder holds only the still (exported, motion lost): the still
    /// there is no Live Photo, so the pair is not whole.
    @Test func motionMissingInOneFolderSplitsBoth() {
        let still = [[Self.file(0, "IMG_1.HEIC", 10)], [Self.file(1, "IMG_1.HEIC", 10)]]
        let motion = [[Self.file(0, "IMG_1.MOV", 20)], [Self.file(1, "x/IMG_7.MOV", 20)]]
        let files = [still[0] + motion[0], still[1] + motion[1]]
        let result = CommonPhotosLive.pair([Self.photo("s", still), Self.photo("m", motion)], files: files)
        #expect(result.photos.isEmpty)
        #expect(Set(result.split.map(\.sha256)) == ["s", "m"])
    }

    @Test func freeNameKeepsTheMotionNameFree() {
        #expect(CommonPhotosLive.freeName(forStill: "IMG_1.HEIC", motionExtension: "MOV", existing: []) == "IMG_1.HEIC")
        // The still's name is free, its motion's is not.
        #expect(CommonPhotosLive.freeName(forStill: "IMG_1.HEIC", motionExtension: "MOV", existing: ["img_1.mov"]) == "IMG_1 (2).HEIC")
        #expect(CommonPhotosLive.freeName(forStill: "IMG_1.HEIC", motionExtension: "MOV",
                                          existing: ["IMG_1.HEIC", "IMG_1 (2).MOV"]) == "IMG_1 (3).HEIC")
    }

    @Test func planNamesThePairTogether() {
        let photos = [CommonPhotosDestinationPlan.Photo(name: "IMG_1.HEIC", size: 10, sha256: "s"),
                      CommonPhotosDestinationPlan.Photo(name: "IMG_1.MOV", size: 20, sha256: "m")]
        let there = [CommonPhotosDestinationPlan.Existing(name: "IMG_1.HEIC", size: 10, sha256: "other")]
        let landings = CommonPhotosDestinationPlan.landings(photos, in: there, motionOf: [0: 1])
        #expect(landings == [.name("IMG_1 (2).HEIC"), .name("IMG_1 (2).MOV")])
        // Both already there: both skipped under their names.
        let both = [CommonPhotosDestinationPlan.Existing(name: "IMG_1.HEIC", size: 10, sha256: "s"),
                    CommonPhotosDestinationPlan.Existing(name: "IMG_1.MOV", size: 20, sha256: "m")]
        #expect(CommonPhotosDestinationPlan.landings(photos, in: both, motionOf: [0: 1])
                == [.alreadyThere("IMG_1.HEIC"), .alreadyThere("IMG_1.MOV")])
    }

    /// Live Photos in `A` and `B`, scanned, paired, a run started.
    struct Fixture {
        let nas = InMemoryRemoteFileClient()
        let store: CommonPhotosStore
        let work: URL
        let still = Data((0..<1_500).map { UInt8(truncatingIfNeeded: $0) })
        let motion = Data((0..<3_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })

        init() throws {
            store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosLiveTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            for folder in ["A", "B"] {
                nas.put("\(folder)/IMG_1.HEIC", still)
                nas.put("\(folder)/IMG_1.MOV", motion)
            }
            nas.addDirectory("C")
        }

        /// `stillPlacement`: where the scan's plan filed the still (§6e).
        func start(action: CommonPhotosRun.Action, organize: BackupOrganize? = nil, stillPlacement: String? = nil) async throws {
            let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
            let found = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])
            // Largest first, as the verifier may: the motion before its still.
            let paired = CommonPhotosLive.pair(found.sorted { $0.size > $1.size }, files: listing.files)
            #expect(paired.motionOf.count == 1)
            var items = CommonPhotosRunner.items(for: paired.photos, runId: "R1", folders: ["A", "B"],
                                                 files: listing.files, sidecars: listing.sidecars)
            items[0].placement = stillPlacement
            var run = CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: action)
            run.organize = organize
            try store.start(run, items: items)
        }

        var runner: CommonPhotosRunner { CommonPhotosRunner(client: nas, store: store, workDirectory: work) }
    }

    /// The still's name is taken by other bytes: both halves move to the
    /// next free name together.
    @Test func copyKeepsOneNameForThePair() async throws {
        let fixture = try Fixture()
        try await fixture.start(action: .copy)
        fixture.nas.put("C/IMG_1.HEIC", Data(repeating: 9, count: 1_500))

        try await fixture.runner.run("R1")

        let items = try fixture.store.items(runId: "R1")
        #expect(items.map(\.destinationPath) == ["C/IMG_1 (2).HEIC", "C/IMG_1 (2).MOV"])
        #expect(fixture.nas.files["C/IMG_1 (2).HEIC"] == fixture.still)
        #expect(fixture.nas.files["C/IMG_1 (2).MOV"] == fixture.motion)
        #expect(fixture.nas.files["C/IMG_1.MOV"] == nil)
    }

    /// Move: the still changed on the server, so it stays — and its motion
    /// stays beside it in every folder.
    @Test func moveNeverPartsThePair() async throws {
        let fixture = try Fixture()
        try await fixture.start(action: .move)
        fixture.nas.put("A/IMG_1.HEIC", Data(repeating: 4, count: 1_500))

        try await fixture.runner.run("R1")

        let items = try fixture.store.items(runId: "R1")
        #expect(items.map(\.status) == [.failed, .failed])
        #expect(items[1].failure?.reason == .liveStillFailed)
        for folder in ["A", "B"] {
            #expect(fixture.nas.files["\(folder)/IMG_1.MOV"] == fixture.motion)
            #expect(fixture.nas.files["\(folder)/IMG_1.HEIC"] != nil)
        }
        #expect(fixture.nas.files["C/IMG_1.MOV"] == nil)
    }

    /// Organize files the motion beside its still, by the still's date.
    @Test func organizeFilesTheMotionBesideItsStill() async throws {
        let fixture = try Fixture()
        var organize = BackupOrganize()
        organize.levels = .yearMonthDay
        try await fixture.start(action: .copy, organize: organize, stillPlacement: "2025/06/01/IMG_1.HEIC")

        try await fixture.runner.run("R1")

        let done = try fixture.store.items(runId: "R1")
        #expect(done.map(\.destinationPath) == ["C/2025/06/01/IMG_1.HEIC", "C/2025/06/01/IMG_1.MOV"])
    }

    /// AC-228, AC-229, AC-233 through the sheet: the pair listed still then
    /// motion, tagged Live; a split pair counted, not listed; unchecking one
    /// half unchecks the other.
    @MainActor
    @Test func sheetHoldsThePairTogether() async throws {
        let fixture = try Fixture()
        // A second Live Photo whose motion differs in B: left out.
        fixture.nas.put("A/IMG_2.HEIC", Data(repeating: 1, count: 1_700))
        fixture.nas.put("B/IMG_2.HEIC", Data(repeating: 1, count: 1_700))
        fixture.nas.put("A/IMG_2.MOV", Data(repeating: 2, count: 2_500))
        fixture.nas.put("B/IMG_2.MOV", Data(repeating: 3, count: 2_500))
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: fixture.nas)
        sheet.destination = "C"
        sheet.scan()
        for _ in 0..<200 where sheet.isScanning || sheet.phase == .idle {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(sheet.rows.map(\.name) == ["IMG_1.HEIC", "IMG_1.MOV"])
        #expect(sheet.rows.filter { !$0.isLive }.isEmpty)
        #expect(sheet.liveLeftOutCount == 1)
        sheet.setIncluded(false, rows: [sheet.rows[1].id])
        #expect(sheet.rows.map(\.isIncluded) == [false, false])
        sheet.setIncluded(true, rows: [sheet.rows[0].id])
        #expect(sheet.rows.map(\.isIncluded) == [true, true])
        await sheet.close()
    }

    /// An incremental scan (§6c) cut away the half it saw before: the cut
    /// puts it back, so the new half is checked with its mate.
    @Test func incrementalCutKeepsTheMate() {
        let still = Self.file(0, "IMG_1.HEIC", 10), motion = Self.file(0, "IMG_1.MOV", 20), other = Self.file(0, "DSC_9.JPG", 30)
        let all = [[still, motion, other]]
        #expect(CommonPhotosLive.keepingMates([[still]], from: all) == [[still, motion]])
        #expect(CommonPhotosLive.keepingMates([[other]], from: all) == [[other]])
        let paired = CommonPhotosLive.Result(photos: [Self.photo("s", [[still]]), Self.photo("m", [[motion]]), Self.photo("o", [[other]])],
                                             split: [], motionOf: ["s": "m"])
        #expect(CommonPhotosLive.withMates([Self.photo("m", [[motion]])], in: paired).map(\.sha256) == ["s", "m"])
        #expect(CommonPhotosLive.withMates([Self.photo("o", [[other]])], in: paired).map(\.sha256) == ["o"])
    }

    /// Two stills of one name and a motion: no Live Photo — and the motion
    /// never lands right after a still of its name, where the run would
    /// take the two for a pair.
    @Test func motionOfTwoStillsNeverFollowsOne() {
        let a = [[Self.file(0, "IMG_1.HEIC", 10)], [Self.file(1, "IMG_1.HEIC", 10)]]
        let b = [[Self.file(0, "IMG_1.JPG", 11)], [Self.file(1, "IMG_1.JPG", 11)]]
        let m = [[Self.file(0, "IMG_1.MOV", 20)], [Self.file(1, "IMG_1.MOV", 20)]]
        let files = [a[0] + b[0] + m[0], a[1] + b[1] + m[1]]
        let result = CommonPhotosLive.pair([Self.photo("a", a), Self.photo("m", m)], files: files)
        #expect(result.motionOf.isEmpty)
        #expect(result.photos.map(\.sha256) == ["m", "a"])
    }

    /// Move: the motion changed on the server since the scan — the still
    /// is not moved either.
    @Test func moveChecksTheMotionBeforeTheStill() async throws {
        let fixture = try Fixture()
        try await fixture.start(action: .move)
        fixture.nas.put("B/IMG_1.MOV", Data(repeating: 6, count: 2_999))

        try await fixture.runner.run("R1")

        let items = try fixture.store.items(runId: "R1")
        #expect(items[0].failure?.reason == .liveMotionChanged)
        #expect(items.map(\.status) == [.failed, .failed])
        for folder in ["A", "B"] { #expect(fixture.nas.files["\(folder)/IMG_1.HEIC"] == fixture.still) }
        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("C/IMG_1") }.isEmpty)
    }

    /// Undo of one half undoes the pair.
    @Test func undoTakesThePair() async throws {
        let fixture = try Fixture()
        try await fixture.start(action: .copy)
        try await fixture.runner.run("R1")

        let undo = try fixture.store.startUndo(of: "R1", positions: [1])

        #expect(try fixture.store.items(runId: undo.id).count == 2)
    }
}
