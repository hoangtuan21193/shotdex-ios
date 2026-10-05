import AVFoundation
import Foundation
import os
import Speech
import Testing
@testable import ShotDex

/// A recogniser that never listens: it writes down what it was asked and
/// answers with the words it was given, timed from the request's start.
final class RecordingRecognizer: SpeechRecognizing, @unchecked Sendable {
    let supportsOnDeviceRecognition: Bool
    let words: [CaptionWord]
    private let log = OSAllocatedUnfairLock<[Bool]>(initialState: [])

    init(onDevice: Bool = true, words: [CaptionWord] = [CaptionWord(text: "hello", start: 0.1, end: 0.5)]) {
        supportsOnDeviceRecognition = onDevice
        self.words = words
    }

    /// `requiresOnDeviceRecognition` of every request it was sent.
    var onDeviceFlags: [Bool] { log.withLock { $0 } }

    func recognize(_ request: SFSpeechAudioBufferRecognitionRequest) async throws -> [CaptionWord] {
        log.withLock { $0.append(request.requiresOnDeviceRecognition) }
        return words
    }
}

/// FS-12.14 §4, AC-3: recognition on the device only, from the clip's own
/// sound inside its trim, with nothing written to disk.
struct SpeechCaptionServiceTests {
    /// AC-3: every request the service sends requires on-device recognition.
    @Test func everyRequestRequiresOnDevice() async throws {
        let recognizer = RecordingRecognizer()
        let service = SpeechCaptionService(recognizer: { _ in recognizer })
        let samples = [Float](repeating: 0, count: 16_000)
        _ = try await service.transcribe(samples: samples, startingAt: 0, language: "en-US")
        _ = try await service.transcribe(samples: samples, startingAt: 4, language: "en-US")
        #expect(recognizer.onDeviceFlags == [true, true])
        #expect(SpeechCaptionService.request(for: samples).requiresOnDeviceRecognition)
    }

    /// A language with no model on the device never starts — no request,
    /// no fallback to a server.
    @Test func localeWithoutModelNeverStarts() async throws {
        let offDevice = RecordingRecognizer(onDevice: false)
        let service = SpeechCaptionService(recognizer: { _ in offDevice })
        await #expect(throws: SpeechCaptionService.Failure.noOnDeviceModel) {
            try await service.transcribe(samples: [0, 0, 0], startingAt: 0, language: "vi-VN")
        }
        #expect(offDevice.onDeviceFlags.isEmpty)
        #expect(service.isAvailable("vi-VN") == false)
        let none = SpeechCaptionService(recognizer: { _ in nil })
        await #expect(throws: SpeechCaptionService.Failure.noOnDeviceModel) {
            try await none.transcribe(samples: [0], startingAt: 0, language: "xx-YY")
        }
    }

    /// Only the trim window is read: source 1.0–2.0 of a 3 s tone is one
    /// second of 16 kHz samples, and the words come back in source time.
    @Test func readsOnlyTheTrimWindow() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tone.m4a")
        try await VideoExportFixtures.writeTone(seconds: 3, to: file)
        let asset = AVURLAsset(url: file)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)

        let samples = try ClipAudioReader.samples(track: track, asset: asset, range: 1...2)
        #expect(abs(samples.count - 16_000) < 400, "read \(samples.count) samples")

        let recognizer = RecordingRecognizer(words: [CaptionWord(text: "here.", start: 0.2, end: 0.6)])
        let service = SpeechCaptionService(recognizer: { _ in recognizer })
        let words = try await service.transcribe(track: track, asset: asset, range: 1...2, language: "en-US")
        #expect(words.count == 1)
        #expect(abs(words[0].start - 1.2) < 1e-9 && abs(words[0].end - 1.6) < 1e-9)
    }

    /// Nothing lands in the temporary folder: the sound is read into memory.
    @Test func leavesNoTemporaryFiles() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tone.m4a")
        try await VideoExportFixtures.writeTone(seconds: 2, to: file)
        let asset = AVURLAsset(url: file)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let temporary = FileManager.default.temporaryDirectory
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path))
        let service = SpeechCaptionService(recognizer: { _ in RecordingRecognizer() })
        _ = try await service.transcribe(track: track, asset: asset, range: 0...2, language: "en-US")
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path))
        // Other suites run alongside and make folders of their own; a sound
        // file at the top of the folder would be this one's.
        let sounds = after.subtracting(before).filter { ["caf", "wav", "aif", "aiff", "m4a", "pcm"].contains(($0 as NSString).pathExtension.lowercased()) }
        #expect(sounds.isEmpty, "new: \(sounds)")
    }

    /// The buffers carry every sample, in order, at 16 kHz mono.
    @Test func buffersCarryEverySample() {
        let samples = (0..<40_000).map { Float($0 % 100) / 100 }
        let buffers = ClipAudioReader.buffers(samples)
        #expect(buffers.reduce(0) { $0 + Int($1.frameLength) } == 40_000)
        #expect(buffers.first?.format.sampleRate == 16_000)
        #expect(buffers.last?.floatChannelData?[0][0] == samples[32_768])
    }
}
