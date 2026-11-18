#if DEBUG
import AVFoundation
import AppKit
import CoreGraphics

extension MacVideoCompressPage {
    /// `-ShotDexSection videoCompare`: the demo batch's files are not in
    /// Photos, so Compare plays a generated clip for both sides — a street
    /// sign with fine text, no people (`no-face-photos-in-tests`).
    struct DemoCompareLoader: VideoCompareLoading {
        func playerItem(for id: String) async -> AVPlayerItem? {
            guard let url = await DemoClip.url() else { return nil }
            return AVPlayerItem(url: url)
        }
    }

    /// Written once per launch into the temporary folder.
    @MainActor
    enum DemoClip {
        private static var task: Task<URL?, Never>?

        static func url() async -> URL? {
            if let task { return await task.value }
            let made = Task.detached(priority: .userInitiated) { try? await write() }
            task = made
            return await made.value
        }

        private nonisolated static func write() async throws -> URL {
            let url = URL.temporaryDirectory.appendingPathComponent("ShotDexCompareDemo.mov")
            try? FileManager.default.removeItem(at: url)
            let width = 1920, height = 1080, frames = 90
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            for index in 0..<frames {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                guard let pool = adaptor.pixelBufferPool else { break }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { break }
                draw(into: buffer, frame: index, width: width, height: height)
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30))
            }
            input.markAsFinished()
            await writer.finishWriting()
            return url
        }

        private nonisolated static func draw(into buffer: CVPixelBuffer, frame: Int, width: Int, height: Int) {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return }
            let w = CGFloat(width), h = CGFloat(height)
            // Sky, wall, road (CoreGraphics' y runs up).
            context.setFillColor(NSColor(red: 0.62, green: 0.72, blue: 0.82, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.setFillColor(NSColor(red: 0.43, green: 0.35, blue: 0.28, alpha: 1).cgColor)
            context.fill(CGRect(x: w * 0.22, y: h * 0.12, width: w * 0.56, height: h * 0.8))
            context.setFillColor(NSColor(red: 0.29, green: 0.31, blue: 0.32, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.12))
            // Shutters, then the sign, drifting a little so playback shows.
            let drift = CGFloat(frame) * 2
            for column in 0..<40 {
                context.setFillColor((column % 2 == 0 ? NSColor(red: 0.17, green: 0.23, blue: 0.28, alpha: 1)
                                                      : NSColor(red: 0.24, green: 0.33, blue: 0.39, alpha: 1)).cgColor)
                context.fill(CGRect(x: w * 0.34 + CGFloat(column) * w * 0.008, y: h * 0.12, width: w * 0.008, height: h * 0.3))
            }
            let sign = CGRect(x: w * 0.34 + drift, y: h * 0.52, width: w * 0.32, height: h * 0.18)
            context.setFillColor(NSColor(red: 0.11, green: 0.16, blue: 0.2, alpha: 1).cgColor)
            context.fill(sign)
            let text = NSAttributedString(string: "OPEN 7–22  ·  fine print 1234567890", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 34),
                .foregroundColor: NSColor(red: 0.95, green: 0.77, blue: 0.42, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(text)
            context.textPosition = CGPoint(x: sign.minX + 30, y: sign.midY - 12)
            CTLineDraw(line, context)
        }
    }
}
#endif
