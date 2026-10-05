import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// Decoding a music file and caching what its beats are (FS-12.12 §4).
struct MusicBeatAnalyzerTests {
    /// A 96 BPM click written as a 44.1 kHz WAV in the test's own folder.
    static func writeClickWAV(bpm: Double = 96, seconds: Double = 20) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beat-test-\(UUID().uuidString).wav")
        let rate = 44_100.0
        let samples = BeatDetectorTests.click(bpm: bpm, seconds: seconds, rate: rate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        return url
    }

    /// The WAV decodes to 96 BPM; the second ask is answered by the cache
    /// with exactly the same result.
    @Test func decodesWavAndCaches() async throws {
        let url = try Self.writeClickWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = AudioAnalysisCache(directory: nil)
        let analyzer = MusicBeatAnalyzer(cache: cache)

        let first = try await analyzer.analysis(for: url)
        #expect(abs(first.bpm - 96) <= 0.5)
        #expect(first.isSteady)
        let key = try #require(AudioAnalysisCache.fileKey(url, kind: "beats"))
        #expect(await cache.value(BeatAnalysis.self, for: key) == first)

        let second = try await analyzer.analysis(for: url)
        #expect(second == first)
    }

    /// The cache on disk survives a new cache object over the same folder.
    @Test func cacheReadsBackFromDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beat-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let analysis = BeatGridTests.morningDrive(seconds: 5)
        await AudioAnalysisCache(directory: folder).store(analysis, for: "k")
        #expect(await AudioAnalysisCache(directory: folder).value(BeatAnalysis.self, for: "k") == analysis)
    }

    /// AC-14's cancel half, on the simulator: a 3:24 track at 44.1 kHz
    /// being analysed stops within a second of being cancelled — the bed
    /// was deleted, the studio closed.
    @Test func cancelStopsWithinOneSecond() async throws {
        let url = try Self.writeClickWAV(bpm: 112, seconds: 204)
        defer { try? FileManager.default.removeItem(at: url) }
        let analyzer = MusicBeatAnalyzer(cache: AudioAnalysisCache(directory: nil))
        let task = Task { try await analyzer.analysis(for: url) }
        try await Task.sleep(for: .milliseconds(150))
        let cancelled = ContinuousClock.now
        task.cancel()
        let result = await task.result
        let stopped = ContinuousClock.now - cancelled
        #expect(stopped < .seconds(1), "stopped after \(stopped)")
        if case .success = result {
            // Finished before the cancel landed — then it was fast enough
            // that the second is moot.
            #expect(stopped < .seconds(1))
        }
    }

    /// AC-14's time on the simulator, recorded rather than asserted
    /// tightly: the whole 3:24 track, decode and detection, under 5 s here
    /// (the device number is measured on an iPhone 17).
    @Test func longTrackTimeOnTheSimulator() async throws {
        let url = try Self.writeClickWAV(bpm: 112, seconds: 204)
        defer { try? FileManager.default.removeItem(at: url) }
        let analyzer = MusicBeatAnalyzer(cache: AudioAnalysisCache(directory: nil))
        let start = ContinuousClock.now
        let analysis = try await analyzer.analysis(for: url)
        let elapsed = ContinuousClock.now - start
        print("FS-12.12 AC-14 sim: 3:24 analysed in \(elapsed), \(analysis.beats.count) beats, \(analysis.bpm) BPM")
        #expect(abs(analysis.bpm - 112) <= 0.5)
        #expect(elapsed < .seconds(5))
    }
}
