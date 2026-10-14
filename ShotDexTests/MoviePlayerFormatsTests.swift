import Foundation
import Testing
import UIKit
@testable import ShotDex

/// FS-23.02 §1: VLCKit plays every container Movies takes. Runs the real
/// engine in the test host on 5-second clips (testsrc2 + sine, made with
/// ffmpeg; no people).
@Suite(.serialized) @MainActor struct MoviePlayerFormatsTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/Movies")

    private func play(_ name: String, until done: (VLCMoviePlayer) -> Bool, timeout: Double = 12) async -> VLCMoviePlayer {
        let engine = VLCMoviePlayer(input: .file(Self.folder.appending(path: name)))
        engine.view.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.addSubview(engine.view)
        engine.play()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !done(engine) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return engine
    }

    /// AC-12: each of the nine reaches playing, runs past 4 s, has sound.
    @Test(arguments: ["clip.mp4", "clip.m4v", "clip.mov", "clip.mkv", "clip.webm", "clip.flv", "clip.avi", "clip.wmv", "clip.ts"])
    func playsEveryContainer(_ name: String) async {
        let engine = await play(name) { $0.timeMs >= 4_000 || $0.state == .ended }
        #expect(engine.timeMs >= 4_000 || engine.state == .ended, "\(name): reached \(engine.timeMs) ms in \(engine.state)")
        #expect(!engine.audioTracks.isEmpty, "\(name): no audio track")
        if case .failed(let reason) = engine.state { Issue.record("\(name) failed: \(reason)") }
        engine.close()
        engine.view.removeFromSuperview()
    }

    /// AC-13: a damaged head ends in a reason, not a silent black screen.
    @Test func damagedFileSaysWhy() async {
        let engine = await play("broken.mkv") {
            if case .failed = $0.state { return true }
            return false
        }
        guard case .failed(let reason) = engine.state else {
            Issue.record("expected failure, got \(engine.state) at \(engine.timeMs) ms")
            return
        }
        #expect(!reason.isEmpty)
        engine.close()
        engine.view.removeFromSuperview()
    }

    /// AC-15: switching to the second audio track keeps the picture and the
    /// clock going — from a file and through a source stream.
    @Test(arguments: [false, true])
    func switchesAudioWhilePlaying(streamed: Bool) async throws {
        let url = Self.folder.appending(path: "two-audio.mkv")
        let input: VLCMoviePlayer.Input
        if streamed {
            let data = try Data(contentsOf: url)
            let nas = InMemoryRemoteFileClient()
            nas.put("Movies/two-audio.mkv", data)
            input = .stream(RemoteMovieStream(client: nas, path: "Movies/two-audio.mkv", size: Int64(data.count)), fileName: "two-audio.mkv")
        } else {
            input = .file(url)
        }
        let engine = VLCMoviePlayer(input: input)
        engine.view.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.addSubview(engine.view)
        defer {
            engine.close()
            engine.view.removeFromSuperview()
        }
        engine.play()
        var deadline = Date().addingTimeInterval(8)
        while Date() < deadline, engine.timeMs < 1_500 || engine.audioTracks.count < 2 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(engine.audioTracks.count == 2)
        let second = try #require(engine.audioTracks.last)
        let before = engine.timeMs
        engine.selectAudioTrack(id: second.id)
        deadline = Date().addingTimeInterval(4)
        while Date() < deadline, engine.timeMs < before + 2_000, engine.state != .ended {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(engine.state == .playing || engine.state == .buffering, "state \(engine.state)")
        #expect(engine.timeMs >= before + 2_000, "clock \(before) → \(engine.timeMs)")
        #expect(engine.selectedAudioTrackId == second.id)
        #expect(engine.audioTracks.count == 2)
    }
}
