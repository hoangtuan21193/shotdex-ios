import AVFoundation
import Foundation

/// Auto Captions while it runs (FS-12.14 §4, §8): the permission, one clip
/// at a time through the on-device recogniser, the progress the card shows,
/// and the clips that could not be read. It never touches the recipe — each
/// finished clip goes to the model through `onClip`, which merges it.
///
/// Recognition runs in the background of the studio: editing, playing and
/// cutting all go on while it does.
@MainActor @Observable
final class VideoCaptionSession {
    enum Status: Equatable {
        case idle
        /// The system is asking for the permission.
        case asking
        case running
        /// Speech recognition is off for ShotDex: Open Settings.
        case denied
        /// Turned off by a profile or Screen Time: no button.
        case restricted
        /// Every clip was read and none had words.
        case noSpeech
    }

    /// One clip to read: where its sound is and which part of it plays.
    struct Clip: Sendable {
        let id: UUID
        let source: VideoClipSource
        let window: ClosedRange<Double>
    }

    /// What one clip came to.
    enum Outcome: Sendable {
        case words([CaptionWord])
        /// The media is not on the device (iCloud, limited access).
        case unreadable
    }

    private(set) var status: Status = .idle
    /// 0…1 over the planned clips' length.
    private(set) var progress: Double = 0
    private(set) var finishedCount = 0
    private(set) var plannedCount = 0
    /// Clips skipped because their media could not be read (AC-13).
    private(set) var unreadableClipIDs: [UUID] = []
    /// Whether the permission was asked in this studio — asked once (AC-1).
    private(set) var askCount = 0

    let authorizer: any SpeechAuthorizing
    /// Reads one clip; the test's and the UI routes' stand in for the
    /// system recogniser.
    let transcribe: @Sendable (Clip, String) async throws -> Outcome
    /// Whether a language's model is on the device.
    let isAvailable: @Sendable (String) -> Bool
    /// Every language the system recognises.
    let supportedLanguages: @Sendable () -> [String]

    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        authorizer: any SpeechAuthorizing,
        transcribe: @escaping @Sendable (Clip, String) async throws -> Outcome,
        isAvailable: @escaping @Sendable (String) -> Bool,
        supportedLanguages: @escaping @Sendable () -> [String]
    ) {
        self.authorizer = authorizer
        self.transcribe = transcribe
        self.isAvailable = isAvailable
        self.supportedLanguages = supportedLanguages
    }

    var isRunning: Bool { status == .running }

    /// Asks for the permission when it has never been asked; reads it
    /// otherwise. Denied or restricted leaves the card saying so.
    func authorize() async -> SpeechAuthorization {
        var answer = authorizer.status()
        if answer == .notDetermined {
            status = .asking
            askCount += 1
            answer = await authorizer.request()
        }
        switch answer {
        case .authorized: status = .idle
        case .restricted: status = .restricted
        case .denied, .notDetermined: status = .denied
        }
        return answer
    }

    /// Whether any language at all can be recognised on this device.
    var hasAnyModel: Bool {
        languageOptions.contains(where: \.isAvailable)
    }

    /// The device's language when it has a model, else English (US).
    var defaultLanguage: String? {
        CaptionLanguages.defaultLanguage(preferred: Locale.preferredLanguages, isAvailable: isAvailable)
    }

    /// Read once per studio: asking the system about every language is
    /// not free, and models do not arrive while the studio is open.
    var languageOptions: [CaptionLanguages.Option] {
        if let cachedOptions { return cachedOptions }
        let options = CaptionLanguages.options(supported: supportedLanguages(), isAvailable: isAvailable)
        cachedOptions = options
        return options
    }

    @ObservationIgnored private var cachedOptions: [CaptionLanguages.Option]?

    /// Reads `clips` one after another. `lengths` weighs the progress;
    /// `onClip` takes each finished clip's words and answers whether to go
    /// on (false when the lane is gone — undone past its making); `onEnd`
    /// runs once when the run ends by itself, not when it is cancelled.
    func run(
        _ clips: [Clip],
        language: String,
        lengths: [UUID: Double],
        alreadyDone: Double = 0,
        onClip: @escaping @MainActor (UUID, [CaptionWord]) -> Bool,
        onUnreadable: @escaping @MainActor (UUID) -> Void,
        onEnd: @escaping @MainActor (_ heardAnything: Bool) -> Void
    ) {
        cancel()
        status = .running
        unreadableClipIDs = []
        plannedCount = clips.count
        finishedCount = 0
        let total = max(lengths.values.reduce(0, +), 0.001)
        var done = alreadyDone
        progress = min(done / total, 1)
        task = Task { [weak self] in
            var heard = false
            for clip in clips {
                guard let self, !Task.isCancelled else { return }
                let outcome: Outcome
                do {
                    outcome = try await self.transcribe(clip, language)
                } catch is CancellationError {
                    return
                } catch {
                    outcome = .unreadable
                }
                guard !Task.isCancelled else { return }
                switch outcome {
                case .words(let words):
                    heard = heard || !words.isEmpty
                    guard onClip(clip.id, words) else {
                        self.status = .idle
                        return
                    }
                case .unreadable:
                    self.unreadableClipIDs.append(clip.id)
                    onUnreadable(clip.id)
                }
                done += lengths[clip.id] ?? 0
                self.finishedCount += 1
                self.progress = min(done / total, 1)
            }
            guard let self, !Task.isCancelled else { return }
            self.status = heard || !self.unreadableClipIDs.isEmpty ? .idle : .noSpeech
            onEnd(heard)
        }
    }

    /// Stops the run within a callback of the recogniser (AC-11: ≤ 1 s).
    func cancel() {
        task?.cancel()
        task = nil
        if status == .running { status = .idle }
    }

    /// Every clip planned was a photo, a freeze or muted: nothing to hear.
    func reportNoSpeech() {
        status = .noSpeech
    }

    /// Forgets a finished state — the card goes when the panel closes.
    func clearMessage() {
        if status == .noSpeech || status == .denied || status == .restricted { status = .idle }
    }

    /// Waits for the run to end; for tests.
    func waitUntilDone() async {
        await task?.value
    }
}

extension VideoCaptionSession {
    /// The app's session: the system's permission and on-device recogniser.
    static func system(service: SpeechCaptionService = .system) -> VideoCaptionSession {
        VideoCaptionSession(
            authorizer: SystemSpeechAuthorizer(),
            transcribe: { clip, language in
                switch clip.source {
                case .video(let asset, _, let audioTrack, _, _, _):
                    guard let audioTrack else { return .words([]) }
                    do {
                        return .words(try await service.transcribe(track: audioTrack, asset: asset, range: clip.window, language: language))
                    } catch SpeechCaptionService.Failure.unreadable {
                        return .unreadable
                    } catch SpeechCaptionService.Failure.noAudio {
                        return .words([])
                    }
                case .unavailable:
                    return .unreadable
                case .photo, .freeze:
                    return .words([])
                }
            },
            isAvailable: { service.isAvailable($0) },
            supportedLanguages: { SFSpeechRecognizerLocales.identifiers() }
        )
    }

    #if DEBUG
    /// `-ShotDexFakeSpeech` (UI routes, simulator): a permission that is
    /// granted, English and German on the device, Vietnamese not, and each
    /// clip "heard" after a pause long enough to photograph the card —
    /// the simulator has no on-device model to trust (plan K8).
    /// `-ShotDexFakeSpeechDenied` answers the permission with no.
    static func fake(denied: Bool, delay: Duration = .seconds(4)) -> VideoCaptionSession {
        VideoCaptionSession(
            authorizer: FakeSpeechAuthorizer(answer: denied ? .denied : .authorized),
            transcribe: { clip, _ in
                try await Task.sleep(for: delay)
                if case .unavailable = clip.source { return .unreadable }
                return .words(FakeSpeech.words(in: clip.window))
            },
            isAvailable: { ["en-US", "en-GB", "de-DE"].contains($0) },
            supportedLanguages: { ["en-US", "en-GB", "de-DE", "vi-VN"] }
        )
    }
    #endif
}

#if DEBUG
struct FakeSpeechAuthorizer: SpeechAuthorizing {
    let answer: SpeechAuthorization
    func status() -> SpeechAuthorization { .notDetermined }
    func request() async -> SpeechAuthorization { answer }
}

/// The words a fake recogniser hears: the sample sentences of FS-12.14 §9,
/// spread over the window.
enum FakeSpeech {
    static let sentences = [
        "The road to Vík", "starts right here.", "Listen to", "that water.",
        "We stopped for the light.", "Day three, Vík.",
    ]

    static func words(in window: ClosedRange<Double>) -> [CaptionWord] {
        var words: [CaptionWord] = []
        var cursor = window.lowerBound + 0.4
        var sentence = Int(window.lowerBound.rounded()) % sentences.count
        while cursor < window.upperBound - 0.6 {
            for text in sentences[sentence].split(separator: " ") {
                let end = cursor + 0.32
                guard end < window.upperBound else { break }
                words.append(CaptionWord(text: String(text), start: cursor, end: end))
                cursor = end + 0.04
            }
            cursor += 0.6
            sentence = (sentence + 1) % sentences.count
        }
        return words
    }
}
#endif
