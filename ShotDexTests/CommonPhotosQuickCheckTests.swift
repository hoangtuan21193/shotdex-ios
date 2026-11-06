import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6e Quick Check: a scan may take a photo at the same path, of
/// the same size, with matching samples, as Same — without reading every
/// byte. A Move reads every byte of it before it removes anything.
@Suite struct CommonPhotosQuickCheckTests {
    /// Bytes bigger than three samples, so the samples are not the file.
    static func photo(_ seed: UInt8, count: Int = 300_000) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    private func verify(_ nas: InMemoryRemoteFileClient, quick: Bool,
                        hashed: @escaping @Sendable ([CommonPhotosFile: String]) -> Void = { _ in }) async throws -> [CommonPhoto] {
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        return try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
                                                                 trustsCache: true, quick: quick, hashed: hashed)
    }

    /// AC-194: `A/2025/03/15/X.ARW` and `B/2025/03/15/x.arw`, same bytes:
    /// Same, quick — three range reads each, no SHA-256, no download.
    @Test func samePathIsQuick() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/x.arw", Self.photo(1))

        let photos = try await verify(nas, quick: true)

        #expect(photos.count == 1)
        #expect(photos.first?.isQuick == true)
        #expect(nas.rangeReadPaths.filter { $0 == "A/2025/03/15/X.ARW" }.count == 3)
        #expect(nas.rangeReadPaths.filter { $0 == "B/2025/03/15/x.arw" }.count == 3)
        #expect(nas.sha256Paths.isEmpty)
        #expect(nas.downloadCount == 0)
    }

    /// AC-195: (1) same path and size, one byte off in the middle sample:
    /// not Same; (2) the same bytes a day apart: Same the long way, not quick.
    @Test func otherwiseTheLongWay() async throws {
        let nas = InMemoryRemoteFileClient()
        var changed = Self.photo(2)
        changed[changed.count / 2] ^= 0xFF
        nas.put("A/2025/03/15/Y.ARW", Self.photo(2))
        nas.put("B/2025/03/15/Y.ARW", changed)
        nas.put("A/2026/07/25/HAT00130.MOV", Self.photo(3, count: 310_000))
        nas.put("B/2026/07/26/HAT00130.MOV", Self.photo(3, count: 310_000))

        let photos = try await verify(nas, quick: true)

        #expect(photos.count == 1)
        let movie = try #require(photos.first)
        #expect(!movie.isQuick)
        #expect(movie.sha256 == FileChecksum.hex(SHA256.hash(data: Self.photo(3, count: 310_000))))
        #expect(Set(nas.sha256Paths) == ["A/2026/07/25/HAT00130.MOV", "B/2026/07/26/HAT00130.MOV"])
    }

    /// Off (the default), the same pair is hashed in full.
    @Test func offHashesEverything() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        let photos = try await verify(nas, quick: false)
        #expect(photos.first?.isQuick == false)
        #expect(nas.sha256Paths.count == 2)
    }

    /// The same photo twice in one folder (`2025/IMG_1` and `Import/IMG_1`
    /// in both A and B): one photo with every copy, as a full scan finds it —
    /// never one quick photo per pair.
    @Test func duplicatesInAFolderGoTheLongWay() async throws {
        let nas = InMemoryRemoteFileClient()
        for folder in ["A", "B"] {
            nas.put("\(folder)/2025/IMG_1.JPG", Self.photo(5))
            nas.put("\(folder)/Import/IMG_1.JPG", Self.photo(5))
        }
        let photos = try await verify(nas, quick: true)
        #expect(photos.count == 1)
        #expect(photos.first?.isQuick == false)
        #expect(photos.first?.files.map(\.count) == [2, 2])
    }

    /// A size the set left a photo out at is never settled quick: the Left
    /// Out list holds SHA-256s, which only a full read matches.
    @Test func leftOutSizesGoTheLongWay() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
                                                                       trustsCache: true, quick: true, fullSizes: [Int64(Self.photo(1).count)])
        #expect(photos.first?.isQuick == false)
    }

    /// Compare of a quick row loads the copy without holding it to a SHA-256
    /// it does not have.
    @Test func compareLoadsAQuickRow() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/X.ARW", Self.photo(1))
        let cache = CompareFileCache()
        let loader = CommonPhotosCompareLoader(client: nas, cache: cache)
        let outcome = try await loader.load(path: "A/X.ARW", sha256: "quick:abc:X.ARW", size: Int64(Self.photo(1).count))
        guard case .file = outcome else { Issue.record("expected a file, got \(outcome)"); return }
    }

    /// AC-196: a quick photo copied — read once from the first folder, its
    /// SHA-256 the one the copy is checked against; the second folder's copy
    /// never read; the row and CSV say quick; nothing of it goes into the
    /// table of SHA-256s read.
    @Test func quickCopyReadsTheFirstCopyOnly() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        nas.addDirectory("C")
        let hashedAtScan = LockedList()
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let photos = try await verify(nas, quick: true) { hashedAtScan.append($0) }
        #expect(hashedAtScan.isEmpty)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("QuickCheck-\(UUID().uuidString)")
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy),
                        items: CommonPhotosRunner.items(for: photos, runId: "R1", folders: ["A", "B"], files: listing.files, sidecars: listing.sidecars))
        let before = nas.commands.count

        try await CommonPhotosRunner(client: nas, store: store, workDirectory: work).run("R1")

        let item = try #require(try store.items(runId: "R1").first)
        let sha = FileChecksum.hex(SHA256.hash(data: Self.photo(1)))
        #expect(item.status == .copied)
        #expect(item.checkMethod == .quick)
        #expect(item.sha256 == sha)
        #expect(nas.files["C/X.ARW"] == Self.photo(1))
        let run = nas.commands.dropFirst(before)
        #expect(!run.contains { $0.contains("B/2025/03/15/X.ARW") })
        #expect(run.filter { $0 == "download A/2025/03/15/X.ARW" }.count == 1)
        let csv = try #require(nas.files.first { $0.key.hasSuffix(".csv") }).value
        #expect(String(decoding: csv, as: UTF8.self).contains(",quick\r\n"))
    }

    /// AC-197: a quick scan, then Move — the results stay (the scan is the
    /// same for both); turning Quick check off drops them.
    @Test @MainActor func moveKeepsQuickResults() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        sheet.quickCheck = true
        await sheet.scanToEnd()
        #expect(sheet.quickCount == 1)

        sheet.action = .move
        #expect(sheet.notice == nil)
        #expect(sheet.phase == .done)
        #expect(sheet.quickCount == 1)
        sheet.action = .copy
        #expect(sheet.quickCount == 1)

        sheet.quickCheck = false
        #expect(sheet.notice == .quickOff)
        #expect(sheet.sameCount == 0)
    }

    /// A quick row and its run, every copy at the same path under A and B.
    private func quickRun(_ nas: InMemoryRemoteFileClient, action: CommonPhotosRun.Action,
                          photos: [CommonPhoto]? = nil) async throws -> CommonPhotosStore {
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let found = try await verify(nas, quick: true)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: action),
                        items: CommonPhotosRunner.items(for: photos ?? found, runId: "R1", folders: ["A", "B"],
                                                        files: listing.files, sidecars: listing.sidecars))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("QuickCheck-\(UUID().uuidString)")
        try await CommonPhotosRunner(client: nas, store: store, workDirectory: work).run("R1")
        return store
    }

    /// A quick row moved: every copy read in full first, then moved; the row
    /// records the SHA-256 and a full check, and the destination's SHA-256
    /// is remembered so no scan reads it again.
    @Test func quickMoveReadsEveryCopy() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        nas.addDirectory("C")

        let store = try await quickRun(nas, action: .move)

        let item = try #require(try store.items(runId: "R1").first)
        let sha = FileChecksum.hex(SHA256.hash(data: Self.photo(1)))
        #expect(item.status == .moved)
        #expect(item.sha256 == sha)
        #expect(item.checkMethod == .full)
        #expect(Set(nas.sha256Paths).isSuperset(of: ["A/2025/03/15/X.ARW", "B/2025/03/15/X.ARW"]))
        #expect(nas.files["C/X.ARW"] == Self.photo(1))
        #expect(nas.files["A/2025/03/15/X.ARW"] == nil && nas.files["B/2025/03/15/X.ARW"] == nil)
        let records = CommonPhotosScanRecords(database: store.database)
        #expect(try records.records(connectionId: "S1", paths: ["C/X.ARW"])["C/X.ARW"]?.sha256 == sha)
    }

    /// A quick row whose copies differ past the samples: nothing is moved
    /// or removed, the row fails as changed.
    @Test func quickMoveOfDifferentCopiesRemovesNothing() async throws {
        let nas = InMemoryRemoteFileClient()
        var other = Self.photo(1)
        other[123_457] &+= 1
        nas.put("A/X.ARW", Self.photo(1))
        nas.put("B/X.ARW", other)
        nas.addDirectory("C")
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let quick = CommonPhoto(sha256: CommonPhoto.quickPrefix + "x", size: Int64(other.count),
                                files: [[listing.files[0][0]], [listing.files[1][0]]])

        let store = try await quickRun(nas, action: .move, photos: [quick])

        let item = try #require(try store.items(runId: "R1").first)
        #expect(item.status == .failed)
        #expect(item.failure?.reason == .changedOnServer)
        #expect(nas.files["A/X.ARW"] == Self.photo(1))
        #expect(nas.files["B/X.ARW"] == other)
        #expect(nas.files["C/X.ARW"] == nil)
    }

    /// A Live Photo whose motion is a quick row with copies that differ past
    /// the samples: the motion is read in full before the still moves, so
    /// neither half moves and nothing is removed (§6f).
    @Test func quickMotionIsReadBeforeTheStillMoves() async throws {
        let nas = InMemoryRemoteFileClient()
        let still = Self.photo(2, count: 200_000)
        var otherMotion = Self.photo(3)
        otherMotion[150_001] &+= 1
        nas.put("A/IMG_1.HEIC", still)
        nas.put("B/IMG_1.HEIC", still)
        nas.put("A/IMG_1.MOV", Self.photo(3))
        nas.put("B/IMG_1.MOV", otherMotion)
        nas.addDirectory("C")
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let file = { (folder: Int, name: String) in try #require(listing.files[folder].first { $0.name == name }) }
        let photos = [
            CommonPhoto(sha256: FileChecksum.hex(SHA256.hash(data: still)), size: Int64(still.count),
                        files: [[try file(0, "IMG_1.HEIC")], [try file(1, "IMG_1.HEIC")]]),
            CommonPhoto(sha256: CommonPhoto.quickPrefix + "m", size: Int64(otherMotion.count),
                        files: [[try file(0, "IMG_1.MOV")], [try file(1, "IMG_1.MOV")]]),
        ]

        let store = try await quickRun(nas, action: .move, photos: photos)

        let items = try store.items(runId: "R1")
        #expect(items.map(\.status) == [.failed, .failed])
        #expect(items[0].failure?.reason == .liveMotionChanged)
        #expect(nas.files["A/IMG_1.HEIC"] == still && nas.files["B/IMG_1.HEIC"] == still)
        #expect(nas.files["A/IMG_1.MOV"] == Self.photo(3) && nas.files["B/IMG_1.MOV"] == otherMotion)
        #expect(nas.files.keys.filter { $0.hasPrefix("C/") && !$0.hasSuffix(".csv") }.isEmpty)
    }
}

/// What a `@Sendable` callback heard.
private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[CommonPhotosFile: String]] = []
    func append(_ value: [CommonPhotosFile: String]) { lock.withLock { values.append(value) } }
    var isEmpty: Bool { lock.withLock { values.allSatisfy(\.isEmpty) } }
}
