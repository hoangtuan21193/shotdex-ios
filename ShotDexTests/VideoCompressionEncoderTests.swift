import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// FS-24 AC-24.06 / AC-24.07: the real encoder on generated files.
@Suite(.timeLimit(.minutes(2)))
struct VideoCompressionEncoderTests {
    /// AC-24.06: HEVC out, same duration, size capped, no audio invented.
    @Test func encodesHEVCAtCappedSize() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 2, fill: .grain(amplitude: 20), to: source)

        try await VideoCompressionEncoder.encode(
            source, to: output,
            settings: .init(quality: .balanced, size: .original),
            progress: { _ in }
        )

        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, descriptions) = try await track.load(.naturalSize, .formatDescriptions)
        let codec = try #require(descriptions.first).mediaSubType
        #expect(codec == .hevc)
        #expect(size == CGSize(width: 1280, height: 720))
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    /// AC-24.04 on a real file: the 1080p cap halves a 4K-wide clip and
    /// leaves a smaller one alone.
    @Test func capsLongEdge() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await VideoExportFixtures.writeVideo(width: 3840, height: 2160, seconds: 0.5, to: source)

        try await VideoCompressionEncoder.encode(
            source, to: output, settings: .init(quality: .high, size: .fullHD), progress: { _ in }
        )

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1920, height: 1080))
    }

    /// AC-24.07: an HLG BT.2020 source stays HLG BT.2020, 10-bit.
    @Test func keepsHLG() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("hlg.mov")
        let output = directory.appendingPathComponent("output.mp4")
        try await Self.writeHLG(to: source)

        try await VideoCompressionEncoder.encode(
            source, to: output, settings: .init(quality: .high, size: .original), progress: { _ in }
        )

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        let primaries = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
        #expect(transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        #expect(primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String))
        let depth = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? Int
        #expect(depth == nil || depth == 10)
    }

    /// AC-24.06: AAC sound is copied, not encoded again. The source carries
    /// AAC at 96 kbps; an encode would come out at 256 kbps.
    @Test func copiesAACSound() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Self.writeVideoWithAAC(in: directory, bitrate: 96_000)
        let output = directory.appendingPathComponent("output.mp4")

        try await VideoCompressionEncoder.encode(
            source, to: output, settings: .init(quality: .high, size: .original), progress: { _ in }
        )

        let sourceAudio = try #require(try await AVURLAsset(url: source).loadTracks(withMediaType: .audio).first)
        let audio = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).first)
        let description = try #require(try await audio.load(.formatDescriptions).first)
        #expect(description.mediaSubType == .mpeg4AAC)
        let rate = try await audio.load(.estimatedDataRate)
        let sourceRate = try await sourceAudio.load(.estimatedDataRate)
        #expect(abs(rate - sourceRate) < sourceRate * 0.05, "copied sound keeps \(sourceRate) bps, got \(rate)")
    }

    /// A 2 s clip with a 440 Hz tone in AAC at `bitrate`.
    private static func writeVideoWithAAC(in directory: URL, bitrate: Int) async throws -> URL {
        let video = directory.appendingPathComponent("video.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2, to: video)
        let audioURL = directory.appendingPathComponent("tone.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: bitrate,
            ])
            let frames = AVAudioFrameCount(48_000 * 2)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            for channel in 0..<2 {
                let samples = buffer.floatChannelData![channel]
                for index in 0..<Int(frames) {
                    samples[index] = 0.3 * sin(2 * .pi * 440 * Float(index) / 48_000)
                }
            }
            try file.write(from: buffer)
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audioURL)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: audioTrack, at: .zero)
        let source = directory.appendingPathComponent("source.mp4")
        let export = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: source, as: .mp4)
        return source
    }

    /// The colour tags are copied, not guessed: an untagged source gives nil.
    @Test func colorPropertiesNeedAllThreeTags() throws {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_HEVC, width: 64, height: 64,
                                       extensions: nil, formatDescriptionOut: &description)
        #expect(VideoCompressionEncoder.colorProperties(of: try #require(description)) == nil)
    }

    /// A half-second HEVC Main10 clip tagged HLG / BT.2020.
    private static func writeHLG(to url: URL) async throws {
        let width = 640, height = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            for plane in 0..<CVPixelBufferGetPlaneCount(pixels) {
                let base = CVPixelBufferGetBaseAddressOfPlane(pixels, plane)!
                let bytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, plane) * CVPixelBufferGetHeightOfPlane(pixels, plane)
                // Mid-level 10-bit samples, shifted into the high bits.
                memset(base, plane == 0 ? 0x80 : 0x7F, bytes)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CancellationError() }
    }
}
