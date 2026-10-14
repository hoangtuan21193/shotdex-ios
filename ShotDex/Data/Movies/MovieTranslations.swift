import Foundation
import Observation

/// Subtitle translations in progress (FS-23.04 §2–4), app-wide: closing the
/// panel or the player does not stop one. Finished blocks are kept in
/// `Movies/<id>/` as they come, so Cancel, an error or a stopped app lose
/// nothing — Translate offers `Continue (412 of 1,380)`.
@MainActor
@Observable
final class MovieTranslations {
    struct Run: Equatable {
        var movieId: String
        var fromId: String
        var toLanguage: String
        var done: Int
        var total: Int
        var state: State
    }

    enum State: Equatable {
        case running
        case failed(Problem)
        /// The new subtitle's id.
        case finished(String)
    }

    /// What went wrong, in FS-23.04 §4's words.
    struct Problem: Equatable, Sendable {
        var title: String
        var message: String
        /// The key was refused: the way out is Settings › AI.
        var opensSettings: Bool
    }

    private(set) var runs: [String: Run] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    let store: MovieStore
    let files: MovieFileStore
    var translator = SubtitleTranslator()

    init(store: MovieStore, files: MovieFileStore) {
        self.store = store
        self.files = files
    }

    /// An unfinished translation of `fromId` into `toLanguage`, if one was
    /// stopped — whoever was translating it.
    func pending(movieId: String, fromId: String, toLanguage: String) -> (done: Int, total: Int)? {
        guard let job = job(movieId: movieId, fromId: fromId, toLanguage: toLanguage), job.cuesDone > 0 else { return nil }
        return (job.cuesDone, job.cueCount)
    }

    func start(
        movie: Movie, from: MovieSubtitle, document: SubtitleDocument, toLanguage: String,
        using: AIChoice, serviceName: String, engine: any SubtitleTranslationEngine
    ) {
        cancel(movieId: movie.id)
        let cues = document.cues
        var job = job(movieId: movie.id, fromId: from.id, toLanguage: toLanguage)
            ?? MovieTranslationJob(movieId: movie.id, fromSubtitleId: from.id, toLanguage: toLanguage, providerId: using.stored,
                                   cueCount: cues.count, partialFileName: "")
        if job.partialFileName.isEmpty { job.partialFileName = "translating-\(job.id).srt" }
        job.providerId = using.stored
        job.cueCount = cues.count
        let already = partial(job, movieId: movie.id)
        job.cuesDone = already.count
        try? store.saveTranslationJob(job)
        runs[movie.id] = Run(movieId: movie.id, fromId: from.id, toLanguage: toLanguage, done: already.count, total: cues.count, state: .running)

        let instructions = SubtitleTranslationPlan.instructions(
            movieTitle: movie.displayTitle,
            from: MovieLanguage.code(from.language).flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) } ?? "the original language",
            to: Locale(identifier: "en").localizedString(forLanguageCode: toLanguage) ?? toLanguage
        )
        let translator = translator
        let store = store
        let files = files
        let movieId = movie.id
        let startedJob = job
        tasks[movie.id] = Task { [weak self] in
            do {
                let translated = try await translator.run(cues: cues, translated: already, engine: engine, instructions: instructions) { done in
                    // Contiguous from the first cue: what a restart can trust.
                    let count = (0..<cues.count).first { done[$0] == nil } ?? cues.count
                    let kept = SubtitleDocument(cues: Array(SubtitleTranslationPlan.document(original: document, translations: done).cues.prefix(count)))
                    _ = try files.write(Data(SubtitleTranslationPlan.srt(kept).utf8), named: startedJob.partialFileName, for: movieId)
                    var saved = startedJob
                    saved.cuesDone = count
                    saved.updatedAt = Int(Date().timeIntervalSince1970)
                    try store.saveTranslationJob(saved)
                    await MainActor.run { self?.runs[movieId]?.done = count }
                }
                let result = SubtitleTranslationPlan.document(original: document, translations: translated)
                var subtitle = MovieSubtitle(
                    movieId: movieId, language: toLanguage, origin: .translated,
                    translatedFromId: from.id, translationProviderId: using.stored, format: .srt, encoding: "utf-8", fileName: ""
                )
                subtitle.fileName = try files.write(Data(SubtitleTranslationPlan.srt(result).utf8), named: "translated-\(subtitle.id).srt", for: movieId)
                try store.saveSubtitle(subtitle)
                try? store.removeTranslationJob(id: startedJob.id)
                try? FileManager.default.removeItem(at: files.directory(for: movieId).appending(path: startedJob.partialFileName))
                self?.runs[movieId] = Run(movieId: movieId, fromId: from.id, toLanguage: toLanguage, done: cues.count, total: cues.count, state: .finished(subtitle.id))
            } catch is CancellationError {
                self?.runs[movieId] = nil
            } catch {
                self?.runs[movieId]?.state = .failed(Self.problem(error, serviceName: serviceName))
            }
            self?.tasks[movieId] = nil
        }
    }

    /// Stops and keeps what is done.
    func cancel(movieId: String) {
        tasks[movieId]?.cancel()
        tasks[movieId] = nil
        if case .running = runs[movieId]?.state { runs[movieId] = nil }
    }

    /// The finished or failed run, once its outcome was taken in.
    func clear(movieId: String) {
        guard tasks[movieId] == nil else { return }
        runs[movieId] = nil
    }

    static func problem(_ error: Error, serviceName: String) -> Problem {
        switch error as? AIProviderClient.Failure {
        case .rejectedKey:
            return Problem(
                title: String(localized: "\(serviceName) Rejected the API Key", comment: "Translate error title, e.g. Anthropic Rejected the API Key"),
                message: String(localized: "Update it in Settings › AI.", comment: "Translate error: rejected key"),
                opensSettings: true
            )
        case .unreachable:
            return Problem(
                title: String(localized: "Can't Reach \(serviceName)", comment: "Translate error title, e.g. Can't Reach Anthropic"),
                message: String(localized: "Check your connection, or translate on this device.", comment: "Translate error: no connection"),
                opensSettings: false
            )
        default:
            return Problem(
                title: String(localized: "Translation Stopped", comment: "Translate error title: the service refused or failed"),
                message: error.localizedDescription,
                opensSettings: false
            )
        }
    }

    private func job(movieId: String, fromId: String, toLanguage: String) -> MovieTranslationJob? {
        (try? store.translationJobs(movieId: movieId))?.first { $0.fromSubtitleId == fromId && $0.toLanguage == toLanguage }
    }

    /// The translations a stopped run kept, by cue index.
    private func partial(_ job: MovieTranslationJob, movieId: String) -> [Int: String] {
        guard let data = try? Data(contentsOf: files.directory(for: movieId).appending(path: job.partialFileName)) else { return [:] }
        let cues = SubtitleParser.parse(String(decoding: data, as: UTF8.self), format: .srt).cues.prefix(job.cuesDone)
        return Dictionary(uniqueKeysWithValues: cues.enumerated().map { ($0.offset, $0.element.plainText) })
    }
}
