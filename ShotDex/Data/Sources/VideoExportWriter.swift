import AVFoundation
import os
import Foundation
import VideoToolbox

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
        /// Set by a cancel. The pumps read it and stop; the reader itself is
        /// cancelled only after both have drained — `cancelReading` while a
        /// pump is inside `copyNextSampleBuffer` crashes in MediaToolbox.
        let isCancelled = OSAllocatedUnfairLock(initialState: false)
    }

    /// The audio half of `Pipeline`, present only when there is real audio.
    /// The subtitle track's input and its samples, one per caption.
    private final class SubtitlePump: @unchecked Sendable {
        let input: AVAssetWriterInput
        let samples: [CMSampleBuffer]
        var next = 0
        init(input: AVAssetWriterInput, samples: [CMSampleBuffer]) {
            self.input = input
            self.samples = samples
        }
    }

    private struct AudioPump: @unchecked Sendable {
        let output: AVAssetReaderAudioMixOutput
        let input: AVAssetWriterInput
    }

    /// An H.264 encoder that will not take this frame size — a 4K portrait
    /// frame on some devices — is said plainly, with the way out; the codec
    /// is not switched behind the user's back (FS-12.10b §5, AC-14).
    static func refusal(_ encoding: VideoEncodingSettings) -> ExportError? {
        guard encoding.codec == .h264 else { return nil }
        return ExportError(errorDescription: VideoStudioCopy.h264SizeRefused)
    }

    /// A writer that failed while encoding: an H.264 frame larger than
    /// 1080p's area is the encoder refusing the size; anything else keeps
    /// its own error.
    static func encoderFailure(_ error: Error?, _ encoding: VideoEncodingSettings) -> Error {
        if encoding.size.width * encoding.size.height > 1920 * 1080, let refusal = refusal(encoding) {
            return refusal
        }
        return error ?? ExportError(errorDescription: String(localized: "Writing the video failed."))
    }

    /// The writer's video settings for an encoding: codec, size, average
    /// bitrate, profile, and the frame rate it should expect.
    static func videoSettings(_ encoding: VideoEncodingSettings) -> [String: Any] {
        let profile: String = encoding.codec == .hevc
            ? kVTProfileLevel_HEVC_Main_AutoLevel as String
            : AVVideoProfileLevelH264HighAutoLevel
        return [
            AVVideoCodecKey: encoding.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(encoding.size.width),
            AVVideoHeightKey: Int(encoding.size.height),
            // SDR Rec. 709, said in the file: an untagged track is left to
            // each player's guess, and Photos and QuickTime guessed #808080
            // ten levels off (FS-12.01 §9).
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: encoding.bitrate,
                AVVideoProfileLevelKey: profile,
                AVVideoExpectedSourceFrameRateKey: encoding.frameRate.rawValue,
            ] as [String: Any],
        ]
    }

    static func write(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix,
        encoding: VideoEncodingSettings,
        totalDuration: Double,
        /// Captions as a soft subtitle track when they are not burnt in
        /// (FS-12.14 §6).
        subtitles: VideoSubtitleTrackWriter.Track? = nil,
        to outputURL: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        do {
            try await pump(
                composition: composition, videoComposition: videoComposition, audioMix: audioMix,
                encoding: encoding, totalDuration: totalDuration, subtitles: subtitles, to: outputURL, progress: progress
            )
        } catch {
            // Cancelled or failed: no half-written file is left behind
            // (FS-12.10b §5).
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func pump(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix,
        encoding: VideoEncodingSettings,
        totalDuration: Double,
        subtitles: VideoSubtitleTrackWriter.Track?,
        to outputURL: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {

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
        // The rate the Output line promised (VideoExportEstimate): ~10 Mbps
        // at 1080p30 H.264, HEVC at 0.6 of that.
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: Self.videoSettings(encoding)
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw refusal(encoding) ?? ExportError(errorDescription: String(localized: "Couldn't prepare the video encoder."))
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

        // Timed text, one sample per caption, appended alongside.
        let subtitlePump = subtitles.flatMap { track in
            VideoSubtitleTrackWriter.input(for: track, writer: writer).map {
                SubtitlePump(input: $0, samples: VideoSubtitleTrackWriter.samples(for: track))
            }
        }

        guard reader.startReading() else {
            throw reader.error ?? ExportError(errorDescription: String(localized: "Couldn't start reading."))
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw refusal(encoding) ?? writer.error ?? ExportError(errorDescription: String(localized: "Couldn't start writing."))
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
                        guard !pipe.isCancelled.withLock({ $0 }), pipe.reader.status == .reading,
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
                            guard !pipe.isCancelled.withLock({ $0 }), pipe.reader.status == .reading,
                                  let sample = audio.output.copyNextSampleBuffer() else {
                                audio.input.markAsFinished()
                                group.leave()
                                return
                            }
                            audio.input.append(sample)
                        }
                    }
                }

                if let subtitlePump {
                    group.enter()
                    let textQueue = DispatchQueue(label: "shotdex.export.subtitles")
                    subtitlePump.input.requestMediaDataWhenReady(on: textQueue) {
                        while subtitlePump.input.isReadyForMoreMediaData {
                            guard !pipe.isCancelled.withLock({ $0 }), subtitlePump.next < subtitlePump.samples.count else {
                                subtitlePump.input.markAsFinished()
                                group.leave()
                                return
                            }
                            subtitlePump.input.append(subtitlePump.samples[subtitlePump.next])
                            subtitlePump.next += 1
                        }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    if pipe.isCancelled.withLock({ $0 }) {
                        pipe.reader.cancelReading()
                        pipe.writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    // The encoder gave up on the frames: for H.264 at a size
                    // past what it takes, that is the refusal of §5.
                    if pipe.writer.status == .failed {
                        pipe.reader.cancelReading()
                        continuation.resume(throwing: encoderFailure(pipe.writer.error, encoding))
                        return
                    }
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
                            continuation.resume(throwing: encoderFailure(pipe.writer.error, encoding))
                        }
                    }
                }
            }
        } onCancel: {
            pipe.isCancelled.withLock { $0 = true }
        }

        await progress(1)
    }
}
