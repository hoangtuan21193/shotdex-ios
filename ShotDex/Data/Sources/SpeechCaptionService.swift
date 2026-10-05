import AVFoundation
import Foundation
import os
import Speech

/// Speech recognition permission, as Auto Captions needs it (FS-12.14 §4).
enum SpeechAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

/// Asking for, and reading, the speech recognition permission. The system's
/// in the app; a stand-in in tests and UI routes.
protocol SpeechAuthorizing: Sendable {
    func status() -> SpeechAuthorization
    func request() async -> SpeechAuthorization
}

/// One language's recogniser, as the service drives it.
protocol SpeechRecognizing: Sendable {
    /// Whether the model for this language is on the device.
    var supportsOnDeviceRecognition: Bool { get }
    /// The words the request's audio holds, timed from its first sample.
    func recognize(_ request: SFSpeechAudioBufferRecognitionRequest) async throws -> [CaptionWord]
}

/// Speech in a clip into timed words, **on the device only** (FS-12.14 §4,
/// NF-03): every request requires on-device recognition, and a language
/// whose model is not on the device never starts — there is no fallback to
/// a server, network or not. The clip's sound is read straight from its
/// asset inside the trim window; nothing is written to disk.
struct SpeechCaptionService: Sendable {
    enum Failure: Error, Equatable {
        /// The language has no on-device model here.
        case noOnDeviceModel
        /// The clip has no sound to read.
        case noAudio
        /// The sound could not be read (iCloud, limited access).
        case unreadable
    }

    /// The recogniser for a BCP-47 language, or nil when the system has none.
    let recognizer: @Sendable (String) -> (any SpeechRecognizing)?

    static let system = SpeechCaptionService(recognizer: { language in
        SFSpeechRecognizer(locale: Locale(identifier: language)).map(SystemSpeechRecognizer.init)
    })

    /// Whether `language` can be recognised on this device.
    func isAvailable(_ language: String) -> Bool {
        recognizer(language)?.supportsOnDeviceRecognition == true
    }

    /// The words of `track` between source seconds `range`, in source time.
    func transcribe(track: AVAssetTrack, asset: AVAsset, range: ClosedRange<Double>, language: String) async throws -> [CaptionWord] {
        guard let engine = recognizer(language), engine.supportsOnDeviceRecognition else { throw Failure.noOnDeviceModel }
        let samples: [Float]
        do {
            samples = try ClipAudioReader.samples(track: track, asset: asset, range: range)
        } catch AudioPCMReader.ReadError.cancelled {
            throw CancellationError()
        } catch AudioPCMReader.ReadError.noAudio {
            throw Failure.noAudio
        } catch {
            throw Failure.unreadable
        }
        try Task.checkCancellation()
        return try await transcribe(samples: samples, startingAt: range.lowerBound, engine: engine)
    }

    /// The words of 16 kHz mono `samples` that begin at source second
    /// `start`.
    func transcribe(samples: [Float], startingAt start: Double, language: String) async throws -> [CaptionWord] {
        guard let engine = recognizer(language), engine.supportsOnDeviceRecognition else { throw Failure.noOnDeviceModel }
        return try await transcribe(samples: samples, startingAt: start, engine: engine)
    }

    private func transcribe(samples: [Float], startingAt start: Double, engine: any SpeechRecognizing) async throws -> [CaptionWord] {
        let request = Self.request(for: samples)
        let words = try await engine.recognize(request)
        return words.map { CaptionWord(text: $0.text, start: start + $0.start, end: start + $0.end) }
    }

    /// One request carrying the whole read, ended — on-device, final
    /// results only, with punctuation (the chunker breaks after it).
    static func request(for samples: [Float]) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        for buffer in ClipAudioReader.buffers(samples) {
            request.append(buffer)
        }
        request.endAudio()
        return request
    }
}

/// The clip's sound for recognition: its first audio track, mono, 16 kHz,
/// inside the trim window only — read through the analysis reader the
/// ducking uses, into memory (FS-12.14 §4: no temporary file).
enum ClipAudioReader {
    static let sampleRate: Double = 16_000
    /// Frames per buffer handed to the recogniser.
    static let bufferFrames = 16_384

    static func samples(track: AVAssetTrack, asset: AVAsset, range: ClosedRange<Double>) throws -> [Float] {
        try AudioPCMReader.read(track: track, asset: asset, sampleRate: sampleRate, range: range)
    }

    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    static func buffers(_ samples: [Float]) -> [AVAudioPCMBuffer] {
        let format = format
        return stride(from: 0, to: samples.count, by: bufferFrames).compactMap { offset in
            let count = min(bufferFrames, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0]
            else { return nil }
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + offset, count: count)
            }
            buffer.frameLength = AVAudioFrameCount(count)
            return buffer
        }
    }
}

/// The languages the system recognises, as BCP-47.
enum SFSpeechRecognizerLocales {
    static func identifiers() -> [String] {
        SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") }
    }
}

// MARK: - The system's recogniser

/// `SFSpeechRecognizer` behind `SpeechRecognizing`: one task per request,
/// bridged to async; cancelling the Swift task cancels the recognition
/// within its next callback.
final class SystemSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer

    init(_ recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    var supportsOnDeviceRecognition: Bool { recognizer.supportsOnDeviceRecognition }

    func recognize(_ request: SFSpeechAudioBufferRecognitionRequest) async throws -> [CaptionWord] {
        let state = OSAllocatedUnfairLock<(task: SFSpeechRecognitionTask?, done: Bool)>(initialState: (nil, false))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CaptionWord], Error>) in
                let finish: @Sendable (Result<[CaptionWord], Error>) -> Void = { result in
                    let first = state.withLock { value -> Bool in
                        guard !value.done else { return false }
                        value.done = true
                        return true
                    }
                    if first { continuation.resume(with: result) }
                }
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        finish(.success(result.bestTranscription.segments.map {
                            CaptionWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                        }))
                    } else if let error {
                        // "No speech detected" is an answer, not a failure.
                        let nsError = error as NSError
                        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                            finish(.success([]))
                        } else {
                            finish(.failure(Task.isCancelled ? CancellationError() : error))
                        }
                    }
                }
                state.withLock { $0.task = task }
            }
        } onCancel: {
            state.withLock { $0.task }?.cancel()
        }
    }
}

/// The system's speech recognition permission.
struct SystemSpeechAuthorizer: SpeechAuthorizing {
    func status() -> SpeechAuthorization {
        Self.map(SFSpeechRecognizer.authorizationStatus())
    }

    func request() async -> SpeechAuthorization {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechAuthorization {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
