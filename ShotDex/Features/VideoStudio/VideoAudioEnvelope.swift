import AVFoundation
import Foundation

/// A stereo peak envelope for one audio track, decoded once and then read at
/// any time by the level meter.
///
/// `VideoWaveform` already decodes a *mono* envelope for the timeline's music
/// band; this is the meter's version and differs in the two ways the meter
/// needs: it keeps the channels apart (a meter that draws two identical bars
/// is drawing one bar twice), and it works from an `AVAssetTrack`, so a clip's
/// audio can be measured without going back to a file URL the studio does not
/// have for a `PHAsset`.
enum VideoAudioEnvelope {
    struct Samples: Sendable {
        /// Peak amplitude, 0…1, one value per bucket, left then right.
        var left: [Float]
        var right: [Float]
        /// Source seconds the buckets span, so a timeline second can be
        /// turned into a bucket index.
        var duration: Double

        /// Peak in each channel at `seconds` into the source. Out-of-range
        /// times read as silence rather than clamping to the nearest edge:
        /// a clip trimmed past its end really is silent there.
        func peak(atSourceSeconds seconds: Double) -> (left: Float, right: Float) {
            guard duration > 0, !left.isEmpty, seconds >= 0, seconds <= duration else {
                return (0, 0)
            }
            let index = min(left.count - 1, Int(seconds / duration * Double(left.count)))
            return (left[index], right.isEmpty ? left[index] : right[min(right.count - 1, index)])
        }
    }

    /// Decodes `buckets` stereo peaks from one audio track.
    ///
    /// The reader is asked for two interleaved channels whatever the source
    /// is, so a mono track arrives as dual mono and the caller never has to
    /// branch on channel count.
    static func samples(
        for track: AVAssetTrack,
        of asset: AVAsset,
        buckets: Int
    ) async -> Samples? {
        guard buckets > 0 else { return nil }
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration > 0 else { return nil }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var leftPeaks: [Float] = []
        var rightPeaks: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                CMSampleBufferInvalidate(sample)
                continue
            }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let frames = raw.bindMemory(to: Int16.self)
                // Sparse stride, same reasoning as the waveform decoder: an
                // envelope needs coverage of the track, not every frame of it.
                // The step stays even so it never slips between channels.
                let step = max(2, (frames.count / 2048) & ~1)
                var index = 0
                while index + 1 < frames.count {
                    leftPeaks.append(abs(Float(frames[index]) / Float(Int16.max)))
                    rightPeaks.append(abs(Float(frames[index + 1]) / Float(Int16.max)))
                    index += step
                }
            }
            CMSampleBufferInvalidate(sample)
        }
        guard !leftPeaks.isEmpty else { return nil }

        return Samples(
            left: bucket(leftPeaks, into: buckets),
            right: bucket(rightPeaks, into: buckets),
            duration: duration
        )
    }

    /// Peak-per-bucket, **not** normalized: a meter reads absolute level, so
    /// scaling the loudest moment to 1.0 — which is right for a waveform
    /// drawing — would tell the user every project peaks at 0 dBFS.
    private static func bucket(_ peaks: [Float], into buckets: Int) -> [Float] {
        var result = [Float](repeating: 0, count: buckets)
        let per = Double(peaks.count) / Double(buckets)
        for bucket in 0..<buckets {
            let low = Int(Double(bucket) * per)
            let high = min(peaks.count, max(low + 1, Int(Double(bucket + 1) * per)))
            guard low < high else { continue }
            var maxValue: Float = 0
            for index in low..<high { maxValue = max(maxValue, peaks[index]) }
            result[bucket] = maxValue
        }
        return result
    }
}
