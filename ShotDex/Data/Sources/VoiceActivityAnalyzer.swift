import AVFoundation
import Foundation
import os
import SoundAnalysis

/// Where a clip's sound holds a voice, and how loud each 50 ms of it is
/// (FS-12.13 §4) — on the device, with SoundAnalysis's built-in classifier
/// and its "speech" class. One read of the clip at 16 kHz mono serves both
/// triggers (D-13), so switching Voices / Any Clip Sound analyses nothing.
/// Only the part of the source the clip plays is read.
enum VoiceActivityAnalyzer {
    static let sampleRate: Double = 16_000
    /// Classifier window, and how far apart two windows start (50 %).
    static let window: Double = 1
    static let overlap: Double = 0.5
    /// A window is a voice from this confidence of "speech".
    static let speechConfidence: Double = 0.5
    /// Voices shorter than this are dropped (§4).
    static let shortestVoice: Double = 0.3

    enum AnalysisError: Error {
        case classifierUnavailable
    }

    /// The sound of `track` over source seconds `range`.
    static func analyze(track: AVAssetTrack, asset: AVAsset, range: ClosedRange<Double>) async throws -> ClipSoundActivity {
        let samples = try AudioPCMReader.read(track: track, asset: asset, sampleRate: sampleRate, range: range)
        try Task.checkCancellation()
        return try analyze(samples: samples, start: range.lowerBound)
    }

    /// The sound of 16 kHz mono `samples` that begin at source second
    /// `start`.
    static func analyze(samples: [Float], start: Double) throws -> ClipSoundActivity {
        let duration = Double(samples.count) / sampleRate
        let rms = rmsLevels(samples)
        let windows = try speechWindows(samples)
        try Task.checkCancellation()
        let voices = voiceSpans(windows: windows, rms: rms, duration: duration).map {
            ClipSoundActivity.Span(start: start + $0.start, end: start + $0.end)
        }
        return ClipSoundActivity(analyzedStart: start, analyzedEnd: start + duration, voices: voices, rmsDB: rms)
    }

    /// dBFS of every 50 ms.
    static func rmsLevels(_ samples: [Float]) -> [Float] {
        let size = Int(sampleRate * ClipSoundActivity.rmsWindow)
        guard size > 0, !samples.isEmpty else { return [] }
        return stride(from: 0, to: samples.count, by: size).map { offset in
            let end = min(offset + size, samples.count)
            var sum: Float = 0
            for index in offset..<end { sum += samples[index] * samples[index] }
            let mean = sum / Float(end - offset)
            return 10 * log10(max(mean, 1e-12))
        }
    }

    /// One classifier window: where it starts in the samples and how sure
    /// it is of speech.
    struct Window: Equatable, Sendable {
        var start: Double
        var duration: Double
        var speech: Double
    }

    /// The classifier's "speech" confidence in each 1 s window, every 0.5 s.
    static func speechWindows(_ samples: [Float]) throws -> [Window] {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw AnalysisError.classifierUnavailable
        }
        let request: SNClassifySoundRequest
        do {
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            throw AnalysisError.classifierUnavailable
        }
        request.windowDuration = CMTime(seconds: window, preferredTimescale: CMTimeScale(sampleRate))
        request.overlapFactor = overlap
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = SpeechObserver()
        try analyzer.add(request, withObserver: observer)
        let chunk = Int(sampleRate) // a second at a time
        var position: AVAudioFramePosition = 0
        while Int(position) < samples.count {
            try Task.checkCancellation()
            let count = min(chunk, samples.count - Int(position))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0]
            else { throw AnalysisError.classifierUnavailable }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + Int(position), count: count)
            }
            analyzer.analyze(buffer, atAudioFramePosition: position)
            position += AVAudioFramePosition(count)
        }
        analyzer.completeAnalysis()
        if observer.failed { throw AnalysisError.classifierUnavailable }
        return observer.windows.sorted { $0.start < $1.start }
    }

    /// Voice spans in seconds from the samples' start. A window counts for
    /// its middle half-second — the stretch no other window covers better —
    /// so a run of speech windows becomes one span at 0.5 s resolution; its
    /// edges then move to where the level actually rises out of, and falls
    /// back into, the room's floor, at most half a second either way.
    static func voiceSpans(windows: [Window], rms: [Float], duration: Double) -> [ClipSoundActivity.Span] {
        var coarse: [ClipSoundActivity.Span] = []
        for window in windows where window.speech >= speechConfidence {
            let quarter = window.duration / 4
            let span = ClipSoundActivity.Span(start: window.start + quarter, end: window.start + window.duration - quarter)
            if let last = coarse.last, span.start <= last.end + 1e-6 {
                coarse[coarse.count - 1].end = max(last.end, span.end)
            } else {
                coarse.append(span)
            }
        }
        let refined = coarse.map { refine($0, rms: rms, duration: duration) }
        var joined: [ClipSoundActivity.Span] = []
        for span in refined {
            if let last = joined.last, span.start <= last.end {
                joined[joined.count - 1].end = max(last.end, span.end)
            } else {
                joined.append(span)
            }
        }
        return joined.filter { $0.duration >= shortestVoice }
    }

    /// The floor is the quietest tenth of the clip; a voice is 12 dB over it.
    private static func refine(_ span: ClipSoundActivity.Span, rms: [Float], duration: Double) -> ClipSoundActivity.Span {
        guard !rms.isEmpty else { return span }
        let sorted = rms.sorted()
        let floor = sorted[sorted.count / 10]
        let loud = floor + 12
        let step = ClipSoundActivity.rmsWindow
        let reach = Int(0.5 / step)
        func isLoud(_ index: Int) -> Bool { index >= 0 && index < rms.count && rms[index] > loud }
        var first = Int((span.start / step).rounded())
        var last = Int((span.end / step).rounded()) - 1
        // Out to where the voice begins and ends…
        var moved = 0
        while moved < reach, isLoud(first - 1) { first -= 1; moved += 1 }
        moved = 0
        while moved < reach, isLoud(last + 1) { last += 1; moved += 1 }
        // …or in, past windows that only caught room tone.
        moved = 0
        while moved < reach, first < last, !isLoud(first) { first += 1; moved += 1 }
        moved = 0
        while moved < reach, last > first, !isLoud(last) { last -= 1; moved += 1 }
        let start = max(0, Double(first) * step)
        let end = min(duration, Double(last + 1) * step)
        return end > start ? ClipSoundActivity.Span(start: start, end: end) : span
    }
}

/// Collects the classifier's results. SoundAnalysis calls it on its own
/// queue, so what it gathers sits behind a lock, not on an actor.
private final class SpeechObserver: NSObject, SNResultsObserving, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (windows: [VoiceActivityAnalyzer.Window](), failed: false))

    var windows: [VoiceActivityAnalyzer.Window] { state.withLock { $0.windows } }
    var failed: Bool { state.withLock { $0.failed } }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let speech = result.classification(forIdentifier: "speech")?.confidence ?? 0
        let window = VoiceActivityAnalyzer.Window(
            start: result.timeRange.start.seconds,
            duration: result.timeRange.duration.seconds,
            speech: speech
        )
        state.withLock { $0.windows.append(window) }
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        state.withLock { $0.failed = true }
    }
}
