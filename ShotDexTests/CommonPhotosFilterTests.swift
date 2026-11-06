import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6g: the Show filter over the scan's results — kind, names that
/// differ, and Problems (unreadable, not checked, failed last time, renamed).
@MainActor
@Suite struct CommonPhotosFilterTests {
    private static func bytes(_ seed: Int, count: Int = 3_000) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* (seed + 1)) })
    }

    private func count(_ sheet: CommonPhotosScanModel, _ filter: CommonPhotosRowFilter) -> Int {
        sheet.rows.filter(filter.keeps).count
    }

    /// Photos, Videos and Names Differ each keep their own rows.
    @Test func kindAndNames() async {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/IMG_1.JPG", Self.bytes(1))
        nas.put("B/x/IMG_1.JPG", Self.bytes(1))
        nas.put("A/clip.MOV", Self.bytes(2))
        nas.put("B/clip.MOV", Self.bytes(2))
        nas.put("A/IMG_2.JPG", Self.bytes(3))
        nas.put("B/2025-06-02 IMG_2.JPG", Self.bytes(3))
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        await sheet.scanToEnd()

        #expect(sheet.sameCount == 3)
        #expect(count(sheet, .all) == 3)
        #expect(count(sheet, .photos) == 2)
        #expect(count(sheet, .videos) == 1)
        #expect(sheet.rows.filter(CommonPhotosRowFilter.namesDiffer.keeps).map(\.name) == ["IMG_2.JPG"])
        #expect(count(sheet, .problems) == 0)
        #expect(sheet.problemFiles.isEmpty)
    }

    /// A copy the server reads back short is listed under Problems with
    /// the reason; it is no Same row.
    @Test func unreadableFileIsListed() async {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/X.JPG", Self.bytes(1))
        nas.put("B/X.JPG", Self.bytes(1))
        nas.shortRangeReads = ["B/X.JPG"]
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        await sheet.scanToEnd()
        for _ in 0..<50 where sheet.problemFiles.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(sheet.sameCount == 0)
        let problem = try? #require(sheet.problemFiles.first)
        #expect(problem?.name == "X.JPG")
        #expect(problem?.place == "B")
        #expect(problem?.unreadable != nil)
    }

    /// A scan that stops lists the first-folder files it never reached.
    @Test func stoppedScanListsWhatItNeverReached() async {
        let nas = InMemoryRemoteFileClient()
        for index in 1...3 {
            nas.put("A/IMG_\(index).JPG", Self.bytes(index, count: 1_000 * index))
            nas.put("B/IMG_\(index).JPG", Self.bytes(index, count: 1_000 * index))
        }
        // The first group's two reads go through; the next fails as a server gone.
        nas.failRangeReadsAfter = 2
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        await sheet.scanToEnd()

        #expect(sheet.failure != nil)
        #expect(sheet.problemFiles.count == 2)
        #expect(sheet.problemFiles.allSatisfy { $0.unreadable == nil && $0.place == "A" })
    }

    /// A photo the set's last run left Failed carries the reason; a photo
    /// whose name the destination holds lands renamed. Both are Problems.
    @Test func failedLastTimeAndRenamed() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/IMG_1.JPG", Self.bytes(1))
        nas.put("B/IMG_1.JPG", Self.bytes(1))
        nas.put("A/IMG_2.JPG", Self.bytes(2))
        nas.put("B/IMG_2.JPG", Self.bytes(2))
        nas.put("A/IMG_3.JPG", Self.bytes(3))
        nas.put("B/IMG_3.JPG", Self.bytes(3))
        nas.put("C/IMG_2.JPG", Self.bytes(9))
        let database = try AppDatabase.makeEmpty()
        let sha1 = FileChecksum.hex(SHA256.hash(data: Self.bytes(1)))
        let store = CommonPhotosStore(database: database)
        try store.start(CommonPhotosRun(id: "R1", connectionId: "nas", folders: ["A", "B"], destination: "C", action: .copy),
                        items: [CommonPhotosItem(runId: "R1", position: 0, sha256: sha1, size: 3_000,
                                                 sources: [.init(path: "A/IMG_1.JPG", size: 3_000), .init(path: "B/IMG_1.JPG", size: 3_000)],
                                                 status: .failed, reason: CommonPhotosItem.Reason.changedOnServer.rawValue)])
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas, database: database)
        sheet.destination = "C"
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done || sheet.rows.contains(where: { $0.landing == nil }) {
            try await Task.sleep(for: .milliseconds(20))
        }

        let rows = Dictionary(uniqueKeysWithValues: sheet.rows.map { ($0.name, $0) })
        #expect(rows["IMG_1.JPG"]?.failedLastTime != nil)
        #expect(rows["IMG_2.JPG"]?.isRenamed == true)
        #expect(rows["IMG_3.JPG"]?.isRenamed == false)
        #expect(Set(sheet.rows.filter(CommonPhotosRowFilter.problems.keeps).map(\.name)) == ["IMG_1.JPG", "IMG_2.JPG"])
        await sheet.close()
    }
}
