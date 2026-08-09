import AVFoundation
import Foundation

/// Writes the composited video to a file with an `AVAssetReader` →
/// `AVAssetWriter` pipeline. The reader's video output carries our
/// `AVVideoComposition` (with the custom `VideoFrameCompositor`), so every
/// frame is composited exactly as the preview shows; the writer re-encodes to
/// H.264. `AVAssetExportSession` is not used — it rejects a custom video
/// compositor outright (-11838 / -16976, regardless of preset).
enum VideoExportWriter {
    /// Reader/writer errors surface as this so the model shows one message.
    struct ExportError: LocalizedError {
        let errorDescription: String?
    }

    static func write(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix,
        renderSize: CGSize,
        totalDuration: Double,
        to outputURL: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        // MARK: Reader
        let reader = try AVAssetReader(asset: composition)
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw ExportError(errorDescription: String(localized: "There is no video to export."))
        }
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ExportError(errorDescription: String(localized: "Couldn't read the video frames."))
        }
        reader.add(videoOutput)

        // Only real audio: a photo-only project still carries the empty A/B
        // audio tracks the builder always adds, and reading those through an
        // audio mix fails with a format error (-12710). Drop empty tracks.
        let audioTracks = composition.tracks(withMediaType: .audio)
            .filter { $0.timeRange.duration.seconds > 0.01 }
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
            )
            output.audioMix = audioMix
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        // MARK: Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // ~10 Mbps at 1080p, scaling with pixel count (≈40 Mbps at 4K).
        let bitrate = Int(renderSize.width * renderSize.height * 4.8)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(renderSize.width),
                AVVideoHeightKey: Int(renderSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw ExportError(errorDescription: String(localized: "Couldn't prepare the video encoder."))
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ]
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw reader.error ?? ExportError(errorDescription: String(localized: "Couldn't start reading."))
        }
        guard writer.startWriting() else {
            throw writer.error ?? ExportError(errorDescription: String(localized: "Couldn't start writing."))
        }
        writer.startSession(atSourceTime: .zero)

        let denominator = max(totalDuration, 0.01)

        // Pump each output→input on its own queue; finish when both drain.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let group = DispatchGroup()

                group.enter()
                let videoQueue = DispatchQueue(label: "shotdex.export.video")
                videoInput.requestMediaDataWhenReady(on: videoQueue) {
                    while videoInput.isReadyForMoreMediaData {
                        guard reader.status == .reading,
                              let sample = videoOutput.copyNextSampleBuffer() else {
                            videoInput.markAsFinished()
                            group.leave()
                            return
                        }
                        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        if seconds.isFinite {
                            let fraction = min(max(seconds / denominator, 0), 1)
                            Task { @MainActor in progress(fraction) }
                        }
                        videoInput.append(sample)
                    }
                }

                if let audioInput, let audioOutput {
                    group.enter()
                    let audioQueue = DispatchQueue(label: "shotdex.export.audio")
                    audioInput.requestMediaDataWhenReady(on: audioQueue) {
                        while audioInput.isReadyForMoreMediaData {
                            guard reader.status == .reading,
                                  let sample = audioOutput.copyNextSampleBuffer() else {
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }
                            audioInput.append(sample)
                        }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    if reader.status == .failed {
                        writer.cancelWriting()
                        continuation.resume(throwing: reader.error
                            ?? ExportError(errorDescription: String(localized: "Reading the video failed.")))
                        return
                    }
                    if reader.status == .cancelled {
                        writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    writer.finishWriting {
                        switch writer.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing: writer.error
                                ?? ExportError(errorDescription: String(localized: "Writing the video failed.")))
                        }
                    }
                }
            }
        } onCancel: {
            reader.cancelReading()
        }

        await progress(1)
    }
}
