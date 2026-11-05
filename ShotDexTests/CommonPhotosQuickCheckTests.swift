import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6e Quick Check: a Copy may take a photo at the same path, of
/// the same size, with matching samples, as Same — without reading every
/// byte at the scan. Move never does.
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

    /// AC-197: a quick scan, then Move — the results go, a Move rescans in
    /// full; turning Quick check off drops them too.
    @Test @MainActor func moveDropsQuickResults() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/03/15/X.ARW", Self.photo(1))
        nas.put("B/2025/03/15/X.ARW", Self.photo(1))
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        sheet.quickCheck = true
        await sheet.scanToEnd()
        #expect(sheet.quickCount == 1)

        sheet.action = .move
        #expect(sheet.notice == .quickCleared)
        #expect(sheet.sameCount == 0)
        await sheet.scanToEnd()
        #expect(sheet.quickCount == 0)
        #expect(sheet.sameCount == 1)

        sheet.action = .copy
        sheet.quickCheck = true
        await sheet.scanToEnd()
        #expect(sheet.quickCount == 1)
        sheet.quickCheck = false
        #expect(sheet.notice == .quickOff)
        #expect(sheet.sameCount == 0)
    }
}

/// What a `@Sendable` callback heard.
private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[CommonPhotosFile: String]] = []
    func append(_ value: [CommonPhotosFile: String]) { lock.withLock { values.append(value) } }
    var isEmpty: Bool { lock.withLock { values.allSatisfy(\.isEmpty) } }
}
