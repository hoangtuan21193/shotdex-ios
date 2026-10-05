import Accelerate
import Foundation

/// What a music track's beat is (FS-12.12 §4): its tempo, where each beat
/// falls in the track's own seconds, which of the four phases is the bar's
/// downbeat, and how sure the analysis is. Derived data — cached by file,
/// never in the recipe.
struct BeatAnalysis: Codable, Equatable, Sendable {
    /// Beats per minute, 60–180.
    var bpm: Double
    /// Every beat, in source seconds, first to last.
    var beats: [Double]
    /// `beats[i]` starts a bar when `(i - downbeatPhase) % 4 == 0`.
    var downbeatPhase: Int
    /// How periodic the onsets are, 0…1 — under `BeatDetector.steadyThreshold`
    /// the track has no steady beat to snap to.
    var confidence: Double

    var isSteady: Bool { confidence >= BeatDetector.steadyThreshold && !beats.isEmpty }

    static let none = BeatAnalysis(bpm: 0, beats: [], downbeatPhase: 0, confidence: 0)
}

/// Finds the beat of a mono signal on the device (FS-12.12 §4), in plain
/// arithmetic — the decode is the Data layer's (`MusicBeatAnalyzer`):
///
/// 1. onset strength: the positive change of a log-magnitude spectrum,
///    frames of 256 samples every 128 (11.6 ms at 11 025 Hz);
/// 2. tempo: the onset curve's autocorrelation, lags of 60–180 BPM, the
///    faster of two near-equal peaks (a click at 170 is not 85);
/// 3. beats: dynamic programming that rewards onsets and lets the period
///    drift ±5 %, each beat then pinned to its onset to the millisecond;
/// 4. downbeat: of the four phases, the one with the most energy under
///    200 Hz;
/// 5. confidence: how far the tempo peak stands above the autocorrelation's
///    floor — noise has no peak worth the name.
enum BeatDetector {
    static let sampleRate: Double = 11_025
    static let frameLength = 256
    static let hop = 128
    static let tempoRange: ClosedRange<Double> = 60...180
    /// Under this the track reads "No steady beat".
    static let steadyThreshold: Double = 0.3

    static var framesPerSecond: Double { sampleRate / Double(hop) }

    static func analyze(_ samples: [Float]) -> BeatAnalysis {
        let onset = OnsetCurve(samples)
        guard onset.strength.count > Int(framesPerSecond * 2) else { return .none }
        guard let tempo = estimatePeriod(onset.strength) else { return .none }
        guard tempo.confidence >= steadyThreshold else {
            return BeatAnalysis(bpm: 60 * framesPerSecond / tempo.period, beats: [], downbeatPhase: 0, confidence: tempo.confidence)
        }
        let frames = trackBeats(onset.strength, period: tempo.period)
        var beats = frames.map { refineOnset(in: samples, nearFrame: $0) }
        beats = Array(Set(beats.map { ($0 * 10_000).rounded() / 10_000 })).sorted()
        guard beats.count >= 4 else { return BeatAnalysis(bpm: 0, beats: [], downbeatPhase: 0, confidence: tempo.confidence) }
        let bpm = 60 / fittedPeriod(beats)
        let phase = downbeatPhase(beats: beats, lowBand: onset.lowBand)
        return BeatAnalysis(bpm: bpm, beats: beats, downbeatPhase: phase, confidence: tempo.confidence)
    }

    // MARK: Onsets

    struct OnsetCurve {
        /// Positive spectral flux per frame, the whole band.
        var strength: [Float]
        /// Energy under 200 Hz per frame.
        var lowBand: [Float]

        init(_ samples: [Float]) {
            let n = BeatDetector.frameLength
            let count = samples.count >= n ? (samples.count - n) / BeatDetector.hop + 1 : 0
            strength = []
            lowBand = []
            guard count > 1, let setup = vDSP_create_fftsetup(vDSP_Length(8), FFTRadix(kFFTRadix2)) else { return }
            defer { vDSP_destroy_fftsetup(setup) }
            var window = [Float](repeating: 0, count: n)
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            let half = n / 2
            let lowBins = max(1, Int(200 / (BeatDetector.sampleRate / Double(n))))
            var previous = [Float](repeating: 0, count: half)
            var frame = [Float](repeating: 0, count: n)
            var real = [Float](repeating: 0, count: half)
            var imaginary = [Float](repeating: 0, count: half)
            var magnitude = [Float](repeating: 0, count: half)
            strength.reserveCapacity(count)
            lowBand.reserveCapacity(count)
            for index in 0..<count {
                let start = index * BeatDetector.hop
                samples.withUnsafeBufferPointer { source in
                    vDSP_vmul(source.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(n))
                }
                real.withUnsafeMutableBufferPointer { realPointer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                        var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                        frame.withUnsafeBufferPointer { framePointer in
                            framePointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, vDSP_Length(8), FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(half))
                    }
                }
                var flux: Float = 0
                var low: Float = 0
                for bin in 1..<half {
                    let value = log1p(magnitude[bin] * 10)
                    let rise = value - previous[bin]
                    if rise > 0 { flux += rise }
                    previous[bin] = value
                    if bin <= lowBins { low += magnitude[bin] * magnitude[bin] }
                }
                strength.append(flux)
                lowBand.append(low)
            }
            // Take out the slow level so the autocorrelation sees pulses,
            // not loudness: subtract the mean of the second around each
            // frame, keep what is above it. Centred, so the first beat of
            // the track is not measured against itself.
            let around = Int(BeatDetector.framesPerSecond / 2)
            var prefix = [Float](repeating: 0, count: strength.count + 1)
            for index in strength.indices { prefix[index + 1] = prefix[index] + strength[index] }
            var smoothed = [Float](repeating: 0, count: strength.count)
            for index in strength.indices {
                let low = max(0, index - around)
                let high = min(strength.count, index + around + 1)
                let mean = (prefix[high] - prefix[low]) / Float(high - low)
                smoothed[index] = max(0, strength[index] - mean)
            }
            strength = smoothed
        }
    }

    // MARK: Tempo

    /// The beat period in frames (sub-frame) and how clearly it stands out.
    static func estimatePeriod(_ onset: [Float]) -> (period: Double, confidence: Double)? {
        let minLag = Int((60 / tempoRange.upperBound * framesPerSecond).rounded(.down))
        let maxLag = Int((60 / tempoRange.lowerBound * framesPerSecond).rounded(.up))
        guard onset.count > maxLag * 2 else { return nil }
        var energy: Float = 0
        vDSP_svesq(onset, 1, &energy, vDSP_Length(onset.count))
        guard energy > 0 else { return nil }
        var correlation = [Double](repeating: 0, count: maxLag + 2)
        onset.withUnsafeBufferPointer { pointer in
            for lag in 1...(maxLag + 1) {
                var dot: Float = 0
                vDSP_dotpr(pointer.baseAddress!, 1, pointer.baseAddress! + lag, 1, &dot, vDSP_Length(onset.count - lag))
                // Unbiased: a long lag has fewer products to sum.
                correlation[lag] = Double(dot) / Double(energy) * Double(onset.count) / Double(onset.count - lag)
            }
        }
        let lags = Array(minLag...maxLag)
        // A period between two frames splits its peak over two lags; judge
        // peaks on the correlation smoothed over its neighbours.
        let smooth: [Double] = correlation.indices.map { lag in
            let left = lag > 0 ? correlation[lag - 1] : correlation[lag]
            let right = lag + 1 < correlation.count ? correlation[lag + 1] : correlation[lag]
            return 0.5 * left + correlation[lag] + 0.5 * right
        }
        guard let best = lags.max(by: { smooth[$0] < smooth[$1] }) else { return nil }
        // The faster of two near-equal peaks: a click every 0.35 s also
        // correlates at 0.7 s, and 85 BPM would be the wrong answer.
        let peaks = lags.filter { lag in
            lag > minLag && lag < maxLag
                && smooth[lag] >= smooth[lag - 1] && smooth[lag] >= smooth[lag + 1]
                && smooth[lag] >= 0.8 * smooth[best]
        }
        let chosen = peaks.min() ?? best
        // Parabolic interpolation for the period between frames.
        var period = Double(chosen)
        if chosen > 1, chosen < correlation.count - 1 {
            let a = correlation[chosen - 1], b = correlation[chosen], c = correlation[chosen + 1]
            let denominator = a - 2 * b + c
            if denominator != 0 { period += 0.5 * (a - c) / denominator }
        }
        let inRange = lags.map { correlation[$0] }.sorted()
        let floor = inRange[inRange.count / 2]
        let confidence = max(0, min(1, (correlation[chosen] - floor) / max(correlation[chosen], 1e-9)))
        return (period, confidence)
    }

    // MARK: Beats

    /// Beat frames by dynamic programming (Ellis 2007): a beat is worth its
    /// onset, and the step from the beat before it may stray ±5 % from the
    /// period. Leading and trailing beats with no onset under them — the
    /// silence before the music — are dropped.
    static func trackBeats(_ onset: [Float], period: Double) -> [Int] {
        let count = onset.count
        let lowest = Int((period * 0.95).rounded(.down))
        let highest = Int((period * 1.05).rounded(.up))
        var score = [Double](repeating: 0, count: count)
        var back = [Int](repeating: -1, count: count)
        let tightness = 100.0
        for t in 0..<count {
            var bestScore = 0.0
            var bestPrevious = -1
            if t >= lowest {
                for previous in max(0, t - highest)...(t - lowest) {
                    let ratio = Double(t - previous) / period
                    let penalty = tightness * pow(log(ratio), 2)
                    let candidate = score[previous] - penalty
                    if bestPrevious < 0 || candidate > bestScore {
                        bestScore = candidate
                        bestPrevious = previous
                    }
                }
            }
            score[t] = Double(onset[t]) + max(0, bestScore)
            back[t] = bestScore > 0 ? bestPrevious : -1
        }
        // Start from the best-scoring frame in the last period.
        let tail = max(0, count - highest)..<count
        guard var t = tail.max(by: { score[$0] < score[$1] }) else { return [] }
        var frames: [Int] = []
        while t >= 0 {
            frames.append(t)
            t = back[t]
        }
        frames.reverse()
        // Drop the ends that sit on nothing.
        let strengths = frames.map { onset[$0] }.sorted()
        let floor = strengths.isEmpty ? 0 : strengths[strengths.count / 2] * 0.15
        while let first = frames.first, onset[first] <= floor { frames.removeFirst() }
        while let last = frames.last, onset[last] <= floor { frames.removeLast() }
        return frames
    }

    /// The onset under a beat frame, to the millisecond: within a frame
    /// either side, the first 1 ms block whose energy reaches half the
    /// loudest block's.
    static func refineOnset(in samples: [Float], nearFrame frame: Int) -> Double {
        let center = frame * hop + frameLength / 2
        let reach = frameLength + hop
        let start = max(0, center - reach)
        let end = min(samples.count, center + reach)
        let block = max(1, Int(sampleRate / 1000))
        guard end - start > block else { return Double(center) / sampleRate }
        var energies: [Float] = []
        var index = start
        while index + block <= end {
            var energy: Float = 0
            samples.withUnsafeBufferPointer { pointer in
                vDSP_svesq(pointer.baseAddress! + index, 1, &energy, vDSP_Length(block))
            }
            energies.append(energy)
            index += block
        }
        guard let peak = energies.max(), peak > 0,
              let first = energies.firstIndex(where: { $0 >= peak * 0.5 })
        else { return Double(center) / sampleRate }
        // From where the loud part begins, step back to where it starts.
        var onsetBlock = first
        while onsetBlock > 0, energies[onsetBlock - 1] > peak * 0.02 { onsetBlock -= 1 }
        return Double(start + onsetBlock * block) / sampleRate
    }

    /// The period that best fits the beats, by least squares on their
    /// index.
    static func fittedPeriod(_ beats: [Double]) -> Double {
        let n = Double(beats.count)
        let meanIndex = (n - 1) / 2
        let meanTime = beats.reduce(0, +) / n
        var numerator = 0.0, denominator = 0.0
        for (index, time) in beats.enumerated() {
            numerator += (Double(index) - meanIndex) * (time - meanTime)
            denominator += pow(Double(index) - meanIndex, 2)
        }
        return denominator > 0 ? numerator / denominator : 0.5
    }

    /// Of the four phases of a 4/4 bar, the one whose beats carry the most
    /// low-band energy — the kick, the bass note on one.
    static func downbeatPhase(beats: [Double], lowBand: [Float]) -> Int {
        var totals = [Float](repeating: 0, count: 4)
        for (index, time) in beats.enumerated() {
            let frame = Int((time * framesPerSecond).rounded())
            let window = max(0, frame - 1)...min(lowBand.count - 1, frame + 3)
            guard !window.isEmpty else { continue }
            totals[index % 4] += window.map { lowBand[$0] }.max() ?? 0
        }
        return totals.indices.max { totals[$0] < totals[$1] } ?? 0
    }
}
