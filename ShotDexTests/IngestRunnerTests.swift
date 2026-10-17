import Foundation
import Testing
@testable import ShotDex

/// FS-20 §7–8: a card import end to end, the card being a `DCIM` folder in
/// a temporary directory and the destination another.
@Suite struct IngestRunnerTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-03 09:00 UTC.
    static let shot = Date(timeIntervalSince1970: 1_791_018_000)

    /// AC-4: `IMG_6123.CR3` shot 2026-10-03, Folders `RAW/{year}/{date}`,
    /// template Date_Kyoto_Original Number → `RAW/2026/2026-10-03/
    /// 2026-10-03_Kyoto_6123.CR3`, byte for byte the card's.
    @Test func copiesVerifiedWithTemplate() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.add("DCIM/100CANON/IMG_6123.CR3", bytes: 3_000_000, date: Self.shot)
        try card.add("DCIM/100CANON/IMG_6123.JPG", bytes: 400_000, date: Self.shot)
        try card.add("DCIM/100CANON/MVI_6124.MP4", bytes: 2_500_000, date: Self.shot)
        try card.add("DCIM/100CANON/MVI_6124.THM", bytes: 1_000, date: Self.shot)
        let (summary, events) = try await card.importAll(template: FileNameTemplate("{date}_Kyoto_{originalNumber}"),
                                                         folders: IngestFolderTemplate(pattern: "RAW/{year}/{date}"))
        #expect(summary.ending == .finished)
        #expect(summary.imported.count == 2)
        #expect(try card.destinationFiles() == [
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3",
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.JPG",
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6124.MP4",
        ])
        #expect(try card.sha("RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3", onDestination: true)
                == card.sha("DCIM/100CANON/IMG_6123.CR3", onDestination: false))
        let verified = events.compactMap { if case .fileVerified(_, let file, _, let sha) = $0 { (file.name, sha) } else { nil } }
        #expect(verified.count == 3)
        #expect(verified.first?.1 == (try card.sha("DCIM/100CANON/IMG_6123.CR3", onDestination: false)))
    }

    /// AC-7: the destination already has `2026-10-03_Kyoto_0001.cr3`; two
    /// photos of the batch name the same (the camera's counter wrapped) →
    /// `…_0001 (2).CR3` and `…_0001 (3).CR3`; the old file is untouched.
    @Test func neverOverwritesKeepBothCaseInsensitive() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.add("DCIM/100CANON/IMG_0001.CR3", bytes: 300_000, date: Self.shot)
        try card.add("DCIM/101CANON/IMG_0001.CR3", bytes: 310_000, date: Self.shot.addingTimeInterval(60))
        let old = card.destination.appendingPathComponent("2026-10-03_Kyoto_0001.cr3")
        try Data("older photo".utf8).write(to: old)
        let oldSHA = try FileChecksum.sha256(of: old)
        let (summary, _) = try await card.importAll(template: FileNameTemplate("{date}_Kyoto_{originalNumber}"))
        #expect(summary.imported.count == 2)
        #expect(try card.destinationFiles() == ["2026-10-03_Kyoto_0001 (2).CR3", "2026-10-03_Kyoto_0001 (3).CR3", "2026-10-03_Kyoto_0001.cr3"])
        #expect(try FileChecksum.sha256(of: old) == oldSHA)
    }

    /// AC-13: what is read back for photo 5 differs from the card, twice:
    /// copied once more, then failed — not in the destination, no part
    /// left, the other nine in, and the card is not let go.
    @Test func mismatchRetriesOnceThenFails() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let attempts = ReadBackCounter()
        var writer = LocalFolderWriter(root: card.destination)
        writer.readBack = { url in
            if url.lastPathComponent.hasPrefix("IMG_0005") { attempts.increment(); return "bad" }
            return try FileChecksum.sha256(of: url)
        }
        let (summary, _) = try await card.importAll(writer: writer)
        #expect(attempts.value == 2)
        #expect(summary.ending == .finished)
        #expect(summary.imported.count == 9)
        #expect(summary.failed.values.map { $0 } == [.checksumMismatch])
        #expect(!(try card.destinationFiles()).contains("IMG_0005.JPG"))
        #expect(try card.parts().isEmpty)
        #expect(!summary.canEject(backupEnabled: false))
        #expect(IngestCopy.failedLine(.checksumMismatch) == "The copy didn't match the card. Nothing was imported for this photo.")
    }

    /// AC-12: the destination says it is full at photo 4: the run stops,
    /// three photos are in, no part is left, the message names it.
    @Test func destinationFullStops() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let reader = card.reader()
        let plan = try await card.plan(reader)
        let full = FailingDestination(LocalFolderWriter(root: card.destination), failsFrom: 4, failure: .destination(.full))
        let summary = await card.runner(reader: reader, plan: plan, primary: full).run()
        #expect(summary.ending == .destinationFailed(.full))
        #expect(summary.imported.count == 3)
        #expect(summary.remaining.count == 7)
        #expect(try card.parts().isEmpty)
        #expect(IngestCopy.endingMessage(summary, card: "EOS_DIGITAL", destination: "T7 RAW Archive")
                == "“T7 RAW Archive” is full — 3 of 10 imported.")
    }

    /// AC-10: the card is pulled out at photo 4: the run stops at once, no
    /// part is left; plugged back in, Import Remaining copies the other 7.
    @Test func cardDisconnectStopsWithinTwoSeconds() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let pulled = FaultyCardReader(inner: card.reader(), disconnectsAt: "IMG_0004.JPG")
        let plan = try await card.plan(pulled)
        let runner = card.runner(reader: pulled, plan: plan, primary: LocalFolderWriter(root: card.destination))
        let started = ContinuousClock.now
        let summary = await runner.run()
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(summary.ending == .cardDisconnected)
        #expect(summary.imported.count == 3)
        #expect(try card.parts().isEmpty)
        #expect(IngestCopy.endingMessage(summary, card: "EOS_DIGITAL", destination: "T7 RAW Archive")
                == "EOS_DIGITAL was disconnected. 3 of 10 imported.")
        let again = await card.runner(reader: card.reader(), plan: plan, primary: LocalFolderWriter(root: card.destination))
            .run(only: Set(summary.remaining))
        #expect(again.imported.count == 7)
        #expect(try card.destinationFiles().count == 10)
    }

    /// AC-14: Stop Import… in the middle of a file stops within a second;
    /// the photos already in stay, no part is left, the card is not let go.
    @Test func stopWithinASecondMidFile() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen(bytes: 640_000)
        let slow = FaultyCardReader(inner: card.reader(), chunkDelay: .milliseconds(60))
        let plan = try await card.plan(slow)
        let runner = card.runner(reader: slow, plan: plan, primary: LocalFolderWriter(root: card.destination))
        let task = Task { await runner.run() }
        try await Task.sleep(for: .milliseconds(1_500))
        let stopped = ContinuousClock.now
        task.cancel()
        let summary = await task.value
        #expect(ContinuousClock.now - stopped < .seconds(1))
        #expect(summary.ending == .stopped)
        #expect(summary.imported.count >= 1 && summary.imported.count < 10)
        #expect(try card.destinationFiles().count == summary.imported.count)
        #expect(try card.parts().isEmpty)
        #expect(!summary.canEject(backupEnabled: false))
    }

    /// AC-9: the backup drive is pulled out at photo 4: every primary copy
    /// still goes in, the card is not let go, the summary says how far the
    /// backup got; Back Up Remaining copies the rest to the backup only.
    @Test func backupDisconnectKeepsPrimaryRunning() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let reader = card.reader()
        let plan = try await card.plan(reader)
        let gone = FailingDestination(LocalFolderWriter(root: card.backup), failsFrom: 4, failure: .destination(.disconnected))
        let summary = await card.runner(reader: reader, plan: plan, primary: LocalFolderWriter(root: card.destination), backup: gone).run()
        #expect(summary.ending == .finished)
        #expect(summary.imported.count == 10)
        #expect(summary.backedUp.count == 3)
        #expect(summary.backupIncomplete)
        #expect(!summary.canEject(backupEnabled: true))
        #expect(IngestCopy.backupLine(summary) == "Backup incomplete — 3 of 10.")
    }

    @Test func backUpRemainingCopiesTheRest() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let reader = card.reader()
        let plan = try await card.plan(reader)
        let gone = FailingDestination(LocalFolderWriter(root: card.backup), failsFrom: 4, failure: .destination(.disconnected))
        let first = await card.runner(reader: reader, plan: plan, primary: LocalFolderWriter(root: card.destination), backup: gone).run()
        let rest = Set(first.imported).subtracting(first.backedUp)
        let second = await card.runner(reader: reader, plan: plan, primary: LocalFolderWriter(root: card.destination),
                                       backup: LocalFolderWriter(root: card.backup)).run(only: rest, copiesPrimary: false)
        #expect(second.backedUp.count == 7)
        #expect(try card.destinationFiles(in: card.backup).count == 10)
        #expect(try card.destinationFiles().count == 10)
    }
}

final class ReadBackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
