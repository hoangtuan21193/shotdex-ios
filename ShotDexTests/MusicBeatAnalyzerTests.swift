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
}
