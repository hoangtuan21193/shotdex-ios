import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// FS-24 §10 Compare Videos: AC-24.15, 17, 18, 20, 21 — which files are in
/// it, the time-sync rule, the shared zoom, and Delete Original per pair.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VideoCompareTests {
    typealias Worker = VideoCompressionBatchTests.ScriptedWorker

    struct NoPlayback: VideoCompareLoading {
        func playerItem(for id: String) async -> AVPlayerItem? { nil }
    }

    /// a, c, d saved; b failed; e not smaller.
    private func finishedBatch() async -> (VideoCompressionBatch, Worker) {
        let worker = Worker([
            "a": .init(sourceBytes: 1000, outputBytes: 400),
            "b": .init(sourceBytes: 1001, failsEncode: true),
            "c": .init(sourceBytes: 1002, outputBytes: 500),
            "d": .init(sourceBytes: 1003, outputBytes: 100),
            "e": .init(sourceBytes: 1004, outputBytes: 1004),
        ])
        let run = VideoCompressionBatch(
            videoIDs: ["a", "b", "c", "d", "e"], worker: worker,
            workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("VCT-\(UUID().uuidString)")
        )
        await run.load()
        run.start()
        await run.waitUntilFinished()
        return (run, worker)
    }

    /// AC-24.15 / AC-24.21: only saved files are compared, with the copy's
    /// id and both real sizes.
    @Test func pairsAreTheSavedFilesOnly() async {
        let (run, _) = await finishedBatch()
        let pairs = run.comparePairs
        #expect(pairs.map(\.id) == ["a", "c", "d"])
        #expect(pairs.map(\.copyID) == ["new-a", "new-c", "new-d"])
        let a = try! #require(pairs.first)
        #expect(a.originalBytes == 1000 && a.copyBytes == 400)
        #expect(abs(a.reduction - 0.6) < 0.0001)
        #expect(a.savedBytes == 600)
    }

    /// AC-24.21: stepping walks the saved files and stops at either end.
    @Test func steppingDoesNotWrap() async {
        let (run, _) = await finishedBatch()
        let model = VideoCompareModel(batch: run, startID: "c", loader: NoPlayback())
        defer { model.tearDown() }
        #expect(model.currentIndex == 1)
        model.stepVideo(1)
        #expect(model.currentID == "d")
        #expect(!model.canStepForward)
        model.stepVideo(1)
        #expect(model.currentID == "d")
        model.stepVideo(-2)
        #expect(model.currentID == "a")
        #expect(!model.canStepBack)
        #expect(VideoCompareRules.index(after: 0, step: -1, count: 3) == nil)
        #expect(VideoCompareRules.index(after: 1, step: 1, count: 3) == 2)
    }

    /// A start that is not a saved file opens on the first one.
    @Test func unknownStartOpensTheFirstPair() async {
        let (run, _) = await finishedBatch()
        let model = VideoCompareModel(batch: run, startID: "b", loader: NoPlayback())
        defer { model.tearDown() }
        #expect(model.currentID == "a")
    }

    /// AC-24.20: Delete Original removes that original only, the next pair
    /// shows, and with none left the screen is told to close.
    @Test func deleteOriginalStepsThenEmpties() async {
        let (run, worker) = await finishedBatch()
        let model = VideoCompareModel(batch: run, startID: "c", loader: NoPlayback())
        defer { model.tearDown() }

        await model.deleteCurrentOriginal()
        #expect(worker.deleted.withLock { $0 } == ["c"])
        #expect(model.currentID == "d")
        #expect(run.comparePairs.map(\.id) == ["a", "d"])
        #expect(!run.hasDeletedOriginals)

        await model.deleteCurrentOriginal()
        #expect(model.currentID == "a")
        await model.deleteCurrentOriginal()
        #expect(model.isEmpty)
        #expect(run.hasDeletedOriginals)
        #expect(worker.deleted.withLock { $0 } == ["c", "d", "a"])
    }

    /// AC-24.20: the summary's Delete Originals skips one Compare already deleted.
    @Test func deleteOriginalsSkipsAlreadyDeleted() async {
        let (run, worker) = await finishedBatch()
        #expect(await run.deleteOriginal(of: "a"))
        #expect(!(await run.deleteOriginal(of: "a")))
        #expect(!(await run.deleteOriginal(of: "b")))
        await run.deleteOriginals()
        #expect(worker.deleted.withLock { $0 } == ["a", "c", "d"])
        #expect(run.hasDeletedOriginals)
        #expect(run.comparePairs.isEmpty)
    }

    /// AC-24.17: paused, B must be on A's frame (half a frame of slack);
    /// playing, it is left alone within one frame.
    @Test(arguments: [
        (0.010, 30.0, false, false),
        (0.020, 30.0, false, true),
        (0.020, 30.0, true, false),
        (0.040, 30.0, true, true),
        (-0.040, 30.0, true, true),
        (0.012, 59.94, false, true),
    ])
    func resyncRule(drift: Double, rate: Double, playing: Bool, expected: Bool) {
        #expect(VideoCompareRules.needsResync(drift: drift, frameRate: rate, isPlaying: playing) == expected)
    }

    /// AC-24.18 (Mac): a pinch keeps the pinched point still and never
    /// shows past the frame's edge; the scale stays in 1…8.
    @Test func zoomKeepsThePointAndTheEdges() {
        let pane = CGSize(width: 400, height: 225)
        let point = CGPoint(x: 100, y: 50)
        let zoomed = VideoCompareRules.zoom(scale: 1, offset: .zero, to: 2, about: point, paneSize: pane)
        #expect(zoomed.scale == 2)
        // The content point under the finger: (point - offset) / scale, same before and after.
        #expect(abs((point.x - zoomed.offset.width) / 2 - point.x) < 0.001)
        #expect(abs((point.y - zoomed.offset.height) / 2 - point.y) < 0.001)

        let far = VideoCompareRules.zoom(scale: 1, offset: .zero, to: 20, about: .zero, paneSize: pane)
        #expect(far.scale == VideoCompareRules.maximumZoom)
        let clamped = VideoCompareRules.clampedOffset(CGSize(width: 10_000, height: -10_000), scale: 2, paneSize: pane)
        #expect(clamped == CGSize(width: 200, height: -112.5))
        #expect(VideoCompareRules.clampedOffset(CGSize(width: 50, height: 50), scale: 1, paneSize: pane) == .zero)
    }

    /// The labels the panes and the summary rows carry.
    @Test func labels() {
        let pair = VideoCompareRules.Pair(id: "a", copyID: "b", originalBytes: 1_000_000_000, copyBytes: 400_000_000)
        #expect(VideoCompressionCopy.copyLabel(pair).hasSuffix("−60%"))
        #expect(VideoCompressionCopy.result(pair).contains("→"))
        #expect(VideoCompressionCopy.originalLabel(bytes: 1_200_000_000, codec: "H.264").hasSuffix("· H.264"))
        #expect(VideoCompareModel.codecName(kCMVideoCodecType_H264) == "H.264")
        #expect(VideoCompareModel.codecName(kCMVideoCodecType_HEVC) == "HEVC")
    }
}
