import AVFoundation
import Foundation
import os
import VideoToolbox

/// FS-24 §3: re-encodes one video file to HEVC at constant quality.
///
/// The settings follow HandBrake's VideoToolbox encoder (`encvt.c`, 1.11.2)
/// — quality instead of a bitrate, `RealTime` off, speed preferred — written
/// with AVFoundation, which hands the same keys to the same hardware encoder.
/// Unlike `VideoExportWriter` (Video Studio, SDR Rec.709 8-bit by design),
/// this keeps the source's colour: frames are read as 10-bit 4:2:0 and the
/// source's primaries, transfer function and matrix are written back, so an
/// HLG or PQ clip stays HDR.
enum VideoCompressionEncoder {
    struct EncodeError: LocalizedError {
        let errorDescription: String?
    }

    struct Settings: Sendable, Equatable {
        var quality: VideoCompressionQuality
        var size: VideoCompressionSize
    }

    /// What the compression rules need about a file, read without decoding.
    static func source(of url: URL, byteCount: Int64? = nil) async throws -> VideoCompressionSource {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw EncodeError(errorDescription: String(localized: "This file has no video.", comment: "Compress Videos: the source has no video track"))
        }
        let (naturalSize, frameRate) = try await track.load(.naturalSize, .nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let bytes = byteCount
            ?? ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        return VideoCompressionSource(
            byteCount: bytes,
            duration: duration.isFinite ? duration : 0,
            pixelSize: naturalSize,
            frameRate: Double(frameRate),
            hasAudio: hasAudio
        )
    }

    /// The writer's video settings for a source track: HEVC Main10 at
    /// constant quality, the capped size, and the source's colour tags.
    static func videoSettings(
        settings: Settings,
        naturalSize: CGSize,
        frameRate: Float,
        colorProperties: [String: Any]?
    ) -> [String: Any] {
        let output = settings.size.outputSize(for: naturalSize)
        var compression: [String: Any] = [
            AVVideoQualityKey: settings.quality.encoderQuality,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            kVTCompressionPropertyKey_RealTime as String: false,
            kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true,
        ]
        if frameRate > 0 {
            compression[AVVideoExpectedSourceFrameRateKey] = Double(frameRate)
        }
        var result: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(output.width),
            AVVideoHeightKey: Int(output.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if let colorProperties { result[AVVideoColorPropertiesKey] = colorProperties }
        return result
    }

    /// `settings` with the source's mastering-display and content-light-level
    /// data, when it has them.
    static func withHDRMetadata(_ settings: [String: Any], from description: CMFormatDescription) -> [String: Any] {
        var settings = settings
        guard var compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any] else { return settings }
        if let mastering = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume) {
            compression[kVTCompressionPropertyKey_MasteringDisplayColorVolume as String] = mastering
        }
        if let lightLevel = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ContentLightLevelInfo) {
            compression[kVTCompressionPropertyKey_ContentLightLevelInfo as String] = lightLevel
        }
        settings[AVVideoCompressionPropertiesKey] = compression
        return settings
    }

    /// `settings` without the speed-over-quality hint.
    static func withoutSpeedPreference(_ settings: [String: Any]) -> [String: Any] {
        var settings = settings
        if var compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any] {
            compression.removeValue(forKey: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String)
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        return settings
    }

    /// The source's colour tags, in the writer's vocabulary. The format
    /// description's extension values are the same strings AVFoundation's
    /// colour keys use (`ITU_R_2020`, `ITU_R_2100_HLG`, …). Nil when the
    /// source does not say — the encoder then tags nothing rather than guess.
    static func colorProperties(of description: CMFormatDescription) -> [String: Any]? {
        let primaries = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
        let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        let matrix = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String
        guard let primaries, let transfer, let matrix else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
    }

    /// Reader, writer and their ends, shared with the pump queues. Each input
    /// is fed only on the queue given to `requestMediaDataWhenReady` — the
    /// pattern AVFoundation documents for these non-Sendable types.
    private struct Pipeline: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let videoOutput: AVAssetReaderTrackOutput
        let videoInput: AVAssetWriterInput
        let audioOutput: AVAssetReaderTrackOutput?
        let audioInput: AVAssetWriterInput?
        let isCancelled = OSAllocatedUnfairLock(initialState: false)
    }

    /// Encodes `source` to `output` (MP4). `progress` gets 0…1 on any queue.
    /// A cancelled or failed encode leaves no file behind.
    static func encode(
        _ source: URL,
        to output: URL,
        settings: Settings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: output)
        do {
            try await pump(source, to: output, settings: settings, progress: progress)
            try await verify(output, against: source)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// AC-24.06: the copy has video, has sound when the source had it, and
    /// runs as long (within half a second). A copy that fails this is never
    /// saved, so its original is never offered for deletion.
    static func verify(_ output: URL, against source: URL) async throws {
        let original = AVURLAsset(url: source)
        let copy = AVURLAsset(url: output)
        let failure = EncodeError(errorDescription: String(localized: "The compressed copy didn't match the original.", comment: "Compress Videos: output check failed (missing track or wrong length)"))
        guard try await !copy.loadTracks(withMediaType: .video).isEmpty else { throw failure }
        let sourceHasAudio = try await !original.loadTracks(withMediaType: .audio).isEmpty
        let copyHasAudio = try await !copy.loadTracks(withMediaType: .audio).isEmpty
        guard sourceHasAudio == copyHasAudio else { throw failure }
        let sourceSeconds = try await original.load(.duration).seconds
        let copySeconds = try await copy.load(.duration).seconds
        if sourceSeconds.isFinite, copySeconds.isFinite, abs(sourceSeconds - copySeconds) > 0.5 { throw failure }
    }

    private static func pump(
        _ source: URL,
        to output: URL,
        settings: Settings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EncodeError(errorDescription: String(localized: "This file has no video.", comment: "Compress Videos: the source has no video track"))
        }
        let (naturalSize, frameRate, transform, descriptions) = try await videoTrack.load(
            .naturalSize, .nominalFrameRate, .preferredTransform, .formatDescriptions
        )
        let duration = try await asset.load(.duration).seconds
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let metadata = (try? await asset.load(.metadata)) ?? []

        // MARK: Reader — 10-bit 4:2:0, which carries an HDR source intact and
        // costs an SDR one nothing.
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ])
        guard reader.canAdd(videoOutput) else {
            throw EncodeError(errorDescription: String(localized: "Couldn't read the video frames.", comment: "Compress Videos: reader refused the video track"))
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioChannels = 2
        var audioSampleRate = 48_000.0
        // AAC sound is copied as it is: it is a small share of the file, and
        // encoding it again only loses quality. Anything else is encoded once.
        var audioPassthroughHint: CMFormatDescription?
        if let audioTrack {
            if let description = try await audioTrack.load(.formatDescriptions).first,
               let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                audioChannels = max(1, min(Int(basic.mChannelsPerFrame), 2))
                if basic.mSampleRate > 0 { audioSampleRate = min(basic.mSampleRate, 48_000) }
                if VideoCompressionRules.copiesAudio(formatID: basic.mFormatID) {
                    audioPassthroughHint = description
                }
            }
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioPassthroughHint != nil ? nil : [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: audioChannels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            // A source with sound must keep it: a silent copy reported as
            // done would let Delete Originals take the only copy with audio.
            guard reader.canAdd(output) else {
                throw EncodeError(errorDescription: String(localized: "Couldn't read the sound of this video.", comment: "Compress Videos: reader refused the audio track"))
            }
            reader.add(output)
            audioOutput = output
        }

        // MARK: Writer
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.metadata = metadata
        writer.shouldOptimizeForNetworkUse = true
        let colors = descriptions.first.flatMap(colorProperties(of:))
        var videoSettings = Self.videoSettings(
            settings: settings, naturalSize: naturalSize, frameRate: frameRate, colorProperties: colors
        )
        // HDR10 / PQ static metadata (mastering display, light levels) rides
        // along with the colour tags, or a PQ clip plays back mis-toned.
        if let description = descriptions.first {
            videoSettings = Self.withHDRMetadata(videoSettings, from: description)
            if !writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
                videoSettings = Self.videoSettings(
                    settings: settings, naturalSize: naturalSize, frameRate: frameRate, colorProperties: colors
                )
            }
        }
        if !writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
            // The speed preference is a hint some encoders do not take (the
            // simulator's refuses it); HandBrake sets it only when the
            // session lists it among its supported properties (encvt.c:1292).
            videoSettings = Self.withoutSpeedPreference(videoSettings)
        }
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw EncodeError(errorDescription: String(localized: "This device can't encode HEVC at this size.", comment: "Compress Videos: the HEVC encoder refused the settings"))
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else {
            throw EncodeError(errorDescription: String(localized: "Couldn't prepare the video encoder.", comment: "Compress Videos: writer refused the video input"))
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input: AVAssetWriterInput
            if let audioPassthroughHint {
                input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioPassthroughHint)
            } else {
                input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audioSampleRate,
                    AVNumberOfChannelsKey: audioChannels,
                    AVEncoderBitRateKey: Int(VideoCompressionRules.audioBitrate),
                ])
            }
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw EncodeError(errorDescription: String(localized: "Couldn't prepare the sound of this video.", comment: "Compress Videos: writer refused the audio input"))
            }
            writer.add(input)
            audioInput = input
        }

        guard reader.startReading() else {
            throw reader.error ?? EncodeError(errorDescription: String(localized: "Couldn't start reading.", comment: "Compress Videos: reader did not start"))
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? EncodeError(errorDescription: String(localized: "Couldn't start writing.", comment: "Compress Videos: writer did not start"))
        }
        writer.startSession(atSourceTime: .zero)

        let pipe = Pipeline(
            reader: reader, writer: writer,
            videoOutput: videoOutput, videoInput: videoInput,
            audioOutput: audioInput == nil ? nil : audioOutput, audioInput: audioInput
        )
        let denominator = max(duration.isFinite ? duration : 0, 0.01)

        // Resumed exactly once: by the pumps finishing, or by a cancel that
        // does not wait for an encoder that may never ask for data again.
        let pending = OSAllocatedUnfairLock<CheckedContinuation<Void, Error>?>(initialState: nil)
        @Sendable func finish(_ result: Result<Void, Error>) {
            pending.withLock { continuation in
                continuation?.resume(with: result)
                continuation = nil
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending.withLock { $0 = continuation }
                if pipe.isCancelled.withLock({ $0 }) {
                    finish(.failure(CancellationError()))
                    return
                }
                let group = DispatchGroup()

                group.enter()
                // Reported once per percent, not per frame.
                var reported = -1.0
                pipe.videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "shotdex.compress.video")) {
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
                            if fraction - reported >= 0.01 {
                                reported = fraction
                                progress(fraction)
                            }
                        }
                        if !pipe.videoInput.append(sample) {
                            pipe.videoInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }

                // Read through `pipe` inside the closure: it is the one
                // Sendable box AVFoundation's documented pattern allows.
                if let audioInput = pipe.audioInput, pipe.audioOutput != nil {
                    group.enter()
                    audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "shotdex.compress.audio")) {
                        guard let input = pipe.audioInput, let output = pipe.audioOutput else { return }
                        while input.isReadyForMoreMediaData {
                            guard !pipe.isCancelled.withLock({ $0 }), pipe.reader.status == .reading,
                                  let sample = output.copyNextSampleBuffer() else {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                            if !input.append(sample) {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    if pipe.isCancelled.withLock({ $0 }) || pipe.reader.status == .cancelled {
                        pipe.reader.cancelReading()
                        pipe.writer.cancelWriting()
                        finish(.failure(CancellationError()))
                        return
                    }
                    if pipe.writer.status == .failed {
                        pipe.reader.cancelReading()
                        finish(.failure(pipe.writer.error
                            ?? EncodeError(errorDescription: String(localized: "Writing the video failed.", comment: "Compress Videos: writer failed"))))
                        return
                    }
                    if pipe.reader.status == .failed {
                        pipe.writer.cancelWriting()
                        finish(.failure(pipe.reader.error
                            ?? EncodeError(errorDescription: String(localized: "Reading the video failed.", comment: "Compress Videos: reader failed"))))
                        return
                    }
                    pipe.writer.finishWriting {
                        if pipe.writer.status == .completed {
                            progress(1)
                            finish(.success(()))
                        } else {
                            finish(.failure(pipe.writer.error
                                ?? EncodeError(errorDescription: String(localized: "Writing the video failed.", comment: "Compress Videos: writer failed"))))
                        }
                    }
                }
            }
        } onCancel: {
            pipe.isCancelled.withLock { $0 = true }
            pipe.reader.cancelReading()
            pipe.writer.cancelWriting()
            finish(.failure(CancellationError()))
        }
    }
}
