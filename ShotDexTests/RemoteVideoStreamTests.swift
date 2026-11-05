import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: Compare plays a video from the server where it lies —
/// AVFoundation reads it through `RemoteVideoStream` in range reads, never
/// a download of the whole file.
@Suite(.timeLimit(.minutes(1)))
struct RemoteVideoStreamTests {
    /// A 2-second H.264 clip, served by an in-memory server at `path`.
    private func served(at path: String) async throws -> (client: InMemoryRemoteFileClient, bytes: Data) {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clip.mp4")
        try await VideoExportFixtures.writeVideo(width: 320, height: 240, seconds: 2, to: url)
        let bytes = try Data(contentsOf: url)
        let client = InMemoryRemoteFileClient()
        client.put(path, bytes)
        return (client, bytes)
    }

    @Test func playsFromRangeReads() async throws {
        let path = "photos/Tuan/2026/05/02/clip.MP4"
        let (client, bytes) = try await served(at: path)
        let stream = RemoteVideoStream(client: client, path: path, size: Int64(bytes.count))
        defer { stream.cancel() }

        #expect(try await stream.asset.load(.isPlayable))
        let duration = try await stream.asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.1, "duration \(duration)")
        // A frame from the middle: the reads reach past the header.
        let generator = AVAssetImageGenerator(asset: stream.asset)
        let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        #expect(image.width == 320 && image.height == 240)
        #expect(!client.rangeReadPaths.isEmpty)
        #expect(Set(client.rangeReadPaths) == [path])
    }

    /// The server holds less than the scan listed: AVFoundation is told, the
    /// asset does not play, nothing hangs.
    @Test func fileShorterThanListedDoesNotPlay() async throws {
        let path = "photos/Vo/clip.mp4"
        let (client, bytes) = try await served(at: path)
        client.put(path, bytes.prefix(bytes.count / 3))
        let stream = RemoteVideoStream(client: client, path: path, size: Int64(bytes.count))
        defer { stream.cancel() }

        let generator = AVAssetImageGenerator(asset: stream.asset)
        await #expect(throws: (any Error).self) {
            _ = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600))
        }
    }
}
