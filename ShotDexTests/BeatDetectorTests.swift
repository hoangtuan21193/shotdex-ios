import Foundation
import Testing
@testable import ShotDex

/// Beat detection on synthetic clicks (FS-12.12 §9): no recorded music —
/// a click and a bass note on every beat, the bar's first beat twice as
/// loud, made in the test at 11 025 Hz.
struct BeatDetectorTests {
    static func click(bpm: Double, seconds: Double, leadingSilence: Double = 0, accent: Bool = true) -> [Float] {
        let rate = BeatDetector.sampleRate
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        let beat = 60 / bpm
        var index = 0
        while true {
            let time = leadingSilence + Double(index) * beat
            guard time < seconds else { break }
            let gain: Float = accent && index % 4 == 0 ? 1.0 : 0.5
            let start = Int(time * rate)
            for n in 0..<Int(0.12 * rate) where start + n < samples.count {
                let t = Double(n) / rate
                let click = Float(sin(2 * .pi * 1_800 * t) * exp(-t * 120))
                let bass = Float(sin(2 * .pi * 55 * t) * exp(-t * 30))
                samples[start + n] += gain * (0.35 * click + 0.45 * bass)
            }
            index += 1
        }
        return samples
    }

    /// AC-1: 30 s of 96 BPM 4/4 from 0.0 — 96 ±0.5 BPM, every beat within
    /// 20 ms of the click, and beats 0, 4, 8… are the bar's first.
    @Test func click96BarAccented() {
        let analysis = BeatDetector.analyze(Self.click(bpm: 96, seconds: 30))
        #expect(abs(analysis.bpm - 96) <= 0.5)
        #expect(analysis.isSteady)
        let period = 60.0 / 96
        #expect(analysis.beats.count >= 46)
        for (index, time) in analysis.beats.enumerated() {
            let expected = Double(index) * period
            #expect(abs(time - expected) <= 0.02, "beat \(index) at \(time), expected \(expected)")
        }
        #expect(analysis.downbeatPhase == 0)
    }

    /// The tempo is not halved: 170 BPM is not 85.
    @Test func click170NotHalved() {
        let analysis = BeatDetector.analyze(Self.click(bpm: 170, seconds: 20))
        #expect(abs(analysis.bpm - 170) <= 1)
    }

    /// Nor doubled: 60 BPM is not 120.
    @Test func click60NotDoubled() {
        let analysis = BeatDetector.analyze(Self.click(bpm: 60, seconds: 30))
        #expect(abs(analysis.bpm - 60) <= 0.5)
    }
}
