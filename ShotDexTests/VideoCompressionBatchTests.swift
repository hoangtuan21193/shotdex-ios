import Foundation
import os
import Testing
@testable import ShotDex

/// FS-24 AC-24.08 / 09 / 11 / 12: the batch queue with a scripted worker.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VideoCompressionBatchTests {
    /// A worker whose files are plain bytes: the "original" is `sourceBytes`
    /// long and the "encode" writes `outputBytes`, or fails / waits.
    final class ScriptedWorker: VideoCompressionWorking, @unchecked Sendable {
        struct Script {
            var sourceBytes: Int = 1000
            var outputBytes: Int = 400
            var failsEncode = false
            var hangsEncode = false
        }
        let scripts: [String: Script]
        let free: Int64?
        let saved = OSAllocatedUnfairLock<[String]>(initialState: [])
        let deleted = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(_ scripts: [String: Script], free: Int64? = nil) {
            self.scripts = scripts
            self.free = free
        }

        func preflight(_ id: String) async -> VideoCompressionSource? {
            VideoCompressionSource(byteCount: Int64(scripts[id]?.sourceBytes ?? 0), duration: 10,
                                   pixelSize: CGSize(width: 1920, height: 1080), frameRate: 30, hasAudio: true)
        }

        func fetchOriginal(_ id: String, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            try Data(count: scripts[id]?.sourceBytes ?? 0).write(to: url)
            progress(1)
        }

        func encode(_ source: URL, to output: URL, settings: VideoCompressionEncoder.Settings,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
            let id = scripts.first { source.lastPathComponent.isEmpty == false && $0.value.sourceBytes == (try? Data(contentsOf: source).count) }?.key
            let script = id.flatMap { scripts[$0] } ?? Script()
            if script.hangsEncode {
                while true { try await Task.sleep(for: .milliseconds(10)) }
            }
            if script.failsEncode { throw VideoCompressionEncoder.EncodeError(errorDescription: "boom") }
            try Data(count: script.outputBytes).write(to: output)
            progress(1)
        }

        func save(_ file: URL, copying id: String) async throws -> String {
            saved.withLock { $0.append(id) }
            return "new-\(id)"
        }

        func freeBytes() -> Int64? { free }

        func deleteOriginals(_ ids: [String]) async throws {
            deleted.withLock { $0.append(contentsOf: ids) }
        }
    }

    private func batch(_ worker: ScriptedWorker, ids: [String]) -> VideoCompressionBatch {
        VideoCompressionBatch(
            videoIDs: ids, worker: worker,
            workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("VCB-\(UUID().uuidString)")
        )
    }

    /// AC-24.11 + AC-24.08: one failure does not stop the rest; a copy that
    /// is not smaller is skipped and not saved.
    @Test func failureAndSkipDoNotStopTheBatch() async {
        // Source sizes tell the scripted encoder which file it has.
        let worker = ScriptedWorker([
            "a": .init(sourceBytes: 1000, outputBytes: 400),
            "b": .init(sourceBytes: 1001, failsEncode: true),
            "c": .init(sourceBytes: 1002, outputBytes: 990),
            "d": .init(sourceBytes: 1003, outputBytes: 100),
        ])
        let run = batch(worker, ids: ["a", "b", "c", "d"])
        await run.load()
        run.start()
        await run.waitUntilFinished()

        #expect(run.phase == .finished)
        #expect(run.items.map(\.state) == [
            .done(savedBytes: 600),
            .failed("boom"),
            .skipped("Already compact"),
            .done(savedBytes: 903),
        ])
        #expect(worker.saved.withLock { $0 } == ["a", "d"])
        #expect(run.savedBytes == 1503)
        #expect(run.doneCount == 2)
        #expect(run.overallProgress == 1)
    }

    /// AC-24.11: Stop ends the current file and leaves the rest unstarted;
    /// nothing is saved for them.
    @Test func stopEndsTheRun() async throws {
        let worker = ScriptedWorker([
            "a": .init(sourceBytes: 1000, hangsEncode: true),
            "b": .init(sourceBytes: 1001),
        ])
        let run = batch(worker, ids: ["a", "b"])
        await run.load()
        run.start()
        while run.items[0].state == .waiting || run.items[0].state == .downloading(0) || run.items[0].state == .downloading(1) {
            try await Task.sleep(for: .milliseconds(5))
        }
        run.stop()
        await run.waitUntilFinished()

        #expect(run.items.map(\.state) == [.stopped, .stopped])
        #expect(worker.saved.withLock { $0 }.isEmpty)
    }

    /// AC-24.09: too little room stops the batch with a reason.
    @Test func lowSpaceStopsTheBatch() async {
        let worker = ScriptedWorker(["a": .init(), "b": .init(sourceBytes: 1001)], free: 1_000)
        let run = batch(worker, ids: ["a", "b"])
        await run.load()
        run.start()
        await run.waitUntilFinished()

        #expect(run.stopReason != nil)
        #expect(run.items.map(\.state) == [.stopped, .stopped])
    }

    /// AC-24.12: Delete Originals removes only the saved files' originals.
    @Test func deleteOriginalsOnlyForSavedCopies() async {
        let worker = ScriptedWorker([
            "a": .init(sourceBytes: 1000, outputBytes: 400),
            "b": .init(sourceBytes: 1001, outputBytes: 1001),
        ])
        let run = batch(worker, ids: ["a", "b"])
        await run.load()
        run.start()
        await run.waitUntilFinished()
        await run.deleteOriginals()

        #expect(worker.deleted.withLock { $0 } == ["a"])
        #expect(run.hasDeletedOriginals)
    }

    /// AC-24.05: the estimate follows the chosen level.
    @Test func estimateFollowsChoices() async {
        let worker = ScriptedWorker(["a": .init(sourceBytes: 500_000_000)])
        let run = batch(worker, ids: ["a"])
        await run.load()
        run.quality = .high
        let high = run.estimatedBytes
        run.quality = .smallest
        #expect(run.estimatedBytes < high)
        #expect(run.sourceBytes == 500_000_000)
    }
}
