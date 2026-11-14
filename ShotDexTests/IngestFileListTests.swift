import Foundation
import Testing
@testable import ShotDex

/// FS-20 §7, board `MAC_IngestProgress`: the run's file list — three done,
/// the one in hand with its step, two waiting — fed by the runner's events.
@Suite struct IngestFileListTests {
    private static func entries(_ count: Int) -> [IngestFileList.Entry] {
        (0..<count).map { IngestFileList.Entry(id: "DCIM/100CANON/IMG_\(6290 + $0).CR3", name: "IMG_\(6290 + $0).CR3", bytes: 31_400_000) }
    }

    @Test func windowAroundThePhotoInHand() {
        var list = IngestFileList(order: Self.entries(10))
        #expect(list.rows.map(\.state) == [.waiting, .waiting])
        #expect(list.moreWaiting == 8)
        for index in 0..<5 {
            let id = list.order[index].id
            list.set(id, .copying)
            list.copied(id, fraction: 0.5)
            list.set(id, .verifying)
            list.verified(id)
            list.finishInHand()
        }
        let id = list.order[5].id
        list.set(id, .copying)
        list.copied(id, fraction: 0.18)
        #expect(list.rows.map(\.name) == ["IMG_6292.CR3", "IMG_6293.CR3", "IMG_6294.CR3", "IMG_6295.CR3", "IMG_6296.CR3", "IMG_6297.CR3"])
        #expect(list.rows.map(\.state) == [.verified, .verified, .verified, .copying(0.18), .waiting, .waiting])
        #expect(list.moreWaiting == 2)
    }

    @Test func backupAndFailureSteps() {
        var list = IngestFileList(order: Self.entries(3))
        let first = list.order[0].id, second = list.order[1].id
        list.set(first, .copying)
        list.verified(first)
        list.set(first, .backingUp)
        #expect(list.inHand?.state == .backingUp)
        list.backedUp(first)
        list.finishInHand()
        list.set(second, .copying)
        list.failed(second)
        list.finishInHand()
        #expect(list.done.map(\.state) == [.backedUp, .failed])
        #expect(list.waiting.map(\.name) == ["IMG_6292.CR3"])
    }

    /// Only the backup copy failed: the photo is in, the row says so.
    @Test func backupFailureKeepsVerified() {
        var list = IngestFileList(order: Self.entries(1))
        let id = list.order[0].id
        list.set(id, .copying)
        list.verified(id)
        list.set(id, .backingUp)
        list.failed(id)
        #expect(list.inHand?.state == .backupFailed)
    }

    /// A mismatch is copied once more: the runner says copying again, and
    /// the row goes back to a bar.
    @Test func retryAfterMismatchCopiesAgain() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        var writer = LocalFolderWriter(root: card.destination)
        writer.readBack = { url in
            if url.lastPathComponent.hasPrefix("IMG_0005") { return "bad" }
            return try FileChecksum.sha256(of: url)
        }
        let (summary, events) = try await card.importAll(writer: writer)
        let failed = try #require(summary.failed.keys.first)
        let steps = events.compactMap { event -> IngestFileStage? in
            if case .stage(let id, let stage) = event, id == failed { stage } else { nil }
        }
        #expect(steps == [.copying, .verifying, .copying, .verifying])
    }

    /// The second file of a RAW + JPG pair goes on from the share the first
    /// left, not back to 0 %.
    @Test func pairKeepsItsShare() {
        var list = IngestFileList(order: Self.entries(2))
        let id = list.order[0].id
        list.set(id, .copying)
        list.copied(id, fraction: 0.9)
        list.set(id, .verifying)
        list.set(id, .copying)
        #expect(list.inHand?.state == .copying(0.9))
        list.copied(id, fraction: 0.95)
        list.verified(id)
        list.finishInHand()
        list.set(list.order[1].id, .copying)
        #expect(list.inHand?.state == .copying(0))
    }

    /// The plan's order replaces the grid's; folders arrive with it.
    @Test func reorderTakesThePlan() {
        var list = IngestFileList(order: Self.entries(3))
        let ids = list.order.map(\.id)
        list.reorder([ids[2], ids[0], ids[1]], folders: [ids[2]: "RAW/2026"])
        #expect(list.waiting.map(\.name) == ["IMG_6292.CR3", "IMG_6290.CR3"])
        #expect(list.folder == "RAW/2026")
    }

    /// The runner's own events, end to end with a backup: every photo ends
    /// verified and backed up, in the plan's order.
    @Test func runnerEventsDriveTheList() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        let shot = Date(timeIntervalSince1970: 1_791_000_000)
        try card.add("DCIM/100CANON/IMG_6123.CR3", bytes: 3_000_000, date: shot)
        try card.add("DCIM/100CANON/IMG_6123.JPG", bytes: 400_000, date: shot)
        try card.add("DCIM/100CANON/IMG_6124.CR3", bytes: 2_000_000, date: shot)
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("IngestFileListBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backup) }
        let (summary, events) = try await card.importAll(backupWriter: LocalFolderWriter(root: backup))
        #expect(summary.backedUp.count == 2)

        let first = summary.imported[0]
        let steps = events.compactMap { event -> String? in
            switch event {
            case .stage(let id, let stage) where id == first: "\(stage)"
            case .fileVerified(let id, _, _, _) where id == first: "fileVerified"
            case .imported(let id) where id == first: "imported"
            case .backedUp(let id, _) where id == first: "backedUp"
            default: nil
            }
        }
        #expect(steps == ["copying", "verifying", "fileVerified", "copying", "verifying", "fileVerified",
                          "imported", "backingUp", "backedUp"])

        var list = IngestFileList(order: summary.imported.map { IngestFileList.Entry(id: $0, name: ($0 as NSString).lastPathComponent, bytes: 1) })
        for event in events {
            switch event {
            case .stage(let id, let stage): list.set(id, stage)
            case .imported(let id): list.verified(id)
            case .backedUp(let id, _): list.backedUp(id)
            case .failed(let id, _): list.failed(id)
            case .progress: list.finishInHand()
            case .fileVerified, .parked: break
            }
        }
        #expect(list.rows.map(\.state) == [.backedUp, .backedUp])
        #expect(list.moreWaiting == 0)
    }
}
