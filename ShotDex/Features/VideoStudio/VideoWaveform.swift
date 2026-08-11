import AVFoundation
import Foundation

/// Decodes an audio file into normalized peak buckets for the timeline's music
/// band. Nonisolated + async so it runs off the main actor; the caller hops the
/// result back. Real samples, not a synthesized pattern (spec §4.4).
enum VideoWaveform {
    /// `buckets` amplitude values in 0…1. Empty on any decode failure — the
    /// band then falls back to a flat bar.
    static func samples(from url: URL, buckets: Int) async -> [Float] {
        guard buckets > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset)
        else { return [] }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var peaks: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return [] }
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
                let ints = raw.bindMemory(to: Int16.self)
                // Sparse stride: a peak envelope needs coverage, not every
                // sample, and a long track is millions of frames.
                let step = max(1, ints.count / 1024)
                var index = 0
                while index < ints.count {
                    peaks.append(abs(Float(ints[index]) / Float(Int16.max)))
                    index += step
                }
            }
            CMSampleBufferInvalidate(sample)
        }
        guard !peaks.isEmpty else { return [] }

        var result = [Float](repeating: 0, count: buckets)
        let per = Double(peaks.count) / Double(buckets)
        for bucket in 0..<buckets {
            let low = Int(Double(bucket) * per)
            let high = min(peaks.count, max(low + 1, Int(Double(bucket + 1) * per)))
            var maxValue: Float = 0
            for i in low..<high { maxValue = max(maxValue, peaks[i]) }
            result[bucket] = maxValue
        }
        let peak = result.max() ?? 1
        if peak > 0 {
            for i in result.indices { result[i] /= peak }
        }
        return result
    }
}
