import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: a run carries out what the scan found — it does not hash the
/// sources again, and it still catches what changed on the server since.
@Suite struct CommonPhotosReviewTests {
    typealias Fixture = CommonPhotosRunnerTests.Fixture

    /// Every source with a write time, as a NAS reports it.
    private func withWriteTimes(_ fixture: Fixture) {
        for (index, path) in fixture.nas.files.keys.sorted().enumerated() {
            fixture.nas.modified[path] = Date(timeIntervalSince1970: TimeInterval(1_000 + index))
        }
    }

    /// The SHA-256 reads of a source copy since `start`.
    private func sourceHashes(_ fixture: Fixture, from start: Int) -> [String] {
        fixture.nas.sha256Paths.dropFirst(start).filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }
    }

    /// AC-177: three Same photos, Copy — no source hashed again; each one
    /// downloaded once, from the first folder, its SHA taken on the way; each
    /// lands under its own name.
    @Test func copyRunReadsNoSource() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        let hashed = fixture.nas.sha256Paths.count

        try await fixture.runner.run("R1")

        #expect(sourceHashes(fixture, from: hashed).isEmpty)
        #expect(fixture.nas.commands.filter { $0.hasPrefix("download ") } == (1...3).map { "download A/IMG_\($0).JPG" })
        let items = try fixture.items()
        #expect(items.map(\.status) == [.copied, .copied, .copied])
        #expect(items.map(\.destinationPath) == (1...3).map { "C/IMG_\($0).JPG" })
    }

    /// AC-177 with sidecars: the photo's `.xmp` goes along, and neither the
    /// photo nor its sidecar is hashed at the source.
    @Test func copyWithSidecarReadsNoSource() async throws {
        let fixture = try Fixture(count: 1)
        fixture.nas.put("A/IMG_1.xmp", Data("<x:xmpmeta rating=4/>".utf8))
        try await fixture.start()
        let hashed = fixture.nas.sha256Paths.count

        try await fixture.runner.run("R1")

        #expect(sourceHashes(fixture, from: hashed).isEmpty)
        #expect(fixture.nas.files["C/IMG_1.xmp"] != nil)
        #expect(try fixture.items().first?.status == .copied)
    }

    /// AC-178: three Same photos, Move — the sources and the renamed copies
    /// are checked by size and write time only; nothing is hashed at all.
    @Test func moveRunReadsNoSource() async throws {
        let fixture = try Fixture(count: 3)
        withWriteTimes(fixture)
        try await fixture.start(action: .move)
        let hashed = fixture.nas.sha256Paths.count

        try await fixture.runner.run("R1")

        #expect(fixture.nas.sha256Paths.dropFirst(hashed).filter { !$0.contains(".csv") }.isEmpty)
        #expect(fixture.nas.downloadCount == 0)
        #expect(try fixture.items().map(\.status) == [.moved, .moved, .moved])
        for (name, bytes) in fixture.photos { #expect(fixture.nas.files["C/\(name)"] == bytes) }
        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.isEmpty)
    }

    /// AC-179: after the scan, B's IMG_2 is rewritten — same size, new bytes,
    /// new write time. IMG_2 fails "changed on the server", no copy of it is
    /// removed, and B keeps the new file; the others are moved.
    @Test func changedAfterScanFails() async throws {
        let fixture = try Fixture(count: 3)
        withWriteTimes(fixture)
        try await fixture.start(action: .move)
        let rewritten = Data(repeating: 9, count: 1_002)
        fixture.nas.put("B/IMG_2.JPG", rewritten)
        fixture.nas.modified["B/IMG_2.JPG"] = Date(timeIntervalSince1970: 5_000)

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.moved, .failed, .moved])
        #expect(items[1].failure?.reason == .changedOnServer)
        #expect(fixture.nas.files["B/IMG_2.JPG"] == rewritten)
        #expect(fixture.nas.files["C/IMG_2.JPG"] == fixture.photos["IMG_2.JPG"])
        #expect(!fixture.nas.removed.contains { $0.contains("IMG_2") })
    }

    /// AC-179, the first folder's copy: A's IMG_2 is rewritten after the scan.
    /// It is never moved into the destination and nothing of IMG_2 goes.
    @Test func firstCopyChangedAfterScanFails() async throws {
        let fixture = try Fixture(count: 2)
        withWriteTimes(fixture)
        try await fixture.start(action: .move)
        let rewritten = Data(repeating: 8, count: 1_002)
        fixture.nas.put("A/IMG_2.JPG", rewritten)
        fixture.nas.modified["A/IMG_2.JPG"] = Date(timeIntervalSince1970: 5_000)

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.moved, .failed])
        #expect(items[1].failure?.reason == .changedOnServer)
        #expect(fixture.nas.files["A/IMG_2.JPG"] == rewritten)
        #expect(fixture.nas.files["B/IMG_2.JPG"] == fixture.photos["IMG_2.JPG"])
        #expect(fixture.nas.files["C/IMG_2.JPG"] == nil)
        #expect(!fixture.nas.removed.contains { $0.contains("IMG_2") })
    }

    /// AC-180: the destination already holds `IMG_1.JPG` (other bytes), and
    /// `IMG_1 (2).JPG` appears after the scan. The run names the photo from
    /// the destination as it is at run time: `IMG_1 (3).JPG`, nothing written
    /// over, the log and CSV name `(3)`. (Scan rows carry no planned name
    /// until R4; then this test also checks the row said `(2)`.)
    @Test func destinationChangedAfterScan() async throws {
        let fixture = try Fixture(count: 1)
        let taken = Data(repeating: 3, count: 1_001)
        fixture.nas.put("C/IMG_1.JPG", taken)
        try await fixture.start()
        let arrived = Data(repeating: 4, count: 1_001)
        fixture.nas.put("C/IMG_1 (2).JPG", arrived)

        try await fixture.runner.run("R1")

        let item = try #require(try fixture.items().first)
        #expect(item.status == .copied)
        #expect(item.destinationPath == "C/IMG_1 (3).JPG")
        #expect(fixture.nas.files["C/IMG_1.JPG"] == taken)
        #expect(fixture.nas.files["C/IMG_1 (2).JPG"] == arrived)
        #expect(fixture.nas.files["C/IMG_1 (3).JPG"] == fixture.photos["IMG_1.JPG"])
        let csv = try #require(fixture.csv?.text)
        #expect(csv.contains("IMG_1 (3).JPG"))
        #expect(!csv.contains("IMG_1 (2).JPG"))
    }
}
