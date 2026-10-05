import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// FS-12.14 §6 end to end, without PhotoKit: captions burnt into the frames
/// the writer encodes (AC-9), or written as a subtitle track with clean
/// frames (AC-10).
@Suite(.serialized) @MainActor
struct VideoCaptionExportTests {
    /// A 9.5 s mid-grey 9:16 project with "starts right here." 6.0–7.4 s.
    private func export(burnsIn: Bool) async throws -> (url: URL, directory: URL, service: VideoStudioService) {
        let directory = try VideoExportFixtures.makeDirectory()
        let file = directory.appendingPathComponent("grey.mp4")
        try await VideoExportFixtures.writeVideo(width: 540, height: 960, seconds: 9.5, fill: .flat(red: 0.5, green: 0.5, blue: 0.5), to: file)
        var recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("grey", seconds: 9.5)])
        recipe.aspect = .r9x16
        var lane = VideoCaptionLane()
        lane.style = .box
        lane.burnsIn = burnsIn
        let clip = recipe.clips[0].id
        lane.cues = [
            CaptionCue(clipID: clip, sourceStart: 2.0, sourceEnd: 3.0, text: "The road to Vík"),
            CaptionCue(clipID: clip, sourceStart: 6.0, sourceEnd: 7.4, text: "starts right here.", words: [
                .init(text: "starts", start: 6.0, end: 6.38), .init(text: "right", start: 6.4, end: 6.7), .init(text: "here.", start: 6.72, end: 7.4),
            ]),
        ]
        recipe.captions = lane
        let service = VideoExportFixtures.service()
        let url = try await service.export(
            recipe: recipe,
            sources: [clip: try await VideoExportFixtures.videoSource(file)],
            progress: { _ in }
        )
        return (url, directory, service)
    }

    /// Rows of the frame holding a pixel brighter than `threshold` inside
    /// the middle third of the width.
    private func brightRows(_ frame: (width: Int, height: Int, bytes: [UInt8]), threshold: Int = 230) -> [Int] {
        (0..<frame.height).filter { row in
            stride(from: frame.width / 3, to: frame.width * 2 / 3, by: 2).contains { column in
                let index = (row * frame.width + column) * 4
                return Int(frame.bytes[index]) > threshold && Int(frame.bytes[index + 1]) > threshold && Int(frame.bytes[index + 2]) > threshold
            }
        }
    }

    /// Rows darker than the grey: the Box plate (black at 62 %, laid on
    /// in the compositor's linear light — the grey 139 reads about 89).
    private func darkRows(_ frame: (width: Int, height: Int, bytes: [UInt8])) -> [Int] {
        (0..<frame.height).filter { row in
            let index = (row * frame.width + frame.width / 2 - 200) * 4
            return Int(frame.bytes[index + 1]) < 110
        }
    }

    /// AC-9: Box, 6 %, Bottom, burnt in at 1080×1920 — at 6.5 s the plate is
    /// there with text 65 ± 3 px tall centred on y 1632 ± 19; at 9.0 s (no
    /// caption) nothing is.
    @Test func boxAt6_5sNoneAt9_0s() async throws {
        let (url, directory, service) = try await export(burnsIn: true)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let frame = try await VideoExportFixtures.frame(of: url, at: 6.5)
        #expect(frame.width == 1080 && frame.height == 1920)
        let text = brightRows(frame)
        let plate = darkRows(frame)
        let textHeight = (text.last ?? 0) - (text.first ?? 0) + 1
        #expect(abs(textHeight - 65) <= 3, "text rows \(text.first ?? -1)…\(text.last ?? -1)")
        let plateCentre = Double((plate.first ?? 0) + (plate.last ?? 0)) / 2
        #expect(abs(plateCentre - 1632) <= 19, "plate rows \(plate.first ?? -1)…\(plate.last ?? -1)")
        let empty = try await VideoExportFixtures.frame(of: url, at: 9.0)
        #expect(brightRows(empty).isEmpty)
        #expect(darkRows(empty).isEmpty)
    }

    /// AC-10: Burn into video off — the frame at 6.5 s is clean, and the file
    /// has one en-US subtitle track with one sample per caption, the one
    /// at 6.5 s reading "starts right here.".
    @Test func softTrackOneSamplePerCue() async throws {
        let (url, directory, service) = try await export(burnsIn: false)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let asset = AVURLAsset(url: url)
        let texts = try await asset.loadTracks(withMediaType: .text) + asset.loadTracks(withMediaType: .subtitle)
        #expect(texts.count == 1)
        let track = try #require(texts.first)
        let (tag, code) = try await track.load(.extendedLanguageTag, .languageCode)
        #expect(tag == "en-US" || code == "eng", "tag \(tag ?? "nil"), code \(code ?? "nil")")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var samples: [(start: Double, text: String)] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 2 else { continue }
            var bytes = [UInt8](repeating: 0, count: length)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
            let count = Int(bytes[0]) << 8 | Int(bytes[1])
            guard count > 0 else { continue }
            let text = String(decoding: bytes[2..<(2 + count)], as: UTF8.self)
            samples.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds, text))
        }
        #expect(samples.count == 2)
        #expect(samples.first { $0.start <= 6.5 && $0.start >= 5.9 }?.text == "starts right here.")
    }

    @Test func burnOffLeavesFramesClean() async throws {
        let (url, directory, service) = try await export(burnsIn: false)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let frame = try await VideoExportFixtures.frame(of: url, at: 6.5)
        #expect(brightRows(frame).isEmpty)
        #expect(darkRows(frame).isEmpty)
    }
}
