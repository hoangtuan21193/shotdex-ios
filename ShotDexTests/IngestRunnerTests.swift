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

extension IngestRunnerTests {
    /// AC-28: Pause lets the file in hand finish — copy, verify, rename —
    /// then waits; Resume carries on from the next one; nothing is copied
    /// twice and no part is left while paused.
    @Test func pauseFinishesCurrentFileThenResumes() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen(bytes: 320_000)
        let slow = FaultyCardReader(inner: card.reader(), chunkDelay: .milliseconds(30))
        let plan = try await card.plan(slow)
        let runner = card.runner(reader: slow, plan: plan, primary: LocalFolderWriter(root: card.destination))
        let task = Task { await runner.run() }
        try await Task.sleep(for: .milliseconds(400))
        await runner.pause()
        try await Task.sleep(for: .milliseconds(600))
        let whilePaused = try card.destinationFiles()
        #expect(!whilePaused.isEmpty && whilePaused.count < 10)
        #expect(try card.parts().isEmpty)
        try await Task.sleep(for: .milliseconds(500))
        #expect(try card.destinationFiles() == whilePaused)
        await runner.resume()
        let summary = await task.value
        #expect(summary.ending == .finished)
        #expect(summary.imported.count == 10)
        #expect(try card.destinationFiles().count == 10)
    }

    /// AC-18: every copy verified, backup included, no failure — the card
    /// may go, and the banner says so; any failure keeps it.
    @Test func ejectsOnlyWhenClean() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.addTen()
        let (summary, _) = try await card.importAll(backupWriter: LocalFolderWriter(root: card.backup))
        #expect(summary.canEject(backupEnabled: true))
        #expect(summary.backedUp.count == 10)
        #expect(IngestCopy.finishedBanner(count: 10, card: "EOS_DIGITAL", ejected: true, canRemove: false)
                == "Imported 10 photos. EOS_DIGITAL ejected.")
        #expect(IngestCopy.finishedBanner(count: 10, card: "EOS_DIGITAL", ejected: false, canRemove: true)
                == "Imported 10 photos. You can remove EOS_DIGITAL now.")
        var failed = summary
        failed.failed["x"] = .checksumMismatch
        #expect(!failed.canEject(backupEnabled: true))
    }
}

/// FS-20 §7.3, AC-5, AC-15, AC-24: what a verified file leaves behind.
@Suite struct IngestRecorderTests {
    private func run(_ card: IngestFixture, metadata: IngestMetadataPreset, database: AppDatabase,
                     stopAfter: Int? = nil) async throws -> IngestSummary {
        let reader = card.reader()
        let items = CardCatalog.items(try await reader.list())
        let plan = try await card.plan(reader)
        let recorder = IngestRecorder(database: database, cardId: "EOS", cardName: "EOS_DIGITAL", sourceId: "src",
                                      destinationRoot: card.destination, metadata: metadata,
                                      items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
        let counter = ReadBackCounter()
        var runnerBox: IngestRunner?
        let runner = IngestRunner(card: reader, plan: plan,
                                  primary: IngestTarget(destination: LocalFolderWriter(root: card.destination), name: "T7"),
                                  onEvent: { event in
                                      recorder.handle(event)
                                      if case .imported = event { counter.increment() }
                                  })
        runnerBox = runner
        guard let stopAfter else { return await runner.run() }
        let task = Task { await runnerBox!.run() }
        while counter.value < stopAfter { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        return await task.value
    }

    /// AC-5: Creator, Copyright and two keywords in a `.xmp` beside each of
    /// three photos; the photos themselves are byte for byte the card's.
    @Test func writesSidecarWithPreset() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        for n in 1...3 {
            try card.add("DCIM/100CANON/IMG_000\(n).JPG", bytes: 50_000, date: IngestRunnerTests.shot)
        }
        let preset = IngestMetadataPreset(name: "Kyoto", creator: "Linh Pham", copyright: "© 2026 Linh Pham", keywords: ["Kyoto", "autumn"])
        let summary = try await run(card, metadata: preset, database: try AppDatabase.makeEmpty())
        #expect(summary.imported.count == 3)
        for n in 1...3 {
            let xmp = try String(contentsOf: card.destination.appendingPathComponent("IMG_000\(n).xmp"), encoding: .utf8)
            #expect(xmp.contains("Linh Pham"))
            #expect(xmp.contains("© 2026 Linh Pham"))
            #expect(xmp.contains("<rdf:li>Kyoto</rdf:li>") && xmp.contains("<rdf:li>autumn</rdf:li>"))
            #expect(xmp.contains("xmp:CreateDate"))
            #expect(try card.sha("IMG_000\(n).JPG", onDestination: true) == card.sha("DCIM/100CANON/IMG_000\(n).JPG", onDestination: false))
        }
    }

    /// AC-24: the sidecar switch in Settings off — the import still writes
    /// its three, and nothing else in the destination gets one. The
    /// recorder never reads the switch (it writes through the static
    /// `SidecarWriter.write`, not the switch-gated queue), so the test does
    /// not flip the shared setting under the suites running beside it.
    @Test func sidecarIgnoresGlobalSwitch() async throws {
        #expect(SidecarSetting.isOn(UserDefaults(suiteName: "ingest-\(UUID().uuidString)")!.withSidecarsOff()) == false)
        let card = try IngestFixture()
        defer { card.cleanUp() }
        for n in 1...3 { try card.add("DCIM/100CANON/IMG_000\(n).JPG", bytes: 50_000, date: IngestRunnerTests.shot) }
        try Data("earlier photo".utf8).write(to: card.destination.appendingPathComponent("OLD_0001.JPG"))
        _ = try await run(card, metadata: IngestMetadataPreset(creator: "Linh Pham"), database: try AppDatabase.makeEmpty())
        let sidecars = try card.destinationFiles().filter { $0.hasSuffix(".xmp") }
        #expect(sidecars == ["IMG_0001.xmp", "IMG_0002.xmp", "IMG_0003.xmp"])
    }

    /// AC-15: each file's history row is written as it is verified, so a
    /// run stopped after two photos opens again with those two imported.
    @Test func historyWrittenPerFile() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        for n in 1...10 {
            try card.add(String(format: "DCIM/100CANON/IMG_%04d.JPG", n), bytes: 400_000,
                         date: IngestRunnerTests.shot.addingTimeInterval(Double(n)))
        }
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let card2 = card
        let items = CardCatalog.items(try await card2.reader().list())
        let recorder = IngestRecorder(database: database, cardId: "EOS", cardName: "EOS_DIGITAL", sourceId: sourceId,
                                      destinationRoot: card.destination, metadata: IngestMetadataPreset(),
                                      items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
        let slow = FaultyCardReader(inner: card.reader(), chunkDelay: .milliseconds(40))
        let plan = try await card.plan(slow)
        let counter = ReadBackCounter()
        let runner = IngestRunner(card: slow, plan: plan, primary: IngestTarget(destination: LocalFolderWriter(root: card.destination), name: "T7"),
                                  onEvent: { event in
                                      recorder.handle(event)
                                      if case .imported = event { counter.increment() }
                                  })
        let task = Task { await runner.run() }
        while counter.value < 2 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        let summary = await task.value
        let done = summary.imported.count
        #expect(done >= 2 && done < 10)
        let matches = try CardImportStore(database: database).matches(for: items.map(\.primary)) { _, path in
            FileManager.default.fileExists(atPath: card.destination.appendingPathComponent(path).path)
        }
        let imported = items.filter { IngestStatus.isImported($0, matches: matches) }
        #expect(imported.count == done)
        #expect(items.count - imported.count == 10 - done)
    }
}

final class ReadBackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private extension UserDefaults {
    func withSidecarsOff() -> UserDefaults {
        set(false, forKey: SettingsKeys.readsAndWritesSidecars)
        return self
    }
}
