import Foundation
import os
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07c AC-13 / NF-02: one photo rendered at a time — the peak of a
/// batch is the peak of one photo, plus at most one original's size; and the
/// scratch folder never holds more than one photo's source.
@Suite(.serialized) struct FileExportMemoryTests {
    final class ScratchCounter: @unchecked Sendable {
        private let peak = OSAllocatedUnfairLock(initialState: 0)
        let directory: URL
        init(directory: URL) { self.directory = directory }

        func sample() {
            let count = (FileManager.default.enumerator(atPath: directory.path)?.allObjects as? [String] ?? [])
                .filter { !$0.hasSuffix("/") && (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent($0).path)[.type] as? FileAttributeType) == .typeRegular }
                .count
            peak.withLock { $0 = max($0, count) }
        }

        var value: Int { peak.withLock { $0 } }
    }

    /// 24 MP JPEGs to 2048 px, one versus twenty. (500 is the AC's number;
    /// the claim is flatness, and twenty renders already show any growth per
    /// photo while keeping the suite under a minute.)
    @Test func fiveHundredPeakIsFlat() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        var options = MetadataFixture.Options()
        options.width = 6_000
        options.height = 4_000
        options.xmp = false
        let jpeg = try MetadataFixture.encode(.jpeg, options: options)
        let fileSize = UInt64(jpeg.count)
        var items: [FileExportItem] = []
        for index in 1...20 {
            let file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: jpeg)
            items.append(FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file], pixelWidth: 6_000, pixelHeight: 4_000))
        }
        let render = FileExportRenderOptions(preset: .twoK, format: .jpeg, quality: 0.8, metadata: .noLocation)
        let work = fixture.root.appendingPathComponent("work")
        let counter = ScratchCounter(directory: work)

        func peak(_ batch: [FileExportItem], folder: String) async throws -> UInt64 {
            let destination = fixture.destination.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let runner = FileExportRunner(source: fixture.source, writer: LocalFolderWriter(root: destination),
                                          rendering: KitExportRenderer(), workDirectory: work) { event in
                if case .step = event { counter.sample() }
            }
            let plan = FileExportPlan.make(items: batch, mode: .currentVersion, template: .originalName, policy: .keepBoth,
                                           dateFolders: false, includesLivePhotoVideo: true, renderExtension: { _ in "jpg" },
                                           existing: [:])
            let baseline = FootprintSampler.current()
            let sampler = FootprintSampler()
            sampler.start()
            let report = await runner.run(FileExportJob(plan: plan, mode: .currentVersion, render: render))
            let top = sampler.stop()
            #expect(report.writtenCount == batch.count)
            return top > baseline ? top - baseline : 0
        }

        _ = await FootprintSampler.waitForQuietProcess()
        let one = try await peak(Array(items.prefix(1)), folder: "one")
        let twenty = try await peak(items, folder: "twenty")

        print("FOOTPRINT file export: 1 photo +\(one / 1_048_576) MB, 20 photos +\(twenty / 1_048_576) MB, file \(fileSize / 1_048_576) MB, scratch peak \(counter.value) file(s)")
        #expect(twenty <= one + fileSize, "1: \(one) B, 20: \(twenty) B, file: \(fileSize) B")
        #expect(counter.value <= 1)
        #expect(fixture.names("twenty").count == 20)
    }
}
