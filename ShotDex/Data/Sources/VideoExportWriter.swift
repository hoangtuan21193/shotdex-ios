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

    /// The reader, writer and their outputs/inputs, handed to the pump
    /// closures. AVFoundation does not mark these `Sendable`, but this is the
    /// pattern it documents for them: each input is fed only on the queue
    /// given to `requestMediaDataWhenReady`, and the reader and writer are
    /// otherwise only asked for their status, cancelled, or finished once
    /// both pumps have drained.
    private struct Pipeline: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let videoOutput: AVAssetReaderVideoCompositionOutput
        let videoInput: AVAssetWriterInput
        let audio: AudioPump?
    }

    /// The audio half of `Pipeline`, present only when there is real audio.
    private struct AudioPump: @unchecked Sendable {
        let output: AVAssetReaderAudioMixOutput
        let input: AVAssetWriterInput
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

        let pipe = Pipeline(reader: reader, writer: writer,
                            videoOutput: videoOutput, videoInput: videoInput,
                            audio: audioOutput.flatMap { output in
                                audioInput.map { AudioPump(output: output, input: $0) }
                            })

        // Pump each output→input on its own queue; finish when both drain.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let group = DispatchGroup()

                group.enter()
                let videoQueue = DispatchQueue(label: "shotdex.export.video")
                // Last fraction actually reported. The pump runs once per
                // sample — thirty times a second, for the length of the
                // video — and a MainActor hop per frame is a task storm
                // competing with the UI for the whole export. A percent is
                // finer than the progress bar can draw.
                var reportedFraction = -1.0
                pipe.videoInput.requestMediaDataWhenReady(on: videoQueue) {
                    while pipe.videoInput.isReadyForMoreMediaData {
                        guard pipe.reader.status == .reading,
                              let sample = pipe.videoOutput.copyNextSampleBuffer() else {
                            pipe.videoInput.markAsFinished()
                            group.leave()
                            return
                        }
                        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        if seconds.isFinite {
                            let fraction = min(max(seconds / denominator, 0), 1)
                            if fraction - reportedFraction >= 0.01 || fraction >= 1 {
                                reportedFraction = fraction
                                Task { @MainActor in progress(fraction) }
                            }
                        }
                        pipe.videoInput.append(sample)
                    }
                }

                if let audio = pipe.audio {
                    group.enter()
                    let audioQueue = DispatchQueue(label: "shotdex.export.audio")
                    audio.input.requestMediaDataWhenReady(on: audioQueue) {
                        while audio.input.isReadyForMoreMediaData {
                            guard pipe.reader.status == .reading,
                                  let sample = audio.output.copyNextSampleBuffer() else {
                                audio.input.markAsFinished()
                                group.leave()
                                return
                            }
                            audio.input.append(sample)
                        }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    if pipe.reader.status == .failed {
                        pipe.writer.cancelWriting()
                        continuation.resume(throwing: pipe.reader.error
                            ?? ExportError(errorDescription: String(localized: "Reading the video failed.")))
                        return
                    }
                    if pipe.reader.status == .cancelled {
                        pipe.writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    pipe.writer.finishWriting {
                        switch pipe.writer.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing: pipe.writer.error
                                ?? ExportError(errorDescription: String(localized: "Writing the video failed.")))
                        }
                    }
                }
            }
        } onCancel: {
            pipe.reader.cancelReading()
        }

        await progress(1)
    }
}
