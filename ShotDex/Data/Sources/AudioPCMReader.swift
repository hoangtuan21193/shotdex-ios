import AVFoundation
import Foundation

/// Reads an audio file — or the sound of a video — as mono 32-bit floats at
/// one sample rate, for analysis (FS-12.12 §4, FS-12.13 §4). The resampling
/// is AVFoundation's. Checks for cancellation on every buffer, so a deleted
/// track or a closed studio stops a decode within a buffer's time.
/// Nonisolated: it runs wherever its caller's task runs.
enum AudioPCMReader {
    enum ReadError: Error, Equatable {
        case noAudio
        case unreadable
        case cancelled
    }

    /// The samples of `url`'s first audio track at `sampleRate`, or of the
    /// part `range` (source seconds) of it.
    static func read(_ url: URL, sampleRate: Double, range: ClosedRange<Double>? = nil) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { throw ReadError.noAudio }
        return try read(track: track, asset: asset, sampleRate: sampleRate, range: range)
    }

    static func read(track: AVAssetTrack, asset: AVAsset, sampleRate: Double, range: ClosedRange<Double>? = nil) throws -> [Float] {
        guard let reader = try? AVAssetReader(asset: asset) else { throw ReadError.unreadable }
        if let range {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: range.upperBound, preferredTimescale: 600)
            )
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ReadError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw ReadError.unreadable }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw ReadError.cancelled
            }
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                let count = length / MemoryLayout<Float>.size
                let start = samples.count
                samples.append(contentsOf: repeatElement(0, count: count))
                samples.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base + start * MemoryLayout<Float>.size)
                }
            }
            CMSampleBufferInvalidate(buffer)
        }
        guard reader.status == .completed else { throw ReadError.unreadable }
        return samples
    }
}
