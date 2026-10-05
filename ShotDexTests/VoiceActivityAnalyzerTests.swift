import Foundation
import Testing
@testable import ShotDex

/// FS-12.13 AC-1: the on-device classifier finds a synthetic voice — the
/// system's `say`, no real person (D-10) — at 2.0–5.0s in a 10s clip whose
/// rest is room tone at −50 dBFS: one span, both edges within 0.25s.
struct VoiceActivityAnalyzerTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/voice-3s.caf")

    /// White noise at `dBFS` RMS, repeatable.
    static func roomTone(seconds: Double, dBFS: Double, seed: UInt64 = 7) -> [Float] {
        var state = seed
        let amplitude = Float(pow(10, dBFS / 20) * 3.0.squareRoot())
        return (0..<Int(seconds * VoiceActivityAnalyzer.sampleRate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(state >> 40) / Float(1 << 24)
            return (unit * 2 - 1) * amplitude
        }
    }

    static func clip(voiceAt start: Double) async throws -> (samples: [Float], voice: Double) {
        let voice = try await AudioPCMReader.read(fixture, sampleRate: VoiceActivityAnalyzer.sampleRate)
        var samples = roomTone(seconds: 10, dBFS: -50)
        let offset = Int(start * VoiceActivityAnalyzer.sampleRate)
        for (index, sample) in voice.enumerated() where offset + index < samples.count {
            samples[offset + index] += sample
        }
        return (samples, Double(voice.count) / VoiceActivityAnalyzer.sampleRate)
    }

    @Test func syntheticVoiceOneSegment() async throws {
        let (samples, length) = try await Self.clip(voiceAt: 2.0)
        #expect(abs(length - 3.0) < 0.1)
        let began = Date()
        let activity = try VoiceActivityAnalyzer.analyze(samples: samples, start: 0)
        let seconds = Date().timeIntervalSince(began)
        print("VoiceActivityAnalyzer: 10s analysed in \(String(format: "%.2f", seconds))s → \(activity.voices)")
        #expect(activity.voices.count == 1)
        let span = try #require(activity.voices.first)
        #expect(abs(span.start - 2.0) <= 0.25)
        #expect(abs(span.end - 5.0) <= 0.25)
        #expect(activity.analyzedStart == 0 && abs(activity.analyzedEnd - 10) < 0.01)
        #expect(activity.rmsDB.count == 200)
    }

    /// Source seconds carry through: the same clip analysed from source
    /// 12.0 reports its voice at 14.0–17.0.
    @Test func spansAreInSourceSeconds() async throws {
        let (samples, _) = try await Self.clip(voiceAt: 2.0)
        let activity = try VoiceActivityAnalyzer.analyze(samples: samples, start: 12)
        let span = try #require(activity.voices.first)
        #expect(abs(span.start - 14.0) <= 0.25 && abs(span.end - 17.0) <= 0.25)
    }

    /// Room tone alone is no voice; nor is wind at −30 dBFS — but the wind
    /// is louder than −40, so Any Clip Sound hears all of it (AC-5).
    @Test func noiseIsNotAVoice() throws {
        let quiet = try VoiceActivityAnalyzer.analyze(samples: Self.roomTone(seconds: 10, dBFS: -50), start: 0)
        #expect(quiet.voices.isEmpty)
        #expect(quiet.soundSpans(gainDB: 0).isEmpty)
        let wind = try VoiceActivityAnalyzer.analyze(samples: Self.roomTone(seconds: 10, dBFS: -30, seed: 3), start: 0)
        #expect(wind.voices.isEmpty)
        let sound = wind.soundSpans(gainDB: 0)
        #expect(sound.count == 1 && abs(sound[0].start) < 0.01 && abs(sound[0].end - 10) < 0.01)
    }

    /// 50 ms RMS reads −50 dBFS room tone as −50 ±0.5.
    @Test func rmsOfRoomTone() {
        let levels = VoiceActivityAnalyzer.rmsLevels(Self.roomTone(seconds: 1, dBFS: -50))
        #expect(levels.count == 20)
        let mean = levels.reduce(0, +) / Float(levels.count)
        #expect(abs(mean + 50) < 0.5)
    }
}
