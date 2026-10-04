import Foundation
import Photos
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07c AC-9 / §1 item 5: iCloud originals download rolling — at most
/// 20 photos or 2 GB ahead of the writer — and a failed one is that photo's
/// problem alone.
@Suite struct RollingOriginalPrefetcherTests {
    /// A destination that takes its time, so downloads run ahead of it.
    struct SlowWriter: ExportDestinationWriter {
        let inner: LocalFolderWriter
        var delay: Duration = .milliseconds(30)
        func existingNames(in folder: String) async throws -> Set<String> { try await inner.existingNames(in: folder) }
        func freeBytes() async -> Int64? { nil }
        func sweepLeftoverParts(in folder: String) async {}
        func write(name: String, in folder: String, replacing: Bool, produce: @Sendable (URL) async throws -> Void) async throws -> ExportWrittenFile {
            try await Task.sleep(for: delay)
            return try await inner.write(name: name, in: folder, replacing: replacing, produce: produce)
        }
    }

    private func items(_ fixture: ExportFixture, count: Int, declaredBytes: Int64) throws -> [FileExportItem] {
        try (1...count).map { index in
            var file = try fixture.file("p\(index)", String(format: "DSCF%04d.JPG", index), role: .photo, data: ExportFixture.randomData(4_000))
            file.byteCount = declaredBytes
            return FileExportItem(id: "p\(index)", filename: file.filename, captureDate: ExportFixture.date(minutes: index),
                                  kind: .photo, files: [file], pixelWidth: 6_000, pixelHeight: 4_000)
        }
    }

    private func prefetcher(_ fixture: ExportFixture, cloud: Set<String>? = nil) -> RollingOriginalPrefetcher {
        RollingOriginalPrefetcher(base: fixture.source, directory: fixture.root.appendingPathComponent("icloud")) { item in
            cloud?.contains(item.id) ?? true
        }
    }

    @Test func neverMoreThan20Or2GBAhead() async throws {
        // Small photos: the 20-photo cap is what holds.
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let small = try items(fixture, count: 50, declaredBytes: 1_000_000)
        let ahead = prefetcher(fixture)
        let runner = FileExportRunner(source: ahead, writer: SlowWriter(inner: fixture.writer()), rendering: KitExportRenderer(),
                                      workDirectory: fixture.root.appendingPathComponent("work"))
        let report = await runner.run(FileExportJob(plan: try fixture.plan(small, mode: .unmodifiedOriginal), mode: .unmodifiedOriginal))
        #expect(report.writtenCount == 50)
        #expect(await ahead.peakAheadItems == RollingOriginalPrefetcher.maximumItems)

        // 150 MB photos: 2 GB holds first — thirteen of them.
        let big = ExportFixture()
        defer { big.cleanUp() }
        let large = try items(big, count: 30, declaredBytes: 150_000_000)
        let window = prefetcher(big)
        let second = FileExportRunner(source: window, writer: SlowWriter(inner: big.writer()), rendering: KitExportRenderer(),
                                      workDirectory: big.root.appendingPathComponent("work"))
        _ = await second.run(FileExportJob(plan: try big.plan(large, mode: .unmodifiedOriginal), mode: .unmodifiedOriginal))
        #expect(await window.peakAheadBytes <= RollingOriginalPrefetcher.maximumBytes)
        #expect(await window.peakAheadItems == 13)
        // Nothing left behind on this device.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: big.root.appendingPathComponent("icloud").path)) ?? []).isEmpty)
    }

    /// AC-9: 20 photos, 5 in iCloud, the 7th fails to download — 19 files,
    /// the 7th named in the summary; Retry Failed fetches only it.
    @Test func failedPhotoGoesToSummary() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let all = try items(fixture, count: 20, declaredBytes: 24_000_000)
        let ahead = prefetcher(fixture, cloud: ["p3", "p5", "p7", "p9", "p11"])
        fixture.source.fail(all[6].files[0].key, with: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.networkError.rawValue))
        let runner = FileExportRunner(source: ahead, writer: fixture.writer(), rendering: KitExportRenderer(),
                                      workDirectory: fixture.root.appendingPathComponent("work"))
        let plan = try fixture.plan(all, mode: .unmodifiedOriginal)
        let job = FileExportJob(plan: plan, mode: .unmodifiedOriginal)

        let report = await runner.run(job)

        #expect(report.writtenCount == 19)
        #expect(report.failed == ["p7": .downloadFailed])
        #expect(fixture.names().count == 19)
        let summary = FileExportSummary(plan: plan, report: report, preflight: nil, folder: nil)
        #expect(summary.failures.map(\.name) == ["DSCF0007.JPG"])
        #expect(summary.offersRetry)

        // Retry Failed: one more download, of that photo only.
        fixture.source.heal(all[6].files[0].key)
        let before = await ahead.downloads
        let retried = await runner.run(job, only: Set(report.failedIds))
        let after = await ahead.downloads
        #expect(retried.failed.isEmpty && retried.writtenCount == 20)
        #expect(Array(after.dropFirst(before.count)) == [all[6].files[0].key])
    }

    @Test func retryFetchesOnlyTheFailed() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let all = try items(fixture, count: 6, declaredBytes: 1_000)
        let ahead = prefetcher(fixture)
        fixture.source.fail(all[2].files[0].key, with: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.networkError.rawValue))
        let runner = FileExportRunner(source: ahead, writer: fixture.writer(), rendering: KitExportRenderer(),
                                      workDirectory: fixture.root.appendingPathComponent("work"))
        let job = FileExportJob(plan: try fixture.plan(all, mode: .unmodifiedOriginal), mode: .unmodifiedOriginal)

        let first = await runner.run(job)
        fixture.source.heal(all[2].files[0].key)
        _ = await runner.run(job, only: Set(first.failedIds))

        let downloads = await ahead.downloads
        #expect(downloads.count == 7)
        #expect(downloads.filter { $0 == all[2].files[0].key }.count == 2)
    }
}
