import Foundation
import os
import Photos
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07c AC-10 / §2: Cancel stops within a second, leaves only whole
/// files, and Export Remaining writes the rest under the names planned.
extension FileExportRunnerTests {
    final class CancelBox: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock<(task: Task<FileExportReport, Never>?, cancelledAt: Date?)>(initialState: (nil, nil))
        func set(_ task: Task<FileExportReport, Never>) { state.withLock { $0.task = task } }
        func cancel() {
            let task = state.withLock { state -> Task<FileExportReport, Never>? in
                if state.cancelledAt == nil { state.cancelledAt = Date() }
                return state.task
            }
            task?.cancel()
        }
        var cancelledAt: Date? { state.withLock { $0.cancelledAt } }
    }

    @Test func cancelStopsWithinASecondAndLeavesNoPart() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        fixture.source.blockDelay = .milliseconds(40)
        var items: [FileExportItem] = []
        for index in 1...100 {
            let file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: ExportFixture.randomData(2_100_000))
            items.append(FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
        }
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal, template: FileNameTemplate("{sequence}"))
        let job = FileExportJob(plan: plan, mode: .unmodifiedOriginal)
        let box = CancelBox()
        let runner = fixture.runner { event in
            // Cancel while the 40th photo is being written.
            if case .step(let id, .writing) = event, id == "p40" { box.cancel() }
        }
        let task = Task { await runner.run(job) }
        box.set(task)

        let report = await task.value
        let stoppedAfter = Date().timeIntervalSince(try #require(box.cancelledAt))

        #expect(stoppedAfter <= 1)
        #expect(report.wasCancelled)
        #expect(fixture.names().count == 39)
        #expect(fixture.names().first == "001.JPG" && fixture.names().last == "039.JPG")
        #expect(!fixture.names().contains { $0.hasSuffix(ServerUploadPath.partSuffix) })

        // Export Remaining: the other 61, numbered 040–100 as planned.
        fixture.source.blockDelay = .zero
        let remaining = report.remaining(in: plan)
        #expect(remaining.count == 61)
        let rest = await runner.run(job, only: Set(remaining))
        #expect(rest.writtenCount == 100)
        #expect(fixture.names().count == 100)
        #expect(fixture.names()[39] == "040.JPG" && fixture.names().last == "100.JPG")
    }

    /// Retry Failed runs only the photos that failed.
    @Test func retryFailedRunsOnlyTheFailed() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        var items: [FileExportItem] = []
        for index in 1...3 {
            let file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: ExportFixture.randomData(10_000))
            items.append(FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
        }
        fixture.source.fail(items[1].files[0].key, with: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.networkError.rawValue))
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal)
        let job = FileExportJob(plan: plan, mode: .unmodifiedOriginal)
        let runner = fixture.runner()

        let first = await runner.run(job)
        #expect(first.failed == ["p2": .downloadFailed])
        fixture.source.heal(items[1].files[0].key)
        let copiesBefore = fixture.source.copies.count
        let second = await runner.run(job, only: Set(first.failedIds))

        #expect(second.failed.isEmpty && second.writtenCount == 3)
        #expect(fixture.source.copies.count == copiesBefore + 1)
    }
}

/// FS-15.02 §6: time left from the last 30 seconds.
@Suite struct TransferRateEstimateTests {
    @Test func estimatesFromTheLastThirtySeconds() {
        var estimate = TransferRateEstimate()
        let start = Date(timeIntervalSince1970: 0)
        estimate.record(0, at: start)
        estimate.record(1_000_000, at: start.addingTimeInterval(1))
        // Under 2 seconds of samples: no guess yet.
        #expect(estimate.secondsLeft(total: 10_000_000) == nil)
        estimate.record(4_000_000, at: start.addingTimeInterval(4))
        #expect(estimate.secondsLeft(total: 10_000_000) == 6)
        // A slow minute ago no longer counts.
        estimate.record(64_000_000, at: start.addingTimeInterval(64))
        estimate.record(124_000_000, at: start.addingTimeInterval(94))
        #expect(estimate.bytesPerSecond == 2_000_000)
    }

    @Test func progressLines() {
        #expect(ExportCopy.exporting(212, of: 500) == "Exporting 212 of 500")
        #expect(ExportCopy.timeLeft(240) == "about 4 min left")
        #expect(ExportCopy.timeLeft(20) == "less than a minute left")
    }
}
