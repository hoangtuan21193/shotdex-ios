import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ShotDex

/// Media for export tests that never touches PhotoKit: synthetic videos and
/// tones written with `AVAssetWriter`, and photos as JPEGs on disk read the
/// way a server photo is (`VideoStudioService.setServerFiles`). The export
/// path under test is the real one — `VideoStudioService.export` through the
/// custom compositor and the reader → writer pipeline.
enum VideoExportFixtures {
    /// A scratch folder per test; the caller removes it.
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexVideoExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A service whose Photos import is never reached by these tests.
    @MainActor
    static func service() -> VideoStudioService {
        VideoStudioService(
            importFile: { _, _ in throw CancellationError() },
            indexNewAsset: { _ in },
            publishCreatedAsset: {}
        )
    }

    enum Fill {
        /// One flat colour, 0…1 sRGB.
        case flat(red: Double, green: Double, blue: Double)
        /// Fresh random pixels every frame — the worst case for an encoder,
        /// so its rate control has to sit at the target bitrate.
        case noise
    }

    /// A video file, H.264 at `fps`, `seconds` long.
    static func writeVideo(
        width: Int, height: Int, seconds: Double, fps: Int = 30,
        fill: Fill = .flat(red: 0.2, green: 0.5, blue: 0.7), to url: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 8],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)

        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        let frames = Int((seconds * Double(fps)).rounded())
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CancellationError() }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            switch fill {
            case let .flat(red, green, blue):
                let pixel = UInt32(255) << 24
                    | UInt32((red * 255).rounded()) << 16
                    | UInt32((green * 255).rounded()) << 8
                    | UInt32((blue * 255).rounded())
                for row in 0..<height {
                    let line = (base + row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
                    for column in 0..<width { line[column] = pixel }
                }
            case .noise:
                let words = bytesPerRow * height / 8
                let pointer = base.assumingMemoryBound(to: UInt64.self)
                for index in 0..<words {
                    state ^= state << 13
                    state ^= state >> 7
                    state ^= state << 17
                    pointer[index] = state | 0xFF00_0000_FF00_0000
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
    }

    /// A 440 Hz tone as AAC, for a music bed.
    static func writeTone(seconds: Double, to url: URL) async throws {
        let sampleRate = 44_100
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)

        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        guard let format else { throw CancellationError() }

        let total = Int(seconds * Double(sampleRate))
        let chunk = 4096
        var written = 0
        while written < total {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let count = min(chunk, total - written)
            var samples = [Int16](repeating: 0, count: count)
            for index in 0..<count {
                let time = Double(written + index) / Double(sampleRate)
                samples[index] = Int16(sin(2 * .pi * 440 * time) * 8000)
            }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block
            )
            guard let block else { throw CancellationError() }
            samples.withUnsafeBytes { bytes in
                _ = CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count * 2
                )
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &sample
            )
            guard let sample else { throw CancellationError() }
            input.append(sample)
            written += count
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
    }

    /// A flat-colour JPEG on disk, the shape of a server photo.
    static func writePhoto(width: Int, height: Int, red: Double = 0.8, green: Double = 0.3, blue: Double = 0.2,
                           to url: URL) throws {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CancellationError() }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CancellationError() }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CancellationError() }
    }

    /// A video file as the composition source the service would resolve.
    static func videoSource(_ url: URL) async throws -> VideoClipSource {
        let asset = AVURLAsset(url: url)
        let track = try await requireTrack(asset.loadTracks(withMediaType: .video).first)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration).seconds
        return .video(asset: asset, videoTrack: track, audioTrack: audio, duration: duration,
                      naturalSize: size, preferredTransform: transform)
    }

    /// A video clip whose trim window is the whole file.
    static func videoClip(_ id: String, seconds: Double) -> VideoClip {
        var clip = VideoClip(assetID: id, kind: .video)
        clip.sourceDuration = seconds
        clip.trimEnd = seconds
        return clip
    }

    /// What came out: size, rate, codec, length and the tracks.
    struct Output {
        let naturalSize: CGSize
        let nominalFrameRate: Float
        let codec: FourCharCode?
        let duration: Double
        let videoTrackDuration: Double
        let estimatedDataRate: Float
        let audioTrackCount: Int
        let videoSampleCount: Int
        let fileBytes: Int
    }

    static func inspect(_ url: URL) async throws -> Output {
        let asset = AVURLAsset(url: url)
        let track = try await requireTrack(asset.loadTracks(withMediaType: .video).first)
        let (size, rate, range, dataRate, formats) = try await track.load(
            .naturalSize, .nominalFrameRate, .timeRange, .estimatedDataRate, .formatDescriptions
        )
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var samples = 0
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { samples += 1 }
        }
        let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return Output(
            naturalSize: size, nominalFrameRate: rate,
            codec: formats.first.map(CMFormatDescriptionGetMediaSubType),
            duration: duration, videoTrackDuration: range.duration.seconds,
            estimatedDataRate: dataRate, audioTrackCount: audio.count,
            videoSampleCount: samples, fileBytes: bytes
        )
    }

    /// One decoded frame of the file, as sRGB bytes (RGBA, row 0 at the top).
    static func frame(of url: URL, at seconds: Double) async throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, bytes)
    }

    struct MissingTrack: Error {}

    private static func requireTrack(_ track: AVAssetTrack?) throws -> AVAssetTrack {
        guard let track else { throw MissingTrack() }
        return track
    }
}
