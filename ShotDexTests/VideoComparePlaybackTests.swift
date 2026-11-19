import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// FS-24 AC-24.17 on real players: an H.264 original and its HEVC copy from
/// the real encoder, played by `VideoCompareModel` on one clock. Paused,
/// seeked or stepped, both show the same presentation time (±1 frame);
/// playing, they never drift apart by more than one frame.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)))
struct VideoComparePlaybackTests {
    typealias Worker = VideoCompressionBatchTests.ScriptedWorker

    /// Hands out the two files on disk by id.
    struct FileLoader: VideoCompareLoading {
        let files: [String: URL]
        func playerItem(for id: String) async -> AVPlayerItem? {
            files[id].map { AVPlayerItem(url: $0) }
        }
    }

    private static let frame = 1.0 / 30

    private func makeModel(in directory: URL) async throws -> VideoCompareModel {
        let source = directory.appendingPathComponent("original.mp4")
        let copy = directory.appendingPathComponent("copy.mp4")
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 4, fill: .grain(amplitude: 20), to: source)
        try await VideoCompressionEncoder.encode(
            source, to: copy, settings: .init(quality: .balanced, size: .original), progress: { _ in }
        )
        let run = VideoCompressionBatch(
            videoIDs: ["a"], worker: Worker(["a": .init(sourceBytes: 1000, outputBytes: 400)]),
            workDirectory: directory.appendingPathComponent("work")
        )
        await run.load()
        run.start()
        await run.waitUntilFinished()
        let model = VideoCompareModel(
            batch: run, startID: "a", loader: FileLoader(files: ["a": source, "new-a": copy])
        )
        model.loadCurrent()
        try await until { !model.isLoading && model.duration > 0 }
        return model
    }

    private func until(seconds: Double = 10, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < end else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func drift(_ model: VideoCompareModel) -> Double {
        model.copy.currentTime().seconds - model.original.currentTime().seconds
    }

    @Test func playingStaysWithinOneFrame() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try await makeModel(in: directory)
        defer { model.tearDown() }

        model.play()
        // The host-time start is 0.1 s ahead; sample once both are running.
        try await until { model.original.rate > 0 && model.original.currentTime().seconds > 0.2 }
        var worst = 0.0
        var samples = 0
        while model.original.currentTime().seconds < 3.0 {
            worst = max(worst, abs(drift(model)))
            samples += 1
            try await Task.sleep(for: .milliseconds(25))
        }
        model.pause()
        #expect(samples > 50)
        #expect(worst <= Self.frame, "worst drift \(worst) s over \(samples) samples")
        print("AC-24.17 playing: worst drift \(worst) s over \(samples) samples")
    }

    /// B knocked half a second off while playing (a stall, a slow decode)
    /// is pulled back onto A's clock by the next ticks.
    @Test func driftIsPulledBackWhilePlaying() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try await makeModel(in: directory)
        defer { model.tearDown() }

        model.play()
        try await until { model.original.currentTime().seconds > 0.5 }
        let knocked = CMTimeAdd(model.copy.currentTime(), CMTime(value: 1, timescale: 2))
        await model.copy.seek(to: knocked, toleranceBefore: .zero, toleranceAfter: .zero)
        #expect(abs(drift(model)) > 0.3)
        try await until(seconds: 2) { abs(drift(model)) <= Self.frame }
        var worst = 0.0
        for _ in 0..<20 {
            worst = max(worst, abs(drift(model)))
            try await Task.sleep(for: .milliseconds(25))
        }
        model.pause()
        #expect(worst <= Self.frame, "worst drift after resync \(worst) s")
    }

    @Test func pausedSeekAndStepLandBothOnOneFrame() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try await makeModel(in: directory)
        defer { model.tearDown() }

        for target in [1.0, 2.5, 0.4] {
            await model.seek(to: target)
            #expect(abs(model.original.currentTime().seconds - target) <= Self.frame)
            #expect(abs(drift(model)) <= Self.frame / 2, "after seek to \(target): \(drift(model))")
        }

        let before = model.original.currentTime().seconds
        model.stepFrame(1)
        try await until { model.original.currentTime().seconds > before + Self.frame / 2 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(model.original.currentTime().seconds - (before + Self.frame)) <= Self.frame / 2)
        #expect(abs(drift(model)) <= Self.frame / 2)

        // Play then pause: B is put back on A's frame.
        model.play()
        try await Task.sleep(for: .milliseconds(700))
        model.pause()
        try await Task.sleep(for: .milliseconds(300))
        #expect(abs(drift(model)) <= Self.frame / 2, "after pause: \(drift(model))")
    }
}
